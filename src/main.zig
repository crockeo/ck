const std = @import("std");

const ts = @import("tree-sitter");

const terminal = @import("terminal.zig");

extern fn tree_sitter_zig() callconv(.C) *ts.Language;

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

    var file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
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

        // TODO: figure out how to do coloring for things which are not _just_ their own object
        // thinking like:
        // - identifiers which start with a capital letter
        // - identifiers which are function invocations

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

        if (std.mem.eql(u8, kind, "builtin_identifier")) {
            try fontifyer.addRegion(.{
                .start = node.startByte(),
                .end = node.endByte(),
                .bytes = "\x1b[34m", // blue
            });
            continue;
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

    // NOTE to self, next steps:
    // - take the tree walker to build up "font regions"
    //   - these should just be segments of byte ranges and associated styles
    //   - for now: this is just going to be colors
    // - provide these font ranges into `renderContents`
    // - each time we print a line in `renderContents`,
    //   actually call a `renderLine` function,
    //   which also takes the font regions
    //   - write out segments of the line until you get to a font boundary
    //   - print the special characters the font region tells you to print
    //     - either the thing to enter the region if it's an enter
    //     - or the thing to return to the original value if it's an exit
    //     - this should _probably_ be a stack, but not super relevant for now
    //   - and then continue on!

    // const cursor = tree.walk();
    // defer cursor.destroy();

    // std.debug.print("{}\n", .{tree});

    // parser.parse(.{
    //     .payload = @ptrCast(contents),
    //     .read = null,
    // }, null);

    var buf: [1]u8 = undefined;
    while (true) {
        try stdout.writeAll("\x1b[H");
        try renderContents(stdout, &fontifyer, contents);

        _ = try stdin.read(&buf);
        if (buf[0] == 'q') {
            break;
        }
    }
}

// NOTE: Keeping this around, even though we're not using it,
// because it will be useful when we have to fontify a file.
//
// const Contents = struct {
//     const Self = @This();

//     contents: []const u8,
//     read_buf: [1024]u8,

//     fn init(contents: []const u8) Self {
//         return Self{
//             .contents = contents,
//             .read_buf = undefined,
//         };
//     }

//     export fn readContent(payload: ?*anyopaque, byte_index: u32, position: tree_sitter.Point, bytes_read: *u32) [*c]const u8 {
//         const verifiedPayload = payload orelse {
//             @panic("Contents.readContent called w/o valid payload.");
//         };
//         var self: *Self = @ptrCast(verifiedPayload);
//         return self.readContentInner(byte_index, position, bytes_read);
//     }

//     fn readContentInner(self: *Self, byte_index: u32, position: tree_sitter.Point, bytes_read: *u32) [*c]const u8 {
//         @panic("TODO!");
//     }
// };

fn renderContents(stdout: std.fs.File, fontifyer: *const Fontifyer, contents: []const u8) !void {
    const size = try terminal.getSize(stdout);

    var start: usize = 0;
    var end: usize = 0;
    var line: usize = 0;
    while (end < contents.len and line < size.rows) {
        if (contents[end] == '\n') {
            const width = end - start;
            const truncatedEnd = start + @min(size.cols, width);

            try fontifyer.render(stdout, start, contents[start..truncatedEnd]);
            try stdout.writeAll("\x1b[0J"); // erase the rest of the line
            if (line != size.rows - 1) {
                try stdout.writeAll("\r\n");
            }
            end += 1;
            start = end;
            line += 1;
            continue;
        }
        end += 1;
    }
}

/// `TreeWalker` lets you walk the entirety of a TreeSitter tree
/// node-by-node in prefix order.
const TreeWalker = struct {
    const Self = @This();

    tree: *ts.Tree,
    cursor: ?ts.TreeCursor,

    pub fn init(tree: *ts.Tree) Self {
        return Self{
            .tree = tree,
            .cursor = tree.walk(),
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
        if (cursor.gotoFirstChild() or cursor.gotoNextSibling()) {
            return node;
        }

        while (true) {
            if (!cursor.gotoParent()) {
                self.cursor = null;
                break; // something else
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

    pub fn render(self: *const Self, stdout: std.fs.File, offset: usize, contents: []const u8) !void {
        var first_relevant_region: ?usize = null;
        var last_relevant_region: ?usize = null;

        var font_region_index: usize = 0;
        while (font_region_index < self.font_regions.items.len) {
            const font_region = self.font_regions.items[font_region_index];

            const is_before_content = font_region.end < offset;
            if (is_before_content) {
                font_region_index += 1;
                continue;
            }

            const is_after_content = font_region.start >= offset + contents.len;
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
            // If there are not relevant font regions for this line,
            // just print it out and don't think too hard about it.
            try stdout.writeAll(contents);
            return;
        }

        // TODO: fix this for font regions which exceed the end of contents.

        const start = first_relevant_region orelse unreachable;
        const end = last_relevant_region orelse unreachable;
        var checkpoint: usize = 0;
        for (self.font_regions.items[start .. end + 1]) |font_region| {
            try stdout.writeAll(contents[checkpoint .. font_region.start - offset]);
            try stdout.writeAll(font_region.bytes);

            const segment_end = @min(contents.len, font_region.end - offset);
            try stdout.writeAll(contents[font_region.start - offset .. segment_end]);
            try stdout.writeAll("\x1b[0m");
            checkpoint = segment_end;
        }
        try stdout.writeAll(contents[checkpoint..contents.len]);
    }
};

const FontRegion = struct {
    start: usize,
    end: usize,
    bytes: []const u8,
};
