const std = @import("std");

const ts = @import("tree-sitter");

const file_buffer = @import("file_buffer.zig");
const terminal = @import("terminal.zig");

extern fn tree_sitter_zig() callconv(.C) *ts.Language;

const UP_ARROW = [_]u8{ 27, 91, 65 };
const DOWN_ARROW = [_]u8{ 27, 91, 66 };
const RIGHT_ARROW = [_]u8{ 27, 91, 67 };
const LEFT_ARROW = [_]u8{ 27, 91, 68 };

pub fn main() !void {
    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();

    terminal.enableRawMode(stdin);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.skip();

    const filename = args.next() orelse "src/main.zig";

    var file_handle = try std.fs.cwd().openFile(filename, .{});
    defer file_handle.close();

    // TODO: decide a good datastructure for text editing
    // - just a sequence of bytes?
    // - lines?
    // - a rope? what is a rope???
    var file = blk: {
        const contents = try file_handle.readToEndAlloc(allocator, std.math.maxInt(usize));
        defer allocator.free(contents);
        break :blk try file_buffer.FileBuffer.init(allocator, contents);
    };
    defer file.deinit();

    // TODO: migrate references to this to instead read subsections from the file directly
    const contents = try file.toString(allocator);
    defer allocator.free(contents);

    const language = tree_sitter_zig();
    defer language.destroy();

    const parser = ts.Parser.create();
    defer parser.destroy();
    try parser.setLanguage(language);

    const tree: *ts.Tree = parser.parseString(contents, null) orelse {
        try stdout.writeAll("Failed to parse tree\r\n");
        return;
    };
    defer tree.destroy();

    var fontifyer = Fontifyer.init(allocator);
    defer fontifyer.deinit();

    var tree_walker = TreeWalker.init(tree);
    while (tree_walker.next()) |node| {
        const kind = node.kind();
        // std.debug.print("{s} -- {s}\r\n", .{ kind, contents[node.startByte()..node.endByte()] });

        if (std.mem.eql(u8, kind, "identifier")) {
            const is_attribute_call = blk: {
                const dot_node = node.prevSibling() orelse break :blk false;
                const parent_node = node.parent() orelse break :blk false;
                const paren_node = parent_node.nextSibling() orelse break :blk false;
                break :blk (std.mem.eql(u8, dot_node.kind(), ".") and std.mem.eql(u8, paren_node.kind(), "("));
            };

            const start_byte = node.startByte();
            const end_byte = node.endByte();
            const identifier = contents[start_byte..end_byte];

            var all_upper_case_letter: bool = true;
            var has_upper_case_letter: bool = false;
            for (identifier) |char| {
                if (char >= 'A' and char <= 'Z') {
                    has_upper_case_letter = true;
                } else if (char != '_') {
                    // '_' is used in constants,
                    // which is what this check is for.
                    all_upper_case_letter = false;
                }
            }

            if (all_upper_case_letter) {
                try fontifyer.addRegion(.{
                    .start = start_byte,
                    .end = end_byte,
                    .bytes = "\x1b[38;5;214m", // orange
                });
            } else if (is_attribute_call or has_upper_case_letter) {
                try fontifyer.addRegion(.{
                    .start = start_byte,
                    .end = end_byte,
                    .bytes = "\x1b[32m", // green
                });
            }
        }

        const symbols = [_][]const u8{
            "(",
            ")",
            ",",
            ".",
            "..",
            "?",
            "[",
            "]",
            "{",
            "}",
        };
        for (symbols) |symbol| {
            if (std.mem.eql(u8, kind, symbol)) {
                try fontifyer.addRegion(.{
                    .start = node.startByte(),
                    .end = node.endByte(),
                    .bytes = "\x1b[2m", // dim
                });
                break;
            }
        }

        const keywords = [_][]const u8{
            "*",
            "*=",
            "+",
            "+=",
            "-",
            "-=",
            "/",
            "/=",
            "<",
            "<=",
            "=",
            "==",
            ">",
            ">=",
            "and",
            "if",
            "continue",
            "while",
            "for",
            "break",
            "builtin_type",
            "const",
            "fn",
            "null",
            "return",
            "or",
            "orelse",
            "pub",
            "unreachable",
            "var",
            "return",
            "try",
        };
        for (keywords) |keyword| {
            if (std.mem.eql(u8, kind, keyword)) {
                try fontifyer.addRegion(.{
                    .start = node.startByte(),
                    .end = node.endByte(),
                    .bytes = "\x1b[31m", // red
                });
                break;
            }
        }

        if (std.mem.eql(u8, kind, "string")) {
            try fontifyer.addRegion(.{
                .start = node.startByte(),
                .end = node.endByte(),
                .bytes = "\x1b[33m", // yellow
            });
            continue;
        }

        const builtin_identifiers = [_][]const u8{
            "builtin_identifier",
            "defer",
        };
        for (builtin_identifiers) |builtin_identifier| {
            if (std.mem.eql(u8, kind, builtin_identifier)) {
                try fontifyer.addRegion(.{
                    .start = node.startByte(),
                    .end = node.endByte(),
                    .bytes = "\x1b[34m", // blue
                });
                break;
            }
        }

        if (std.mem.eql(u8, kind, "integer")) {
            try fontifyer.addRegion(.{
                .start = node.startByte(),
                .end = node.endByte(),
                .bytes = "\x1b[35m", // magenta
            });
            continue;
        }

        if (std.mem.eql(u8, kind, "comment")) {
            try fontifyer.addRegion(.{
                .start = node.startByte(),
                .end = node.endByte(),
                .bytes = "\x1b[90m", // bright black
            });
            continue;
        }
    }

    var buffered_writer = std.io.BufferedWriter(8192, std.fs.File.Writer){ .unbuffered_writer = stdout.writer() };

    var vertical_offset: usize = 0;
    var horizontal_offset: usize = 0;
    var buf: [8]u8 = undefined;
    while (true) {
        try writeAll(&buffered_writer, "\x1b[H");
        try renderContents(
            stdout,
            buffered_writer.writer(),
            &fontifyer,
            &file,
            vertical_offset,
            horizontal_offset,
        );
        try buffered_writer.flush();

        const size = try stdin.read(&buf);
        if (size == 0) {
            continue;
        }

        const buf_segment = buf[0..size];
        if (std.mem.eql(u8, buf_segment, &[_]u8{'q'})) {
            break;
        }

        if (std.mem.eql(u8, buf_segment, &UP_ARROW) and vertical_offset > 0) {
            vertical_offset -= 1;
        }
        if (std.mem.eql(u8, buf_segment, &DOWN_ARROW)) {
            const terminalSize = try terminal.getSize(stdout);
            if (vertical_offset < file.lineCount() - terminalSize.rows) {
                vertical_offset += 1;
            }
        }
        if (std.mem.eql(u8, buf_segment, &LEFT_ARROW) and horizontal_offset > 0) {
            horizontal_offset -= 1;
        }
        if (std.mem.eql(u8, buf_segment, &RIGHT_ARROW)) {
            const width = findWidth(contents);
            if (horizontal_offset < width) {
                horizontal_offset += 1;
            }
        }
    }
}

