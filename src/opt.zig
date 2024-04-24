const std = @import("std");
const utils = @import("./utils.zig");

const testing = std.testing;

pub const Error = error{
    DuplicateName,
    InvalidParameters,
    MissingValue,
    UnknownValueType,
    WrongValueAccessor,
};

pub const ValueType = enum {
    string,
    int,
    boolean,
};

pub const Value = union(ValueType) {
    string: []const u8,
    int: i32,
    boolean: bool,
};

fn validate(_: Option) anyerror!void {}

pub const Option = struct {
    const Self = @This();

    // defaults to true. if set to false will use the default value.
    required: bool = true,

    // list of unique names for this option. single character strings are interpreted as short names
    // and two or more character strings are interpreted as long option names.
    names: []const []const u8,

    // different than bool type, does not require a value.
    is_flag: bool = false,

    // description of the option
    description: ?[]const u8 = null,

    // default value of the option, parset according to the type value
    default: ?[]const u8 = null,

    // option's value type
    type: ValueType = ValueType.string,

    // parsed value of the option.
    // computed at the parse time.
    // DO NOT set this attribute directly
    value: ?Value = null,

    // assigned at the parse time. raw value of the option.
    // DO NOT set this attribute directly
    str: ?[]const u8 = null,

    // custom validation function for the option.
    validate: ?*const fn (self: Self) anyerror!void = validate,

    pub fn init(names: []const []const u8) Self {
        return Self{ .names = names };
    }

    pub fn help(self: Self, allocator: std.mem.Allocator) ![]const u8 {
        var buffer = std.ArrayList([]const u8).init(allocator);
        defer buffer.deinit();

        for (self.names) |name| {
            const dash = if (name.len == 1) "-" else "--";
            const n = try std.fmt.allocPrint(allocator, "{s}{s}", .{ dash, name });
            try buffer.append(n);
        }
        const names = try std.mem.join(allocator, ",", buffer.items);
        defer allocator.free(names);
        defer for (buffer.items) |b| allocator.free(b);

        return try std.fmt.allocPrint(allocator, "{s:<30}{?s}", .{ names, self.desc() });
    }

    pub fn reset(self: *Self) void {
        self.value = null;
        self.str = null;
    }

    pub fn eq(self: Self, name: []const u8) bool {
        for (self.names) |n| if (std.mem.eql(u8, name, n)) return true;
        return false;
    }

    pub fn setValue(self: *Self, str: []const u8) !void {
        if (self.is_flag) {
            self.value = Value{ .boolean = std.mem.eql(u8, str, "true") };
        } else {
            self.value = switch (self.type) {
                ValueType.boolean => Value{ .boolean = std.mem.eql(u8, str, "true") },
                ValueType.string => Value{ .string = str },
                ValueType.int => Value{ .int = try std.fmt.parseInt(i32, str, 10) },
            };
        }
    }

    pub fn compute(self: *Self) !void {
        if (self.str) |str| {
            try self.setValue(str);
        } else if (self.default) |default| {
            try self.setValue(default);
        } else if (self.is_flag) {
            try self.setValue("false");
        } else if (self.required) {
            return Error.MissingValue;
        }
    }
    // convenience

    pub fn isBoolean(self: Self) bool {
        return self.type == ValueType.boolean or self.is_flag;
    }

    pub fn boolValue(self: Self) ?bool {
        if (self.value) |v| return v.boolean;
        return null;
    }

    pub fn stringValue(self: Self) ?[]const u8 {
        if (self.value) |v| return v.string;
        return null;
    }

    pub fn intValue(self: Self) ?i32 {
        if (self.value) |v| return v.int;
        return null;
    }

    pub fn desc(self: Self) []const u8 {
        return self.description orelse "";
    }

    // validations

    pub fn validateRequired(self: Self) !void {
        if (self.required and self.default != null) return Error.InvalidParameters;
    }

    pub fn validateNames(self: Self) !void {
        if (utils.hasDuplicate([]const []const u8, self.names)) return Error.DuplicateName;
    }
};

