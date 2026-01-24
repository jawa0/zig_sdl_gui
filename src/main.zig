const std = @import("std");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
});

const WINDOW_WIDTH = 1400;
const WINDOW_HEIGHT = 900;
const TARGET_FPS = 60;
const FRAME_TIME_MS: u32 = 1000 / TARGET_FPS;
const FPS_UPDATE_INTERVAL_MS: u32 = 500;

/// Cached text texture with metadata for scaled rendering.
const TextCache = struct {
    texture: ?*c.SDL_Texture = null,
    rendered_font_size: f32 = 0,
    native_w: i32 = 0,
    native_h: i32 = 0,

    const UPSCALE_TOLERANCE: f32 = 1.1; // Allow 10% upscale before re-rasterizing
    const MAX_FONT_SIZE: f32 = 128.0; // Don't rasterize larger than this
    const MIN_FONT_SIZE: f32 = 6.0; // Don't rasterize smaller than this

    /// Free the cached texture.
    fn deinit(self: *TextCache) void {
        if (self.texture) |tex| {
            c.SDL_DestroyTexture(tex);
            self.texture = null;
        }
    }

    /// Check if we need to re-rasterize for the given target font size.
    fn needsRasterize(self: *const TextCache, target_font_size: f32) bool {
        if (self.texture == null) return true;

        const EPSILON: f32 = 0.001; // Tolerance for float comparison
        const max_size_with_tolerance = self.rendered_font_size * UPSCALE_TOLERANCE;

        // Re-rasterize if target exceeds cached size by more than tolerance
        return target_font_size > max_size_with_tolerance + EPSILON;
    }

    /// Rasterize text at the specified font size and cache the texture.
    fn rasterize(
        self: *TextCache,
        renderer: *c.SDL_Renderer,
        font: *c.TTF_Font,
        text: [*:0]const u8,
        font_size: f32,
        color: c.SDL_Color,
    ) bool {
        // Free old texture
        self.deinit();

        // Clamp font size to reasonable bounds
        const clamped_size = std.math.clamp(font_size, MIN_FONT_SIZE, MAX_FONT_SIZE);
        const int_size: c_int = @intFromFloat(clamped_size);

        // Set font size (SDL_ttf 2.20+)
        if (c.TTF_SetFontSize(font, int_size) != 0) {
            return false;
        }

        // Render text to surface
        const surface = c.TTF_RenderText_Blended(font, text, color) orelse return false;
        defer c.SDL_FreeSurface(surface);

        // Create texture from surface
        self.texture = c.SDL_CreateTextureFromSurface(renderer, surface) orelse return false;
        self.rendered_font_size = clamped_size;
        self.native_w = surface.*.w;
        self.native_h = surface.*.h;

        return true;
    }

    /// Draw the cached text at the specified position and target size.
    /// Re-rasterizes if necessary. Returns the displayed dimensions.
    fn draw(
        self: *TextCache,
        renderer: *c.SDL_Renderer,
        font: *c.TTF_Font,
        text: [*:0]const u8,
        x: i32,
        y: i32,
        target_font_size: f32,
        color: c.SDL_Color,
    ) ?struct { w: i32, h: i32 } {
        // Re-rasterize if needed
        if (self.needsRasterize(target_font_size)) {
            if (!self.rasterize(renderer, font, text, target_font_size, color)) {
                return null;
            }
        }

        const tex = self.texture orelse return null;

        // Calculate scale factor (will be <= 1.1, usually <= 1.0)
        const scale = target_font_size / self.rendered_font_size;
        const display_w: i32 = @intFromFloat(@as(f32, @floatFromInt(self.native_w)) * scale);
        const display_h: i32 = @intFromFloat(@as(f32, @floatFromInt(self.native_h)) * scale);

        var dst_rect = c.SDL_Rect{
            .x = x,
            .y = y,
            .w = display_w,
            .h = display_h,
        };
        _ = c.SDL_RenderCopy(renderer, tex, null, &dst_rect);

        return .{ .w = display_w, .h = display_h };
    }

    /// Get the display dimensions for a given target font size without drawing.
    fn getDisplaySize(self: *const TextCache, target_font_size: f32) ?struct { w: i32, h: i32 } {
        if (self.texture == null) return null;
        const scale = target_font_size / self.rendered_font_size;
        return .{
            .w = @intFromFloat(@as(f32, @floatFromInt(self.native_w)) * scale),
            .h = @intFromFloat(@as(f32, @floatFromInt(self.native_h)) * scale),
        };
    }
};

/// Renders text at the specified position (non-cached, for dynamic text like FPS).
fn drawText(
    renderer: *c.SDL_Renderer,
    font: *c.TTF_Font,
    text: [*:0]const u8,
    x: i32,
    y: i32,
    color: c.SDL_Color,
) ?struct { w: i32, h: i32 } {
    const surface = c.TTF_RenderText_Blended(font, text, color) orelse return null;
    defer c.SDL_FreeSurface(surface);

    const texture = c.SDL_CreateTextureFromSurface(renderer, surface) orelse return null;
    defer c.SDL_DestroyTexture(texture);

    var dst_rect = c.SDL_Rect{
        .x = x,
        .y = y,
        .w = surface.*.w,
        .h = surface.*.h,
    };
    _ = c.SDL_RenderCopy(renderer, texture, null, &dst_rect);

    return .{ .w = surface.*.w, .h = surface.*.h };
}

