const std = @import("std");
const math = @import("math.zig");
const Vec2 = math.Vec2;

pub const Camera = struct {
    position: Vec2, // Camera center in world space
    zoom: f32, // Zoom level (1.0 = 100%)
    viewport_width: f32,
    viewport_height: f32,
    min_zoom: f32 = 0.25,
    max_zoom: f32 = 4.0,

    pub fn init(position: Vec2, zoom: f32, viewport_width: f32, viewport_height: f32) Camera {
        return Camera{
            .position = position,
            .zoom = zoom,
            .viewport_width = viewport_width,
            .viewport_height = viewport_height,
        };
    }

    /// Convert world coordinates (center origin, y-up) to screen pixels (top-left origin, y-down)
    pub fn worldToScreen(self: Camera, world_pos: Vec2) Vec2 {
        // Offset from camera center
        const relative = world_pos.sub(self.position);

        // Apply zoom
        const zoomed = Vec2{
            .x = relative.x * self.zoom,
            .y = relative.y * self.zoom,
        };

        // Convert to screen space: flip Y and move origin to top-left
        return Vec2{
            .x = self.viewport_width / 2.0 + zoomed.x,
            .y = self.viewport_height / 2.0 - zoomed.y, // Flip Y
        };
    }

    /// Convert screen pixels (top-left origin, y-down) to world coordinates (center origin, y-up)
    pub fn screenToWorld(self: Camera, screen_pos: Vec2) Vec2 {
        // Convert from screen space to camera-relative space
        const relative = Vec2{
            .x = screen_pos.x - self.viewport_width / 2.0,
            .y = -(screen_pos.y - self.viewport_height / 2.0), // Flip Y
        };

        // Remove zoom
        const unzoomed = Vec2{
            .x = relative.x / self.zoom,
            .y = relative.y / self.zoom,
        };

        // Offset by camera position
        return unzoomed.add(self.position);
    }

    /// Pan the camera by a screen-space delta
    pub fn pan(self: *Camera, screen_delta: Vec2) void {
        // Convert screen delta to world delta (accounting for zoom and Y-flip)
        const world_delta = Vec2{
            .x = screen_delta.x / self.zoom,
            .y = -screen_delta.y / self.zoom, // Flip Y for world space
        };

        self.position = self.position.add(world_delta);
    }

    /// Zoom centered on a cursor position in screen space
    pub fn zoomAt(self: *Camera, cursor_screen: Vec2, zoom_delta: f32) void {
        // Get world position under cursor before zoom
        const world_before = self.screenToWorld(cursor_screen);

        // Apply zoom
        const new_zoom = std.math.clamp(self.zoom + zoom_delta, self.min_zoom, self.max_zoom);
        self.zoom = new_zoom;

        // Get world position under cursor after zoom
        const world_after = self.screenToWorld(cursor_screen);

        // Adjust camera position to keep world_before under cursor
        const correction = world_before.sub(world_after);
        self.position = self.position.add(correction);
    }

    pub fn setViewportSize(self: *Camera, width: f32, height: f32) void {
        self.viewport_width = width;
        self.viewport_height = height;
    }
};
