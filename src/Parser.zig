const Parser = @This();

const std = @import("std");
const Command = @import("Command.zig");
const Option = @import("Option.zig");
const Token = @import("Token.zig");

const Error = error{
    ParseErrorExpectingValue,
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

fn parse(self: *Parser, args: []const []const u8) !Result {
    var option_waiting_value: ?*Option = null;

    for (args, 0..) |arg, arg_index| {
        if (arg.len == 0) continue;
        var token = Token.init(self.allocator, arg);
        try token.parse();
        if (token.isHelp()) return .Help;
        if (token.isOption() and self.state == .expecting_value) {
            return error.ParseErrorExpectingValue;
        }
        std.debug.print("\n arg: {s}\n", .{arg});
        if (token.isOption() and !token.isChained()) {
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
                    var new_option = try self.allocator.create(Option);
                    errdefer self.allocator.destroy(new_option);

                    new_option.* = Option.init(Option.ValueType.String, &.{try token.key()});

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
            if (option_waiting_value) |option| {
                try option.set(try token.key());
                option_waiting_value = null;
                self.state = .void;
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
    const res = try parse(&parser, &.{ "-o", "v", "--o1=v1", "--help" });
    try std.testing.expectEqual(res, .Help);

    std.debug.print("\nOptionCpount: {d}\n", .{cmd.options.?.items.len});
    if (cmd.options) |options| {
        for (options.items) |option| {
            std.debug.print("\no{s} {any}\n", .{ option.names[0], option.get() });
        }
    }
}

fn findOption(self: Parser, name: []const u8) ?*Option {
    if (self.command.options) |options| for (options.items) |o| if (o.hasName(name)) return o;
    return null;
}
