const std = @import("std");

const app = @import("argz");

const Command = app.Command;
const Option = app.Option;
const ValueType = app.ValueType;
const print = std.debug.print;

pub fn myRootCommand(c: *Command) anyerror!void {
    if (c.getOption("i")) |o| if (o.intValue()) |v| {
        print("value of int option: {d}\n", .{v});
    };
    if (c.getOption("s")) |o| if (o.stringValue()) |v| {
        print("value of string option: {s}\n", .{v});
    };
    if (c.getOption("b")) |o| if (o.boolValue()) |v| {
        print("value of boolean option: {}\n", .{v});
    };
    if (c.getFlag("f")) |o| if (o.boolValue()) |v| {
        print("value of flag: {}\n", .{v});
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const check = gpa.deinit();
        if (check == .leak) @panic("memory leaked");
    }
    var allocator = gpa.allocator();

    var root = Command{
        .allocator = allocator,
        .name = "root",
        .run = myRootCommand,
    };
    defer root.deinit();

    var intop = Option{
        .type = ValueType.int,
        .names = &.{ "int-option", "i" },
        .default = "10",
        .required = false,
    };
    var strop = Option{
        .type = ValueType.string,
        .names = &.{ "str-option", "s" },
        .default = "mystring",
        .required = false,
    };

    var boolop = Option{
        .type = ValueType.boolean,
        .names = &.{ "bool-option", "b" },
        .default = "true",
        .required = false,
    };

    var flag = Option{
        .is_flag = true,
        .names = &.{ "my-flag", "f" },
    };

    try root.addOptions(&.{ intop, strop, boolop, flag });

    try root.parseAndStart();
}
