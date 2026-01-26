const std = @import("std");
const math = @import("math.zig");
const camera = @import("camera.zig");
const sdl = @import("sdl.zig");

const Vec2 = math.Vec2;
const Camera = camera.Camera;
const c = sdl.c;

/// Grid rendering configuration
pub const Grid = struct {
    /// Spacing between major grid lines in world units
    /// Default: 150 world units (gives ~6 divisions at screen height 900 with zoom 1.0)
    major_spacing: f32 = 150.0,

    /// Number of minor divisions per major division
    minor_divisions: u32 = 5,

    /// Render the grid lines
    pub fn render(self: Grid, renderer: *c.SDL_Renderer, cam: *const Camera, grid_color: c.SDL_Color) void {
        // Set grid line color
        _ = c.SDL_SetRenderDrawColor(renderer, grid_color.r, grid_color.g, grid_color.b, grid_color.a);

        // Calculate visible world bounds
        const top_left_screen = Vec2{ .x = 0, .y = 0 };
        const bottom_right_screen = Vec2{ .x = cam.viewport_width, .y = cam.viewport_height };
        const top_left_world = cam.screenToWorld(top_left_screen);
        const bottom_right_world = cam.screenToWorld(bottom_right_screen);

        // Calculate the range of grid lines to draw
        const min_x = top_left_world.x;
        const max_x = bottom_right_world.x;
        const min_y = bottom_right_world.y; // Remember Y is flipped
        const max_y = top_left_world.y;

        // Draw vertical major grid lines
        const first_vertical = @floor(min_x / self.major_spacing) * self.major_spacing;
        var x = first_vertical;
        while (x <= max_x) : (x += self.major_spacing) {
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

        // Draw horizontal major grid lines
        const first_horizontal = @floor(min_y / self.major_spacing) * self.major_spacing;
        var y = first_horizontal;
        while (y <= max_y) : (y += self.major_spacing) {
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
};
