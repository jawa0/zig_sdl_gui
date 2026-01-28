const std = @import("std");
const builtin = @import("builtin");

pub const Platform = enum {
    windows,
    macos,
    linux,
    linux_wsl,

    /// Returns whether vsync should be enabled for the renderer.
    /// WSL's compositor causes severe frame rate issues with vsync.
    pub fn useVsync(self: Platform) bool {
        return self != .linux_wsl;
    }
};

/// Whether the compile target uses macOS-style keybindings
/// (Cmd for shortcuts, Option for word movement).
pub const use_mac_keybindings = builtin.os.tag == .macos;

/// Detect the current platform at startup. Compile-time OS detection is
/// combined with a runtime check for WSL (Linux running under Windows).
pub fn detect() Platform {
    if (comptime builtin.os.tag == .macos) return .macos;
    if (comptime builtin.os.tag == .windows) return .windows;
    if (comptime builtin.os.tag == .linux) {
        // /proc/version contains "Microsoft" or "microsoft" only under WSL.
        var buf: [256]u8 = undefined;
        const f = std.fs.openFileAbsolute("/proc/version", .{}) catch return .linux;
        defer f.close();
        const len = f.read(&buf) catch return .linux;
        const version = std.ascii.lowerString(&buf, buf[0..len]);
        if (std.mem.indexOf(u8, version, "microsoft") != null) {
            std.debug.print("WSL detected: disabling vsync (using software frame cap)\n", .{});
            return .linux_wsl;
        }
        return .linux;
    }
    // Fallback for other OS targets
    return .linux;
}
