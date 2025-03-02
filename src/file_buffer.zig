const std = @import("std");

const Line = std.ArrayList(u8);
const Lines = std.ArrayList(Line);

pub const FileBuffer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    lines: Lines,

    pub fn init(allocator: std.mem.Allocator, contents: []const u8) !Self {
        var lines = Lines.init(allocator);
        var start: usize = 0;
        var end: usize = 0;
        while (end < contents.len) {
            if (contents[end] == '\n') {
                var line = try Line.initCapacity(allocator, end - start);
                try line.appendSlice(contents[start..end]);
                try lines.append(line);
                end += 1;
                start = end;
                continue;
            }

            end += 1;
        }
        return .{
            .allocator = allocator,
            .lines = lines,
        };
    }

    pub fn deinit(self: Self) void {
        for (self.lines.items) |line| {
            line.deinit();
        }
        self.lines.deinit();
    }

    pub fn iterLines(self: Self, start_line: usize, end_line: usize) FileBufferLineIterator {
        return .{
            .file_buffer = self,
            .index = start_line,
            .end_line = end_line,
        };
    }

    pub fn lineCount(self: Self) usize {
        return self.lines.items.len;
    }

    pub fn toString(self: Self, allocator: std.mem.Allocator) ![]const u8 {
        var buf = std.ArrayList(u8).init(allocator);
        for (self.lines.items) |line| {
            try buf.appendSlice(line.items);
            try buf.append('\n');
        }
        return try buf.toOwnedSlice();
    }
};

pub const FileBufferLineIterator = struct {
    const Self = @This();

    file_buffer: FileBuffer,
    index: usize,
    end_line: usize,

    pub fn next(self: *Self) ?[]const u8 {
        if (self.index == self.end_line or self.index == self.file_buffer.lines.items.len) {
            return null;
        }
        const line = self.file_buffer.lines.items[self.index];
        self.index += 1;
        return line.items;
    }
};

test "file_buffer full test suite" {
    std.testing.refAllDecls(@This());
}