test "initialize an `option`" {
    const o = Option.init(&[_][]const u8{ "o", "option" });
    try testing.expectEqual(o.names.len, 2);
}

test "show `option` help" {
    var o = Option.init(&[_][]const u8{ "o", "option" });
    o.description = "my option description";
    const help = try o.help(testing.allocator);
    defer testing.allocator.free(help);
    const expected = "-o,--option                   my option description";
    try testing.expectEqualStrings(expected, help);
}

test "Option.eq" {
    var o = Option.init(&[_][]const u8{ "o", "option" });
    for (&[_][]const u8{ "o", "option" }) |n| {
        try testing.expect(o.eq(n));
    }
    try testing.expect(!o.eq("O"));
    try testing.expect(!o.eq("--option"));
    try testing.expect(!o.eq("-o"));
}

test "Option.compute required int" {
    var o = Option{
        .names = &[_][]const u8{"op"},
        .type = ValueType.int,
        .str = "10",
        .required = true,
    };
    try o.compute();
    try testing.expectEqual(o.value.?.int, 10);
}

test "Option.compute required string" {
    var o = Option{
        .names = &[_][]const u8{"op"},
        .type = ValueType.string,
        .str = "10",
        .required = true,
    };
    try o.compute();
    try testing.expectEqualStrings(o.value.?.string, "10");
}

test "Option.compute required bool" {
    var o = Option{
        .names = &[_][]const u8{"op"},
        .type = ValueType.boolean,
        .str = "true",
        .required = true,
    };
    try o.compute();
    try testing.expectEqual(o.value.?.boolean, true);
}

test "Option.compute optional int" {
    var o = Option{
        .names = &[_][]const u8{"op"},
        .type = ValueType.int,
        .required = false,
    };
    try o.compute();
    try testing.expect(o.value == null);
}

test "Option.compute optional string" {
    var o = Option{
        .names = &[_][]const u8{"op"},
        .type = ValueType.string,
        .required = false,
    };
    try o.compute();
    try testing.expect(o.value == null);
}

test "Option.compute optional bool" {
    var o = Option{
        .names = &[_][]const u8{"op"},
        .type = ValueType.boolean,
        .required = false,
    };
    try o.compute();
    try testing.expect(o.value == null);
}

test "Option.compute optional int with default" {
    var o = Option{
        .names = &[_][]const u8{"op"},
        .type = ValueType.int,
        .required = false,
        .default = "10",
    };
    try o.compute();
    try testing.expectEqual(o.intValue().?, 10);
}

test "Option.compute optional string with default" {
    var o = Option{
        .names = &[_][]const u8{"op"},
        .type = ValueType.string,
        .required = false,
        .default = "10",
    };
    try o.compute();
    try testing.expectEqualStrings(o.stringValue().?, "10");
}

test "Option.compute optional boolean with default" {
    var o = Option{
        .names = &[_][]const u8{"op"},
        .type = ValueType.boolean,
        .required = false,
        .default = "true",
    };
    try o.compute();
    try testing.expectEqual(o.boolValue().?, true);
}

test "Option.compute flag" {
    var o = Option{
        .names = &[_][]const u8{"op"},
        .is_flag = true,
        .str = "true",
    };
    try o.compute();
    try testing.expectEqual(o.boolValue().?, true);
}

test "Option.compute flag default" {
    var o = Option{
        .names = &[_][]const u8{"op"},
        .is_flag = true,
        .default = "true",
    };
    try o.compute();
    try testing.expectEqual(o.value.?.boolean, true);
}

test "Option.compute flag unset" {
    var o = Option{
        .names = &[_][]const u8{"op"},
        .is_flag = true,
    };
    try o.compute();
    try testing.expectEqual(o.value.?.boolean, false);
}

test "Option.validateRequired" {
    var o = Option{
        .names = &[_][]const u8{"op"},
        .type = ValueType.int,
        .str = "10",
        .required = true,
        .default = "10",
    };
    try testing.expectError(Error.InvalidParameters, o.validateRequired());
}