pub fn main() !void {
    // Initialize SDL
    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        std.debug.print("SDL init failed: {s}\n", .{c.SDL_GetError()});
        return error.SDLInitFailed;
    }
    defer c.SDL_Quit();

    // Initialize SDL_ttf
    if (c.TTF_Init() != 0) {
        std.debug.print("TTF init failed: {s}\n", .{c.TTF_GetError()});
        return error.TTFInitFailed;
    }
    defer c.TTF_Quit();

    // Create window
    const window = c.SDL_CreateWindow(
        "Zig SDL2 GUI",
        c.SDL_WINDOWPOS_CENTERED,
        c.SDL_WINDOWPOS_CENTERED,
        WINDOW_WIDTH,
        WINDOW_HEIGHT,
        c.SDL_WINDOW_SHOWN,
    ) orelse {
        std.debug.print("Window creation failed: {s}\n", .{c.SDL_GetError()});
        return error.WindowCreationFailed;
    };
    defer c.SDL_DestroyWindow(window);

    // Create hardware-accelerated renderer with vsync (provides double buffering)
    const renderer = c.SDL_CreateRenderer(
        window,
        -1,
        c.SDL_RENDERER_ACCELERATED | c.SDL_RENDERER_PRESENTVSYNC,
    ) orelse {
        std.debug.print("Renderer creation failed: {s}\n", .{c.SDL_GetError()});
        return error.RendererCreationFailed;
    };
    defer c.SDL_DestroyRenderer(renderer);

    // Enable linear filtering for better scaled text quality
    _ = c.SDL_SetHint(c.SDL_HINT_RENDER_SCALE_QUALITY, "1");

    // Load font (initial size doesn't matter much, we'll resize as needed)
    const font = c.TTF_OpenFont("assets/fonts/JetBrainsMono-Regular.ttf", 16) orelse {
        std.debug.print("Font loading failed: {s}\n", .{c.TTF_GetError()});
        return error.FontLoadFailed;
    };
    defer c.TTF_CloseFont(font);

    const white = c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 };

    var running = true;
    var event: c.SDL_Event = undefined;

    // FPS tracking
    var frame_count: u32 = 0;
    var fps_timer: u32 = c.SDL_GetTicks();
    var current_fps: f32 = 0;
    var fps_text_buf: [64]u8 = undefined;

    // Zoom state
    var zoom: f32 = 1.0;
    const base_font_size: f32 = 16.0;
    const zoom_speed: f32 = 0.1;
    const min_zoom: f32 = 0.25;
    const max_zoom: f32 = 4.0;

    // Text cache for the repeated line
    var line_cache = TextCache{};
    defer line_cache.deinit();

    while (running) {
        const frame_start = c.SDL_GetTicks();

        // Handle events
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => running = false,
                c.SDL_KEYDOWN => {
                    if (event.key.keysym.scancode == c.SDL_SCANCODE_ESCAPE) {
                        running = false;
                    } else if (event.key.keysym.scancode == c.SDL_SCANCODE_EQUALS or
                        event.key.keysym.scancode == c.SDL_SCANCODE_KP_PLUS)
                    {
                        zoom = @min(zoom + zoom_speed, max_zoom);
                    } else if (event.key.keysym.scancode == c.SDL_SCANCODE_MINUS or
                        event.key.keysym.scancode == c.SDL_SCANCODE_KP_MINUS)
                    {
                        zoom = @max(zoom - zoom_speed, min_zoom);
                    }
                },
                c.SDL_MOUSEWHEEL => {
                    if (event.wheel.y > 0) {
                        zoom = @min(zoom + zoom_speed, max_zoom);
                    } else if (event.wheel.y < 0) {
                        zoom = @max(zoom - zoom_speed, min_zoom);
                    }
                },
                else => {},
            }
        }

        // Update FPS counter
        frame_count += 1;
        const elapsed = c.SDL_GetTicks() - fps_timer;
        if (elapsed >= FPS_UPDATE_INTERVAL_MS) {
            current_fps = @as(f32, @floatFromInt(frame_count)) * 1000.0 / @as(f32, @floatFromInt(elapsed));
            frame_count = 0;
            fps_timer = c.SDL_GetTicks();
        }

        // Clear screen (blank canvas - black)
        _ = c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
        _ = c.SDL_RenderClear(renderer);

        // Calculate current font size based on zoom
        const current_font_size = base_font_size * zoom;
        const line_spacing: i32 = @intFromFloat(4.0 * zoom);

        // Render centered text lines from top to bottom using cached texture
        const line_text = "This is a line of text.";

        // First draw to get/update cache and get dimensions
        if (line_cache.draw(renderer, font, line_text, 0, -1000, current_font_size, white)) |dims| {
            const line_x = @divTrunc(WINDOW_WIDTH - dims.w, 2);
            var y: i32 = 0;
            while (y < WINDOW_HEIGHT) : (y += dims.h + line_spacing) {
                _ = line_cache.draw(renderer, font, line_text, line_x, y, current_font_size, white);
            }
        }

        // Render FPS and zoom info (at fixed size, not cached)
        _ = c.TTF_SetFontSize(font, 16);
        const fps_text = std.fmt.bufPrintZ(&fps_text_buf, "FPS: {d:.1} | Zoom: {d:.0}% | Font: {d:.1}px", .{ current_fps, zoom * 100, current_font_size }) catch "FPS: ---";
        var text_w: c_int = 0;
        _ = c.TTF_SizeText(font, fps_text.ptr, &text_w, null);
        _ = drawText(renderer, font, fps_text.ptr, WINDOW_WIDTH - text_w - 10, 10, white);

        // Present the frame (swap buffers)
        c.SDL_RenderPresent(renderer);

        // Frame timing - cap at target FPS if vsync isn't working
        const frame_time = c.SDL_GetTicks() - frame_start;
        if (frame_time < FRAME_TIME_MS) {
            c.SDL_Delay(FRAME_TIME_MS - frame_time);
        }
    }
}
