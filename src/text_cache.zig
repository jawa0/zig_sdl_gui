const std = @import("std");
const sdl = @import("sdl.zig");
const c = sdl.c;

/// Cached text texture with metadata for scaled rendering.
pub const TextCache = struct {
    texture: ?*c.SDL_Texture = null,
    rendered_font_size: f32 = 0,
    native_w: i32 = 0,
    native_h: i32 = 0,

    const UPSCALE_TOLERANCE: f32 = 1.1; // Allow 10% upscale before re-rasterizing
    const MAX_FONT_SIZE: f32 = 128.0; // Don't rasterize larger than this
    const MIN_FONT_SIZE: f32 = 6.0; // Don't rasterize smaller than this

    /// Free the cached texture.
    pub fn deinit(self: *TextCache) void {
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
    pub fn draw(
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
    pub fn getDisplaySize(self: *const TextCache, target_font_size: f32) ?struct { w: i32, h: i32 } {
        if (self.texture == null) return null;
        const scale = target_font_size / self.rendered_font_size;
        return .{
            .w = @intFromFloat(@as(f32, @floatFromInt(self.native_w)) * scale),
            .h = @intFromFloat(@as(f32, @floatFromInt(self.native_h)) * scale),
        };
    }
};

/// Renders text at the specified position (non-cached, for dynamic text like FPS).
pub fn drawText(
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
