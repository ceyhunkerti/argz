# argz: CLI application helper for Zig

Supports:

- Subcommands `app sub1 sub2`
- Input options for primitive types `string` `integer` `boolean`
- Chained options for boolean types `-abc` is same as `-a -b -c`
- Flags for on/off behavior types
- Typed arguments
- Builtin and customizable help system
- Hooks for attaching user functions to specified locations.


## Installation

Use zig fetch --save to pull a version of the library into your `build.zig.zon`. (This requires at least Zig 0.11.)

```sh
zig fetch --save "https://github.com/ceyhunkerti/argz/archive/refs/tags/0.0.1.tar.gz"
```

Then in your `build.zig` file
```zig

...
const argz = b.dependency("argz", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("argz", argz.module("argz"));
...

```

To access help, add `-h` or `--help` option. This will print the attached help for the current command.

See [examples/help.zig](./examples/help.zig)

