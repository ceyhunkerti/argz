const std = @import("std");

const testing = std.testing;

pub fn contains(comptime T: type, items: []const T, item: T) bool {
    switch (T) {
        []const u8 => for (items) |it| if (std.mem.eql(u8, it, item)) return true,
        else => for (items) |it| return it == item,
    }
    return false;
}

pub fn hasDuplicate(comptime T: type, items: T) bool {
    switch (T) {
        [][]const u8 => {
            for (items, 0..) |a, i| if (i != items.len and contains([]const u8, items[i + 1 ..], a)) {
                return true;
            };
        },
        [][][]const u8 => {
            for (items, 0..) |aa, i| {
                if (hasDuplicate([][]const u8, aa)) return true;
                if (i != items.len - 1) for (aa) |a| for (items[i + 1 ..]) |next|
                    if (contains([]const u8, next, a)) return true;
            }
        },
        else => return false,
    }
    return false;
}

test "contains" {
    try testing.expectEqual(true, contains([]const u8, &[_][]const u8{ "a", "b" }, "a"));
    try testing.expectEqual(false, contains([]const u8, &[_][]const u8{ "a", "b" }, "x"));
    try testing.expectEqual(true, contains(u8, &[_]u8{ 1, 2, 3 }, 1));
    try testing.expectEqual(false, contains(u8, &[_]u8{ 1, 2, 3 }, 10));
    try testing.expectEqual(true, contains([]const u8, &[_][]const u8{ "a", "b", "c", "a" }, "a"));
}

test "hasDuplicate" {
    var d1_unq1 = [_][]const u8{ "a", "b", "c" };
    try testing.expectEqual(false, hasDuplicate([][]const u8, &d1_unq1));

    var d1_dup1 = [_][]const u8{ "a", "b", "c", "a" };
    try testing.expectEqual(true, hasDuplicate([][]const u8, &d1_dup1));

    var d2_dup2 = [_][][]const u8{ &d1_unq1, &d1_dup1 };
    try testing.expectEqual(true, hasDuplicate([][][]const u8, &d2_dup2));

    var d2_dup3 = [_][][]const u8{&d1_dup1};
    try testing.expectEqual(true, hasDuplicate([][][]const u8, &d2_dup3));

    var d1_unq2 = [_][]const u8{ "x", "y", "z" };

    var d2_unq3 = [_][][]const u8{ &d1_unq1, &d1_unq2 };
    try testing.expectEqual(false, hasDuplicate([][][]const u8, &d2_unq3));
}
