const std = @import("std");
const Mode = @import("bench.zig").Mode;

pub fn build(b: *std.Build) void {
    const mod = b.addModule("comptime-string-map-revised", .{
        .root_source_file = .{ .path = "comptime-string-map.zig" },
    });
    _ = mod;

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const tests = b.addTest(.{
        .name = "tests",
        .root_source_file = .{ .path = "comptime-string-map.zig" },
        .target = target,
        .optimize = optimize,
        .filter = b.option([]const u8, "test-filter", "test filter"),
    });
    const test_cmd = b.addRunArtifact(tests);
    test_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("test", "Run the tests");
    run_step.dependOn(&test_cmd.step);

    const bench = b.addExecutable(.{
        .name = "bench",
        .root_source_file = .{ .path = "bench.zig" },
        .target = target,
        .optimize = optimize,
    });
    const bench_cmd = b.addRunArtifact(bench);
    if (b.args) |args| bench_cmd.addArgs(args);
    bench_cmd.step.dependOn(b.getInstallStep());
    const bench_step = b.step("bench", "Run the benchmark");
    bench_step.dependOn(&bench_cmd.step);
    const build_options = b.addOptions();
    const width = 33;
    const mode = b.option(Mode, "mode", "bench mode\n" ++ " " ** width ++
        "std: use std.ComptimeStringMap\n" ++ " " ** width ++
        "rev: use ComptimeStringMap from this package\n" ++ " " ** width ++
        "default rev") orelse .rev;
    const num_iters = b.option(usize, "num-iters", "number of iterations per bench run") orelse 1000;
    build_options.addOption(Mode, "mode", mode);
    build_options.addOption(usize, "num_iters", num_iters);
    bench.root_module.addOptions("build_options", build_options);
    b.installArtifact(bench);
}
