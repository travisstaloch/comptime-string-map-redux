const std = @import("std");

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
}
