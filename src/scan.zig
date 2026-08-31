//! Scan Disk: a deterministic, read-only snapshot of how disk space is used.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const DiskScanOptions = struct {
    roots: []const []const u8 = &.{},
    top: u32 = 100,
    min_size_bytes: u64 = 0,
};

pub const SizedPath = struct {
    path: []const u8,
    size_bytes: u64,
};

pub const Volume = struct {
    path: []const u8,
    capacity_bytes: u64,
    free_bytes: u64,
    largest_files: []const SizedPath,
    largest_dirs: []const SizedPath,
    skipped: []const []const u8,
};

pub const DiskScan = struct {
    arena: *std.heap.ArenaAllocator,
    started_at_ms: i64,
    duration_ms: i64,
    volumes: []const Volume,

    pub fn deinit(scan: DiskScan) void {
        const gpa = scan.arena.child_allocator;
        scan.arena.deinit();
        gpa.destroy(scan.arena);
    }

    pub fn jsonStringify(scan: DiskScan, s: *std.json.Stringify) !void {
        try s.beginObject();
        try s.objectField("started_at_ms");
        try s.write(scan.started_at_ms);
        try s.objectField("duration_ms");
        try s.write(scan.duration_ms);
        try s.objectField("volumes");
        try s.write(scan.volumes);
        try s.endObject();
    }
};

pub const ScanDiskError = error{ OutOfMemory, RootNotFound, RootUnreadable };

/// Walks each root and reports capacity, free space, the largest files and
/// directories, and the paths that could not be read. Roots default to every
/// mounted fixed volume. Directory sizes are recursive; symbolic links and
/// junctions are never followed.
pub fn scanDisk(gpa: Allocator, io: Io, options: DiskScanOptions) ScanDiskError!DiskScan {
    const arena_ptr = try gpa.create(std.heap.ArenaAllocator);
    errdefer gpa.destroy(arena_ptr);
    arena_ptr.* = .init(gpa);
    errdefer arena_ptr.deinit();
    const arena = arena_ptr.allocator();

    const started = Io.Timestamp.now(io, .real);
    const t0 = Io.Timestamp.now(io, .awake);

    const roots = if (options.roots.len == 0) try fixedVolumeRoots(arena) else options.roots;

    var volumes: std.ArrayList(Volume) = .empty;
    for (roots) |root| {
        try volumes.append(arena, try scanVolume(arena, io, root, options));
    }

    return .{
        .arena = arena_ptr,
        .started_at_ms = started.toMilliseconds(),
        .duration_ms = t0.untilNow(io, .awake).toMilliseconds(),
        .volumes = volumes.items,
    };
}

fn scanVolume(arena: Allocator, io: Io, root: []const u8, options: DiskScanOptions) ScanDiskError!Volume {
    var dir = Io.Dir.cwd().openDir(io, root, .{ .iterate = true }) catch |err| return switch (err) {
        error.FileNotFound, error.NotDir => error.RootNotFound,
        else => error.RootUnreadable,
    };
    defer dir.close(io);

    var ctx: WalkContext = .{
        .arena = arena,
        .io = io,
        .min_size_bytes = options.min_size_bytes,
        .files = .{ .cap = options.top },
        .dirs = .{ .cap = options.top },
    };

    var path: std.ArrayList(u8) = .empty;
    try path.appendSlice(arena, root);
    while (path.items.len > 0 and (path.items[path.items.len - 1] == '/' or path.items[path.items.len - 1] == '\\')) {
        _ = path.pop();
    }
    _ = try walkDir(&ctx, dir, &path);

    const space = diskSpace(arena, root) catch DiskSpace{ .capacity_bytes = 0, .free_bytes = 0 };
    return .{
        .path = try arena.dupe(u8, root),
        .capacity_bytes = space.capacity_bytes,
        .free_bytes = space.free_bytes,
        .largest_files = ctx.files.entries.items,
        .largest_dirs = ctx.dirs.entries.items,
        .skipped = ctx.skipped.items,
    };
}

const WalkContext = struct {
    arena: Allocator,
    io: Io,
    min_size_bytes: u64,
    files: TopList,
    dirs: TopList,
    skipped: std.ArrayList([]const u8) = .empty,

    fn noteSkipped(ctx: *WalkContext, path: []const u8) error{OutOfMemory}!void {
        try ctx.skipped.append(ctx.arena, try ctx.arena.dupe(u8, path));
    }
};

fn walkDir(ctx: *WalkContext, dir: Io.Dir, path: *std.ArrayList(u8)) error{OutOfMemory}!u64 {
    var total: u64 = 0;
    var it = dir.iterate();
    while (true) {
        const entry = (it.next(ctx.io) catch {
            try ctx.noteSkipped(path.items);
            break;
        }) orelse break;
        const parent_len = path.items.len;
        try path.append(ctx.arena, std.fs.path.sep);
        try path.appendSlice(ctx.arena, entry.name);
        defer path.shrinkRetainingCapacity(parent_len);
        switch (entry.kind) {
            .file => {
                const stat = dir.statFile(ctx.io, entry.name, .{ .follow_symlinks = false }) catch {
                    try ctx.noteSkipped(path.items);
                    continue;
                };
                total += stat.size;
                if (stat.size >= ctx.min_size_bytes) {
                    try ctx.files.consider(ctx.arena, path.items, stat.size);
                }
            },
            .directory => {
                var sub = dir.openDir(ctx.io, entry.name, .{ .iterate = true, .follow_symlinks = false }) catch {
                    try ctx.noteSkipped(path.items);
                    continue;
                };
                defer sub.close(ctx.io);
                const sub_total = try walkDir(ctx, sub, path);
                total += sub_total;
                if (sub_total >= ctx.min_size_bytes) {
                    try ctx.dirs.consider(ctx.arena, path.items, sub_total);
                }
            },
            else => {},
        }
    }
    return total;
}

