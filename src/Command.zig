const Command = @This();

const std = @import("std");
const mem = std.mem;
const Option = @import("Option.zig");
const Parser = @import("Parser.zig");

const ArgumentType = enum { String, Integer, Boolean };
const ArgumentValue = union(ArgumentType) {
    String: []const u8,
    Integer: i32,
    Boolean: bool,
};

pub const Arguments = struct {
    type: ArgumentType = .String,
    min_count: u8 = 0,
    max_count: u8 = std.math.maxInt(u8),
    _values: ?std.ArrayList(ArgumentValue) = null,

    pub fn deinit(self: Arguments, allocator: std.mem.Allocator) void {
        if (self._values) |vals| {
            for (vals.items) |v| switch (v) {
                .String => allocator.free(v.String),
                else => {},
            };
            vals.deinit();
        }
    }

    pub fn values(self: Arguments) []ArgumentValue {
        if (self._values) |vals| return vals.items;
    }
};

const Error = error{
    ArgumentCountOverflow,
    CommandNotExpectingArguments,
    MultiOptionIsNotSupported,
    CommandAlreadyExists,
    NonRootCommandCannotBeParsed,
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
_commands: ?std.ArrayList(Command) = null,

// computed in the parse step.
// DO NOT set it directly
// _args: ?std.ArrayList([]const u8) = null,

// computed argument count limits during parse step.
// DO NOT set this attribute directly
// number_of_arguments: struct { lower: ?u8 = null, upper: ?u8 = null } = .{},

// null means we don't want arguments
// initialize it with arguments if you accept arguments
arguments: ?Arguments = null,

// custom validation function for this command
validation: ?*const fn (self: Command) anyerror!void = null,

// custom run function for this command.
runner: ?*const fn (self: *Command) anyerror!i32,

// custom help string generator. owner must deallocate the returned memory!
helpgen: ?*const fn (cmd: Command) anyerror![]const u8 = null,

allow_unknown_options: bool = false,

// computed at the parse time.
// DO NOT set this attribute directly
_active: bool = false,

_is_root: bool = true,

pub fn init(allocator: std.mem.Allocator, name: []const u8, runner: ?*const fn (self: *Command) anyerror!i32) Command {
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
    if (self.arguments) |args| args.deinit(self.allocator);
    if (self._commands) |commands| {
        for (commands.items) |command| command.deinit();
        commands.deinit();
    }
}

pub fn run(self: *Command) anyerror!i32 {
    if (self.runner) |runner| {
        return runner(self);
    }
    if (self._commands) |commands| {
        for (commands.items) |*command| {
            std.debug.print("\n=---> sub command {s} is_active: {any} \n", .{ command.name, command._active });
            // from the list of sub commands only the active command can be run
            // there can be only one active command in the sub command list.
            if (command._active) return try command.run();
        }
    }

    return 0;
}

test "Command.run" {
    const allocator = std.testing.allocator;
    var cmd = Command.init(allocator, "my-command", null);

    try std.testing.expectEqualStrings("my-command", cmd.name);
    try std.testing.expect(try cmd.run() == 0);
}

pub fn parse(self: *Command) !void {
    if (!self._is_root) return Error.NonRootCommandCannotBeParsed;

    var args_it = try std.process.argsWithAllocator(self.allocator);

    var args = std.ArrayList([]const u8).init(self.allocator);
    defer args.deinit();
    while (args_it.next()) |arg| {
        try args.append(arg);
    }
    var parser = Parser.init(self.allocator, self);
    const res = try parser.parse(args.items);
    if (res == .Help) {
        try parser.command.printHelp();
    }
}

pub fn addCommand(self: *Command, command: *Command) !void {
    if (self._commands == null) {
        self._commands = std.ArrayList(Command).init(self.allocator);
    } else {
        if (self.findSubCommand(command.name) != null) {
            return error.CommandAlreadyExists;
        }
    }
    command._is_root = false;
    try self._commands.?.append(command.*);
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
    if (self._commands) |subs| for (subs.items) |*s| if (mem.eql(u8, s.name, name)) return s;
    return null;
}

pub fn addArgument(self: *Command, argument: []const u8) !void {
    if (self.arguments) |*args| {
        if (args._values == null) {
            args._values = std.ArrayList(ArgumentValue).init(self.allocator);
        }
        if (args._values.?.items.len == args.max_count) {
            return error.ArgumentCountOverflow;
        }
        switch (args.type) {
            .String => try args._values.?.append(ArgumentValue{ .String = try self.allocator.dupe(u8, argument) }),
            .Integer => try args._values.?.append(ArgumentValue{ .Integer = try std.fmt.parseInt(i32, argument, 10) }),
            .Boolean => try args._values.?.append(ArgumentValue{ .Boolean = std.mem.eql(u8, argument, "true") }),
        }
    } else {
        return Error.CommandNotExpectingArguments;
    }
}

pub fn printHelp(self: *Command) !void {
    if (self.helpgen) |helpgen| {
        const help = try helpgen(self.*);
        defer self.allocator.free(help);
        std.debug.print("{s}\n", .{help});
    } else {
        // todo
        std.debug.print("{s}\n", .{self.name});
    }
}
