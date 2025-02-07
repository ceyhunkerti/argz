const Option = @This();
const std = @import("std");

pub const ValueType = enum {
    String,
    Int,
    Boolean,
};

pub const Value = union(ValueType) {
    String: []const u8,
    Int: i32,
    Boolean: bool,
    // StringArray: std.ArrayList([]const u8),
};

allocator: std.mem.Allocator,

_raw_value: []const u8 = undefined,

_value: Value = undefined,

value_type: ValueType = ValueType.String,

names: std.ArrayList([]const u8) = undefined,

comptime default: ?Value = null,

description: ?[]const u8 = null,

// different than bool type, does not require a value.
is_flag: bool = false,

validation: ?*const fn (self: Option) anyerror!void = null,

_is_dynamic_option: bool = false,

pub fn init(allocator: std.mem.Allocator, value_type: ValueType, names: []const []const u8) Option {
    var option = Option{
        .allocator = allocator,
        .value_type = value_type,
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
    switch (self._value) {
        .String => |v| self.allocator.free(v),
        else => {},
    }
}

pub fn validate(self: Option) anyerror!void {
    if (self.validation) |f| try f(self);
}

pub fn help(self: Option, allocator: std.mem.Allocator) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
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
    var o = Option.init(allocator, ValueType.String, &[_][]const u8{ "o", "option" });
    defer o.deinit();
    o.description = "my option description";

    const s = try o.help(allocator);
    defer allocator.free(s);

    try std.testing.expectEqualStrings("-o,--option                   my option description", s);
}

pub fn hasName(self: Option, name: []const u8) bool {
    for (self.names.items) |n| if (std.mem.eql(u8, name, n)) return true;
    return false;
}

pub fn set(self: *Option, value: []const u8) !void {
    self._raw_value = value;
    self._value = switch (self.value_type) {
        .Boolean => .{ .Boolean = std.mem.eql(u8, value, "true") },
        .String => .{ .String = try self.allocator.dupe(u8, value) },
        .Int => .{ .Int = try std.fmt.parseInt(i32, value, 10) },
    };
}
test "Option.set" {
    const allocator = std.testing.allocator;
    var o1 = Option.init(allocator, ValueType.String, &[_][]const u8{ "o", "option" });
    defer o1.deinit();
    try o1.set("value");
    try std.testing.expectEqualStrings("value", o1.getString());

    var o2 = Option.init(allocator, ValueType.Int, &[_][]const u8{ "o", "option" });
    defer o2.deinit();
    try o2.set("10");
    try std.testing.expectEqual(Value{ .Int = 10 }, o2.get());
    try std.testing.expectEqual(o2.getInt(), 10);

    var o3 = Option.init(allocator, ValueType.Boolean, &[_][]const u8{ "o", "option" });
    defer o3.deinit();
    try o3.set("true");
    try std.testing.expectEqual(Value{ .Boolean = true }, o3.get());
    try std.testing.expectEqual(o3.getBoolean(), true);

    var o4 = Option.init(allocator, ValueType.Int, &[_][]const u8{ "o", "option" });
    defer o4.deinit();
    try o4.set("20");

    const E = error{
        InvalidOptionValue,
    };
    const s = struct {
        pub fn validation(self: Option) E!void {
            if (self.getInt() > 10) return error.InvalidOptionValue;
        }
    };
    o4.validation = s.validation;
    try std.testing.expectError(E.InvalidOptionValue, o4.validate());
}

pub fn get(self: Option) Value {
    return self._value;
}
pub fn getInt(self: Option) i32 {
    return self._value.Int;
}
pub fn getString(self: Option) []const u8 {
    return self._value.String;
}
pub fn getBoolean(self: Option) bool {
    return self._value.Boolean;
}
