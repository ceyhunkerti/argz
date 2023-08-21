const std = @import("std");
const Dash = @import("./dash.zig").Dash;
const testing = std.testing;

pub const Token = @This();

allocator: std.mem.Allocator,

content: []const u8,

pub const KeyValue = struct { key: []const u8, value: []const u8 };

pub const ParseResult = struct {
    const Self = @This();

    dash: Dash = .void,

    body: ?[]const u8 = null,

    kv: ?KeyValue = null,

    pub fn isOption(self: Self) bool {
        return self.dash == .single or self.dash == .double;
    }
    pub fn isKeyValue(self: Self) bool {
        return self.kv != null;
    }
    pub fn isChained(self: Self) bool {
        return self.kv == null and self.dash == .single and self.body != null and self.body.?.len > 1;
    }
    pub fn isAtom(self: Self) bool {
        return self.dash == .void and self.body != null;
    }
    pub fn isOptionTerminator(self: Self) bool {
        return self.dash == .terminator;
    }

    pub fn isHelp(self: Self) bool {
        if (!self.isOption()) return false;
        if (self.isKeyValue()) return false;
        if (self.isChained()) for (self.body.?) |c| if (c == 'h') return true;
        return std.mem.eql(u8, self.body.?, "help") or std.mem.eql(u8, self.body.?, "h");
    }
};

pub fn init(allocator: std.mem.Allocator, content: []const u8) Token {
    return Token{ .allocator = allocator, .content = content };
}

pub fn parse(self: *Token) !ParseResult {
    var result: ParseResult = .{};

    if (std.mem.eql(u8, self.content, "-")) {
        result.body = self.content;
        return result;
    } else if (std.mem.eql(u8, self.content, "--")) {
        result.dash = .terminator;
        return result;
    } else if (std.mem.startsWith(u8, self.content, "--")) {
        result.dash = .double;
        result.body = self.content[2..];
    } else if (std.mem.startsWith(u8, self.content, "-")) {
        result.dash = .single;
        result.body = self.content[1..];
    } else {
        result.body = self.content;
        return result;
    }

    if (std.mem.indexOf(u8, result.body.?, "=")) |idx| {
        result.kv = KeyValue{ .key = result.body.?[0..idx], .value = result.body.?[idx + 1 ..] };
        return result;
    }

    return result;
}

test "short key-value option" {
    const content = "-x=y";
    var token = Token.init(testing.allocator, content);
    var result = try token.parse();
    try testing.expectEqualStrings("x=y", result.body.?);
    try testing.expectEqualStrings("x", result.kv.?.key);
    try testing.expectEqualStrings("y", result.kv.?.value);
    try testing.expect(.single == result.dash);
    try testing.expect(result.isOption());
    try testing.expect(!result.isAtom());
    try testing.expect(!result.isOptionTerminator());
    try testing.expect(!result.isChained());
}

test "long key-value option" {
    const content = "--abc=xyz";
    var token = Token.init(testing.allocator, content);
    var result = try token.parse();
    try testing.expectEqualStrings("abc=xyz", result.body.?);
    try testing.expectEqualStrings("abc", result.kv.?.key);
    try testing.expectEqualStrings("xyz", result.kv.?.value);
    try testing.expect(.double == result.dash);
    try testing.expect(result.isOption());
    try testing.expect(!result.isAtom());
    try testing.expect(!result.isOptionTerminator());
    try testing.expect(!result.isChained());
}

test "chained flags" {
    const content = "-xyz";
    var token = Token.init(testing.allocator, content);
    var result = try token.parse();
    try testing.expectEqualStrings("xyz", result.body.?);
    try testing.expect(result.kv == null);
    try testing.expect(.single == result.dash);
    try testing.expect(result.isOption());
    try testing.expect(!result.isAtom());
    try testing.expect(!result.isOptionTerminator());
    try testing.expect(result.isChained());
}

test "long option body only" {
    const content = "--xyz";
    var token = Token.init(testing.allocator, content);
    var result = try token.parse();
    try testing.expectEqualStrings("xyz", result.body.?);
    try testing.expect(result.kv == null);
    try testing.expect(.double == result.dash);
    try testing.expect(result.isOption());
    try testing.expect(!result.isAtom());
    try testing.expect(!result.isOptionTerminator());
    try testing.expect(!result.isChained());
}

test "short option body only" {
    const content = "-x";
    var token = Token.init(testing.allocator, content);
    var result = try token.parse();
    try testing.expectEqualStrings("x", result.body.?);
    try testing.expect(result.kv == null);
    try testing.expect(.single == result.dash);
    try testing.expect(result.isOption());
    try testing.expect(!result.isAtom());
    try testing.expect(!result.isOptionTerminator());
    try testing.expect(!result.isChained());
}

test "atom" {
    const content = "xyz";
    var token = Token.init(testing.allocator, content);
    var result = try token.parse();
    try testing.expectEqualStrings("xyz", result.body.?);
    try testing.expect(result.kv == null);
    try testing.expect(.void == result.dash);
    try testing.expect(!result.isOption());
    try testing.expect(result.isAtom());
    try testing.expect(!result.isOptionTerminator());
    try testing.expect(!result.isChained());
}

test "isHelp" {
    var token = Token.init(testing.allocator, "abc");
    var r = try token.parse();
    try testing.expect(!r.isHelp());

    token = Token.init(testing.allocator, "-abch");
    r = try token.parse();
    try testing.expect(r.isHelp());

    token = Token.init(testing.allocator, "-h");
    r = try token.parse();
    try testing.expect(r.isHelp());

    token = Token.init(testing.allocator, "--help");
    r = try token.parse();
    try testing.expect(r.isHelp());
}
