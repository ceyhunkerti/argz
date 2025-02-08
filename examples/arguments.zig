// Run the example with the following command
// zig build run-example-arguments -- hi and hello world

const std = @import("std");
const mem = std.mem;
const app = @import("argz");

const Command = app.Command;
const Option = app.Option;
const print = std.debug.print;

fn commandWithArbitraryArguments(allocator: mem.Allocator) !void {
    std.debug.print("\n=== Command with arbitrary number of arguments. ===\n", .{});

    var cmd = Command.init(allocator, "mycommand", struct {
        fn run(self: *Command) anyerror!i32 {
            if (self.argumentValues()) |values| for (values, 0..) |a, i| {
                print("Argument {d}: {s}\n", .{ i, a.String });
            };
            return 0;
        }
    }.run);
    cmd.allow_unknown_options = true;
    defer cmd.deinit();
    cmd.arguments = .{};

    try cmd.parse();
    const res = try cmd.run();
    std.debug.assert(res == 0);
}

fn commandWithMaxArgumentCount(allocator: mem.Allocator) !void {
    // Command with arbitrary number of arguments.
    std.debug.print("\n=== Command with max argument count. ===\n", .{});

    var cmd = Command.init(allocator, "mycommand", struct {
        fn run(self: *Command) anyerror!i32 {
            if (self.argumentValues()) |values| for (values, 0..) |a, i| {
                print("Argument {d}: {s}\n", .{ i, a.String });
            };
            return 0;
        }
    }.run);
    cmd.allow_unknown_options = true;
    defer cmd.deinit();
    cmd.arguments = .{ .max_count = 2 };

    if (cmd.parse() == error.ArgumentCountOverflow) {
        print("Argument count overflow!\n", .{});
        print("Expecting at most {d} arguments but received more!\n", .{cmd.arguments.?.max_count});
        return;
    }
}

fn commandWithMinArgumentCount(allocator: mem.Allocator) !void {
    // Command with arbitrary number of arguments.
    std.debug.print("\n=== Command with min argument count. ===\n", .{});

    var cmd = Command.init(allocator, "mycommand", struct {
        fn run(self: *Command) anyerror!i32 {
            if (self.argumentValues()) |values| for (values, 0..) |a, i| {
                print("Argument {d}: {s}\n", .{ i, a.String });
            };
            return 0;
        }
    }.run);
    cmd.allow_unknown_options = true;
    defer cmd.deinit();
    cmd.arguments = .{ .min_count = 10 };

    const parse_result = cmd.parse();
    if (parse_result == error.MissingArguments) {
        print("Missing arguments!\n", .{});
        print("Expecting at least {d} arguments but received {d}!\n", .{
            cmd.arguments.?.min_count,
            cmd.argumentValues().?.len,
        });
        return;
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const check = gpa.deinit();
        if (check == .leak) @panic("memory leaked");
    }
    const allocator = gpa.allocator();
    try commandWithArbitraryArguments(allocator);
    try commandWithMaxArgumentCount(allocator);
    try commandWithMinArgumentCount(allocator);
}
