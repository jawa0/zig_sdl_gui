// Single source for SDL C imports to avoid type conflicts
const builtin = @import("builtin");

pub const c = if (builtin.os.tag == .macos) @cImport({
    // Workaround for macOS SDK TargetConditionals.h not recognizing Zig's clang
    @cDefine("__clang__", "1");
    @cDefine("__clang_major__", "14");
    @cDefine("__clang_minor__", "0");
    @cDefine("__clang_patchlevel__", "0");
    @cDefine("__GNUC__", "4");
    @cDefine("__GNUC_MINOR__", "2");
    @cDefine("__GNUC_PATCHLEVEL__", "1");
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
}) else @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
});
