const std = @import("std");

const BytesWriter = @import("bytes_writer.zig").BytesWriter;

pub const Rope = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    root: ?*RopeNode,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .root = null,
        };
    }

    pub fn deinit(self: *const Self) void {
        if (self.root) |root| {
            root.deinit();
            self.allocator.destroy(root);
        }
    }

    pub fn len(self: Self) usize {
        if (self.root) |root| {
            return root.len();
        }
        return 0;
    }

    pub fn insert(self: *Self, index: usize, str: []const u8) !void {
        if (str.len == 0) {
            return;
        }
        if (index > self.len()) {
            return error.IndexOutOfBounds;
        }

        const new_node = try RopeNode.initTree(self.allocator, str);
        errdefer new_node.deinit();

        if (self.root == null) {
            self.root = new_node;
            return;
        }

        if (index == 0) {
            self.root = try concat(self.allocator, new_node, self.root.?);
            return;
        }

        if (index == self.len()) {
            self.root = try concat(self.allocator, self.root.?, new_node);
            return;
        }

        var lhs: ?*RopeNode = null;
        var rhs: ?*RopeNode = null;
        try split(self.allocator, self.root.?, index, &lhs, &rhs);

        const tmp = try concat(self.allocator, lhs.?, new_node);
        self.root = try concat(self.allocator, tmp, rhs.?);
    }

    pub fn append(self: *Self, str: []const u8) !void {
        // TODO: track the length of the rope, so this goes faster?
        try self.insert(self.len(), str);
    }

    pub fn delete(self: *Self, start: usize, end: usize) !void {
        if (start >= end) {
            return;
        }
        if (end > self.len()) {
            return error.IndexOutOfBounds;
        }

        if (start == 0 and end == self.len()) {
            self.root.?.deinit();
            self.allocator.destroy(self.root.?);
            self.root = null;
        }

        var lhs: ?*RopeNode = null;
        var deleted_segment: ?*RopeNode = null;
        var rhs: ?*RopeNode = null;

        if (start > 0) {
            try split(self.allocator, self.root.?, start, &lhs, &deleted_segment);
        } else {
            deleted_segment = self.root;
        }

        if (end < self.len()) {
            try split(self.allocator, deleted_segment.?, end - start, &deleted_segment, &rhs);
        }

        if (deleted_segment) |ds| {
            ds.deinit();
            self.allocator.destroy(ds);
        }

        self.root = try concat(self.allocator, lhs, rhs);
    }

    pub fn writeAll(self: *const Self, writer: anytype) !void {
        if (self.root) |root| {
            try root.writeAll(writer);
        }
    }

    pub fn toString(self: *const Self, allocator: std.mem.Allocator) ![]const u8 {
        var bytes_writer = BytesWriter.init(allocator);
        try self.writeAll(bytes_writer.writer());
        return try bytes_writer.toOwnedSlice();
    }
};

const RopeNode = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    content: union(enum) {
        node: struct {
            lhs_size: usize,
            lhs: ?*RopeNode,
            rhs: ?*RopeNode,
        },
        leaf: struct {
            buf: [64]u8,
            len: usize,
        },
    },

    fn initNode(allocator: std.mem.Allocator, lhs: ?*RopeNode, rhs: ?*RopeNode) !*RopeNode {
        var lhs_size: usize = 0;
        if (lhs) |bound_lhs| {
            lhs_size = bound_lhs.len();
        }
        const rope_node = try allocator.create(RopeNode);
        rope_node.* = .{
            .allocator = allocator,
            .content = .{
                .node = .{
                    .lhs_size = lhs_size,
                    .lhs = lhs,
                    .rhs = rhs,
                },
            },
        };
        return rope_node;
    }

    fn initLeaf(allocator: std.mem.Allocator, contents: []const u8) !*RopeNode {
        const rope_node = try allocator.create(RopeNode);
        rope_node.* = .{
            .allocator = allocator,
            .content = .{
                .leaf = .{
                    .buf = undefined,
                    .len = contents.len,
                },
            },
        };
        std.mem.copyForwards(u8, &rope_node.content.leaf.buf, contents);
        return rope_node;
    }

    fn initTree(allocator: std.mem.Allocator, contents: []const u8) !*RopeNode {
        if (contents.len <= 32) {
            return try initLeaf(allocator, contents);
        }
        const mid = contents.len / 2;
        const lhs = try initTree(allocator, contents[0..mid]);
        const rhs = try initTree(allocator, contents[mid..contents.len]);
        return initNode(allocator, lhs, rhs);
    }

    fn deinit(self: *const Self) void {
        switch (self.content) {
            .node => |node| {
                if (node.lhs) |lhs| {
                    lhs.deinit();
                    self.allocator.destroy(lhs);
                }
                if (node.rhs) |rhs| {
                    rhs.deinit();
                    self.allocator.destroy(rhs);
                }
            },
            else => {},
        }
    }

    fn len(self: *const Self) usize {
        switch (self.content) {
            .node => |node| {
                var length: usize = node.lhs_size;
                if (node.rhs) |rhs| {
                    length += rhs.len();
                }
                return length;
            },
            .leaf => |leaf| {
                return leaf.len;
            },
        }
    }

    fn writeAll(self: *const Self, writer: anytype) !void {
        switch (self.content) {
            .node => |node| {
                if (node.lhs) |lhs| {
                    try lhs.writeAll(writer);
                }
                if (node.rhs) |rhs| {
                    try rhs.writeAll(writer);
                }
            },
            .leaf => |leaf| {
                try writer.writeAll(leaf.buf[0..leaf.len]);
            },
        }
    }
};

