//! The model interface: one prompt in, schema-conforming JSON out, by
//! shelling out to the Claude Code CLI in print mode. Swapping the
//! intelligence layer means replacing this file.
//!
//! The child environment drops `ANTHROPIC_API_KEY` and `ANTHROPIC_AUTH_TOKEN`
//! so a run always bills the signed-in Claude subscription, never a stray API
//! key. Tools, MCP servers, settings, and session persistence are all
//! disabled, so an invocation is a single self-contained model call.
const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const Error = error{
    OutOfMemory,
    ClaudeCliNotFound,
    ClaudeCliNotSignedIn,
    ClaudeCliFailed,
    ModelOutputInvalid,
};

const max_output_bytes: usize = 4 * 1024 * 1024;

/// Sends `prompt` to the given model and returns the JSON value conforming to
/// `json_schema` (a JSON Schema document). Everything is allocated from
/// `arena`, whose owner frees the result.
pub fn promptStructured(
    arena: Allocator,
    io: Io,
    environ_map: *const std.process.Environ.Map,
    model: []const u8,
    prompt: []const u8,
    json_schema: []const u8,
) Error!std.json.Value {
    var env = environ_map.clone(arena) catch return error.OutOfMemory;
    _ = env.swapRemove("ANTHROPIC_API_KEY");
    _ = env.swapRemove("ANTHROPIC_AUTH_TOKEN");

    try checkSignedIn(arena, io, &env);

    const argv: []const []const u8 = &.{
        "claude",                   "-p",
        "--model",                  model,
        "--output-format",          "json",
        "--json-schema",            json_schema,
        "--tools",                  "",
        "--disallowedTools",        "mcp__*",
        "--permission-mode",        "dontAsk",
        "--setting-sources",        "",
        "--no-session-persistence", "--strict-mcp-config",
        "--disable-slash-commands",
    };
    const stdout_bytes = try runWithStdin(arena, io, &env, argv, prompt);
    return parseEnvelope(arena, stdout_bytes);
}

fn checkSignedIn(arena: Allocator, io: Io, env: *const std.process.Environ.Map) Error!void {
    const status = std.process.run(arena, io, .{
        .argv = &.{ "claude", "auth", "status" },
        .environ_map = env,
        .stdout_limit = .limited(1 << 16),
        .stderr_limit = .limited(1 << 16),
    }) catch |err| return switch (err) {
        error.FileNotFound => error.ClaudeCliNotFound,
        error.OutOfMemory => error.OutOfMemory,
        else => error.ClaudeCliFailed,
    };
    switch (status.term) {
        .exited => |code| if (code != 0) return error.ClaudeCliNotSignedIn,
        else => return error.ClaudeCliFailed,
    }
}

fn runWithStdin(
    arena: Allocator,
    io: Io,
    env: *const std.process.Environ.Map,
    argv: []const []const u8,
    stdin_bytes: []const u8,
) Error![]u8 {
    var child = std.process.spawn(io, .{
        .argv = argv,
        .environ_map = env,
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .pipe,
        .create_no_window = true,
    }) catch |err| return switch (err) {
        error.FileNotFound => error.ClaudeCliNotFound,
        else => error.ClaudeCliFailed,
    };
    defer child.kill(io);

    {
        const stdin_file = child.stdin.?;
        var write_buffer: [4096]u8 = undefined;
        var stdin_writer: Io.File.Writer = .init(stdin_file, io, &write_buffer);
        stdin_writer.interface.writeAll(stdin_bytes) catch return error.ClaudeCliFailed;
        stdin_writer.interface.flush() catch return error.ClaudeCliFailed;
        stdin_file.close(io);
        child.stdin = null;
    }

    var multi_reader_buffer: Io.File.MultiReader.Buffer(2) = undefined;
    var multi_reader: Io.File.MultiReader = undefined;
    multi_reader.init(arena, io, multi_reader_buffer.toStreams(), &.{ child.stdout.?, child.stderr.? });
    defer multi_reader.deinit();
    const stdout_reader = multi_reader.reader(0);

    while (multi_reader.fill(64, .none)) |_| {
        if (stdout_reader.buffered().len > max_output_bytes) return error.ClaudeCliFailed;
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => return error.ClaudeCliFailed,
    }
    multi_reader.checkAnyError() catch return error.ClaudeCliFailed;

    const term = child.wait(io) catch return error.ClaudeCliFailed;
    const stdout_bytes = multi_reader.toOwnedSlice(0) catch return error.OutOfMemory;
    switch (term) {
        .exited => |code| if (code != 0) return failureFromResultText(stdout_bytes),
        else => return error.ClaudeCliFailed,
    }
    return stdout_bytes;
}

// With --output-format json the CLI prints one result object; some settings
// make it print an array of every message instead, with the result last.
fn parseEnvelope(arena: Allocator, stdout_bytes: []const u8) Error!std.json.Value {
    const root = std.json.parseFromSliceLeaky(std.json.Value, arena, stdout_bytes, .{}) catch
        return error.ModelOutputInvalid;
    const result: std.json.Value = switch (root) {
        .object => root,
        .array => |array| blk: {
            var i = array.items.len;
            while (i > 0) {
                i -= 1;
                const element = array.items[i];
                if (element != .object) continue;
                const element_type = element.object.get("type") orelse continue;
                if (element_type == .string and std.mem.eql(u8, element_type.string, "result")) break :blk element;
            }
            return error.ModelOutputInvalid;
        },
        else => return error.ModelOutputInvalid,
    };
    const object = result.object;
    if (object.get("is_error")) |is_error| {
        if (is_error == .bool and is_error.bool) {
            if (object.get("result")) |r| {
                if (r == .string) return failureFromResultText(r.string);
            }
            return error.ClaudeCliFailed;
        }
    }
    return object.get("structured_output") orelse error.ModelOutputInvalid;
}

fn failureFromResultText(text: []const u8) Error {
    if (std.mem.indexOf(u8, text, "login") != null or std.mem.indexOf(u8, text, "authentication") != null) {
        return error.ClaudeCliNotSignedIn;
    }
    return error.ClaudeCliFailed;
}
