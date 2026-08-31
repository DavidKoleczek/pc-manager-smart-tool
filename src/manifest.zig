//! Manifest: the packaged SMART_TOOL.md read back as structured data.
const std = @import("std");
const Allocator = std.mem.Allocator;

const raw_manifest = @embedFile("SMART_TOOL.md");

pub const Requirement = struct {
    name: []const u8,
    purpose: []const u8,
    install: []const u8,
    optional: bool = false,
};

pub const Manifest = struct {
    arena: *std.heap.ArenaAllocator,
    smart_tool_format: u32,
    name: []const u8,
    version: []const u8,
    description: []const u8,
    use_cases: []const []const u8,
    platforms: []const []const u8,
    requires: []const Requirement,

    pub fn deinit(m: Manifest) void {
        const gpa = m.arena.child_allocator;
        m.arena.deinit();
        gpa.destroy(m.arena);
    }

    pub fn jsonStringify(m: Manifest, s: *std.json.Stringify) !void {
        try s.beginObject();
        try s.objectField("smart_tool_format");
        try s.write(m.smart_tool_format);
        try s.objectField("name");
        try s.write(m.name);
        try s.objectField("version");
        try s.write(m.version);
        try s.objectField("description");
        try s.write(m.description);
        try s.objectField("use_cases");
        try s.write(m.use_cases);
        try s.objectField("platforms");
        try s.write(m.platforms);
        try s.objectField("requires");
        try s.write(m.requires);
        try s.endObject();
    }
};

pub const LoadManifestError = error{ OutOfMemory, ManifestInvalid };

/// Parses the frontmatter of the SMART_TOOL.md embedded in this library, so
/// the manifest is readable after installation without locating the file.
pub fn loadManifest(gpa: Allocator) LoadManifestError!Manifest {
    const arena_ptr = try gpa.create(std.heap.ArenaAllocator);
    errdefer gpa.destroy(arena_ptr);
    arena_ptr.* = .init(gpa);
    errdefer arena_ptr.deinit();

    var m = try parseFrontmatter(arena_ptr.allocator(), try frontmatterOf(raw_manifest));
    m.arena = arena_ptr;
    return m;
}

fn frontmatterOf(text: []const u8) error{ManifestInvalid}![]const u8 {
    const open = "---\n";
    const start: usize = if (std.mem.startsWith(u8, text, open))
        open.len
    else if (std.mem.startsWith(u8, text, "---\r\n"))
        "---\r\n".len
    else
        return error.ManifestInvalid;
    const close = std.mem.indexOfPos(u8, text, start, "\n---") orelse return error.ManifestInvalid;
    return text[start..close];
}

// The frontmatter subset used by SMART_TOOL.md: top-level scalars, folded
// scalars (`>`), lists of strings, and a list of flat mappings. Anything
// outside that subset is ManifestInvalid rather than silently misread.
fn parseFrontmatter(arena: Allocator, frontmatter: []const u8) LoadManifestError!Manifest {
    var line_list: std.ArrayList([]const u8) = .empty;
    var line_it = std.mem.splitScalar(u8, frontmatter, '\n');
    while (line_it.next()) |line| {
        try line_list.append(arena, std.mem.trimEnd(u8, line, "\r"));
    }
    const lines = line_list.items;

    var smart_tool_format: ?u32 = null;
    var name: ?[]const u8 = null;
    var version: ?[]const u8 = null;
    var description: ?[]const u8 = null;
    var use_cases: ?[]const []const u8 = null;
    var platforms: ?[]const []const u8 = null;
    var requires: []const Requirement = &.{};

    var i: usize = 0;
    while (i < lines.len) {
        const line = lines[i];
        if (isBlank(line)) {
            i += 1;
            continue;
        }
        if (indentOf(line) != 0) return error.ManifestInvalid;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse return error.ManifestInvalid;
        const key = line[0..colon];
        const rest = std.mem.trim(u8, line[colon + 1 ..], " ");
        i += 1;
        if (std.mem.eql(u8, key, "smart_tool_format")) {
            smart_tool_format = std.fmt.parseInt(u32, rest, 10) catch return error.ManifestInvalid;
        } else if (std.mem.eql(u8, key, "name")) {
            name = try scalar(arena, lines, &i, rest, 0);
        } else if (std.mem.eql(u8, key, "version")) {
            version = try scalar(arena, lines, &i, rest, 0);
        } else if (std.mem.eql(u8, key, "description")) {
            description = try scalar(arena, lines, &i, rest, 0);
        } else if (std.mem.eql(u8, key, "use_cases")) {
            use_cases = try stringList(arena, lines, &i);
        } else if (std.mem.eql(u8, key, "platforms")) {
            platforms = try stringList(arena, lines, &i);
        } else if (std.mem.eql(u8, key, "requires")) {
            requires = try requirementList(arena, lines, &i);
        } else {
            return error.ManifestInvalid;
        }
    }

    return .{
        .arena = undefined,
        .smart_tool_format = smart_tool_format orelse return error.ManifestInvalid,
        .name = name orelse return error.ManifestInvalid,
        .version = version orelse return error.ManifestInvalid,
        .description = description orelse return error.ManifestInvalid,
        .use_cases = use_cases orelse return error.ManifestInvalid,
        .platforms = platforms orelse return error.ManifestInvalid,
        .requires = requires,
    };
}

