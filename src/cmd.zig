const builtin = @import("builtin");
const std = @import("std");
const opt = @import("./opt.zig");
const Token = @import("./token.zig").Token;
const hooks = @import("./hooks.zig");
const utils = @import("./utils.zig");

const testing = std.testing;
const Hooks = hooks.Hooks;
const Hook = hooks.Hook;
const Option = opt.Option;

pub const Error = error{
    NotEnoughArguments,
    ArgumentCountOverflow,
    DuplicateCommandName,
    DuplicateOptionName,
    DublicateSubCommand,
    InvalidArgumentCountSpec,
    NotRootCommand,
    ParseError,
    UnknownOption,
    UnknownFlag,
};

pub const State = enum {
    void,

    expect_value,
    options_terminated,
};

pub fn run(_: *Command) anyerror!void {}

fn run_wrapper(c: *Command) anyerror!void {
    if (c.run) |r| try r(c);
    if (c.getActiveCommand()) |a| try run_wrapper(a);
}

fn validateArgs(c: Command) anyerror!void {
    const al = if (c.args) |a| a.items.len else 0;

    const n = c.n_args orelse return Error.ParseError;

    if (al < (n.lower orelse 0)) return Error.NotEnoughArguments;
    if (n.upper != null and n.upper.? < al) return Error.ArgumentCountOverflow;
}

pub fn validate(c: Command) anyerror!void {
    if (c.options) |options|
        for (options.items) |option| if (option.validate) |vl| try vl(option);

    try validateArgs(c);

    if (c.commands) |subs| for (subs.items) |sub| if (sub.validate) |vl| try vl(sub);
}

fn buildUsage(c: Command) ![]const u8 {
    var cmd_path = std.ArrayList([]const u8).init(c.allocator);
    defer cmd_path.deinit();
    try cmd_path.append(c.name);
    var parent = c.parent;

    while (parent) |p| {
        try cmd_path.append(p.name);
        parent = p.parent;
    }

    var usage = std.ArrayList([]const u8).init(c.allocator);
    defer usage.deinit();
    try usage.append("Usage:");

    var i: usize = 0;
    while (i != cmd_path.items.len) {
        try usage.append(cmd_path.items[cmd_path.items.len - 1 - i]);
        i += 1;
    }
    if (c.n_args) |n| if (n.upper != 0) try usage.append("[arguments]");
    if (c.options) |_| try usage.append("[options]");
    if (c.commands) |_| try usage.append("[commands]");

    return try std.mem.join(c.allocator, " ", usage.items);
}

pub fn help(c: Command) ![]const u8 {
    var buffer = std.ArrayList([]const u8).init(c.allocator);
    defer {
        for (buffer.items) |b| {
            c.allocator.free(b);
        }
        buffer.deinit();
    }

    var usage = try buildUsage(c);
    try buffer.append(usage);
    try buffer.append(
        try std.fmt.allocPrint(c.allocator, "\n{s}", .{c.desc()}),
    );
    if (c.commands) |subs| {
        try buffer.append(try std.fmt.allocPrint(c.allocator, "\nCommands:\n", .{}));
        for (subs.items) |sub|
            try buffer.append(
                try std.fmt.allocPrint(c.allocator, "  {s:<30}{?s}", .{ sub.name, sub.desc() }),
            );
    }
    if (c.options) |options| {
        try buffer.append(try std.fmt.allocPrint(c.allocator, "\nOptions:\n", .{}));
        for (options.items) |o| {
            var h = try o.help(c.allocator);
            var ind = try std.fmt.allocPrint(c.allocator, "  {s}", .{h});
            c.allocator.free(h);
            try buffer.append(ind);
        }
    }
    return try std.mem.join(c.allocator, "\n", buffer.items);
}