fn renderContents(
    stdout: std.fs.File,
    writer: anytype,
    fontifyer: *const Fontifyer,
    file: *const file_buffer.FileBuffer,
    vertical_offset: usize,
    horizontal_offset: usize,
) !void {
    const size = try terminal.getSize(stdout);

    // TODO: can we optimize this out by keeping track of it somewhere?
    var byte_offset: usize = 0;
    var file_line_iter = file.iterLines(0, vertical_offset);
    while (file_line_iter.next()) |line_content| {
        // Add `1` to the end, for the extra '\n' byte.
        byte_offset += line_content.len + 1;
    }

    var line: usize = 0;
    while (line < size.rows) {
        const line_content = file.lines.items[line + vertical_offset].items;
        const sliced_line_content = blk: {
            const start = @min(line_content.len, horizontal_offset);
            const end = @min(line_content.len, size.cols + horizontal_offset);
            break :blk line_content[start..end];
        };
        try fontifyer.render(
            writer,
            byte_offset + horizontal_offset,
            sliced_line_content,
        );
        try writeAll(writer, "\x1b[0J"); // erase the rest of the line
        if (line != size.rows - 1) {
            try writeAll(writer, "\r\n");
        }
        byte_offset += line_content.len + 1;
        line += 1;
    }
}

