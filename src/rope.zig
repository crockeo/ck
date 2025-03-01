const std = @import("std");

pub const Rope = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    root: *RopeNode,

    pub fn init(allocator: std.mem.Allocator) !Self {
        return .{
            .allocator = allocator,
            .root = try RopeNode.initNode(allocator, null, null),
        };
    }

    pub fn deinit(self: *const Self) void {
        self.root.deinit();
        self.allocator.destroy(self.root);
    }

    pub fn len(self: *const Self) usize {
        return self.root.len();
    }

    pub fn printAll(self: *const Self, writer: std.io.AnyWriter) !void {
        if (self.lhs) |lhs| {
            try lhs.printAll(writer);
        }
        if (self.element.contents) |contents| {
            try writer.writeAll(contents[0..contents.len]);
        }
        if (self.rhs) |rhs| {
            try rhs.printAll(writer);
        }
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

const RopeNode = struct {
    allocator: std.mem.Allocator,
    lhs: ?*RopeNode,
    rhs: ?*RopeNode,
    element: RopeElement,

    fn initNode(allocator: std.mem.Allocator, lhs: ?*RopeNode, rhs: ?*RopeNode) !*RopeNode {
        var lhs_size: usize = 0;
        if (lhs) |bound_lhs| {
            lhs_size = bound_lhs.len();
        }
        const rope_node = try allocator.create(RopeNode);
        rope_node.* = .{
            .allocator = allocator,
            .lhs = lhs,
            .rhs = rhs,
            .element = .{ .lhs_size = lhs_size },
        };
        return rope_node;
    }

    fn initLeaf(allocator: std.mem.Allocator, contents: []const u8) !*RopeNode {
        var element_contents = RopeElementContents{
            .buf = undefined,
            .len = contents.len,
        };
        std.mem.copyForwards(u8, &element_contents.buf, contents);

        const rope_node = try allocator.create(RopeNode);
        rope_node.* = .{
            .allocator = allocator,
            .lhs = null,
            .rhs = null,
            .element = .{ .contents = element_contents },
        };
        return rope_node;
    }

    fn deinit(self: *const RopeNode) void {
        if (self.lhs) |lhs| {
            lhs.deinit();
            self.allocator.destroy(lhs);
        }
        if (self.rhs) |rhs| {
            rhs.deinit();
            self.allocator.destroy(rhs);
        }
    }

    fn len(self: *const RopeNode) usize {
        switch (self.element) {
            .lhs_size => |lhs_size| {
                const rhs_size = blk: {
                    if (self.rhs) |rhs| {
                        break :blk rhs.len();
                    } else {
                        break :blk 0;
                    }
                };
                return lhs_size + rhs_size;
            },
            .contents => |contents| {
                // If we have string contents this must be a leaf node,
                // so just return the length here.
                return contents.len;
            },
        }
    }
};

const RopeElement = union(enum) {
    lhs_size: usize,
    contents: RopeElementContents,
};

const RopeElementContents = struct {
    buf: [32]u8,
    len: usize,
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
