const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const module = b.addModule("argz", .{
        .root_source_file = .{ .path = "src/main.zig" },
    });

    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "argz",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_tests = b.addRunArtifact(tests);

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build test`
    // This will evaluate the `test` step rather than the default, which is "install".
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests.step);

    const examples_step = b.step("examples", "Build examples");
    inline for (comptime [_][]const u8{
        "arguments",
        "help",
        "mixed",
        "options",
        "subcommand",
    }) |name| {
        const example = b.addExecutable(.{
            .name = name,
            .root_source_file = .{ .path = "examples" ++ std.fs.path.sep_str ++ name ++ ".zig" },
            .target = target,
            .optimize = optimize,
        });
        example.root_module.addImport("argz", module);
        example.linkLibrary(lib);

        var run = b.addRunArtifact(example);
        if (b.args) |args| run.addArgs(args);
        b.step("run-example-" ++ name, "Run the " ++ name ++ " example").dependOn(&run.step);

        examples_step.dependOn(&example.step);
    }
}