pub const Command = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    name: []const u8,

    options: ?std.ArrayList(Option) = null,

    description: ?[]const u8 = null,

    commands: ?std.ArrayList(Command) = null,

    args: ?std.ArrayList([]const u8) = null,

    // *    : zero or more arguments
    // n    : exacly n arguments. n is an unsigned interger
    // n..  : n or more arguments.
    // ..n  : up to n arguments, inclusive
    // n..m : between n and m arguments, inclusive. m is and unsigned integer
    // null : (default) same as zero arguments
    nargs: ?[]const u8 = null,

    validate: ?*const fn (cmd: Self) anyerror!void = validate,

    run: ?*const fn (self: *Self) anyerror!void = run,

    hooks: ?*Hooks = null,

    help: *const fn (cmd: Self) anyerror![]const u8 = help,

    n_args: ?struct { lower: ?u8 = null, upper: ?u8 = null } = null,

    active: bool = false,

    root: bool = true,

    parent: ?*Command = null,

    seek_help: bool = false,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) Self {
        return Self{
            .allocator = allocator,
            .name = name,
        };
    }
    pub fn deinit(self: *Self) void {
        if (self.args) |args| args.deinit();
        if (self.options) |options| options.deinit();
        if (self.commands) |subs| {
            for (subs.items) |*sub| sub.deinit();
            subs.deinit();
        }
    }

    pub fn start(self: *Self) !void {
        if (!self.root) return Error.NotRootCommand;

        if (self.seek_help) {
            try self.seekHelp();
        } else {
            try self.runHooks(Hooks.Location.pre_start);
            try run_wrapper(self);
            try self.runHooks(Hooks.Location.success);
        }
    }

    pub fn parseAndStart(self: *Self) !void {
        try self.parse();
        try self.start();
    }

    pub fn reset(self: *Self) void {
        self.n_args = null;
        self.active = false;
        self.root = true;
        if (self.options) |opts| for (opts.items) |*o| o.reset();
        if (self.commands) |subs| for (subs.items) |*s| s.reset();
    }

    // arguments

    pub fn setNArgs(self: *Self) !void {
        const nargs = self.nargs orelse {
            self.n_args = .{ .lower = 0, .upper = 0 };
            return;
        };

        if (std.mem.eql(u8, nargs, "*")) {
            self.n_args = .{ .lower = 0 };
        } else if (std.mem.startsWith(u8, nargs, "..")) {
            const upper = try std.fmt.parseInt(u8, nargs[2..], 10);
            self.n_args = .{ .lower = 0, .upper = upper };
        } else if (std.mem.endsWith(u8, nargs, "..")) {
            const lower = try std.fmt.parseInt(u8, nargs[0 .. nargs.len - 2], 10);
            self.n_args = .{ .lower = lower };
        } else if (std.mem.indexOf(u8, nargs, "..")) |index| {
            const upper = try std.fmt.parseInt(u8, nargs[index + 2 ..], 10);
            const lower = try std.fmt.parseInt(u8, nargs[0..index], 10);
            self.n_args = .{ .lower = lower, .upper = upper };
        } else {
            const val = try std.fmt.parseInt(u8, nargs, 10);
            self.n_args = .{ .lower = val, .upper = val };
        }
    }

    fn addArgument(self: *Self, argument: []const u8) !void {
        self.args = self.args orelse std.ArrayList([]const u8).init(self.allocator);

        if (self.n_args.?.upper) |upper| if (self.args.?.items.len >= upper)
            return error.ArgumentCountOverflow;

        return self.args.?.append(argument);
    }

    // options

    pub fn addOption(self: *Command, option: Option) !void {
        self.options = self.options orelse std.ArrayList(Option).init(self.allocator);
        try self.options.?.append(option);
    }

    pub fn addOptions(self: *Command, options: []const Option) !void {
        self.options = self.options orelse std.ArrayList(Option).init(self.allocator);
        try self.options.?.appendSlice(options);
    }

    pub fn getOption(self: Self, name: []const u8) ?*Option {
        const options = self.options orelse return null;

        for (options.items) |*o| if (utils.contains([]const u8, o.names, name)) return o;

        return null;
    }

    pub fn getFlag(self: Self, name: []const u8) ?*Option {
        const options = self.options orelse return null;

        for (options.items) |*o| if (o.is_flag and utils.contains([]const u8, o.names, name)) return o;

        return null;
    }

    fn computeOptions(self: *Self) !void {
        if (self.options) |ops| for (ops.items) |*o| try o.compute();
        if (self.commands) |subs| for (subs.items) |*s| try s.computeOptions();
    }

    // subcommands

    pub fn getCommand(self: Command, name: []const u8) ?*Command {
        if (self.commands) |subs| for (subs.items) |*s| if (std.mem.eql(u8, s.name, name)) return s;
        return null;
    }

    pub fn addCommand(self: *Command, command: Command) !void {
        self.commands = self.commands orelse std.ArrayList(Self).init(self.allocator);
        var c = command;
        c.root = false;
        c.parent = self;
        try self.commands.?.append(c);
    }

    pub fn getActiveCommand(self: Self) ?*Self {
        if (self.commands) |subs| for (subs.items) |*s| if (s.active) return s;
        return null;
    }

    // hooks

    pub fn initHooks(self: *Self) !void {
        self.hooks = try Hooks.init(self.allocator);
    }

    pub fn deinitHooks(self: *Self) void {
        if (self.hooks) |h| h.deinit();
    }

    pub fn addHook(self: *Self, loc: Hooks.Location, hook: Hook) !void {
        if (self.hooks) |h| try h.add(loc, hook);
    }

    pub fn runHooks(self: *Self, loc: Hooks.Location) !void {
        if (self.hooks) |h| try h.run(loc, self);
    }

    // validations

    pub fn validateUniqueSubCommandName(self: Self) !void {
        const subs = self.commands orelse return;
        var names = try self.allocator.alloc([]const u8, subs.items.len);
        defer self.allocator.free(names);

        for (subs.items, 0..) |s, i| names[i] = s.name;

        if (utils.hasDuplicate([][]const u8, names)) return Error.DublicateSubCommand;
    }

    pub fn validateNargs(self: Self) !void {
        const nargs = self.nargs orelse return;

        if (std.mem.eql(u8, nargs, "*")) {
            return;
        } else if (std.mem.containsAtLeast(u8, nargs, 3, ".")) {
            return error.InvalidArgumentCountSpec;
        } else if (std.mem.startsWith(u8, nargs, "..") or std.mem.endsWith(u8, nargs, "..")) {
            _ = std.fmt.parseInt(u8, std.mem.trim(u8, nargs, ".."), 10) catch return error.InvalidArgumentCountSpec;
        } else if (std.mem.indexOf(u8, nargs, "..")) |i| {
            _ = std.fmt.parseInt(u8, nargs[i + 2 ..], 10) catch return error.InvalidArgumentCountSpec;
        } else {
            _ = std.fmt.parseInt(u8, nargs, 10) catch return error.InvalidArgumentCountSpec;
        }
    }

    pub fn validateUniqueOptionName(self: Self) !void {
        const opts = self.options orelse return;

        var m = std.StringHashMap(u8).init(self.allocator);
        defer m.deinit();

        for (opts.items) |o| for (o.names) |n| if ((try m.getOrPut(n)).found_existing)
            return Error.DuplicateOptionName;
    }

    pub fn validateParameters(self: Self) anyerror!void {
        try self.validateNargs();
        try self.validateUniqueOptionName();
        try self.validateUniqueSubCommandName();
    }

    fn seekHelp(self: Self) !void {
        if (self.getActiveCommand()) |a| try seekHelp(a.*) else try self.print();
    }

    pub fn print(self: Self) !void {
        if (builtin.is_test) return;

        var content = try self.help(self);
        defer self.allocator.free(content);
        std.debug.print("\n{s}\n", .{content});
    }

    pub fn prepare(self: *Self) !void {
        self.reset();

        try self.validateParameters();
        try self.setNArgs();

        self.active = true;
    }

    pub fn parse(self: *Self) !void {
        var it = try std.process.argsWithAllocator(self.allocator);
        var items = std.ArrayList([]const u8).init(self.allocator);
        defer items.deinit();
        while (it.next()) |n| try items.append(n);
        var arguments = try items.toOwnedSlice();
        defer self.allocator.free(arguments);
        self.parseSlice(arguments[1..]) catch |err| {
            try self.print();
            return err;
        };
    }

    pub fn parseSlice(self: *Self, arguments: ?[]const []const u8) !void {
        var state = State.void;
        var partial: ?*Option = null;

        errdefer {
            self.runHooks(Hooks.Location.parse_error) catch
                std.debug.print("failed to execute parse error hooks!", .{});
        }

        try self.runHooks(Hooks.Location.pre_parse);

        try self.prepare();

        if (arguments) |args| for (args, 0..) |arg, i| {
            if (arg.len == 0) continue;

            var tok = Token.init(self.allocator, arg);
            const token = try tok.parse();

            if (token.isHelp()) {
                self.seek_help = true;
                var p: ?*Self = self.parent;
                while (p != null) {
                    p.?.seek_help = true;
                    p = p.?.parent;
                }
                return;
            }

            if (state == .expect_value and !token.isAtom())
                return error.ParseError;
            if (state == .expect_value and partial == null)
                return error.ParseError;

            if (token.isKeyValue()) {
                var option = self.getOption(token.kv.?.key) orelse return error.UnknownOption;
                option.str = token.kv.?.value;
                continue;
            }

            if (token.isChained()) {
                for (token.body.?) |flag| {
                    var option = self.getFlag(&[_]u8{flag}) orelse return error.UnknownFlag;
                    option.str = "true";
                }
                continue;
            }

            if (token.isOption() and !token.isKeyValue() and !token.isChained()) {
                var option = self.getOption(token.body.?) orelse return error.UnknownOption;
                if (option.is_flag) {
                    option.str = "true";
                } else {
                    if (state == .expect_value) return error.ParseError;
                    partial = option;
                    state = .expect_value;
                    continue;
                }
            } else if (token.isAtom()) {
                const atom = token.body orelse return Error.ParseError;

                // can be an argument or the value of the partial or a sub command
                if (state == .expect_value) {
                    if (partial) |p| {
                        p.str = token.body;
                        partial = null;
                        state = .void;
                        continue;
                    }
                } else if (self.getCommand(atom)) |sub| {
                    sub.root = false;
                    sub.parent = self;
                    try sub.parseSlice(if (i == args.len) null else args[i + 1 ..]);
                    break;
                } else {
                    try self.addArgument(atom);
                    continue;
                }
            }
        };
        if (!self.seek_help) {
            try self.computeOptions();
            if (self.validate) |vl| try vl(self.*);
            try self.runHooks(Hooks.Location.parse_success);
        }
    }

    // convenience

    pub fn desc(self: Self) []const u8 {
        return self.description orelse "";
    }
};