/// `TreeWalker` lets you walk the entirety of a TreeSitter tree
/// node-by-node in prefix order.
const TreeWalker = struct {
    const Self = @This();

    tree: *ts.Tree,
    cursor: ?ts.TreeCursor,
    depth: usize,

    pub fn init(tree: *ts.Tree) Self {
        return Self{
            .tree = tree,
            .cursor = tree.walk(),
            .depth = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.cursor.destroy();
    }

    pub fn next(self: *Self) ?ts.Node {
        var cursor = &(self.cursor orelse {
            return null;
        });

        const node = cursor.node();
        if (cursor.gotoFirstChild()) {
            self.depth += 1;
            return node;
        } else if (cursor.gotoNextSibling()) {
            return node;
        }

        while (true) {
            if (!cursor.gotoParent()) {
                self.cursor = null;
                break; // something else
            } else {
                self.depth -= 1;
            }

            if (cursor.gotoNextSibling()) {
                break;
            }
        }

        return node;
    }
};

const Fontifyer = struct {
    const Self = @This();

    font_regions: std.ArrayList(FontRegion),

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .font_regions = std.ArrayList(FontRegion).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.font_regions.deinit();
    }

    pub fn addRegion(self: *Self, region: FontRegion) !void {
        if (self.font_regions.items.len == 0) {
            try self.font_regions.append(region);
            return;
        }

        const last_font_region = &self.font_regions.items[self.font_regions.items.len - 1];
        if (last_font_region.end <= region.start) {
            try self.font_regions.append(region);
            return;
        }

        @panic("TODO: implement non-sorted insertion");
    }

    pub fn render(self: *const Self, writer: anytype, absolute_start: usize, contents: []const u8) !void {
        if (contents.len == 0) return;

        var first_relevant_region: ?usize = null;
        var last_relevant_region: ?usize = null;
        const content_start = absolute_start;
        const content_end = content_start + contents.len;

        var font_region_index: usize = 0;
        while (font_region_index < self.font_regions.items.len) {
            const font_region = self.font_regions.items[font_region_index];

            const is_before_content = font_region.end <= content_start;
            if (is_before_content) {
                font_region_index += 1;
                continue;
            }

            const is_after_content = font_region.start >= content_end;
            if (is_after_content) {
                break;
            }

            if (first_relevant_region == null) {
                first_relevant_region = font_region_index;
            }
            last_relevant_region = font_region_index;
            font_region_index += 1;
        }

        if (first_relevant_region == null or last_relevant_region == null) {
            // If there are no relevant font regions for this line,
            // just print it out and don't think too hard about it.
            try writeAll(writer, contents);
            return;
        }

        const start = first_relevant_region orelse unreachable;
        const end = (last_relevant_region orelse unreachable) + 1;
        var checkpoint: usize = 0;

        for (self.font_regions.items[start..end]) |font_region| {
            const fr_start = if (font_region.start > content_start)
                font_region.start - content_start
            else
                0;

            const fr_end = if (font_region.end < content_end)
                font_region.end - content_start
            else
                contents.len;

            if (fr_start > checkpoint) {
                try writeAll(writer, contents[checkpoint..fr_start]);
            }

            try writeAll(writer, font_region.bytes);
            try writeAll(writer, contents[fr_start..fr_end]);
            try writeAll(writer, "\x1b[0m");

            checkpoint = fr_end;
        }

        // Write any remaining content after the last font region
        if (checkpoint < contents.len) {
            try writeAll(writer, contents[checkpoint..]);
        }
    }
};

const FontRegion = struct {
    start: usize,
    end: usize,
    bytes: []const u8,
};

fn writeAll(writer: anytype, buf: []const u8) !void {
    var start: usize = 0;
    while (start < buf.len) {
        start += try writer.write(buf[start..buf.len]);
    }
}

fn findLength(contents: []const u8) usize {
    var length: usize = 0;
    for (contents) |char| {
        if (char == '\n') {
            length += 1;
        }
    }
    return length;
}

fn findWidth(contents: []const u8) usize {
    var width: usize = 0;
    var max_width: usize = 0;
    for (contents) |char| {
        if (char == '\n') {
            if (width > max_width) {
                max_width = width;
            }
            width = 0;
        } else {
            width += 1;
        }
    }

    // If the file doesn't end with a `\n`,
    // this lets us count the last line.
    if (width > max_width) {
        return width;
    }
    return max_width;
}
