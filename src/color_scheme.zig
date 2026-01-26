const sdl = @import("sdl.zig");
const c = sdl.c;

/// Color scheme types
pub const SchemeType = enum {
    light,
    dark,
};

/// Color scheme definition with named colors
pub const ColorScheme = struct {
    background: c.SDL_Color,
    text: c.SDL_Color,
    border: c.SDL_Color,
    rect_red: c.SDL_Color,
    rect_green: c.SDL_Color,
    rect_yellow: c.SDL_Color,
    grid: c.SDL_Color,

    /// Get the color scheme for the given type
    pub fn get(scheme_type: SchemeType) ColorScheme {
        return switch (scheme_type) {
            .light => ColorScheme{
                .background = c.SDL_Color{ .r = 216, .g = 216, .b = 216, .a = 255 }, // Light grey (10% darker)
                .text = c.SDL_Color{ .r = 0, .g = 0, .b = 0, .a = 255 }, // Black
                .border = c.SDL_Color{ .r = 100, .g = 150, .b = 255, .a = 255 }, // Light blue
                .rect_red = c.SDL_Color{ .r = 255, .g = 50, .b = 50, .a = 255 },
                .rect_green = c.SDL_Color{ .r = 50, .g = 255, .b = 50, .a = 255 },
                .rect_yellow = c.SDL_Color{ .r = 255, .g = 255, .b = 50, .a = 255 },
                .grid = c.SDL_Color{ .r = 180, .g = 180, .b = 180, .a = 255 }, // Medium grey
            },
            .dark => ColorScheme{
                .background = c.SDL_Color{ .r = 0, .g = 0, .b = 0, .a = 255 }, // Black
                .text = c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 }, // White
                .border = c.SDL_Color{ .r = 100, .g = 150, .b = 255, .a = 255 }, // Light blue
                .rect_red = c.SDL_Color{ .r = 255, .g = 50, .b = 50, .a = 255 },
                .rect_green = c.SDL_Color{ .r = 50, .g = 255, .b = 50, .a = 255 },
                .rect_yellow = c.SDL_Color{ .r = 255, .g = 255, .b = 50, .a = 255 },
                .grid = c.SDL_Color{ .r = 40, .g = 40, .b = 40, .a = 255 }, // Dark grey
            },
        };
    }

    /// Toggle between light and dark schemes
    pub fn toggle(current: SchemeType) SchemeType {
        return switch (current) {
            .light => .dark,
            .dark => .light,
        };
    }
};
