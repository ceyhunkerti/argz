const std = @import("std");

const testing = std.testing;

pub const Parser = @import("Parser.zig");
pub const Command = @import("Command.zig");
pub const Option = @import("Option.zig");
pub const Argument = @import("Argument.zig");

pub const Error = Parser.Error || Command.Error;

test "all" {
    testing.refAllDecls(@This());
}
