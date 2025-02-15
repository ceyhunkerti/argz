// ! do not set attributes beginning with _ directly

const Command = @This();

const std = @import("std");
const mem = std.mem;
const Option = @import("Option.zig");
const Argument = @import("Argument.zig");
const Parser = @import("Parser.zig");

pub const Error = error{
    CommandNotExpectingArguments,
    MultiOptionIsNotSupported,
    CommandAlreadyExists,
    NonRootCommandCannotBeParsed,
    InvalidArgumentLimits,
    MissingArguments,
    MissingRequiredOption,
    OptionNotFound,
} || Argument.Error;

allocator: mem.Allocator,

// name of the command if it's a subcommand must be unique among the siblings
name: []const u8,

// list of options for the command
// option names should be unique for the attached command.
// different options attached to the same command can not have the same name in their `names` list.
// Options are heap allocated and must be deallocated by the owner command.
options: ?std.ArrayList(Option) = null,

// description of the command
description: ?[]const u8 = null,

// list of subcommands for this command.
// use `addCommand` to add subcommands
commands: ?std.ArrayList(Command) = null,

// null means we don't want arguments
// initialize it with arguments if you accept arguments
arguments: ?std.ArrayList(Argument) = null,

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
    return .{
        .allocator = allocator,
        .name = name,
        .runner = runner,
    };
}

pub fn deinit(self: *Command) void {
    if (self.options) |options| {
        for (options.items) |*option| {
            option.deinit();
        }
        options.deinit();
    }
    if (self.arguments) |args| {
        for (args.items) |*arg| {
            arg.deinit();
        }
        args.deinit();
    }
    if (self.commands) |commands| {
        for (commands.items) |*command| {
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
    if (self.commands) |commands| {
        for (commands.items) |*command| {
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
    defer cmd.deinit();

    try std.testing.expectEqualStrings("my-command", cmd.name);
    try std.testing.expect(try cmd.run(null) == 0);
}

// Only the root command is parsable
// ! You should call this only for the root command.
pub fn parse(self: *Command) !void {
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
    if (self.commands == null) {
        self.commands = std.ArrayList(Command).init(self.allocator);
    } else {
        if (self.findSubCommand(command.name) != null) {
            return error.CommandAlreadyExists;
        }
    }
    command._is_root = false;
    try self.commands.?.append(command.*);
}

// Add option to this command. Option names must be unique!
pub fn addOption(self: *Command, option: Option) !void {
    if (self.options == null) {
        self.options = std.ArrayList(Option).init(self.allocator);
    } else {
        if (self.findOption(option.names.items) != null) {
            return error.MultiOptionIsNotSupported;
        }
    }
    try self.options.?.append(option);
}

pub fn addOptions(self: *Command, options: []const Option) !void {
    if (self.options == null) {
        self.options = std.ArrayList(Option).init(self.allocator);
    }
    try self.options.?.appendSlice(options);
}

// Find the option with one of possible names of it.
pub fn findOption(self: Command, names: []const []const u8) ?*Option {
    if (self.options) |options| {
        for (options.items) |*option| {
            for (names) |name| if (mem.eql(u8, option.names.items[0], name)) return option;
        }
    }
    return null;
}

pub fn getOption(self: Command, name: []const u8) !*Option {
    if (self.options) |options| {
        for (options.items) |*option| {
            for (option.names.items) |n| if (mem.eql(u8, n, name)) return option;
        }
    }
    return Error.OptionNotFound;
}

// Find the subcommand from this commands commands list.
pub fn findSubCommand(self: *Command, name: []const u8) ?*Command {
    if (self.commands) |subs| for (subs.items) |*s| if (mem.eql(u8, s.name, name)) return s;
    return null;
}

pub fn addArgument(self: *Command, argument: Argument) !void {
    if (self.arguments == null) {
        self.arguments = std.ArrayList(Argument).init(self.allocator);
    }
    try self.arguments.?.append(argument);
}

pub fn addArguments(self: *Command, arguments: []const Argument) !void {
    if (self.arguments == null) {
        self.arguments = std.ArrayList(Argument).init(self.allocator);
    }
    try self.arguments.?.appendSlice(arguments);
}

// Prints the help for this command
pub fn printHelp(self: *Command) !void {
    if (self.helpgen) |helpgen| {
        const help = try helpgen(self.*);
        defer self.allocator.free(help);
        std.debug.print("{s}\n", .{help});
        return;
    }

    var output = std.ArrayList(u8).init(self.allocator);
    defer output.deinit();

    try output.appendSlice("Usage: ");
    try output.appendSlice(self.name);

    if (self.arguments) |_| {
        try output.appendSlice(" [arguments]");
    }
    if (self.options) |_| {
        try output.appendSlice(" [options]");
    }
    if (self.commands) |_| {
        try output.appendSlice(" [sub-commands]");
    }

    try output.appendSlice("\n");

    if (self.commands) |commands| {
        try output.appendSlice("\nSub commands:\n");
        for (commands.items) |command| {
            try output.appendSlice(" - ");
            try output.appendSlice(command.name);
            try output.appendSlice("\n");
        }
    }

    if (self.arguments) |args| {
        try output.writer().print("\nArguments:\n", .{});
        for (args.items) |arg| {
            var line = std.ArrayList(u8).init(self.allocator);
            defer line.deinit();
            try output.appendSlice(" - ");
            try output.appendSlice(arg.name);
            if (arg.description) |desc| {
                if (line.items.len < 30) {
                    try line.appendNTimes(' ', 30 - line.items.len);
                } else {
                    try line.appendNTimes(' ', 1);
                }
                try line.appendSlice(desc);
            }
            try output.writer().print("{s}\n", .{line.items});
        }
    }
    if (self.options) |options| {
        try output.writer().print("\nOptions:\n", .{});

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
            try output.writer().print("{s}\n", .{line.items});
        }
        if (self.examples) |examples| {
            try output.writer().print("\nExamples:\n", .{});
            for (examples) |example| {
                try output.writer().print("{s}\n", .{example});
            }
        }
    }
    try output.writer().print("\n", .{});
    std.debug.print("{s}", .{output.items});
}

pub fn validate(self: Command) !void {
    if (self.arguments) |args| {
        for (args.items) |arg| {
            try arg.validate();
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
