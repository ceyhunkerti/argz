# argz: CLI application helper for Zig

Supports:

- subcommands `app sub1 sub2`
- input options for primitive types `string` `integer` `boolean`
- flags for on/off behavior types
- argument specification with rules eg. `1..3`
- builtin and customizable help system
- hooks for attaching user functions to specified locations.


## Options

You can specify number of options and attach those options to the command you want. Options are only valid
in the scope of the attached command.

See [examples/options.zig](./examples/options.zig) for example usage.

## Arguments

Arguments are just strings and can be limited by using the `nargs` parameter.
```zig
// *    : zero or more arguments
// n    : exacly n arguments. n is an unsigned interger
// n..  : n or more arguments.
// ..n  : up to n arguments, inclusive
// n..m : between n and m arguments, inclusive. m is and unsigned integer
// null : (default) same as zero arguments
```
See [examples/arguments.zig](./examples/options.zig) for example usage.


## Subcommands

You can add as many subcommands as you like. It's a tree like structure so you can nest any number of subcommands.

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


## Help

To access help, add `-h` or `--help` option. This will print the attached help for the current command.

See [examples/help.zig](./examples/help.zig)

