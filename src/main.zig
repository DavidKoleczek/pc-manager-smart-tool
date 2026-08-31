const std = @import("std");
const Io = std.Io;

const pc_manager = @import("pc_manager");

const brief_help =
    \\pc-manager: scans a PC's disk space and suggests cleanups
    \\
    \\usage:
    \\  pc-manager scan [disk] [--root <path>]... [--top <n>] [--min-size <size>]
    \\  pc-manager suggest --request "<what you want suggestions about>" [--root <path>]...
    \\  pc-manager manifest
    \\
    \\-h prints this summary; --help prints the complete listing.
    \\
;

const full_help =
    \\pc-manager: manages and monitors a personal computer, starting with disk space.
    \\Scans and suggestions are read-only; nothing here modifies the system.
    \\All results are indented JSON on stdout.
    \\
    \\commands:
    \\
    \\scan [kind] [flags]
    \\  Deterministic snapshot of one aspect of the system. Bare `scan` runs every
    \\  kind and prints one object keyed by kind; `scan <kind>` prints that kind's
    \\  result alone. Kinds: disk.
    \\  flags for `scan disk`:
    \\    --root <path>      path to scan, repeatable; every mounted fixed volume when omitted
    \\    --top <n>          largest files and largest directories kept per volume; 100 when omitted
    \\    --min-size <size>  ignore entries below this size, as bytes or suffixed like 500MB or 2GB; 0 when omitted
    \\  Prints started_at_ms, duration_ms, and per volume: path, capacity_bytes,
    \\  free_bytes, largest_files, largest_dirs (recursive sizes), and skipped,
    \\  the paths the scan could not read.
    \\
    \\suggest --request <text> [--root <path>]...
    \\  Model-backed cleanup proposals steered by the request. Runs the scans it
    \\  needs on its own; --root, repeatable, narrows them to those paths instead
    \\  of every mounted fixed volume. Prints items, each with path, size_bytes, action,
    \\  rationale, and risk (low, medium, high), and message, the model's closing
    \\  message. Needs the Claude Code CLI installed and signed in; the model is
    \\  set in the settings file, see the configuration documentation.
    \\
    \\manifest
    \\  The tool's manifest as structured data. Deterministic, needs nothing
    \\  configured, and doubles as an install smoke test.
    \\
    \\exit codes:
    \\  0  success
    \\  1  the command failed; stdout carries {"error": {"code", "message", "remedy"}}
    \\  2  invalid usage: unknown command, scan kind, or flag; same error object on stdout
    \\
;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const out = &stdout_writer.interface;

    if (args.len < 2 or std.mem.eql(u8, args[1], "-h")) {
        try out.writeAll(brief_help);
        try out.flush();
        std.process.exit(if (args.len < 2) 2 else 0);
    }
    const command = args[1];
    if (std.mem.eql(u8, command, "--help")) {
        try out.writeAll(full_help);
        try out.flush();
        return;
    }
    if (std.mem.eql(u8, command, "manifest")) return runManifest(init, out);
    if (std.mem.eql(u8, command, "scan")) return runScan(init, out, args[2..]);
    if (std.mem.eql(u8, command, "suggest")) return runSuggest(init, out, args[2..]);
    fail(out, 2, "unknown_command", command, "Commands are scan, suggest, and manifest; see --help.");
}

fn runManifest(init: std.process.Init, out: *Io.Writer) !void {
    const manifest = pc_manager.loadManifest(init.gpa) catch |err| failFrom(out, err);
    defer manifest.deinit();
    try printJson(out, manifest);
}

fn runScan(init: std.process.Init, out: *Io.Writer, args: []const [:0]const u8) !void {
    const arena = init.arena.allocator();
    var kind: ?[]const u8 = null;
    var roots: std.ArrayList([]const u8) = .empty;
    var options: pc_manager.DiskScanOptions = .{};

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (i == 0 and !std.mem.startsWith(u8, arg, "-")) {
            kind = arg;
            continue;
        }
        if (std.mem.eql(u8, arg, "--root")) {
            try roots.append(arena, flagValue(out, args, &i));
        } else if (std.mem.eql(u8, arg, "--top")) {
            options.top = std.fmt.parseInt(u32, flagValue(out, args, &i), 10) catch
                fail(out, 2, "invalid_flag_value", "--top", "--top takes a whole number, like --top 50.");
        } else if (std.mem.eql(u8, arg, "--min-size")) {
            options.min_size_bytes = std.fmt.parseIntSizeSuffix(flagValue(out, args, &i), 10) catch
                fail(out, 2, "invalid_flag_value", "--min-size", "--min-size takes bytes or a suffixed size like 500MB or 2GB.");
        } else {
            fail(out, 2, "unknown_flag", arg, "Flags for scan are --root, --top, and --min-size; see --help.");
        }
    }
    if (kind) |k| {
        if (!std.mem.eql(u8, k, "disk")) {
            fail(out, 2, "unknown_scan_kind", k, "The scan kinds are: disk.");
        }
    }
    options.roots = roots.items;

    const scan = pc_manager.scanDisk(init.gpa, init.io, options) catch |err| failFrom(out, err);
    defer scan.deinit();
    if (kind == null) {
        try printJson(out, .{ .disk = scan });
    } else {
        try printJson(out, scan);
    }
}

fn runSuggest(init: std.process.Init, out: *Io.Writer, args: []const [:0]const u8) !void {
    const arena = init.arena.allocator();
    var request: ?[]const u8 = null;
    var roots: std.ArrayList([]const u8) = .empty;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--request")) {
            request = flagValue(out, args, &i);
        } else if (std.mem.eql(u8, args[i], "--root")) {
            try roots.append(arena, flagValue(out, args, &i));
        } else {
            fail(out, 2, "unknown_flag", args[i], "The flags for suggest are --request and --root; see --help.");
        }
    }
    const the_request = request orelse
        fail(out, 2, "missing_flag", "--request", "suggest needs --request, like: pc-manager suggest --request \"what can safely be removed?\"");

    const suggestions = pc_manager.suggest(init.gpa, init.io, init.environ_map, .{
        .request = the_request,
        .roots = roots.items,
    }) catch |err| failFrom(out, err);
    defer suggestions.deinit();
    try printJson(out, suggestions);
}

fn flagValue(out: *Io.Writer, args: []const [:0]const u8, i: *usize) [:0]const u8 {
    i.* += 1;
    if (i.* >= args.len) {
        fail(out, 2, "missing_flag_value", args[i.* - 1], "This flag takes a value; see --help.");
    }
    return args[i.*];
}

fn printJson(out: *Io.Writer, value: anytype) !void {
    try out.print("{f}\n", .{std.json.fmt(value, .{ .whitespace = .indent_2 })});
    try out.flush();
}

fn failFrom(out: *Io.Writer, err: anyerror) noreturn {
    const remedy = pc_manager.remedyFor(err) orelse "Re-run the command; if the failure persists, file an issue with this error.";
    fail(out, 1, @errorName(err), "The command failed.", remedy);
}

fn fail(out: *Io.Writer, exit_code: u8, code: []const u8, message: []const u8, remedy: []const u8) noreturn {
    printJson(out, .{ .@"error" = .{
        .code = code,
        .message = message,
        .remedy = remedy,
    } }) catch {};
    std.process.exit(exit_code);
}
