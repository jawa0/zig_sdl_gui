const std = @import("std");
const builtin = @import("builtin");

// Zig 0.16+ moved these methods to root_module
const zig_version = builtin.zig_version;
const is_zig_16_or_later = zig_version.major > 0 or zig_version.minor >= 16;

fn addIncludePath(compile: *std.Build.Step.Compile, path: std.Build.LazyPath) void {
    if (is_zig_16_or_later) {
        compile.root_module.addIncludePath(path);
    } else {
        compile.addIncludePath(path);
    }
}

fn addLibraryPath(compile: *std.Build.Step.Compile, path: std.Build.LazyPath) void {
    if (is_zig_16_or_later) {
        compile.root_module.addLibraryPath(path);
    } else {
        compile.addLibraryPath(path);
    }
}

fn linkSystemLibrary(compile: *std.Build.Step.Compile, name: []const u8) void {
    if (is_zig_16_or_later) {
        compile.root_module.linkSystemLibrary(name, .{});
    } else {
        compile.linkSystemLibrary(name);
    }
}

fn linkLibC(compile: *std.Build.Step.Compile) void {
    if (is_zig_16_or_later) {
        compile.root_module.link_libc = true;
    } else {
        compile.linkLibC();
    }
}

fn addCSourceFile(compile: *std.Build.Step.Compile, b: *std.Build, file: []const u8, flags: []const []const u8) void {
    if (is_zig_16_or_later) {
        compile.root_module.addCSourceFile(.{
            .file = b.path(file),
            .flags = flags,
        });
    } else {
        compile.addCSourceFile(.{
            .file = b.path(file),
            .flags = flags,
        });
    }
}

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
    const is_macos = target.result.os.tag == .macos;

    if (is_windows) {
        // Windows: use bundled SDL2 libraries
        addIncludePath(exe, b.path("libs/SDL2/include"));
        addIncludePath(exe, b.path("libs/SDL2/include/SDL2")); // For SDL_ttf.h which uses #include "SDL.h"
        addLibraryPath(exe, b.path("libs/SDL2/lib/x64"));
        linkSystemLibrary(exe, "SDL2");

        // Windows: use bundled SDL2_ttf libraries
        addIncludePath(exe, b.path("libs/SDL2_ttf/include"));
        addLibraryPath(exe, b.path("libs/SDL2_ttf/lib/x64"));
        linkSystemLibrary(exe, "SDL2_ttf");

        // Windows: use bundled SDL2_image libraries
        addIncludePath(exe, b.path("libs/SDL2_image/include"));
        addLibraryPath(exe, b.path("libs/SDL2_image/lib/x64"));
        linkSystemLibrary(exe, "SDL2_image");

        // Copy DLLs to output directory
        const install_sdl2_dll = b.addInstallBinFile(b.path("libs/SDL2/lib/x64/SDL2.dll"), "SDL2.dll");
        const install_ttf_dll = b.addInstallBinFile(b.path("libs/SDL2_ttf/lib/x64/SDL2_ttf.dll"), "SDL2_ttf.dll");
        const install_image_dll = b.addInstallBinFile(b.path("libs/SDL2_image/lib/x64/SDL2_image.dll"), "SDL2_image.dll");
        b.getInstallStep().dependOn(&install_sdl2_dll.step);
        b.getInstallStep().dependOn(&install_ttf_dll.step);
        b.getInstallStep().dependOn(&install_image_dll.step);
    } else if (is_macos) {
        // macOS: use pkg-config to find SDL2 libraries
        // This works for both Homebrew locations (Apple Silicon /opt/homebrew, Intel /usr/local)
        exe.linkSystemLibrary2("sdl2", .{ .use_pkg_config = .force });
        exe.linkSystemLibrary2("SDL2_ttf", .{ .use_pkg_config = .force });
        exe.linkSystemLibrary2("SDL2_image", .{ .use_pkg_config = .force });
    } else {
        // Linux/WSL: use system libraries
        linkSystemLibrary(exe, "SDL2");
        linkSystemLibrary(exe, "SDL2_ttf");
        linkSystemLibrary(exe, "SDL2_image");
    }
    linkLibC(exe);

    // SQLite: compile from amalgamation (all platforms)
    addCSourceFile(exe, b, "libs/sqlite3/sqlite3.c", &.{ "-DSQLITE_THREADSAFE=0", "-DSQLITE_OMIT_LOAD_EXTENSION" });
    addIncludePath(exe, b.path("libs/sqlite3"));

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
        addIncludePath(unit_tests, b.path("libs/SDL2/include"));
        addIncludePath(unit_tests, b.path("libs/SDL2/include/SDL2"));
        addLibraryPath(unit_tests, b.path("libs/SDL2/lib/x64"));
        linkSystemLibrary(unit_tests, "SDL2");

        addIncludePath(unit_tests, b.path("libs/SDL2_ttf/include"));
        addLibraryPath(unit_tests, b.path("libs/SDL2_ttf/lib/x64"));
        linkSystemLibrary(unit_tests, "SDL2_ttf");

        addIncludePath(unit_tests, b.path("libs/SDL2_image/include"));
        addLibraryPath(unit_tests, b.path("libs/SDL2_image/lib/x64"));
        linkSystemLibrary(unit_tests, "SDL2_image");
    } else if (is_macos) {
        unit_tests.linkSystemLibrary2("sdl2", .{ .use_pkg_config = .force });
        unit_tests.linkSystemLibrary2("SDL2_ttf", .{ .use_pkg_config = .force });
        unit_tests.linkSystemLibrary2("SDL2_image", .{ .use_pkg_config = .force });
    } else {
        linkSystemLibrary(unit_tests, "SDL2");
        linkSystemLibrary(unit_tests, "SDL2_ttf");
        linkSystemLibrary(unit_tests, "SDL2_image");
    }
    linkLibC(unit_tests);

    // SQLite: compile from amalgamation (all platforms)
    addCSourceFile(unit_tests, b, "libs/sqlite3/sqlite3.c", &.{ "-DSQLITE_THREADSAFE=0", "-DSQLITE_OMIT_LOAD_EXTENSION" });
    addIncludePath(unit_tests, b.path("libs/sqlite3"));

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