test "Command.init" {
    var command = Command.init(testing.allocator, "my-command");
    defer command.deinit();
    try testing.expectEqualStrings("my-command", command.name);
}

test "Command.addOption" {
    var command = Command.init(testing.allocator, "my-command");
    defer command.deinit();
    var option = Option{ .names = &.{"my-option"} };
    try command.addOption(option);
    try testing.expect(command.options != null);
    try testing.expect(command.options.?.items.len == 1);
    try testing.expectEqualStrings("my-option", command.options.?.items[0].names[0]);
}

test "Command.addOptions" {
    var command = Command.init(testing.allocator, "my-command");
    defer command.deinit();
    var fo = Option{ .names = &.{"my-first-option"} };
    var so = Option{ .names = &.{"my-second-option"} };
    try command.addOptions(&.{ fo, so });
    try testing.expect(command.options != null);
    try testing.expect(command.options.?.items.len == 2);
    try testing.expectEqualStrings("my-first-option", command.options.?.items[0].names[0]);
    try testing.expectEqualStrings("my-second-option", command.options.?.items[1].names[0]);
}

test "Command.validateUniqueSubCommandName" {
    var command = Command.init(testing.allocator, "my-command");
    defer command.deinit();

    try command.validateUniqueSubCommandName();

    var s0 = Command.init(testing.allocator, "x");
    try command.addCommand(s0);

    var s1 = Command.init(testing.allocator, "s");
    try command.addCommand(s1);

    try command.validateUniqueSubCommandName();

    var s2 = Command.init(testing.allocator, "s");
    try command.addCommand(s2);

    try testing.expectError(Error.DublicateSubCommand, command.validateUniqueSubCommandName());
}

