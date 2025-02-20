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

    const filename = args.next() orelse {
        try stdout.writeAll("Must provide filename\r\n");
        return;
    };

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

    const node = tree.rootNode();
    std.debug.print("{s}\n", .{node.kind()});

    // const cursor = tree.walk();
    // defer cursor.destroy();

    // std.debug.print("{}\n", .{tree});

    // parser.parse(.{
    //     .payload = @ptrCast(contents),
    //     .read = null,
    // }, null);

    // try renderContents(stdout, contents);
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

fn renderContents(stdout: std.fs.File, contents: []const u8) !void {
    const size = try terminal.getSize(stdout);

    var start: usize = 0;
    var end: usize = 0;
    while (end < contents.len) {
        if (contents[end] == '\n') {
            const width = end - start;
            const truncatedEnd = start + @min(size.cols + 1, width);

            try stdout.writeAll(contents[start..truncatedEnd]);
            try stdout.writeAll("\r\n");
            end += 1;
            start = end;
        }
        end += 1;
    }
}
