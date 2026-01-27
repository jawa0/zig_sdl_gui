const std = @import("std");
const sdl = @import("sdl.zig");
const c = sdl.c;

/// Button content type
pub const ButtonContent = union(enum) {
    text: []const u8,
    icon: IconType,
};

/// Available icon types
pub const IconType = enum {
    cursor_arrow, // Selection tool - arrow cursor
    text_t, // Text tool - "T" glyph
    rectangle, // Rectangle tool
};

/// Icon texture cache - must be initialized before rendering buttons with icons
pub const IconCache = struct {
    cursor_arrow_texture: ?*c.SDL_Texture = null,
    text_t_texture: ?*c.SDL_Texture = null,
    rectangle_texture: ?*c.SDL_Texture = null,
    renderer: ?*c.SDL_Renderer = null,

    pub fn init(renderer: *c.SDL_Renderer) IconCache {
        var cache = IconCache{
            .renderer = renderer,
        };

        // Load cursor arrow icon
        const cursor_surface = c.IMG_Load("assets/icons/cursor.png");
        if (cursor_surface != null) {
            defer c.SDL_FreeSurface(cursor_surface);
            cache.cursor_arrow_texture = c.SDL_CreateTextureFromSurface(renderer, cursor_surface);
            if (cache.cursor_arrow_texture != null) {
                _ = c.SDL_SetTextureBlendMode(cache.cursor_arrow_texture, c.SDL_BLENDMODE_BLEND);
            }
        }

        // Load text icon
        const text_surface = c.IMG_Load("assets/icons/text.png");
        if (text_surface != null) {
            defer c.SDL_FreeSurface(text_surface);
            cache.text_t_texture = c.SDL_CreateTextureFromSurface(renderer, text_surface);
            if (cache.text_t_texture != null) {
                _ = c.SDL_SetTextureBlendMode(cache.text_t_texture, c.SDL_BLENDMODE_BLEND);
            }
        }

        // Load rectangle icon
        const rect_surface = c.IMG_Load("assets/icons/rectangle.png");
        if (rect_surface != null) {
            defer c.SDL_FreeSurface(rect_surface);
            cache.rectangle_texture = c.SDL_CreateTextureFromSurface(renderer, rect_surface);
            if (cache.rectangle_texture != null) {
                _ = c.SDL_SetTextureBlendMode(cache.rectangle_texture, c.SDL_BLENDMODE_BLEND);
            }
        }

        return cache;
    }

    pub fn deinit(self: *IconCache) void {
        if (self.cursor_arrow_texture != null) {
            c.SDL_DestroyTexture(self.cursor_arrow_texture);
            self.cursor_arrow_texture = null;
        }
        if (self.text_t_texture != null) {
            c.SDL_DestroyTexture(self.text_t_texture);
            self.text_t_texture = null;
        }
        if (self.rectangle_texture != null) {
            c.SDL_DestroyTexture(self.rectangle_texture);
            self.rectangle_texture = null;
        }
    }
};