test "Command.validateUniqueOptionName" {
    var command = Command.init(testing.allocator, "my-command");
    defer command.deinit();

    try command.validateUniqueOptionName();

    var o1 = Option{ .is_flag = true, .names = &.{ "a", "b" } };
    var o2 = Option{ .is_flag = true, .names = &.{ "a", "c" } };

    try command.addOption(o1);
    try command.validateUniqueOptionName();

    o1.names = &.{ "a", "a" };
    try command.addOption(o1);
    try testing.expectError(Error.DuplicateOptionName, command.validateUniqueOptionName());

    try command.addOption(o2);
    try testing.expectError(Error.DuplicateOptionName, command.validateUniqueOptionName());
}

test "Command.setNArgs" {
    var command = Command.init(testing.allocator, "my-command");
    defer command.deinit();

    try command.setNArgs();
    try testing.expectEqual(command.n_args.?.lower, 0);
    try testing.expectEqual(command.n_args.?.upper, 0);

    command.nargs = "*";
    try command.setNArgs();
    try testing.expectEqual(command.n_args.?.lower, 0);
    try testing.expect(command.n_args.?.upper == null);

    command.nargs = "1..";
    try command.setNArgs();
    try testing.expectEqual(command.n_args.?.lower, 1);
    try testing.expect(command.n_args.?.upper == null);

    command.nargs = "..1";
    try command.setNArgs();
    try testing.expectEqual(command.n_args.?.lower, 0);
    try testing.expectEqual(command.n_args.?.upper, 1);

    command.nargs = "1..2";
    try command.setNArgs();
    try testing.expectEqual(command.n_args.?.lower, 1);
    try testing.expectEqual(command.n_args.?.upper, 2);
}

