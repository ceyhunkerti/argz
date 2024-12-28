const std = @import("std");
const testing = std.testing;

const cmd = @import("./cmd.zig");
const Command = cmd.Command;

const Error = error{
    UnknownHookLocation,
};

pub const Hook = struct {
    name: []const u8,
    description: ?[]const u8,
    run: *const fn (*Command) anyerror!void,
};

pub const Hooks = struct {
    const Self = @This();

    const HookList = std.ArrayList(Hook);

    allocator: std.mem.Allocator,

    map: std.hash_map.AutoHashMap(Location, HookList),

    pub const Location = enum {
        pre_parse,
        parse_success,
        parse_error,
        pre_start,
        success,
    };

    pub fn init(allocator: std.mem.Allocator) !Hooks {
        var map = std.hash_map.AutoHashMap(Location, HookList).init(testing.allocator);

        for (std.enums.values(Location)) |loc| {
            try map.put(loc, HookList.init(allocator));
        }
        return Hooks{
            .allocator = testing.allocator,
            .map = map,
        };
    }

    pub fn deinit(self: *Self) void {
        defer self.map.deinit();
        var it = self.map.iterator();
        while (it.next()) |m| m.value_ptr.*.deinit();
    }

    pub fn add(self: Self, loc: Location, hook: Hook) !void {
        if (self.map.getPtr(loc)) |hl| try hl.append(hook) else return Error.UnknownHookLocation;
    }

    pub fn run(self: *Self, loc: Location, command: *Command) !void {
        const hook_loc = self.map.getPtr(loc) orelse return Error.UnknownHookLocation;
        for (hook_loc.items) |h| try h.run(command);
    }
};

test "Hooks.init" {
    var hoks = try Hooks.init(testing.allocator);
    hoks.deinit();
}

test "Hooks.add" {
    const hook = Hook{
        .name = "validation hook",
        .description = "hook description",
        .run = struct {
            pub fn v(_: *Command) anyerror!void {}
        }.v,
    };
    var hooks = try Hooks.init(testing.allocator);
    defer hooks.deinit();
    try hooks.add(Hooks.Location.pre_start, hook);
}

test "Hook.run" {
    var hook = Hook{
        .name = "validation hook",
        .description = "hook description",
        .run = struct {
            pub fn v(_: *Command) anyerror!void {}
        }.v,
    };
    var command = cmd.Command.init(testing.allocator, "command");
    defer command.deinit();
    try hook.run(&command);
}

test "Hooks.run" {
    var hooks = try Hooks.init(testing.allocator);
    defer hooks.deinit();
    const hook = Hook{
        .name = "validation hook",
        .description = "hook description",
        .run = struct {
            pub fn v(_: *Command) anyerror!void {}
        }.v,
    };
    try hooks.add(Hooks.Location.pre_start, hook);
    var command = cmd.Command.init(testing.allocator, "command");
    defer command.deinit();
    try hooks.run(Hooks.Location.pre_start, &command);
}