/// A reusable UI button with support for text or icons
pub const Button = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,
    content: ButtonContent,

    const highlight_color = c.SDL_Color{ .r = 200, .g = 220, .b = 255, .a = 255 }; // Light desaturated blue
    const default_color = c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 }; // White
    const border_color = c.SDL_Color{ .r = 180, .g = 180, .b = 180, .a = 255 };
    const content_color = c.SDL_Color{ .r = 0, .g = 0, .b = 0, .a = 255 }; // Black for text on white

    /// Check if a point is inside the button
    pub fn contains(self: Button, px: f32, py: f32) bool {
        return px >= @as(f32, @floatFromInt(self.x)) and
            px <= @as(f32, @floatFromInt(self.x + self.w)) and
            py >= @as(f32, @floatFromInt(self.y)) and
            py <= @as(f32, @floatFromInt(self.y + self.h));
    }

    /// Render the button
    pub fn render(self: Button, renderer: *c.SDL_Renderer, font: *c.TTF_Font, is_active: bool, icon_cache: ?*const IconCache) void {
        // Background
        const bg_color = if (is_active) highlight_color else default_color;
        _ = c.SDL_SetRenderDrawColor(renderer, bg_color.r, bg_color.g, bg_color.b, bg_color.a);
        var btn_rect = c.SDL_Rect{
            .x = self.x,
            .y = self.y,
            .w = self.w,
            .h = self.h,
        };
        _ = c.SDL_RenderFillRect(renderer, &btn_rect);

        // Border
        _ = c.SDL_SetRenderDrawColor(renderer, border_color.r, border_color.g, border_color.b, border_color.a);
        _ = c.SDL_RenderDrawRect(renderer, &btn_rect);

        // Content
        switch (self.content) {
            .text => |label| {
                self.renderText(renderer, font, label);
            },
            .icon => |icon_type| {
                self.renderIcon(renderer, font, icon_type, icon_cache);
            },
        }
    }

    fn renderText(self: Button, renderer: *c.SDL_Renderer, font: *c.TTF_Font, label: []const u8) void {
        _ = c.TTF_SetFontSize(font, 14);
        var text_buf: [64]u8 = undefined;
        const label_z = std.fmt.bufPrintZ(&text_buf, "{s}", .{label}) catch return;
        const text_surface = c.TTF_RenderText_Blended(font, label_z.ptr, content_color);
        if (text_surface != null) {
            defer c.SDL_FreeSurface(text_surface);
            const text_texture = c.SDL_CreateTextureFromSurface(renderer, text_surface);
            if (text_texture != null) {
                defer c.SDL_DestroyTexture(text_texture);
                const text_x = self.x + @divTrunc(self.w - text_surface.*.w, 2);
                const text_y = self.y + @divTrunc(self.h - text_surface.*.h, 2);
                var text_rect = c.SDL_Rect{
                    .x = text_x,
                    .y = text_y,
                    .w = text_surface.*.w,
                    .h = text_surface.*.h,
                };
                _ = c.SDL_RenderCopy(renderer, text_texture, null, &text_rect);
            }
        }
    }

    fn renderIcon(self: Button, renderer: *c.SDL_Renderer, font: *c.TTF_Font, icon_type: IconType, icon_cache: ?*const IconCache) void {
        const center_x = self.x + @divTrunc(self.w, 2);
        const center_y = self.y + @divTrunc(self.h, 2);
        const icon_size: i32 = 20; // Target icon size

        switch (icon_type) {
            .cursor_arrow => {
                // Try to use cached PNG texture first
                if (icon_cache) |cache| {
                    if (cache.cursor_arrow_texture) |texture| {
                        var dest_rect = c.SDL_Rect{
                            .x = center_x - @divTrunc(icon_size, 2),
                            .y = center_y - @divTrunc(icon_size, 2),
                            .w = icon_size,
                            .h = icon_size,
                        };
                        _ = c.SDL_RenderCopy(renderer, texture, null, &dest_rect);
                        return;
                    }
                }

                // Fallback: draw simple arrow if texture not available
                _ = c.SDL_SetRenderDrawColor(renderer, content_color.r, content_color.g, content_color.b, content_color.a);
                const tip_x = center_x - 4;
                const tip_y = center_y - 8;
                var y: i32 = 0;
                while (y < 16) : (y += 1) {
                    const progress = @as(f32, @floatFromInt(y)) / 16.0;
                    const width_at_y: i32 = @intFromFloat(progress * 12.0);
                    if (width_at_y > 0) {
                        _ = c.SDL_RenderDrawLine(renderer, tip_x, tip_y + y, tip_x + width_at_y, tip_y + y);
                    }
                }
                const stem_start_y = tip_y + 12;
                const stem_x = tip_x + 3;
                _ = c.SDL_RenderDrawLine(renderer, stem_x, stem_start_y, stem_x + 6, stem_start_y + 6);
                _ = c.SDL_RenderDrawLine(renderer, stem_x + 1, stem_start_y, stem_x + 7, stem_start_y + 6);
            },
            .text_t => {
                // Try to use cached PNG texture first
                if (icon_cache) |cache| {
                    if (cache.text_t_texture) |texture| {
                        var dest_rect = c.SDL_Rect{
                            .x = center_x - @divTrunc(icon_size, 2),
                            .y = center_y - @divTrunc(icon_size, 2),
                            .w = icon_size,
                            .h = icon_size,
                        };
                        _ = c.SDL_RenderCopy(renderer, texture, null, &dest_rect);
                        return;
                    }
                }

                // Fallback: draw "T" glyph using font if texture not available
                _ = c.TTF_SetFontSize(font, 20);
                const text_surface = c.TTF_RenderText_Blended(font, "T", content_color);
                if (text_surface != null) {
                    defer c.SDL_FreeSurface(text_surface);
                    const text_texture = c.SDL_CreateTextureFromSurface(renderer, text_surface);
                    if (text_texture != null) {
                        defer c.SDL_DestroyTexture(text_texture);
                        const text_x = center_x - @divTrunc(text_surface.*.w, 2);
                        const text_y = center_y - @divTrunc(text_surface.*.h, 2);
                        var text_rect = c.SDL_Rect{
                            .x = text_x,
                            .y = text_y,
                            .w = text_surface.*.w,
                            .h = text_surface.*.h,
                        };
                        _ = c.SDL_RenderCopy(renderer, text_texture, null, &text_rect);
                    }
                }
            },
            .rectangle => {
                // Try to use cached PNG texture first
                if (icon_cache) |cache| {
                    if (cache.rectangle_texture) |texture| {
                        var dest_rect = c.SDL_Rect{
                            .x = center_x - @divTrunc(icon_size, 2),
                            .y = center_y - @divTrunc(icon_size, 2),
                            .w = icon_size,
                            .h = icon_size,
                        };
                        _ = c.SDL_RenderCopy(renderer, texture, null, &dest_rect);
                        return;
                    }
                }

                // Fallback: draw simple rectangle outline if texture not available
                _ = c.SDL_SetRenderDrawColor(renderer, content_color.r, content_color.g, content_color.b, content_color.a);
                const rect_w: i32 = 14;
                const rect_h: i32 = 10;
                var rect = c.SDL_Rect{
                    .x = center_x - @divTrunc(rect_w, 2),
                    .y = center_y - @divTrunc(rect_h, 2),
                    .w = rect_w,
                    .h = rect_h,
                };
                _ = c.SDL_RenderDrawRect(renderer, &rect);
            },
        }
    }
};
