// ! do not set attributes beginning with _ directly

const Option = @This();
const std = @import("std");
const mem = std.mem;
const testing = std.testing;

pub const ValueType = enum {
    String,
    Integer,
    Boolean,
};

pub const Value = union(ValueType) {
    String: []const u8,
    Integer: i32,
    Boolean: bool,
    // StringArray: std.ArrayList([]const u8),
};

allocator: mem.Allocator,

_raw_value: ?[]const u8 = null,

_value: ?Value = null,

value_type: ValueType = ValueType.String,

// Options can have multiple names
// This also enables both short and long names to be specified
// eg. -c, --config
// short options are always single characters and be chained with other options
names: std.ArrayList([]const u8) = undefined,

default: ?Value = null,

// it's owned by the option and managed inside this.
description: ?[]const u8 = null,

// different than bool type, does not require a value.
// -v, --version
is_flag: bool = false,

// custom validation function for this option.
validation: ?*const fn (self: Option) anyerror!void = null,

// If command accepts unknown options and this one is, then this is set to true during parse step.
// You can also use isUnknown() to check if an option is unknown in your app.
_is_unknown_option: bool = false,

required: bool = false,

pub fn init(
    allocator: mem.Allocator,
    value_type: ValueType,
    names: []const []const u8,
    description: ?[]const u8,
) !*Option {
    var option = try allocator.create(Option);
    option.* = .{
        .allocator = allocator,
        .value_type = value_type,
        .description = if (description) |d| try allocator.dupe(u8, d) else null,
    };
    option.names = std.ArrayList([]const u8).init(allocator);
    for (names) |name| {
        option.names.append(allocator.dupe(u8, name) catch unreachable) catch unreachable;
    }
    return option;
}

pub fn deinit(self: Option) void {
    for (self.names.items) |name| self.allocator.free(name);
    self.names.deinit();
    if (self._value) |val| switch (val) {
        .String => |v| self.allocator.free(v),
        else => {},
    };
    if (self.description) |d| self.allocator.free(d);
}

pub fn destroy(o: *Option) void {
    o.deinit();
    o.allocator.destroy(o);
}

pub fn isUnknown(self: Option) bool {
    return self._is_unknown_option;
}

pub fn validate(self: Option) anyerror!void {
    if (self.validation) |f| try f(self);
}

pub fn help(self: Option) ![]const u8 {
    var result = std.ArrayList(u8).init(self.allocator);
    defer result.deinit();

    for (self.names.items, 0..) |name, i| {
        try result.append('-');
        if (name.len > 1) try result.append('-');
        try result.appendSlice(name);
        if (i != self.names.items.len - 1) try result.append(',');
    }
    if (result.items.len < 30) {
        try result.appendNTimes(' ', 30 - result.items.len);
    } else {
        try result.appendNTimes(' ', 1);
    }
    if (self.description) |desc| {
        try result.appendSlice(desc);
    }
    return try result.toOwnedSlice();
}

test "Option.help" {
    const allocator = std.testing.allocator;
    var o = try Option.init(allocator, ValueType.String, &[_][]const u8{ "o", "option" }, "my option description");
    defer Option.destroy(o);

    const s = try o.help();
    defer allocator.free(s);

    try testing.expectEqualStrings("-o,--option                   my option description", s);
}

pub fn hasName(self: Option, name: []const u8) bool {
    for (self.names.items) |n| if (mem.eql(u8, name, n)) return true;
    return false;
}

pub fn set(self: *Option, value: []const u8) !void {
    self._raw_value = value;
    self._value = switch (self.value_type) {
        .Boolean => .{ .Boolean = mem.eql(u8, value, "true") },
        .String => .{ .String = try self.allocator.dupe(u8, value) },
        .Integer => .{ .Integer = try std.fmt.parseInt(i32, value, 10) },
    };
}
test "Option.set" {
    const allocator = std.testing.allocator;
    var o1 = try Option.init(allocator, ValueType.String, &[_][]const u8{ "o", "option" }, null);
    defer Option.destroy(o1);
    try o1.set("value");
    try testing.expectEqualStrings("value", o1.getString().?);

    var o2 = try Option.init(allocator, ValueType.Integer, &[_][]const u8{ "o", "option" }, null);
    defer Option.destroy(o2);

    try o2.set("10");
    try testing.expectEqual(Value{ .Integer = 10 }, o2.get());
    try testing.expectEqual(o2.getInt(), 10);

    var o3 = try Option.init(allocator, ValueType.Boolean, &[_][]const u8{ "o", "option" }, null);
    defer Option.destroy(o3);

    try o3.set("true");
    try testing.expectEqual(Value{ .Boolean = true }, o3.get());
    try testing.expectEqual(o3.getBoolean(), true);

    var o4 = try Option.init(allocator, ValueType.Integer, &[_][]const u8{ "o", "option" }, null);
    defer Option.destroy(o4);

    try o4.set("20");

    const E = error{
        InvalidOptionValue,
    };
    const s = struct {
        pub fn validation(self: Option) E!void {
            if (self.getInt().? > 10) return error.InvalidOptionValue;
        }
    };
    o4.validation = s.validation;
    try testing.expectError(E.InvalidOptionValue, o4.validate());
}

pub fn get(self: Option) ?Value {
    return self._value;
}
pub fn getInt(self: Option) ?i32 {
    return if (self._value) |v| v.Integer else null;
}
pub fn getString(self: Option) ?[]const u8 {
    return if (self._value) |v| v.String else null;
}
pub fn getBoolean(self: Option) ?bool {
    return if (self._value) |v| v.Boolean else null;
}
