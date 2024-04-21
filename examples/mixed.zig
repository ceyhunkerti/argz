const std = @import("std");

const lib = @import("argz");

const Command = lib.Command;
const Option = lib.Option;
const ValueType = lib.ValueType;

const Error = error{
    GenericError,
};

fn fatal(comptime fmt_string: []const u8, args: anytype) noreturn {
    const stderr = std.io.getStdErr().writer();
    stderr.print("error: " ++ fmt_string ++ "\n", args) catch {};
    std.os.exit(1);
}

pub fn runRoot(c: *Command) anyerror!void {
    const int_option = c.getOption("i");
    if (int_option) |io| {
        std.debug.print("@root: the value of the option 'i' is {d}\n", .{io.intValue().?});
    } else {
        fatal("failed to find option 'i'", .{});
    }
}

pub fn runSub1(c: *Command) anyerror!void {
    std.debug.print("@{s}: running subcommand\n", .{c.name});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const check = gpa.deinit();
        if (check == .leak) @panic("memory leaked");
    }
    const allocator = gpa.allocator();

    const oi1 = Option{
        .names = &.{ "i", "int-option-1" },
        .type = ValueType.int,
        .default = "10",
    };
    const of1 = Option{
        .names = &.{ "f", "flag-option-1" },
        .is_flag = true,
    };

    const os1 = Option{
        .names = &.{ "s", "string-option-1" },
        .type = ValueType.string,
        .required = false,
    };

    const sub1 = Command{
        .allocator = allocator,
        .name = "sub",
        .description = "my sub command description",
        .nargs = "1..3",
        .run = runSub1,
    };

    var root = Command{
        .allocator = allocator,
        .name = "root",
        .description = "my root command description",
        .nargs = "1..3",
        .run = runRoot,
    };
    defer root.deinit();
    try root.addOptions(&.{ oi1, os1, of1 });
    try root.addCommand(sub1);

    try root.parse();
    try root.start();
}
