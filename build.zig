const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("sm", "src/main.zig");

    // simple package
    exe.addPackagePath("emacs", "src/emacs.zig");

    //const modules = [_]std.Build.ModuleDependency{
    //    .{ .name = "clap", .module = clap_module },
    //    .{ .name = "folders", .module = folders_module },
    //    .{ .name = "ston", .module = ston_module },
    //    .{ .name = "ziter", .module = ziter_module },

    //    .{ .name = "core", .module = core_module },

    //    .{ .name = "util", .module = util_module },
    //};
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest("src/main.zig");
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
