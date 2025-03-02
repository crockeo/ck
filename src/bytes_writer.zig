const std = @import("std");

pub const BytesWriter = struct {
    const Self = @This();

    const Error = std.mem.Allocator.Error;
    const Writer = std.io.GenericWriter(*Self, Self.Error, Self.write);

    buf: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .buf = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.buf.deinit();
    }

    pub fn write(self: *Self, data: []const u8) Self.Error!usize {
        try self.buf.appendSlice(data);
        return data.len;
    }

    pub fn writer(self: *Self) Self.Writer {
        return .{ .context = self };
    }

    pub fn toOwnedSlice(self: *Self) Self.Error![]const u8 {
        return self.buf.toOwnedSlice();
    }

    pub fn format(self: *Self, comptime fmt: []const u8, args: anytype) Self.Error!void {
        try std.fmt.format(self.writer(), fmt, args);
    }
};
