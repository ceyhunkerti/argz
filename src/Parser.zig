const Parser = @This();

const std = @import("std");
const Command = @import("Command.zig");
const Option = @import("Option.zig");
const Token = @import("Token.zig");

const Error = error{ ExpectingValue, UnknownNotLongOption, UnknownOption } || Token.Error;

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
    var option_waiting_value: ?*Option = null;

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
        if (token.isOption() and !token.isChained()) {
            if (self.findOption(try token.key())) |option| {
                if (option.is_flag) {
                    try option.set("true");
                    continue;
                }

                if (token.isKeyValue()) {
                    try option.set(try token.value());
                } else {
                    option_waiting_value = option;
                    self.state = .expecting_value;
                }
            } else {
                if (self.command.allow_unknown_options) {
                    if (!token.hasDoubleDash()) {
                        // only long format is allowed for unknown options
                        return error.UnknownNotLongOption;
                    }
                    var new_option = try Option.init(self.allocator, Option.ValueType.String, &.{try token.key()}, "Unknown option");
                    new_option._is_unknown_option = true;

                    errdefer {
                        new_option.deinit();
                        self.allocator.destroy(new_option);
                    }
                    if (token.isKeyValue()) {
                        try new_option.set(try token.value());
                        self.state = .void;
                    } else {
                        option_waiting_value = new_option;
                        self.state = .expecting_value;
                    }
                    try self.command.addOption(new_option);
                } else {
                    std.debug.print("Unknown option: {s}\n", .{arg});
                    return error.UnknownOption;
                }
            }
        } else if (token.isAtom()) {
            if (option_waiting_value) |option| {
                try option.set(try token.key());
                option_waiting_value = null;
                self.state = .void;
            } else if (self.command.findSubCommand(try token.key())) |sub| {
                sub._active = true;
                self.command = sub;
                if (arg_index < args.len - 1) {
                    return try self.parse(args[arg_index + 1 ..]);
                }
            } else {
                try self.command.addArgument(try token.key());
            }
        }
    }
    return .Ok;
}

test "Parser.parse" {
    const allocator = std.testing.allocator;
    var cmd = Command.init(allocator, "my-command", struct {
        fn run(self: *Command) anyerror!i32 {
            _ = self;
            return 0;
        }
    }.run);
    cmd.arguments = .{};
    defer cmd.deinit();

    cmd.allow_unknown_options = true;
    var parser = Parser.init(allocator, &cmd);

    try std.testing.expectEqual(.Help, try parser.parse(&.{ "--o", "v", "--help" }));
    try std.testing.expectError(Error.InvalidShortOption, parser.parse(&.{ "-abc=value", "--o1=v1" }));
    try std.testing.expectEqual(.Help, try parser.parse(&.{ "--o11", "v", "--o12=v1", "arg1", "arg2", "--help" }));
    _ = try parser.parse(&.{ "--xyz", "=", "val", "--help" });

    // if (cmd.options) |options| {
    //     for (options.items) |option| {
    //         std.debug.print("\nOption:  {s} {any}\n", .{ option.names.items[0], option.get() });
    //     }
    // }
}

test "Parser.parse subcommands" {
    const allocator = std.testing.allocator;
    var root_cmd = Command.init(allocator, "my-command", null);
    defer root_cmd.deinit();

    var cmd1 = Command.init(allocator, "cmd1", struct {
        fn run(self: *Command) anyerror!i32 {
            _ = self;
            return 42;
        }
    }.run);
    defer cmd1.deinit();
    try root_cmd.addCommand(&cmd1);
    var parser = Parser.init(allocator, &root_cmd);
    try std.testing.expectEqual(.Ok, try parser.parse(&.{"cmd1"}));
    try std.testing.expect(root_cmd.arguments == null);

    try std.testing.expectEqual(@as(i32, 42), try root_cmd.run());

    try std.testing.expectError(error.NonRootCommandCannotBeParsed, cmd1.parse());
}

fn findOption(self: Parser, name: []const u8) ?*Option {
    if (self.command.options) |options| for (options.items) |o| if (o.hasName(name)) return o;
    return null;
}
