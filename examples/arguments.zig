// Run the example with the following command
// zig build run-example-arguments -- hi and hello world

const std = @import("std");
const mem = std.mem;
const app = @import("argz");

const Command = app.Command;
const Option = app.Option;
const Argument = app.Argument;
const print = std.debug.print;

fn commandWithArbitraryArguments(allocator: mem.Allocator) !void {
    std.debug.print("\n=== Command with arbitrary number of arguments. ===\n", .{});

    var cmd = Command.init(allocator, "mycommand", struct {
        fn run(self: *const Command, ctx: ?*anyopaque) anyerror!i32 {
            _ = ctx;
            for (self.arguments.?.items, 0..) |a, i| {
                print("Argument {d}: {s}\n", .{ i, a._value.?.String });
            }
            return 0;
        }
    }.run);
    cmd.allow_unknown_options = true;
    defer cmd.deinit();
    try cmd.addArgument(try Argument.init(allocator, "ARG_NAME", .String, null, '*', null));

    try cmd.parse();
    const res = try cmd.run(null);
    std.debug.assert(res == 0);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const check = gpa.deinit();
        if (check == .leak) @panic("memory leaked");
    }
    const allocator = gpa.allocator();
    try commandWithArbitraryArguments(allocator);
}
