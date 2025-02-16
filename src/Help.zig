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
    var parent = self.command._parent;
    break_parent: while (true) {
        if (parent) |p| {
            try output.insertSlice(0, " ");
            try output.insertSlice(0, p.name);
            parent = p._parent;
        } else {
            break :break_parent;
        }
    }
    try output.writer().print("{s}", .{self.command.name});
    try output.insertSlice(0, "Usage: ");

    if (self.command.subcommands) |_| {
        try output.writer().print(" <command>", .{});
    }
    if (self.command.arguments) |_| {
        try output.writer().print(" [<arguments>]", .{});
    }
    if (self.command.subcommands) |commands| {
        try output.appendSlice("\n\nSubcommands:\n");
        for (commands.items) |command| {
            try output.writer().print("  - {s}\n", .{command.name});
        }
    }

    if (self.command.arguments) |arguments| {
        try output.appendSlice("\n\nArguments:\n");
        for (arguments.items) |argument| {
            try output.writer().print(" - {s:<20} {s}\n", .{ argument.name, argument.description orelse "" });
        }
    }

    if (self.command.options) |options| {
        try output.appendSlice("\n\nOptions:\n");
        for (options.items) |option| {
            if (option._is_unknown_option) continue;
            try output.appendSlice("  ");
            for (option.names.items, 0..) |name, ni| {
                if (ni > 0 and ni <= option.names.items.len - 1) {
                    try output.append(',');
                }
                if (name.len == 1) {
                    try output.writer().print("-{s}", .{name});
                } else {
                    try output.writer().print("--{s}", .{name});
                }
            }
            if (option.description) |desc| {
                try output.writer().print("\n       {s}\n", .{desc});
            }
        }
    }
}
