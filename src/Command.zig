// ! do not set attributes beginning with _ directly

const Command = @This();

const std = @import("std");
const mem = std.mem;
const Option = @import("Option.zig");
const Parser = @import("Parser.zig");

pub const Error = error{
    ArgumentCountOverflow,
    CommandNotExpectingArguments,
    MultiOptionIsNotSupported,
    CommandAlreadyExists,
    NonRootCommandCannotBeParsed,
    InvalidArgumentLimits,
    MissingArguments,
    MissingRequiredOption,
};

// Arguments are typed
// Arguments generate parse error if we encounter an argument that is not of the expected type
const ArgumentType = enum { String, Integer, Boolean };

// Union of the possible argument types
const ArgumentValue = union(ArgumentType) {
    String: []const u8,
    Integer: i32,
    // ! case sensitive "true" is considered as true anything else is false
    Boolean: bool,
};

pub const Arguments = struct {
    // Default argument type is string.
    type: ArgumentType = .String,

    // min_count and max_count are inclusive
    // if min count is let's say 4 and we got only 3 arguments
    // todo: we generate an error in the validation step
    min_count: u8 = 0,

    // If we receive more than this number of arguments we generate an error in the parse step.
    max_count: u8 = std.math.maxInt(u8),

    // internal values
    _values: ?std.ArrayList(ArgumentValue) = null,

    pub fn deinit(self: Arguments, allocator: mem.Allocator) void {
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

allocator: mem.Allocator,

// name of the command if it's a subcommand must be unique among the siblings
name: []const u8,

// list of options for the command
// option names should be unique for the attached command.
// different options attached to the same command can not have the same name in their `names` list.
// Options are heap allocated and must be deallocated by the owner command.
options: ?std.ArrayList(*Option) = null,

// description of the command
description: ?[]const u8 = null,

// list of subcommands for this command.
// use `addCommand` to add subcommands
_commands: ?std.ArrayList(*Command) = null,

// null means we don't want arguments
// initialize it with arguments if you accept arguments
arguments: ?Arguments = null,

// custom validation function for this command
// todo: will be called within the validate command
validation: ?*const fn (self: Command) anyerror!void = null,

// custom run function for this command.
runner: ?*const fn (self: *const Command, ctx: ?*anyopaque) anyerror!i32 = null,

// custom help string generator. owner must deallocate the returned memory!
helpgen: ?*const fn (cmd: Command) anyerror![]const u8 = null,

examples: ?[]const []const u8 = null,

// If this attribute is set to true unknown options are allowed and the parser
// add these options to the options list.
// ! Unknown options can only be long options (i.e --option)
// If set to true and a short unknown option is encountered during the parse phase we generate error.
allow_unknown_options: bool = false,

// computed at the parse time.
// DO NOT set this attribute directly
_active: bool = false,

_is_root: bool = true,

// if -h or --help is encountered during the parse phase
_help_requested: bool = false,

// If command parameter is a group command you can set it to null in most of the cases.
pub fn init(allocator: mem.Allocator, name: []const u8, runner: ?*const fn (self: *const Command, ctx: ?*anyopaque) anyerror!i32) Command {
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
        for (commands.items) |command| {
            command.deinit();
        }
        commands.deinit();
    }
}

// command first checks if it's runner function is not null
// if it's not null it calls the runner function then calls the sub-commands in order.
// From the list of the sub commands only one command is marked as "active" during the parse step.
// Only the active command is then called.
pub fn run(self: *const Command, ctx: ?*anyopaque) anyerror!i32 {

    // if help is requested just return 0
    // help is printed during parse phase
    if (self._help_requested) return 0;

    if (self.runner) |runner| {
        return runner(self, ctx);
    }
    if (self._commands) |commands| {
        for (commands.items) |command| {
            // from the list of sub commands only the active command can be run
            // there can be only one active command in the sub command list.
            if (command._active) return try command.run(ctx);
        }
    }

    return 0;
}

test "Command.run" {
    const allocator = std.testing.allocator;
    var cmd = Command.init(allocator, "my-command", null);

    try std.testing.expectEqualStrings("my-command", cmd.name);
    try std.testing.expect(try cmd.run(null) == 0);
}

// Only the root command is parsable
// ! You should call this only for the root command.
pub fn parse(self: *Command) !void {
    // pre checks
    if (self.arguments) |args| {
        if (args.min_count > args.max_count) {
            return Error.InvalidArgumentLimits;
        }
    }

    if (!self._is_root) return Error.NonRootCommandCannotBeParsed;

    // parse the process arguments
    var args_it = try std.process.argsWithAllocator(self.allocator);

    var args = std.ArrayList([]const u8).init(self.allocator);
    defer args.deinit();
    while (args_it.next()) |arg| {
        try args.append(arg);
    }
    var parser = Parser.init(self.allocator, self);
    if (args.items.len == 0) {
        try self.validate();
        return;
    }
    if (try parser.parse(args.items[1..]) == .Help) {
        try parser.command.printHelp();
        return;
    }
    try self.validate();
}

// Add subcommand to this command. Sub command names must be unique!
pub fn addCommand(self: *Command, command: *Command) !void {
    if (self._commands == null) {
        self._commands = std.ArrayList(*Command).init(self.allocator);
    } else {
        if (self.findSubCommand(command.name) != null) {
            return error.CommandAlreadyExists;
        }
    }
    command._is_root = false;
    try self._commands.?.append(command);
}

// Add option to this command. Option names must be unique!
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

// Find the option with one of possible names of it.
pub fn findOption(self: *Command, names: []const []const u8) ?*Option {
    if (self.options) |options| {
        for (options.items) |option| {
            for (names) |name| if (mem.eql(u8, option.names.items[0], name)) return option;
        }
    }
    return null;
}

// Find the subcommand from this commands commands list.
pub fn findSubCommand(self: *Command, name: []const u8) ?*Command {
    if (self._commands) |subs| for (subs.items) |s| if (mem.eql(u8, s.name, name)) return s;
    return null;
}

// Adds arguments to this command.
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
            .Boolean => try args._values.?.append(ArgumentValue{ .Boolean = mem.eql(u8, argument, "true") }),
        }
    } else {
        return Error.CommandNotExpectingArguments;
    }
}