fn concat(allocator: std.mem.Allocator, lhs: ?*RopeNode, rhs: ?*RopeNode) !?*RopeNode {
    if (lhs == null) return rhs;
    if (rhs == null) return lhs;
    const node = try RopeNode.initNode(allocator, lhs, rhs);
    return balance(allocator, node);
}

fn balance(allocator: std.mem.Allocator, node: *RopeNode) !*RopeNode {
    _ = allocator;
    return node;
    // // Balance the tree
    // fn balance(allocator: std.mem.Allocator, node: *Node) !*Node {
    //     if (node.isLeaf) return node;

    //     const left_height: isize = if (node.data.internal.left) |left| @intCast(left.height) else 0;
    //     const right_height: isize = if (node.data.internal.right) |right| @intCast(right.height) else 0;
    //     const balance_factor = left_height - right_height;

    //     // Tree is balanced
    //     if (balance_factor >= -1 and balance_factor <= 1) {
    //         return node;
    //     }

    //     if (balance_factor > 1) {
    //         // Left heavy - rotate right
    //         const left = node.data.internal.left;
    //         const right = node.data.internal.right;

    //         // Create new root with left's left child and a new node from left's right child and original right
    //         const new_right = try concat(allocator, left.data.internal.right, right);
    //         const new_root = try concat(allocator, left.data.internal.left, new_right);

    //         allocator.destroy(node);
    //         return new_root;
    //     } else {
    //         // Right heavy - rotate left
    //         const left = node.data.internal.left;
    //         const right = node.data.internal.right;

    //         // Create new root with a new node from original left and right's left child, and right's right child
    //         const new_left = try concat(allocator, left, right.data.internal.left);
    //         const new_root = try concat(allocator, new_left, right.data.internal.right);

    //         allocator.destroy(node);
    //         return new_root;
    //     }
    // }
}

fn split(
    allocator: std.mem.Allocator,
    node: *RopeNode,
    index: usize,
    left: *?*RopeNode,
    right: *?*RopeNode,
) !void {
    if (index == 0) {
        left.* = null;
        right.* = node;
    }

    if (index == node.len()) {
        left.* = node;
        right.* = null;
    }

    switch (node.content) {
        .node => |subnode| {
            var tmp_lhs: ?*RopeNode = null;
            var tmp_rhs: ?*RopeNode = null;
            if (index < subnode.lhs_size) {
                try split(allocator, subnode.lhs.?, index, &tmp_lhs, &tmp_rhs);
                left.* = tmp_lhs;
                right.* = try concat(allocator, tmp_rhs, subnode.rhs);
            } else {
                try split(allocator, subnode.rhs.?, index - subnode.lhs_size, &tmp_lhs, &tmp_rhs);
                left.* = try concat(allocator, subnode.lhs, tmp_lhs);
                right.* = tmp_rhs;
            }
        },
        .leaf => |leaf| {
            const left_segment = leaf.buf[0..index];
            const right_segment = leaf.buf[index..leaf.len];
            left.* = try RopeNode.initLeaf(allocator, left_segment);
            right.* = try RopeNode.initLeaf(allocator, right_segment);
        },
    }
}

test "Rope full test suite" {
    // Run all Rope tests
    std.testing.refAllDecls(Rope);
}

test "insert into rope" {
    const allocator = std.heap.page_allocator;
    var rope = Rope.init(allocator);
    defer rope.deinit();

    try rope.append("hello world");

    const contents = try rope.toString(allocator);
    defer allocator.free(contents);

    try std.testing.expectEqualSlices(u8, "hello world", contents);
}

test "build up text in rope" {
    const allocator = std.heap.page_allocator;
    var rope = Rope.init(allocator);
    defer rope.deinit();

    try rope.append("hello");
    try rope.append(" world");

    const contents = try rope.toString(allocator);
    defer allocator.free(contents);

    try std.testing.expectEqualSlices(u8, "hello world", contents);
}

test "insert into the middle" {
    const allocator = std.heap.page_allocator;
    var rope = Rope.init(allocator);
    defer rope.deinit();

    try rope.append("hello world");
    try rope.insert(5, ", cruel");

    const contents = try rope.toString(allocator);
    defer allocator.free(contents);

    try std.testing.expectEqualSlices(u8, "hello, cruel world", contents);
}

test "insert / delete / whatnot" {
    const allocator = std.heap.page_allocator;
    var rope = Rope.init(allocator);
    defer rope.deinit();

    try rope.append("hello world");
    try rope.insert(5, ", cruel"); // add `, cruel` b/t `hello` and `world`
    try rope.delete(13, 18); // delete `world`
    try rope.append("enemy"); // add `enemy`

    const contents = try rope.toString(allocator);
    defer allocator.free(contents);

    try std.testing.expectEqualSlices(u8, "hello, cruel enemy", contents);
}