test "Command.validateNargs" {
    var command = Command.init(testing.allocator, "command");
    defer command.deinit();
    for ([_][]const u8{ "1", "0", "1..", "..1", "1..2" }) |nargs| {
        command.nargs = nargs;
        try command.validateNargs();
    }
    for ([_][]const u8{ ".", ".1", "1.", "...", "..", "1..2..3", "1..2#", "##1", "1%%", "1$2" }) |nargs| {
        command.nargs = nargs;
        try testing.expectError(error.InvalidArgumentCountSpec, command.validateNargs());
    }
}

test "Command.computeOptions" {
    var command = Command.init(testing.allocator, "my-command");
    defer command.deinit();
    var option = Option{
        .names = &.{ "my-option", "o" },
        .type = opt.ValueType.boolean,
        .str = "true",
    };
    try command.addOption(option);
    var sub = Command.init(testing.allocator, "sub");
    try sub.addOption(option);
    try command.addCommand(sub);
    try command.computeOptions();

    var option2 = Option{
        .names = &.{"option2"},
        .type = opt.ValueType.string,
        .required = true,
        .str = null,
    };

    try command.getCommand("sub").?.addOption(option2);

    try testing.expectError(opt.Error.MissingValue, command.computeOptions());
}

test "Command.parse basic success" {
    var command = Command.init(testing.allocator, "mycommand");
    defer command.deinit();
    var i_option = Option{
        .required = false,
        .names = &.{ "int-option", "i" },
        .default = "10",
        .type = opt.ValueType.int,
    };
    var s_option = Option{
        .required = false,
        .names = &.{ "str-option", "s" },
        .default = "my-string",
        .type = opt.ValueType.string,
    };
    var b_option = Option{
        .required = false,
        .names = &.{ "bool-option", "b" },
        .is_flag = true,
        .default = "false",
    };
    var x_option = Option{
        .required = false,
        .names = &.{ "xflag", "x" },
        .is_flag = true,
    };
    try command.addOptions(&[_]Option{ b_option, s_option, i_option, x_option });

    try command.parseSlice(
        &.{ "--int-option=1", "-b", "-s=hello" },
    );

    var option = command.getFlag("b");
    try testing.expect(option != null);
    try testing.expectEqual(option.?.value.?.boolean, true);

    option = command.getOption("s");
    try testing.expect(option != null);
    try testing.expectEqualStrings(option.?.value.?.string, "hello");

    option = command.getOption("i");
    try testing.expect(option != null);
    try testing.expectEqual(option.?.value.?.int, 1);

    command.nargs = "*";
    try command.parseSlice(
        &.{ "argument_1", "argument_2", "argument_3" },
    );
    try testing.expectEqual(command.args.?.items.len, 3);
    try testing.expectEqualStrings(command.args.?.items[0], "argument_1");
    try testing.expectEqualStrings(command.args.?.items[1], "argument_2");
    try testing.expectEqualStrings(command.args.?.items[2], "argument_3");
}