fn indentOf(line: []const u8) usize {
    for (line, 0..) |c, i| {
        if (c != ' ') return i;
    }
    return line.len;
}

fn isBlank(line: []const u8) bool {
    return std.mem.trim(u8, line, " ").len == 0;
}

fn scalar(arena: Allocator, lines: []const []const u8, i: *usize, rest: []const u8, key_indent: usize) LoadManifestError![]const u8 {
    if (std.mem.eql(u8, rest, ">") or std.mem.eql(u8, rest, ">-")) {
        return folded(arena, lines, i, key_indent);
    }
    return arena.dupe(u8, rest);
}

fn folded(arena: Allocator, lines: []const []const u8, i: *usize, key_indent: usize) LoadManifestError![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    while (i.* < lines.len) {
        const line = lines[i.*];
        if (isBlank(line)) break;
        if (indentOf(line) <= key_indent) break;
        if (out.items.len != 0) try out.append(arena, ' ');
        try out.appendSlice(arena, std.mem.trim(u8, line, " "));
        i.* += 1;
    }
    if (out.items.len == 0) return error.ManifestInvalid;
    return out.toOwnedSlice(arena);
}

fn stringList(arena: Allocator, lines: []const []const u8, i: *usize) LoadManifestError![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    while (i.* < lines.len) {
        const line = lines[i.*];
        if (isBlank(line) or indentOf(line) == 0) break;
        const item = std.mem.trim(u8, line, " ");
        if (!std.mem.startsWith(u8, item, "- ")) return error.ManifestInvalid;
        try out.append(arena, try arena.dupe(u8, item[2..]));
        i.* += 1;
    }
    return out.toOwnedSlice(arena);
}

fn requirementList(arena: Allocator, lines: []const []const u8, i: *usize) LoadManifestError![]const Requirement {
    var out: std.ArrayList(Requirement) = .empty;
    while (i.* < lines.len) {
        const line = lines[i.*];
        if (isBlank(line) or indentOf(line) == 0) break;
        const item_indent = indentOf(line);
        const dash = std.mem.trim(u8, line, " ");
        if (!std.mem.startsWith(u8, dash, "- ")) return error.ManifestInvalid;

        var req_name: ?[]const u8 = null;
        var purpose: ?[]const u8 = null;
        var install: ?[]const u8 = null;
        var optional = false;

        // The first field rides on the dash line; the rest are indented under it.
        const key_indent = item_indent + 2;
        var key_line = dash[2..];
        i.* += 1;
        while (true) {
            const colon = std.mem.indexOfScalar(u8, key_line, ':') orelse return error.ManifestInvalid;
            const key = key_line[0..colon];
            const rest = std.mem.trim(u8, key_line[colon + 1 ..], " ");
            if (std.mem.eql(u8, key, "name")) {
                req_name = try scalar(arena, lines, i, rest, key_indent);
            } else if (std.mem.eql(u8, key, "purpose")) {
                purpose = try scalar(arena, lines, i, rest, key_indent);
            } else if (std.mem.eql(u8, key, "install")) {
                install = try scalar(arena, lines, i, rest, key_indent);
            } else if (std.mem.eql(u8, key, "optional")) {
                optional = std.mem.eql(u8, rest, "true");
            } else {
                return error.ManifestInvalid;
            }
            if (i.* >= lines.len) break;
            const next = lines[i.*];
            if (isBlank(next) or indentOf(next) != key_indent) break;
            key_line = std.mem.trim(u8, next, " ");
            i.* += 1;
        }

        try out.append(arena, .{
            .name = req_name orelse return error.ManifestInvalid,
            .purpose = purpose orelse return error.ManifestInvalid,
            .install = install orelse return error.ManifestInvalid,
            .optional = optional,
        });
    }
    return out.toOwnedSlice(arena);
}

test "loadManifest parses the packaged SMART_TOOL.md" {
    const m = try loadManifest(std.testing.allocator);
    defer m.deinit();
    try std.testing.expectEqual(@as(u32, 1), m.smart_tool_format);
    try std.testing.expectEqualStrings("pc-manager", m.name);
    try std.testing.expectEqualStrings("0.1.0", m.version);
    try std.testing.expect(m.description.len > 0);
    try std.testing.expect(std.mem.indexOfScalar(u8, m.description, '\n') == null);
    try std.testing.expectEqual(@as(usize, 3), m.use_cases.len);
    try std.testing.expectEqual(@as(usize, 2), m.platforms.len);
    try std.testing.expectEqual(@as(usize, 1), m.requires.len);
    try std.testing.expectEqualStrings("claude-code", m.requires[0].name);
    try std.testing.expect(m.requires[0].optional);
}
