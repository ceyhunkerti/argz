const std = @import("std");

const lib = @import("argz");

const Command = lib.Command;
const Option = lib.Option;
const ValueType = lib.ValueType;

const printf = std.debug.print;
fn print(s: []const u8) void {
    printf("{s}", .{s});
}

const Error = error{
    GenericError,
};

pub fn runRoot(c: *Command) anyerror!void {
    _ = c;
}

pub fn runSub1(c: *Command) anyerror!void {
    _ = c;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const check = gpa.deinit();
        if (check == .leak) @panic("memory leaked");
    }
    var allocator = gpa.allocator();

    var oi1 = Option{
        .names = &.{ "i", "int-option-1" },
        .type = ValueType.int,
        .default = "10",
    };
    var of1 = Option{
        .names = &.{ "f", "flag-option-1" },
        .is_flag = true,
    };

    var os1 = Option{
        .names = &.{ "s", "string-option-1" },
        .is_flag = true,
    };

    var sub1 = Command{
        .allocator = allocator,
        .name = "root",
        .description = "my root command description",
        .options = &.{ &oi1, &of1, &os1 },
        .nargs = "1..3",
        .run = runRoot,
    };
    _ = sub1;

    var root = Command{
        .allocator = allocator,
        .name = "root",
        .description = "my root command description",
        .options = &.{ &oi1, &of1, &os1 },
        .nargs = "1..3",
        .run = runRoot,
    };
    _ = root;

    // Command.init(allocator, "root");
    // root.run = runRoot;

    // var o1 = Option{
    //     .names = &.{ "f", "my-flag" },
    //     .is_flag = true,
    //     .description = "flag option description",
    // };

    // try root.addOption(&o1);

    // var sub1 = Command.init(allocator, "sub1");
    // sub1.description = "my sub command description";
    // try root.addCommand(&sub1);

    // defer root.deinit();
    // root.description = "root command desc";
    // try root.parse();
    // try root.start();
}
