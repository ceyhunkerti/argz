const std = @import("std");

pub const cmd = @import("./cmd.zig");
pub const dash = @import("./dash.zig");
pub const hooks = @import("./hooks.zig");
pub const opt = @import("./opt.zig");
pub const token = @import("./token.zig");
pub const utils = @import("./utils.zig");

const testing = std.testing;

pub const Command = cmd.Command;
pub const Option = opt.Option;
pub const ValueType = opt.ValueType;
pub const Hook = hooks.Hook;
pub const Hooks = hooks.Hooks;

pub const Option2 = @import("Option.zig");
pub const Command2 = @import("Command.zig");
pub const Parser2 = @import("Parser.zig");

test "all" {
    testing.refAllDecls(@This());
}
