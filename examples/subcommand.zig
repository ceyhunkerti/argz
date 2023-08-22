const std = @import("std");

const app = @import("argz");

const Command = app.Command;

pub fn mySubCommand(c: *Command) anyerror!void {
    std.debug.print("@{s}: running subcommand\n", .{c.name});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const check = gpa.deinit();
        if (check == .leak) @panic("memory leaked");
    }
    var allocator = gpa.allocator();

    var root = Command.init(allocator, "root");
    defer root.deinit();

    var sub = Command.init(allocator, "my-sub-command");
    sub.run = mySubCommand;

    try root.addCommand(sub);

    try root.parse();
    try root.start();
}
