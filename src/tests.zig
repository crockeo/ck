const rope = @import("rope.zig");

test "tests.zig" {
    // NOTE: This is load-bearing, and makes sure that all of our tests are run.
    @import("std").testing.refAllDecls(rope);
}
