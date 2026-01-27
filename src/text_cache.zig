const std = @import("std");
const sdl = @import("sdl.zig");
const c = sdl.c;

/// Cached text texture with metadata for scaled rendering.
/// Textures are rendered at appropriate size for current zoom and re-cached when zoom changes.
pub const TextCache = struct {
    texture: ?*c.SDL_Texture = null,
    rendered_font_size: f32 = 0,
    native_w: i32 = 0,  // Texture pixel dimensions at rendered_font_size
    native_h: i32 = 0,

    // Re-render threshold: regenerate texture if target size differs by more than this
    const RERENDER_THRESHOLD: f32 = 0.15; // 15% change triggers re-render

    /// Free the cached texture.
    pub fn deinit(self: *TextCache) void {
        if (self.texture) |tex| {
            c.SDL_DestroyTexture(tex);
            self.texture = null;
        }
    }

    /// Check if we need to re-render for the target font size
    fn needsRasterize(self: *const TextCache, target_font_size: f32) bool {
        if (self.texture == null) return true;

        // Re-render if target size differs significantly from cached size
        const size_ratio = target_font_size / self.rendered_font_size;
        return size_ratio < (1.0 - RERENDER_THRESHOLD) or size_ratio > (1.0 + RERENDER_THRESHOLD);
    }

    /// Rasterize text at target font size for optimal quality at current zoom.
    /// Re-renders when zoom changes significantly to maintain sharpness.
    fn rasterize(
        self: *TextCache,
        renderer: *c.SDL_Renderer,
        font: *c.TTF_Font,
        text: [*:0]const u8,
        target_font_size: f32,
        color: c.SDL_Color,
    ) bool {
        // Free old texture
        self.deinit();

        // Render at target size (with reasonable bounds)
        const render_size = std.math.clamp(target_font_size, 6.0, 256.0);
        const int_size: c_int = @intFromFloat(render_size);

        // Set font size (SDL_ttf 2.20+)
        if (c.TTF_SetFontSize(font, int_size) != 0) {
            return false;
        }

        // Render text to surface
        const surface = c.TTF_RenderText_Blended(font, text, color) orelse return false;
        defer c.SDL_FreeSurface(surface);

        // Create texture from surface
        self.texture = c.SDL_CreateTextureFromSurface(renderer, surface) orelse return false;

        // Enable best quality scaling and proper alpha blending
        if (self.texture) |tex| {
            _ = c.SDL_SetTextureScaleMode(tex, c.SDL_ScaleModeLinear);
            _ = c.SDL_SetTextureBlendMode(tex, c.SDL_BLENDMODE_BLEND);
        }

        self.rendered_font_size = render_size;
        self.native_w = surface.*.w;
        self.native_h = surface.*.h;

        return true;
    }

    /// Draw the cached text scaled to exact dimensions.
    /// Re-renders at appropriate size when zoom changes significantly for optimal quality.
    pub fn draw(
        self: *TextCache,
        renderer: *c.SDL_Renderer,
        font: *c.TTF_Font,
        text: [*:0]const u8,
        x: i32,
        y: i32,
        dest_w: i32,  // Exact width to render (from authoritative bbox)
        dest_h: i32,  // Exact height to render (from authoritative bbox)
        target_font_size: f32,  // Font size at current zoom
        color: c.SDL_Color,
    ) bool {
        // Re-rasterize if zoom changed significantly
        if (self.needsRasterize(target_font_size)) {
            if (!self.rasterize(renderer, font, text, target_font_size, color)) {
                return false;
            }
        }

        const tex = self.texture orelse return false;

        // Render at destination size (minimal scaling from cached texture)
        var dst_rect = c.SDL_Rect{
            .x = x,
            .y = y,
            .w = dest_w,
            .h = dest_h,
        };
        _ = c.SDL_RenderCopy(renderer, tex, null, &dst_rect);

        return true;
    }

    /// Get the native texture dimensions (at TEXTURE_QUALITY_FONT_SIZE).
    /// Use this when initially creating a text element to set bbox.
    pub fn getNativeDimensions(self: *const TextCache) ?struct { w: i32, h: i32 } {
        if (self.texture == null) return null;
        return .{ .w = self.native_w, .h = self.native_h };
    }
};

/// Renders text at the specified position (non-cached, for dynamic text like FPS).
/// Font should already be set to the target size before calling.
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

    // Enable linear filtering and alpha blending
    _ = c.SDL_SetTextureScaleMode(texture, c.SDL_ScaleModeLinear);
    _ = c.SDL_SetTextureBlendMode(texture, c.SDL_BLENDMODE_BLEND);

    // Render at 1:1 scale (already rendered at target size)
    var dst_rect = c.SDL_Rect{
        .x = x,
        .y = y,
        .w = surface.*.w,
        .h = surface.*.h,
    };
    _ = c.SDL_RenderCopy(renderer, texture, null, &dst_rect);

    return .{ .w = surface.*.w, .h = surface.*.h };
}
