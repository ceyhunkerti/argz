// Run the example with the following command
// zig build run-example-arguments -- hi and hello world

const std = @import("std");
const mem = std.mem;
const app = @import("argz");

const Command = app.Command;
const Option = app.Option;
const print = std.debug.print;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const check = gpa.deinit();
        if (check == .leak) @panic("memory leaked");
    }
    const allocator = gpa.allocator();

    var cmd = Command.init(allocator, "mycommand", struct {
        fn run(self: *Command) anyerror!i32 {
            if (self.options) |options| for (options.items, 0..) |o, i| {
                print("Option {d}: {s} {any}\n", .{ i, o.names.items[0], o.get() });
            };
            return 0;
        }
    }.run);
    defer cmd.deinit();

    const intop = try Option.init(allocator, .Integer, &[_][]const u8{ "int-option", "i" });
    try cmd.addOption(intop);

    try cmd.parse();
    const res = try cmd.run();
    std.debug.assert(res == 0);
}