test "Command.parse error" {
    var command = Command.init(testing.allocator, "mycommand");
    defer command.deinit();
    try testing.expectError(error.UnknownOption, command.parseSlice(&.{"--option"}));
    try testing.expectError(error.UnknownFlag, command.parseSlice(&.{"-abc"}));

    for ([_][]const u8{ "0", "1", "..1", "0..1" }) |nargs| {
        command.nargs = nargs;
        try testing.expectError(error.ArgumentCountOverflow, command.parseSlice(&.{ "abc", "def" }));
    }
}

test "Command.parse chained flags" {
    var command = Command.init(testing.allocator, "command");
    command.nargs = "*";

    defer command.deinit();
    var a = Option{ .names = &.{"a"}, .is_flag = true };
    var b = Option{ .names = &.{"b"}, .is_flag = true };
    var c = Option{ .names = &.{"c"}, .is_flag = true };
    try command.addOptions(&[_]Option{ a, b });
    try command.addOption(c);
    try command.parseSlice(&.{"-abc"});

    try command.parseSlice(&.{ "-ac", "arg", "arg" });
    try testing.expectEqual(command.options.?.items[1].value.?.boolean, false);
}

test "Command.parse with subcommands" {
    var root = Command.init(testing.allocator, "root");
    defer root.deinit();
    var sub = Command.init(testing.allocator, "sub");
    var a = Option{ .names = &.{"a"}, .is_flag = true };
    var b = Option{ .names = &.{"b"}, .is_flag = true };
    var c = Option{ .names = &.{"c"}, .is_flag = true };
    try sub.addOptions(&.{ a, b, c });
    try root.addCommand(sub);
    try root.parseSlice(&.{ "sub", "-abc" });

    root.getCommand("sub").?.nargs = "*";
    try root.parseSlice(&.{ "sub", "-ac", "arg", "arg" });
    try testing.expectEqual(sub.options.?.items[1].value.?.boolean, false);
}

test "buildUsage" {
    var c = Command.init(testing.allocator, "root");
    defer c.deinit();
    var h1 = try help(c);
    defer testing.allocator.free(h1);
    try testing.expectEqualStrings("Usage: root\n\n", h1);
    var sub = Command.init(testing.allocator, "sub");
    try c.addCommand(sub);
    var h2 = try help(c.getCommand("sub").?.*);
    defer testing.allocator.free(h2);
    try testing.expectEqualStrings("Usage: root sub\n\n", h2);
}

test "Command.help" {
    var command = Command.init(testing.allocator, "root");
    command.description = "my root command";
    defer command.deinit();
    var e1 = try command.help(command);
    defer testing.allocator.free(e1);
    var h1 = "Usage: root" ++ "\n\nmy root command";

    try testing.expectEqualStrings(h1, e1);

    var o1 = Option{
        .is_flag = true,
        .names = &.{ "o", "op1" },
        .description = "option 1",
    };
    var o2 = Option{
        .is_flag = true,
        .names = &.{"x"},
        .description = "option 2",
    };
    try command.addOptions(&.{ o1, o2 });
    var e2 = try command.help(command);
    defer testing.allocator.free(e2);
    var h2 =
        "Usage: root [options]\n" ++
        "\nmy root command\n" ++
        "\nOptions:\n\n" ++
        "  -o,--op1                      option 1\n" ++
        "  -x                            option 2";
    try testing.expectEqualStrings(h2, e2);

    var s1 = Command.init(testing.allocator, "subcommand");
    s1.description = "subcommand desc";
    try command.addCommand(s1);
    var e3 = try command.help(command);
    defer testing.allocator.free(e3);
    var h3 =
        "Usage: root [options] [commands]\n" ++
        "\nmy root command\n" ++
        "\nCommands:\n\n" ++
        "  subcommand                    subcommand desc\n" ++
        "\nOptions:\n\n" ++
        "  -o,--op1                      option 1\n" ++
        "  -x                            option 2";
    try testing.expectEqualStrings(h3, e3);
}

test "Command.print" {
    var root = Command.init(testing.allocator, "root-command");
    defer root.deinit();
    var o1 = Option{ .names = &.{ "a", "abc" }, .is_flag = true };
    try root.addOption(o1);
    try root.print();
}
