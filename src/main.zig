const std = @import("std");

const terminal = @import("terminal.zig");

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

    try renderContents(stdout, contents);
}

fn renderContents(stdout: std.fs.File, contents: []const u8) !void {
    var start: usize = 0;
    var end: usize = 0;
    while (end < contents.len) {
        if (contents[end] == '\n') {
            try stdout.writeAll(contents[start..end]);
            try stdout.writeAll("\r\n");
            end += 1;
            start = end;
        }
        end += 1;
    }
}
