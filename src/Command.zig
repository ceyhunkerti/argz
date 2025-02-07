const Command = @This();

const std = @import("std");
const mem = std.mem;
const Option = @import("Option.zig");

const Error = error{
    ArgumentCountOverflow,
    CommandNotExpectingArguments,
    MultiOptionIsNotSupported,
    CommandAlreadyExists,
};

allocator: std.mem.Allocator,

// name of the command if it's a subcommand must be unique among the siblings
name: []const u8,

// list of option parameters
// option names should be unique for the attached command.
// different options attached to the same command can not have the same name in their `names` list.
options: ?std.ArrayList(*Option) = null,

// description of the command
description: ?[]const u8 = null,

// list of subcommands for this command.
commands: ?std.ArrayList(Command) = null,

// computed in the parse step.
// DO NOT set it directly
_args: ?std.ArrayList([]const u8) = null,

// computed argument count limits during parse step.
// DO NOT set this attribute directly
number_of_arguments: struct { lower: ?u8 = null, upper: ?u8 = null } = .{},

// custom validation function for this command
validation: ?*const fn (self: Command) anyerror!void = null,

// custom run function for this command.
runner: *const fn (self: *Command) anyerror!i32,

// custom help string generator. owner must deallocate the returned memory!
helpgen: ?*const fn (cmd: Command) anyerror![]const u8 = null,

allow_unknown_options: bool = false,

pub fn init(allocator: std.mem.Allocator, name: []const u8, runner: *const fn (self: *Command) anyerror!i32) Command {
    return Command{
        .allocator = allocator,
        .name = name,
        .runner = runner,
    };
}

pub fn deinit(self: Command) void {
    if (self.options) |options| {
        for (options.items) |option| {
            option.deinit();
            self.allocator.destroy(option);
        }
        options.deinit();
    }
    if (self._args) |args| args.deinit();
    if (self.commands) |commands| {
        for (commands.items) |command| command.deinit();
        commands.deinit();
    }
}

pub fn run(self: *Command) anyerror!i32 {
    return self.runner(self);
}

test "Command.run" {
    const allocator = std.testing.allocator;
    var cmd = Command.init(allocator, "my-command", struct {
        fn run(self: *Command) anyerror!i32 {
            _ = self;
            return 0;
        }
    }.run);

    try std.testing.expectEqualStrings("my-command", cmd.name);
    try std.testing.expect(try cmd.run() == 0);
}

pub fn parse(self: *Command) !void {
    var args_it = try std.process.argsWithAllocator(self.allocator);

    var args = std.ArrayList([]const u8).init(self.allocator);
    defer args.deinit();
    while (args_it.next()) |arg| {
        try args.append(arg);
    }
}

pub fn addCommand(self: *Command, command: Command) !void {
    if (self.commands == null) {
        self.commands = std.ArrayList(Command).init(self.allocator);
    } else {
        if (self.findSubCommand(command.name) != null) {
            return error.CommandAlreadyExists;
        }
    }
    try self.commands.?.append(command);
}

pub fn addOption(self: *Command, option: *Option) !void {
    if (self.options == null) {
        self.options = std.ArrayList(*Option).init(self.allocator);
    } else {
        if (self.findOption(option.names.items) != null) {
            return error.MultiOptionIsNotSupported;
        }
    }
    try self.options.?.append(option);
}

pub fn findOption(self: *Command, names: []const []const u8) ?*Option {
    if (self.options) |options| {
        for (options.items) |option| {
            for (names) |name| if (mem.eql(u8, option.names.items[0], name)) return option;
        }
    }
    return null;
}

pub fn findSubCommand(self: *Command, name: []const u8) ?*Command {
    if (self.commands) |subs| for (subs.items) |*s| if (mem.eql(u8, s.name, name)) return s;
    return null;
}

pub fn addArgument(self: *Command, argument: []const u8) !void {
    if (self.number_of_arguments.lower == 0) {
        return Error.CommandNotExpectingArguments;
    }

    if (self._args == null) {
        self._args = std.ArrayList([]const u8).init(self.allocator);
    }

    if (self.number_of_arguments.upper) |upper| if (self._args.?.items.len >= upper)
        return error.ArgumentCountOverflow;

    try self._args.?.append(argument);
}
