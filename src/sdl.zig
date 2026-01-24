// Single source for SDL C imports to avoid type conflicts
const builtin = @import("builtin");

pub const c = @cImport({
    // Workaround for macOS SDK TargetConditionals.h not recognizing Zig's clang
    if (builtin.os.tag == .macos) {
        @cDefine("__clang__", "1");
        @cDefine("__clang_major__", "14");
        @cDefine("__clang_minor__", "0");
        @cDefine("__clang_patchlevel__", "0");
    }
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
});
