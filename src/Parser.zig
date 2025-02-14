const Parser = @This();

const std = @import("std");
const Command = @import("Command.zig");
const Option = @import("Option.zig");
const Token = @import("Token.zig");
const Argument = @import("Argument.zig");

pub const Error = error{
    ExpectingValue,
    UnknownNotLongOption,
    UnknownOption,
    FailedToParseChainedOptions,
    UnexpectedArgument,
} || Token.Error;

const State = enum {
    void,

    expecting_value,
};

pub const Result = enum { Ok, Help };

allocator: std.mem.Allocator,
root: *Command,
command: *Command,
state: State = .void,

pub fn init(allocator: std.mem.Allocator, command: *Command) Parser {
    return .{ .allocator = allocator, .command = command, .root = command };
}

pub fn parse(self: *Parser, args: []const []const u8) !Result {
    for (args, 0..) |arg, arg_index| {
        if (arg.len == 0) continue;
        var token = Token.init(self.allocator, arg);
        try token.parse();
        if (token.isHelp()) {
            self.root._help_requested = true;
            return .Help;
        }

        if (token.isEqual()) {
            if (self.state == .expecting_value) {
                continue;
            }
        }

        if (token.isOption() and self.state == .expecting_value) {
            return error.ExpectingValue;
        }
        if (token.isUnchainedOption()) {
            if (self.findOption(try token.key())) |option| {
                if (option.is_flag) {
                    try option.set("true");
                    continue;
                }

                if (token.isKeyValue()) {
                    try option.set(try token.value());
                } else {
                    self.state = .expecting_value;
                }
            } else {
                if (self.command.allow_unknown_options) {
                    if (!token.hasDoubleDash()) {
                        // only long format is allowed for unknown options
                        return error.UnknownNotLongOption;
                    }

                    // var new_option = try self.allocator.create(Option);
                    // errdefer self.allocator.destroy(new_option);

                    var new_option = try Option.init(self.allocator, Option.ValueType.String, &.{try token.key()}, "Unknown option");
                    new_option._is_unknown_option = true;

                    errdefer {
                        new_option.deinit();
                    }
                    if (token.isKeyValue()) {
                        try new_option.set(try token.value());
                        self.state = .void;
                    } else {
                        self.state = .expecting_value;
                    }
                    try self.command.addOption(new_option);
                } else {
                    std.debug.print("Unknown option: {s}\n", .{token.key() catch arg});
                    return error.UnknownOption;
                }
            }
        } else if (token.isChainedOption()) {
            for (try token.key()) |char| {
                if (self.findOption(&[_]u8{char})) |option| {
                    if (!option.is_flag) {
                        return error.FailedToParseChainedOptions;
                    } else {
                        try option.set("true");
                    }
                } else {
                    return error.UnknownOption;
                }
            }
        } else if (token.isAtom()) {
            if (self.state == .expecting_value) {
                try self.command.options.?.items[self.command.options.?.items.len - 1].set(try token.key());
                self.state = .void;
            } else if (self.command.findSubCommand(try token.key())) |sub| {
                sub._active = true;
                self.command = sub;
                if (arg_index < args.len - 1) {
                    return try self.parse(args[arg_index + 1 ..]);
                }
            } else {
                try self.setArgument(try token.key());
            }
        }
    }
    return .Ok;
}

test "Parser.parse" {
    const allocator = std.testing.allocator;
    var cmd = Command.init(allocator, "my-command", struct {
        fn run(self: *const Command, ctx: ?*anyopaque) anyerror!i32 {
            _ = self;
            _ = ctx;
            return 0;
        }
    }.run);
    defer cmd.deinit();

    cmd.allow_unknown_options = true;
    var parser = Parser.init(allocator, &cmd);

    try std.testing.expectEqual(.Help, try parser.parse(&.{ "--o", "v", "--help" }));
    try std.testing.expectError(Error.InvalidShortOption, parser.parse(&.{ "-abc=value", "--o1=v1" }));

    try cmd.addArguments(&.{
        try Argument.init(allocator, "ARG_NAME", .String, null, null, null),
        try Argument.init(allocator, "ARG_NAME2", .String, null, null, null),
        try Argument.init(allocator, "ARG_NAME2", .String, null, null, true),
    });

    try std.testing.expectEqual(.Ok, try parser.parse(&.{ "--o11", "v", "--o12=v1", "arg1", "arg2" }));
    try std.testing.expectError(error.MissingRequiredArgument, cmd.validate());

    _ = try parser.parse(&.{ "--xyz", "=", "val", "--help" });

    // if (cmd.options) |options| {
    //     for (options.items) |option| {
    //         std.debug.print("\nOption:  {s} {any}\n", .{ option.names.items[0], option.get() });
    //     }
    // }
}

fn setArgument(self: *Parser, value: []const u8) !void {
    if (self.command.arguments == null) {
        return error.CommandNotExpectingArguments;
    }

    var argument_set = false;
    set_arg: for (self.command.arguments.?.items) |*argument| {
        if (argument._value == null) {
            try argument.setValue(value);
            argument_set = true;
            break :set_arg;
        } else if (argument.isArrayType()) {
            argument.setValue(value) catch |err| {
                if (err == Argument.Error.TooManyValues) {
                    continue :set_arg;
                }
                return err;
            };
            argument_set = true;
            break :set_arg;
        }
    }
    if (!argument_set) return Error.UnexpectedArgument;
}

test "Parser.parse subcommands" {
    const allocator = std.testing.allocator;
    var root_cmd = Command.init(allocator, "my-command", null);
    defer root_cmd.deinit();

    const arg = struct {
        arg: u8 = 42,
    };

    var cmd1 = Command.init(allocator, "cmd1", struct {
        fn run(cmd: *const Command, ctx: ?*anyopaque) anyerror!i32 {
            _ = cmd;
            if (ctx == null) return -1;
            const a: *arg = @ptrCast(@alignCast(ctx.?));
            return a.arg;
        }
    }.run);
    try root_cmd.addCommand(&cmd1);
    var parser = Parser.init(allocator, &root_cmd);
    try std.testing.expectEqual(.Ok, try parser.parse(&.{"cmd1"}));
    try std.testing.expect(root_cmd.arguments == null);

    var args = arg{ .arg = 42 };

    try std.testing.expectEqual(@as(i32, 42), try root_cmd.run(&args));

    try std.testing.expectError(error.NonRootCommandCannotBeParsed, cmd1.parse());
}

fn findOption(self: Parser, name: []const u8) ?*Option {
    if (self.command.options) |options| for (options.items) |*o| if (o.hasName(name)) return o;
    return null;
}
