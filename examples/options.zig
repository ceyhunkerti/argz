// Run the example with the following command
// zig build run-example-options -- --int-option 1 -af -s "hello" --unknown-option = val

const app = @import("argz");
const std = @import("std");
const mem = std.mem;

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
        fn run(self: *const Command, ctx: ?*anyopaque) anyerror!i32 {
            _ = ctx;
            if (self.options) |options| for (options.items, 0..) |o, i| {
                const val = val: {
                    switch (o.get().?) {
                        .String => |s| break :val try self.allocator.dupe(u8, s),
                        .Integer => |n| break :val try std.fmt.allocPrint(self.allocator, "{d}", .{n}),
                        .Boolean => |b| break :val try std.fmt.allocPrint(self.allocator, "{any}", .{b}),
                    }
                };
                defer self.allocator.free(val);

                print("Option {d}: {s} {s}\n", .{ i, o.names.items[0], val });
            };
            return 0;
        }
    }.run);

    // we allow unknown options here
    cmd.allow_unknown_options = true;
    defer cmd.deinit();

    const int_op = try Option.init(allocator, .Integer, &[_][]const u8{ "int-option", "i" }, "int option description");
    try cmd.addOption(int_op);

    const flag_op = try Option.init(allocator, .Boolean, &[_][]const u8{ "flag-option", "f" }, "flag option description");
    flag_op.is_flag = true;
    try cmd.addOption(flag_op);

    const another_flag_op = try Option.init(
        allocator,
        .Boolean,
        &[_][]const u8{ "another-flag-option", "a" },
        "another flag option description",
    );
    another_flag_op.is_flag = true;
    try cmd.addOption(another_flag_op);

    const str_op = try Option.init(allocator, .String, &[_][]const u8{ "string-option", "s" }, "string option description");
    try cmd.addOption(str_op);

    try cmd.parse();
    const res = try cmd.run(null);
    std.debug.assert(res == 0);
}