pub fn argumentValues(self: Command) ?[]ArgumentValue {
    if (self.arguments) |args| return args._values.?.items;
    return null;
}

// Prints the help for this command
pub fn printHelp(self: *Command) !void {
    if (self.helpgen) |helpgen| {
        const help = try helpgen(self.*);
        defer self.allocator.free(help);
        std.debug.print("{s}\n", .{help});
        return;
    }

    std.debug.print("\nCommand: {s}\n", .{self.name});
    if (self.arguments) |args| {
        if (args.min_count > 0) {
            std.debug.print("Arguments (min: {d}, max: {d}): \n", .{ args.min_count, args.max_count });
        } else {
            std.debug.print("Arguments (max: {d}): \n", .{args.max_count});
        }
    }
    if (self.options) |options| {
        std.debug.print("\nOptions:\n", .{});

        for (options.items) |option| {
            var line = std.ArrayList(u8).init(self.allocator);
            defer line.deinit();

            for (option.names.items, 0..) |name, i| {
                if (name.len == 1) {
                    try line.append('-');
                } else {
                    try line.appendSlice("--");
                }
                try line.appendSlice(name);
                if (i != option.names.items.len - 1) try line.append(',');
            }
            if (option.description) |desc| {
                if (line.items.len < 30) {
                    try line.appendNTimes(' ', 30 - line.items.len);
                } else {
                    try line.appendNTimes(' ', 1);
                }
                try line.appendSlice(desc);
            }
            std.debug.print("{s}\n", .{line.items});
        }
        if (self.examples) |examples| {
            std.debug.print("\nExamples:\n", .{});
            for (examples) |example| {
                std.debug.print("{s}\n", .{example});
            }
        }
    }
}

pub fn validate(self: Command) !void {
    if (self.arguments) |args| {
        if (args.min_count > 0 and (args._values == null or args._values.?.items.len < args.min_count)) {
            return error.MissingArguments;
        }
    }
    if (self.options) |options| {
        for (options.items) |option| {
            if (option.required and option._value == null) {
                return error.MissingRequiredOption;
            }
        }
    }

    if (self.validation) |f| try f(self);
}
