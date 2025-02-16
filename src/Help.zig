const Help = @This();
const std = @import("std");
const Allocator = std.mem.Allocator;
const Command = @import("Command.zig");
const Option = @import("Option.zig");

allocator: Allocator,
command: *const Command,

pub fn init(allocator: Allocator, command: *const Command) Help {
    return .{
        .allocator = allocator,
        .command = command,
    };
}

pub fn print(self: Help) !void {
    const h = try self.help();
    defer self.allocator.free(h);
    std.debug.print("{s}\n", .{h});
}

pub fn help(self: Help) ![]const u8 {
    var output = std.ArrayList(u8).init(self.allocator);
    defer output.deinit();

    try self.usageHelp(&output);
    return try output.toOwnedSlice();
}

fn usageHelp(self: Help, output: *std.ArrayList(u8)) !void {
    break_parent: while (true) {
        var parent: *Command = undefined;
        if (self.command._parent) |p| {
            std.debug.print("1\n", .{});
            parent = p;
            // try output.resize(output.items.len + parent.name.len + 2);
            std.debug.print("{s}\n", .{parent.name});
            try output.insert(0, ' ');
            try output.insertSlice(0, parent.name);
        } else {
            break :break_parent;
        }
    }

    try output.writer().print("\nUsage: {s}", .{self.command.name});

    if (self.command.options) |options| {
        for (options.items, 0..) |option, i| {
            if (i > 0) try output.append(' ');

            try output.append('[');
            for (option.names.items, 0..) |name, ni| {
                if (ni > 0 and ni < option.names.items.len - 1) {
                    try output.appendSlice(" | ");
                }
                if (name.len == 1) {
                    try output.writer().print("-{s}", .{name});
                } else {
                    try output.writer().print("--{s}", .{name});
                }
            }
            try output.append(']');
            if (i % 3 == 0) try output.append('\n');
        }
    }

    if (self.command.subcommands) |_| {
        try output.writer().print(" <command>", .{});
    }
    if (self.command.arguments) |_| {
        try output.writer().print(" [<arguments>]", .{});
    }
    if (self.command.subcommands) |commands| {
        try output.appendSlice("\n\nSubcommands:\n");
        for (commands.items) |command| {
            try output.writer().print(" - {s}\n", .{command.name});
        }
    }
}