/// A bounded, descending-sorted list of the largest entries seen so far.
const TopList = struct {
    cap: u32,
    entries: std.ArrayList(SizedPath) = .empty,

    fn consider(t: *TopList, arena: Allocator, path: []const u8, size_bytes: u64) error{OutOfMemory}!void {
        if (t.cap == 0) return;
        const full = t.entries.items.len == t.cap;
        if (full and size_bytes <= t.entries.items[t.entries.items.len - 1].size_bytes) return;
        var lo: usize = 0;
        var hi: usize = t.entries.items.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (t.entries.items[mid].size_bytes >= size_bytes) lo = mid + 1 else hi = mid;
        }
        if (full) _ = t.entries.pop();
        try t.entries.insert(arena, lo, .{
            .path = try arena.dupe(u8, path),
            .size_bytes = size_bytes,
        });
    }
};

const DiskSpace = struct {
    capacity_bytes: u64,
    free_bytes: u64,
};

fn fixedVolumeRoots(arena: Allocator) error{OutOfMemory}![]const []const u8 {
    switch (builtin.os.tag) {
        .windows => {
            var roots: std.ArrayList([]const u8) = .empty;
            const drives = GetLogicalDrives();
            var letter: u8 = 'A';
            while (letter <= 'Z') : (letter += 1) {
                const bit = @as(u32, 1) << @intCast(letter - 'A');
                if (drives & bit == 0) continue;
                const root_w = [4:0]u16{ letter, ':', '\\', 0 };
                if (GetDriveTypeW(&root_w) != DRIVE_FIXED) continue;
                try roots.append(arena, try std.fmt.allocPrint(arena, "{c}:\\", .{letter}));
            }
            return roots.toOwnedSlice(arena);
        },
        else => return arena.dupe([]const u8, &.{"/"}),
    }
}

fn diskSpace(arena: Allocator, root: []const u8) !DiskSpace {
    switch (builtin.os.tag) {
        .windows => {
            const root_w = try std.unicode.wtf8ToWtf16LeAllocZ(arena, root);
            var capacity: u64 = 0;
            var free: u64 = 0;
            if (GetDiskFreeSpaceExW(root_w.ptr, null, &capacity, &free) == 0) return error.Unavailable;
            return .{ .capacity_bytes = capacity, .free_bytes = free };
        },
        .linux => {
            const root_z = try arena.dupeZ(u8, root);
            var buf: LinuxStatfs = undefined;
            const rc = std.os.linux.syscall2(.statfs, @intFromPtr(root_z.ptr), @intFromPtr(&buf));
            if (std.os.linux.errno(rc) != .SUCCESS) return error.Unavailable;
            const unit: u64 = if (buf.f_frsize > 0) @intCast(buf.f_frsize) else @intCast(buf.f_bsize);
            return .{
                .capacity_bytes = buf.f_blocks * unit,
                .free_bytes = buf.f_bavail * unit,
            };
        },
        else => return error.Unavailable,
    }
}

const DRIVE_FIXED: std.os.windows.UINT = 3;

extern "kernel32" fn GetLogicalDrives() callconv(.winapi) std.os.windows.DWORD;
extern "kernel32" fn GetDriveTypeW(lpRootPathName: ?std.os.windows.LPCWSTR) callconv(.winapi) std.os.windows.UINT;
extern "kernel32" fn GetDiskFreeSpaceExW(
    lpDirectoryName: ?std.os.windows.LPCWSTR,
    lpFreeBytesAvailableToCaller: ?*u64,
    lpTotalNumberOfBytes: ?*u64,
    lpTotalNumberOfFreeBytes: ?*u64,
) callconv(.winapi) c_int;

const LinuxStatfs = extern struct {
    f_type: i64,
    f_bsize: i64,
    f_blocks: u64,
    f_bfree: u64,
    f_bavail: u64,
    f_files: u64,
    f_ffree: u64,
    f_fsid: [2]i32,
    f_namelen: i64,
    f_frsize: i64,
    f_flags: i64,
    f_spare: [4]i64,
};

test "TopList keeps the largest entries in descending order" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var top: TopList = .{ .cap = 3 };
    try top.consider(arena, "a", 10);
    try top.consider(arena, "b", 30);
    try top.consider(arena, "c", 20);
    try top.consider(arena, "d", 5);
    try top.consider(arena, "e", 25);

    try std.testing.expectEqual(@as(usize, 3), top.entries.items.len);
    try std.testing.expectEqual(@as(u64, 30), top.entries.items[0].size_bytes);
    try std.testing.expectEqual(@as(u64, 25), top.entries.items[1].size_bytes);
    try std.testing.expectEqual(@as(u64, 20), top.entries.items[2].size_bytes);
    try std.testing.expectEqualStrings("e", top.entries.items[1].path);
}
