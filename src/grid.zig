const std = @import("std");
const math = @import("math.zig");
const camera = @import("camera.zig");
const sdl = @import("sdl.zig");

const Vec2 = math.Vec2;
const Camera = camera.Camera;
const c = sdl.c;
const lerp = math.lerp;
const clamp = math.clamp;

/// Grid rendering configuration
pub const Grid = struct {
    /// Base spacing between major grid lines in world units
    /// Default: 150 world units (gives ~6 divisions at screen height 900 with zoom 1.0)
    major_spacing: f32 = 150.0,

    /// Number of minor divisions per major division
    minor_divisions: u32 = 5,

    /// Minimum spacing in pixels before grid lines fade out
    min_spacing_px: f32 = 20.0,

    /// Target spacing in pixels where grid lines are fully visible
    target_spacing_px: f32 = 100.0,

    /// Interpolate between two SDL colors
    fn lerpColor(a: c.SDL_Color, b: c.SDL_Color, t: f32) c.SDL_Color {
        return c.SDL_Color{
            .r = @intFromFloat(lerp(@floatFromInt(a.r), @floatFromInt(b.r), t)),
            .g = @intFromFloat(lerp(@floatFromInt(a.g), @floatFromInt(b.g), t)),
            .b = @intFromFloat(lerp(@floatFromInt(a.b), @floatFromInt(b.b), t)),
            .a = @intFromFloat(lerp(@floatFromInt(a.a), @floatFromInt(b.a), t)),
        };
    }

    /// Calculate fade factor based on spacing in screen pixels
    fn calculateFade(self: Grid, spacing_px: f32) f32 {
        if (spacing_px < self.min_spacing_px) return 0.0;
        if (spacing_px >= self.target_spacing_px) return 1.0;

        // Fade in between min and target spacing
        const t = (spacing_px - self.min_spacing_px) / (self.target_spacing_px - self.min_spacing_px);
        return clamp(t, 0.0, 1.0);
    }

    /// Render grid lines at a specific spacing with a given color
    fn renderGridLevel(
        _: Grid,
        renderer: *c.SDL_Renderer,
        cam: *const Camera,
        spacing: f32,
        color: c.SDL_Color,
        min_x: f32,
        max_x: f32,
        min_y: f32,
        max_y: f32,
    ) void {
        _ = c.SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a);

        // Draw vertical grid lines
        const first_vertical = @floor(min_x / spacing) * spacing;
        var x = first_vertical;
        while (x <= max_x) : (x += spacing) {
            const top_world = Vec2{ .x = x, .y = max_y };
            const bottom_world = Vec2{ .x = x, .y = min_y };
            const top_screen = cam.worldToScreen(top_world);
            const bottom_screen = cam.worldToScreen(bottom_world);

            _ = c.SDL_RenderDrawLine(
                renderer,
                @intFromFloat(top_screen.x),
                @intFromFloat(top_screen.y),
                @intFromFloat(bottom_screen.x),
                @intFromFloat(bottom_screen.y),
            );
        }

        // Draw horizontal grid lines
        const first_horizontal = @floor(min_y / spacing) * spacing;
        var y = first_horizontal;
        while (y <= max_y) : (y += spacing) {
            const left_world = Vec2{ .x = min_x, .y = y };
            const right_world = Vec2{ .x = max_x, .y = y };
            const left_screen = cam.worldToScreen(left_world);
            const right_screen = cam.worldToScreen(right_world);

            _ = c.SDL_RenderDrawLine(
                renderer,
                @intFromFloat(left_screen.x),
                @intFromFloat(left_screen.y),
                @intFromFloat(right_screen.x),
                @intFromFloat(right_screen.y),
            );
        }
    }

    /// Render the grid lines with recursive minor divisions
    pub fn render(self: Grid, renderer: *c.SDL_Renderer, cam: *const Camera, grid_color: c.SDL_Color, background_color: c.SDL_Color) void {
        // Calculate visible world bounds
        const top_left_screen = Vec2{ .x = 0, .y = 0 };
        const bottom_right_screen = Vec2{ .x = cam.viewport_width, .y = cam.viewport_height };
        const top_left_world = cam.screenToWorld(top_left_screen);
        const bottom_right_world = cam.screenToWorld(bottom_right_screen);

        const min_x = top_left_world.x;
        const max_x = bottom_right_world.x;
        const min_y = bottom_right_world.y; // Remember Y is flipped
        const max_y = top_left_world.y;

        // Calculate which grid levels to render
        // Start with the finest level that's visible and work up to coarser levels
        var spacing = self.major_spacing / @as(f32, @floatFromInt(self.minor_divisions));
        var level: u32 = 1;
        const max_levels: u32 = 10; // Prevent infinite recursion

        // Render from finest to coarsest for proper blending
        while (level <= max_levels) : (level += 1) {
            const spacing_px = spacing * cam.zoom;
            const fade = self.calculateFade(spacing_px);

            if (fade > 0.0) {
                // Interpolate between background and grid color based on fade
                const level_color = lerpColor(background_color, grid_color, fade);
                self.renderGridLevel(renderer, cam, spacing, level_color, min_x, max_x, min_y, max_y);
            }

            // Move to next coarser level
            spacing *= @floatFromInt(self.minor_divisions);

            // Stop when spacing gets too large (e.g., larger than the visible area)
            const world_width = max_x - min_x;
            const world_height = max_y - min_y;
            const max_dimension = @max(world_width, world_height);
            if (spacing > max_dimension * 10.0) break;
        }
    }
};
