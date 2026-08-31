//! User settings: machine-local configuration stored in the per-user config
//! directory, `%APPDATA%\pc-manager\settings.json` on Windows and
//! `$XDG_CONFIG_HOME/pc-manager/settings.json` (default `~/.config/...`) elsewhere.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const default_model = "claude-sonnet-5";

pub const Settings = struct {
    model: []const u8 = default_model,
};

pub const SettingsError = error{ OutOfMemory, SettingsInvalid };

/// The path of the settings file, allocated from `arena`, or null when the
/// platform's config directory cannot be determined from the environment.
pub fn settingsPath(arena: Allocator, environ_map: *const std.process.Environ.Map) error{OutOfMemory}!?[]u8 {
    const base = switch (builtin.os.tag) {
        .windows => environ_map.get("APPDATA") orelse return null,
        else => blk: {
            if (environ_map.get("XDG_CONFIG_HOME")) |xdg| break :blk xdg;
            const home = environ_map.get("HOME") orelse return null;
            break :blk try std.fs.path.join(arena, &.{ home, ".config" });
        },
    };
    return try std.fs.path.join(arena, &.{ base, "pc-manager", "settings.json" });
}

/// Reads the settings file. A missing file yields the defaults; a file that
/// exists but does not parse is an error, so a typo never silently reverts
/// the model to the default.
pub fn loadSettings(arena: Allocator, io: Io, environ_map: *const std.process.Environ.Map) SettingsError!Settings {
    const path = (try settingsPath(arena, environ_map)) orelse return .{};
    const bytes = Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(1 << 16)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return .{},
    };
    const parsed = std.json.parseFromSliceLeaky(
        struct { model: ?[]const u8 = null },
        arena,
        bytes,
        .{ .ignore_unknown_fields = true },
    ) catch return error.SettingsInvalid;
    return .{ .model = parsed.model orelse default_model };
}
