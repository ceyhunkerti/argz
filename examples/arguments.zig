const std = @import("std");

const app = @import("argz");

const Command = app.Command;
const Option = app.Option;
const ValueType = app.ValueType;
const print = std.debug.print;

pub fn myRootCommand(c: *Command) anyerror!void {
    if (c.args) |args| for (args.items, 0..) |a, i|
        print("Argument {d}: {s}\n", .{ i, a });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const check = gpa.deinit();
        if (check == .leak) @panic("memory leaked");
    }
    var allocator = gpa.allocator();

    var root = Command{ .allocator = allocator, .name = "root", .run = myRootCommand, .nargs = "*" };
    defer root.deinit();

    try root.parseAndStart();
}
