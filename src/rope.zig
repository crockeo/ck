const std = @import("std");

pub const Rope = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    lhs: ?*Rope,
    rhs: ?*Rope,
    element: RopeElement,

    pub fn init(allocator: std.mem.Allocator) !Self {
        return .{
            .allocator = allocator,
            .lhs = null,
            .rhs = null,
            .element = .{ .lhs_size = 0 },
        };
    }

    pub fn deinit(self: *const Self) void {
        if (self.lhs) |lhs| {
            lhs.deinit();
            self.allocator.destroy(lhs);
        }
        if (self.rhs) |rhs| {
            rhs.deinit();
            self.allocator.destroy(rhs);
        }
    }

    pub fn len(self: *const Self) usize {
        var length: usize = 0;
        switch (self.element) {
            .lhs_size => |lhs_size| length += lhs_size,
            // TODO: this isn't quite right. we don't always take all 32 bytes.
            .contents => |contents| length += contents.len,
        }
        if (self.rhs) |rhs| {
            length += rhs.len();
        }
        return length;
    }

    pub fn insert(self: *Self, index: usize, _: []const u8) !void {
        if (index == 0) {
            // TODO: special-case prepending
            return;
        }

        if (index == self.len()) {
            // TODO: special-case appending
            return;
        }
    }
};

const RopeElement = union(enum) {
    lhs_size: usize,
    contents: [32]u8,
};

test "create rope" {
    const allocator = std.heap.page_allocator;
    const rope = try Rope.init(allocator);
    defer rope.deinit();
}

test "empty rope" {
    const allocator = std.heap.page_allocator;
    const rope = try Rope.init(allocator);
    defer rope.deinit();
    try std.testing.expectEqual(0, rope.len());
}

test "non-empty rope" {
    const allocator = std.heap.page_allocator;
    var rope = try Rope.init(allocator);
    defer rope.deinit();
    try rope.insert(0, "hello");
    try std.testing.expectEqual(5, rope.len());
}
