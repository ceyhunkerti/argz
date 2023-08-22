# argz: CLI application helper for Zig

Supports:

- subcommands `app sub1 sub2`
- input options for primitive types `string` `integer` `boolean`
- flags for on/off behavior types
- argument specification with rules eg. `1..3`
- builtin and customizable help system
- hooks for attaching user functions to specified locations.


Examples:

## Subcommands

```zig
//demo.zig

const std = @import("std");

const app = @import("argz");

const Command = app.Command;

pub fn mySubCommand(c: *Command) anyerror!void {
    std.debug.print("@{s}: running subcommand\n", .{c.name});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const check = gpa.deinit();
        if (check == .leak) @panic("memory leaked");
    }
    var allocator = gpa.allocator();

    var root = Command.init(allocator, "root");
    defer root.deinit();

    var sub = Command.init(allocator, "my-sub-command");
    sub.run = mySubCommand;

    try root.addCommand(sub);

    try root.parse();
    try root.start();
}
```

```sh
$ <appname> my-sub-command
# will print  @my-sub-command running subcommand
```
