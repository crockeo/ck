const std = @import("std");

const terminal = @import("terminal.zig");

pub fn main() !void {
    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();

    terminal.enableRawMode(stdin);

    try stdout.writeAll("hello world\r\n");
}
