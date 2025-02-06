const std = @import("std");

const D = struct {};
const K = struct {};

pub fn main() !void {
    // const n1: u32 = 1;

    std.debug.print("{any}", .{@typeInfo(D)});
}
