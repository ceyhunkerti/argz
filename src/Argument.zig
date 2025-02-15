const Argument = @This();

const std = @import("std");

pub const Error = error{
    TooManyValues,
    ZeroArgumentCountNotAllowed,
    CountValueRequiresArrayType,
    MissingRequiredArgument,
};

pub const Type = enum {
    String,
    Integer,
    Boolean,
    StringArray,
    IntegerArray,
    BooleanArray,
};

// Union of the possible argument types
pub const Value = union(Type) {
    String: []const u8,
    Integer: i32,
    // ! case sensitive "true" is considered as true anything else is false
    Boolean: bool,

    StringArray: std.ArrayList([]const u8),
    IntegerArray: std.ArrayList(i32),
    BooleanArray: std.ArrayList(bool),
};

allocator: std.mem.Allocator,
name: []const u8,
type: Type = .String,

_value: ?Value = null,
// set * means you can set the argument multiple times

_count: u8 = 1,

required: bool = false,

description: ?[]const u8 = null,

pub fn init(allocator: std.mem.Allocator, name: []const u8, arg_type: Type, description: ?[]const u8, count: ?u8, required: ?bool) !Argument {
    if (count) |c| if (c == 0) return error.ZeroArgumentCountNotAllowed;

    const argument_type: Type = argument_type: {
        if (count) |c| if (c > 0 or c == '*') {
            switch (arg_type) {
                .String => break :argument_type .StringArray,
                .Integer => break :argument_type .IntegerArray,
                .Boolean => break :argument_type .BooleanArray,
                else => return error.CountValueRequiresArrayType,
            }
        };
        break :argument_type arg_type;
    };

    return .{
        .allocator = allocator,
        .name = allocator.dupe(u8, name) catch unreachable,
        .type = argument_type,
        .description = if (description) |d| allocator.dupe(u8, d) catch unreachable else null,
        ._count = count orelse 1,
        .required = required orelse false,
    };
}

pub fn deinit(self: Argument) void {
    self.allocator.free(self.name);
    if (self.description) |d| self.allocator.free(d);
    if (self._value) |value| switch (self.type) {
        .String => self.allocator.free(value.String),
        .IntegerArray => value.IntegerArray.deinit(),
        .BooleanArray => value.BooleanArray.deinit(),
        .StringArray => {
            for (value.StringArray.items) |item| self.allocator.free(item);
            value.StringArray.deinit();
        },
        else => {},
    };
}

pub fn setValue(self: *Argument, value: []const u8) !void {
    switch (self.type) {
        .String => {
            self._value = .{ .String = self.allocator.dupe(u8, value) catch unreachable };
        },
        .Boolean => self._value = .{ .Boolean = std.mem.eql(u8, value, "true") },
        .Integer => self._value = .{ .Integer = try std.fmt.parseInt(i32, value, 10) },
        .StringArray => {
            if (self._value == null) {
                self._value = .{ .StringArray = std.ArrayList([]const u8).init(self.allocator) };
            }
            if (self._count != '*' and self._value.?.StringArray.items.len == self._count) {
                return error.TooManyValues;
            }
            self._value.?.StringArray.append(self.allocator.dupe(u8, value) catch unreachable) catch unreachable;
        },
        .IntegerArray => {
            if (self._value == null) {
                self._value = .{ .IntegerArray = std.ArrayList(i32).init(self.allocator) };
            }
            if (self._count != '*' and self._value.?.IntegerArray.items.len == self._count) {
                return error.TooManyValues;
            }
            self._value.?.IntegerArray.append(try std.fmt.parseInt(i32, value, 10)) catch unreachable;
        },
        .BooleanArray => {
            if (self._value == null) {
                self._value = .{ .BooleanArray = std.ArrayList(bool).init(self.allocator) };
            }
            if (self._count != '*' and self._value.?.BooleanArray.items.len == self._count) {
                return error.TooManyValues;
            }
            self._value.?.BooleanArray.append(std.mem.eql(u8, value, "true")) catch unreachable;
        },
    }
}

pub fn isArrayType(self: Argument) bool {
    return switch (self.type) {
        .StringArray,
        .IntegerArray,
        .BooleanArray,
        => true,
        else => false,
    };
}

pub fn validate(self: Argument) !void {
    // todo check other requirements.
    if (self.required and self._value == null) return Error.MissingRequiredArgument;
}

pub fn getString(self: Argument) !?[]const u8 {
    if (self._value) |v| {
        switch (v) {
            .String => return v.String,
            else => unreachable,
        }
    } else {
        return null;
    }
}

pub fn getBoolean(self: Argument) !?bool {
    if (self._value) |v| {
        switch (v) {
            .Boolean => return v.Boolean,
            else => unreachable,
        }
    } else {
        return null;
    }
}

pub fn getInteger(self: Argument) !?i32 {
    if (self._value) |v| {
        switch (v) {
            .Integer => return v.Integer,
            else => unreachable,
        }
    } else {
        return null;
    }
}
