const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zig_sdl_gui",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const is_windows = target.result.os.tag == .windows;

    if (is_windows) {
        // Windows: use bundled SDL2 libraries
        exe.addIncludePath(b.path("libs/SDL2/include"));
        exe.addIncludePath(b.path("libs/SDL2/include/SDL2")); // For SDL_ttf.h which uses #include "SDL.h"
        exe.addLibraryPath(b.path("libs/SDL2/lib/x64"));
        exe.linkSystemLibrary("SDL2");

        // Windows: use bundled SDL2_ttf libraries
        exe.addIncludePath(b.path("libs/SDL2_ttf/include"));
        exe.addLibraryPath(b.path("libs/SDL2_ttf/lib/x64"));
        exe.linkSystemLibrary("SDL2_ttf");

        // Copy DLLs to output directory
        const install_sdl2_dll = b.addInstallBinFile(b.path("libs/SDL2/lib/x64/SDL2.dll"), "SDL2.dll");
        const install_ttf_dll = b.addInstallBinFile(b.path("libs/SDL2_ttf/lib/x64/SDL2_ttf.dll"), "SDL2_ttf.dll");
        b.getInstallStep().dependOn(&install_sdl2_dll.step);
        b.getInstallStep().dependOn(&install_ttf_dll.step);
    } else {
        // Linux/WSL: use system libraries
        exe.linkSystemLibrary("SDL2");
        exe.linkSystemLibrary("SDL2_ttf");
    }
    exe.linkLibC();

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);

    // Test step
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Add the same dependencies as the main executable
    if (is_windows) {
        unit_tests.addIncludePath(b.path("libs/SDL2/include"));
        unit_tests.addIncludePath(b.path("libs/SDL2/include/SDL2"));
        unit_tests.addLibraryPath(b.path("libs/SDL2/lib/x64"));
        unit_tests.linkSystemLibrary("SDL2");

        unit_tests.addIncludePath(b.path("libs/SDL2_ttf/include"));
        unit_tests.addLibraryPath(b.path("libs/SDL2_ttf/lib/x64"));
        unit_tests.linkSystemLibrary("SDL2_ttf");
    } else {
        unit_tests.linkSystemLibrary("SDL2");
        unit_tests.linkSystemLibrary("SDL2_ttf");
    }
    unit_tests.linkLibC();

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
