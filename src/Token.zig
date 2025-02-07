// ! do not set attributes beginning with _ directly

const std = @import("std");
const mem = std.mem;
const Token = @This();

pub const Error = error{
    TokenHasNoValue,
    TokenIsKeyValue,
    TokenHasNoKey,
    InvalidShortOption,
    InvalidEqualPosition,
};

pub const Dash = enum {
    single_dash,
    double_dash,
    terminator_dash,
};

pub const KeyValue = struct {
    key: []const u8,
    value: []const u8,
};

allocator: std.mem.Allocator,
content: []const u8,

_dash: ?Dash = null,
_key: ?[]const u8 = null,
_value: ?[]const u8 = null,

pub fn init(allocator: std.mem.Allocator, content: []const u8) Token {
    return Token{ .allocator = allocator, .content = content };
}

pub fn parse(self: *Token) !void {
    var str: ?[]const u8 = null;

    if (mem.eql(u8, self.content, "-")) {
        // its only a single dash without postfix
        self._key = self.content;
    } else if (mem.eql(u8, self.content, "--")) {
        // its only a double dash without postfix then it's marked as terminator.
        self._dash = .terminator_dash;
    } else if (mem.startsWith(u8, self.content, "--")) {
        self._dash = .double_dash;
        str = self.content[2..];
    } else if (mem.startsWith(u8, self.content, "-")) {
        self._dash = .single_dash;
        str = self.content[1..];
    } else {
        str = self.content;
    }

    if (str) |s| {
        if (quoteEnclosed(s)) {
            // "some=thing"
            self._key = s;
        } else if (self.hasDash()) {
            if (std.mem.indexOf(u8, s, "=")) |idx| {
                //
                if (idx == 0) {
                    // --=abc, -=abc
                    return Error.InvalidEqualPosition;
                } else {
                    self._key = s[0..idx];
                }
                if (idx < s.len - 1) {
                    self._value = s[idx + 1 ..];
                }
            } else {
                self._key = s;
            }
        } else {
            self._key = s;
        }
    }

    // validate
    if (self._dash) |d| if (self._key) |k| if (self._value != null) {
        if (d == .single_dash and k.len > 1) {
            // -abc=something is not valid it should be a long option --abc=something
            return Error.InvalidShortOption;
        }
    };
}

fn quoteEnclosed(content: []const u8) bool {
    if (content.len < 2) return false;
    return mem.startsWith(u8, content, "\"") and mem.endsWith(u8, content, "\"");
}

pub fn isHelp(self: Token) bool {
    if (self._key) |k| {
        return mem.eql(u8, k, "help") or mem.eql(u8, k, "h");
    }
    return false;
}

pub fn isOption(self: Token) bool {
    return self._dash != null;
}

pub fn isChainedOption(self: Token) bool {
    if (self._dash == .single_dash) {
        if (self._key) |k| return k.len > 1;
    }
    return false;
}

pub fn isUnchainedOption(self: Token) bool {
    if (self._dash == .double_dash) return true;
    if (self._dash == .single_dash) if (self._key) |k| return k.len == 1;
    return false;
}

pub fn key(self: Token) ![]const u8 {
    if (self._key) |k| return k;
    return error.TokenHasNoKey;
}
pub fn value(self: Token) ![]const u8 {
    if (self._value) |v| return v;
    return error.TokenHasNoValue;
}

pub fn isKeyValue(self: Token) bool {
    return self._key != null and self._value != null;
}

pub fn isAtom(self: Token) bool {
    return self._dash == null and self._key != null and self._value == null;
}

pub fn isEqual(self: Token) bool {
    if (self._key) |k| return k.len == 1 and k[0] == '=';
    return false;
}

pub fn hasSingleDash(self: Token) bool {
    if (self._dash) |d| return d == .single_dash;
    return false;
}

pub fn hasDoubleDash(self: Token) bool {
    if (self._dash) |d| return d == .double_dash;
    return false;
}

pub fn hasDash(self: Token) bool {
    return self._dash != null;
}
