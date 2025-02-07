const Parser = @This();

const std = @import("std");
const Command = @import("Command.zig");
const Option = @import("Option.zig");
const Token = @import("Token.zig");

const Error = error{ ExpectingValue, UnknownNotLongOption } || Token.Error;

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

fn parse(self: *Parser, args: []const []const u8) !Result {
    var option_waiting_value: ?*Option = null;

    for (args, 0..) |arg, arg_index| {
        if (arg.len == 0) continue;
        var token = Token.init(self.allocator, arg);
        try token.parse();
        if (token.isHelp()) return .Help;

        if (token.isEqual()) {
            if (self.state == .expecting_value) {
                continue;
            }
        }

        if (token.isOption() and self.state == .expecting_value) {
            std.debug.print("\n arg: {s}\n", .{arg});
            return error.ExpectingValue;
        }
        std.debug.print("\narg: {s}\n", .{arg});
        if (token.isOption() and !token.isChained()) {
            std.debug.print("\n {s} is option\n", .{arg});
            if (self.findOption(try token.key())) |option| {
                if (option.is_flag) try option.set("true");
                if (token.isKeyValue()) {
                    try option.set(try token.value());
                } else {
                    option_waiting_value = option;
                    self.state = .expecting_value;
                }
            } else {
                std.debug.print("\nunknown option: {s}\n", .{try token.key()});
                if (self.command.allow_unknown_options) {
                    if (!token.hasDoubleDash()) {
                        // only long format is allowed for unknown options
                        return error.UnknownNotLongOption;
                    }

                    var new_option = try self.allocator.create(Option);
                    errdefer self.allocator.destroy(new_option);

                    new_option.* = Option.init(self.allocator, Option.ValueType.String, &.{try token.key()});

                    if (token.isKeyValue()) {
                        try new_option.set(try token.value());
                        self.state = .void;
                    } else {
                        option_waiting_value = new_option;
                        self.state = .expecting_value;
                    }
                    try self.command.addOption(new_option);
                }
            }
        } else if (token.isAtom()) {
            std.debug.print("\n {s} is atom\n", .{arg});
            if (option_waiting_value) |option| {
                try option.set(try token.key());
                option_waiting_value = null;
                self.state = .void;
                std.debug.print("\nstate reset\n", .{});
            } else if (self.command.findSubCommand(try token.key())) |sub| {
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
    defer cmd.deinit();

    cmd.allow_unknown_options = true;
    var parser = Parser.init(allocator, &cmd);
    try std.testing.expectEqual(.Help, try parse(&parser, &.{ "--o", "v", "--help" }));
    try std.testing.expectError(Error.InvalidShortOption, parse(&parser, &.{ "-abc=value", "--o1=v1" }));
    try std.testing.expectEqual(.Help, try parse(&parser, &.{ "--o11", "v", "--o12=v1", "arg1", "arg2", "--help" }));
    // cmd.number_of_arguments.lower = 0;
    // try std.testing.expectError(error.CommandNotExpectingArguments, parse(&parser, &.{ "-o", "v", "--o1=v1", "arg1", "arg2", "--help" }));
    // cmd.number_of_arguments.lower = null;

    // _ = try parse(&parser, &.{ "--xyz", "=", "val", "--o1=v1", "arg1", "arg2", "--help" });

    std.debug.print("\nOptionCpount: {d}\n", .{cmd.options.?.items.len});
    if (cmd.options) |options| {
        for (options.items) |option| {
            std.debug.print("\nOption:  {s} {any}\n", .{ option.names.items[0], option.get() });
        }
    }
}

fn findOption(self: Parser, name: []const u8) ?*Option {
    if (self.command.options) |options| for (options.items) |o| if (o.hasName(name)) return o;
    return null;
}
