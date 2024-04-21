const std = @import("std");

const lib = @import("argz");

const Command = lib.Command;
const Option = lib.Option;

const printf = std.debug.print;
fn print(s: []const u8) void {
    printf("{s}", .{s});
}

const Error = error{
    GenericError,
};

pub fn runRoot(c: *Command) anyerror!void {
    print("running root ...\n");
    if (c.getFlag("f")) |f| {
        if (f.value.?.boolean) {
            print("bool true in root command\n");
        } else {
            print("bool false in root command\n");
        }
    } else {
        print("flag not found");
        return error.GenericError;
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const check = gpa.deinit();
        if (check == .leak) @panic("memory leaked");
    }
    const allocator = gpa.allocator();

    var root = Command.init(allocator, "root");
    root.run = runRoot;

    const o1 = Option{
        .names = &.{ "f", "my-flag" },
        .is_flag = true,
        .description = "flag option description",
    };

    try root.addOption(o1);

    var sub1 = Command.init(allocator, "sub1");
    sub1.description = "my sub command description";
    try root.addCommand(sub1);

    defer root.deinit();
    root.description = "root command desc";
    try root.parse();
    try root.start();
}
