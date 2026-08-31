//! Suggest: model-backed cleanup proposals over scan data. Never modifies
//! the system; acting on a suggestion is the caller's decision.
const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const claude = @import("claude.zig");
const config = @import("config.zig");
const scan = @import("scan.zig");

pub const SuggestOptions = struct {
    request: []const u8,
    roots: []const []const u8 = &.{},
};

pub const Risk = enum { low, medium, high };

pub const Suggestion = struct {
    path: []const u8,
    size_bytes: u64,
    action: []const u8,
    rationale: []const u8,
    risk: Risk,
};

pub const Suggestions = struct {
    arena: *std.heap.ArenaAllocator,
    items: []const Suggestion,
    message: []const u8,

    pub fn deinit(s: Suggestions) void {
        const gpa = s.arena.child_allocator;
        s.arena.deinit();
        gpa.destroy(s.arena);
    }

    pub fn jsonStringify(s: Suggestions, jws: *std.json.Stringify) !void {
        try jws.beginObject();
        try jws.objectField("items");
        try jws.write(s.items);
        try jws.objectField("message");
        try jws.write(s.message);
        try jws.endObject();
    }
};

pub const SuggestError = claude.Error || config.SettingsError || scan.ScanDiskError;

// Bounds what a suggest run scans so the prompt stays a manageable size.
const scan_top = 50;
const scan_min_size_bytes = 10 * 1024 * 1024;

const suggestion_schema =
    \\{
    \\  "type": "object",
    \\  "additionalProperties": false,
    \\  "required": ["items", "message"],
    \\  "properties": {
    \\    "items": {
    \\      "type": "array",
    \\      "items": {
    \\        "type": "object",
    \\        "additionalProperties": false,
    \\        "required": ["path", "size_bytes", "action", "rationale", "risk"],
    \\        "properties": {
    \\          "path": {"type": "string"},
    \\          "size_bytes": {"type": "integer"},
    \\          "action": {"type": "string"},
    \\          "rationale": {"type": "string"},
    \\          "risk": {"type": "string", "enum": ["low", "medium", "high"]}
    \\        }
    \\      }
    \\    },
    \\    "message": {"type": "string"}
    \\  }
    \\}
;

/// Runs the scans it needs, sends them to the configured model with the
/// caller's request, and returns the proposed cleanups.
pub fn suggest(
    gpa: Allocator,
    io: Io,
    environ_map: *const std.process.Environ.Map,
    options: SuggestOptions,
) SuggestError!Suggestions {
    const arena_ptr = try gpa.create(std.heap.ArenaAllocator);
    errdefer gpa.destroy(arena_ptr);
    arena_ptr.* = .init(gpa);
    errdefer arena_ptr.deinit();
    const arena = arena_ptr.allocator();

    const settings = try config.loadSettings(arena, io, environ_map);

    const disk = try scan.scanDisk(gpa, io, .{
        .roots = options.roots,
        .top = scan_top,
        .min_size_bytes = scan_min_size_bytes,
    });
    defer disk.deinit();
    const scan_json = std.json.Stringify.valueAlloc(arena, disk, .{}) catch return error.OutOfMemory;

    var prompt: Io.Writer.Allocating = .init(arena);
    prompt.writer.print(
        \\You are the suggest capability of pc-manager, a tool that manages disk space on a personal computer.
        \\Propose cleanups based on the disk scan below. Nothing you propose is executed; a person reviews every suggestion and acts on it themselves.
        \\
        \\The person's request: {s}
        \\
        \\For each suggestion:
        \\- path: an exact path taken from the scan
        \\- size_bytes: its size as reported by the scan
        \\- action: what the person could do, such as deleting the path, uninstalling the owning program through the system's installed-programs list, or archiving it elsewhere
        \\- rationale: why this space is likely reclaimable, tied to what the path holds
        \\- risk: low for caches, temporary files, and other content rebuilt automatically; medium for things rebuilt with effort, like package caches or old development environments; high for anything that could hold personal data or break an installed program
        \\
        \\Only propose paths that appear in the scan. Prefer fewer well-reasoned suggestions over many speculative ones. Put an overall summary of what you found in message.
        \\
        \\Disk scan (JSON):
        \\{s}
    , .{ options.request, scan_json }) catch return error.OutOfMemory;

    const value = try claude.promptStructured(
        arena,
        io,
        environ_map,
        settings.model,
        prompt.written(),
        suggestion_schema,
    );
    const Payload = struct {
        items: []const Suggestion,
        message: []const u8,
    };
    const payload = std.json.parseFromValueLeaky(Payload, arena, value, .{ .ignore_unknown_fields = true }) catch
        return error.ModelOutputInvalid;

    return .{
        .arena = arena_ptr,
        .items = payload.items,
        .message = payload.message,
    };
}
