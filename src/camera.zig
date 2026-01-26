const std = @import("std");
const math = @import("math.zig");
const Vec2 = math.Vec2;

pub const Camera = struct {
    position: Vec2, // Camera center in world space
    zoom: f32, // Zoom level (1.0 = 100%)
    viewport_width: f32,
    viewport_height: f32,
    min_zoom: f32 = 0.01,
    max_zoom: f32 = 100.0,

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

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;
const expectEqual = testing.expectEqual;
const expectApproxEqAbs = testing.expectApproxEqAbs;

test "Camera.init" {
    const cam = Camera.init(Vec2{ .x = 10, .y = 20 }, 2.0, 800, 600);
    try expectEqual(10, cam.position.x);
    try expectEqual(20, cam.position.y);
    try expectEqual(2.0, cam.zoom);
    try expectEqual(800, cam.viewport_width);
    try expectEqual(600, cam.viewport_height);
}

test "Camera.worldToScreen at origin with identity zoom" {
    const cam = Camera.init(Vec2{ .x = 0, .y = 0 }, 1.0, 800, 600);
    const world_origin = Vec2{ .x = 0, .y = 0 };
    const screen = cam.worldToScreen(world_origin);

    // World origin should be at screen center
    try expectEqual(400, screen.x);
    try expectEqual(300, screen.y);
}

test "Camera.worldToScreen Y-axis flip" {
    const cam = Camera.init(Vec2{ .x = 0, .y = 0 }, 1.0, 800, 600);

    // Positive Y in world space should be UP (negative in screen space)
    const world_up = Vec2{ .x = 0, .y = 100 };
    const screen = cam.worldToScreen(world_up);

    try expectEqual(400, screen.x); // Center X
    try expectEqual(200, screen.y); // 300 - 100 (up in world = lower Y in screen)
}

test "Camera.worldToScreen with zoom" {
    const cam = Camera.init(Vec2{ .x = 0, .y = 0 }, 2.0, 800, 600);
    const world_pos = Vec2{ .x = 50, .y = 0 };
    const screen = cam.worldToScreen(world_pos);

    // 50 world units * 2 zoom = 100 screen pixels from center
    try expectEqual(500, screen.x); // 400 + 100
    try expectEqual(300, screen.y); // Center Y unchanged
}

test "Camera.worldToScreen with camera offset" {
    const cam = Camera.init(Vec2{ .x = 100, .y = 50 }, 1.0, 800, 600);
    const world_pos = Vec2{ .x = 100, .y = 50 }; // Same as camera position
    const screen = cam.worldToScreen(world_pos);

    // Camera looking at same point should show it at center
    try expectEqual(400, screen.x);
    try expectEqual(300, screen.y);
}

test "Camera.screenToWorld at center with identity zoom" {
    const cam = Camera.init(Vec2{ .x = 0, .y = 0 }, 1.0, 800, 600);
    const screen_center = Vec2{ .x = 400, .y = 300 };
    const world = cam.screenToWorld(screen_center);

    // Screen center should be world origin
    try expectEqual(0, world.x);
    try expectEqual(0, world.y);
}

test "Camera.screenToWorld Y-axis flip" {
    const cam = Camera.init(Vec2{ .x = 0, .y = 0 }, 1.0, 800, 600);

    // Lower Y in screen space (200) should be higher Y in world space
    const screen_pos = Vec2{ .x = 400, .y = 200 };
    const world = cam.screenToWorld(screen_pos);

    try expectEqual(0, world.x);
    try expectEqual(100, world.y); // 300 - 200 = 100 up in world
}

test "Camera.screenToWorld with zoom" {
    const cam = Camera.init(Vec2{ .x = 0, .y = 0 }, 2.0, 800, 600);
    const screen_pos = Vec2{ .x = 500, .y = 300 };
    const world = cam.screenToWorld(screen_pos);

    // 100 screen pixels / 2 zoom = 50 world units from origin
    try expectEqual(50, world.x);
    try expectEqual(0, world.y);
}

test "Camera.worldToScreen and screenToWorld roundtrip" {
    const cam = Camera.init(Vec2{ .x = 25, .y = 35 }, 1.5, 800, 600);
    const original_world = Vec2{ .x = 100, .y = 200 };

    const screen = cam.worldToScreen(original_world);
    const back_to_world = cam.screenToWorld(screen);

    try expectApproxEqAbs(original_world.x, back_to_world.x, 0.0001);
    try expectApproxEqAbs(original_world.y, back_to_world.y, 0.0001);
}

test "Camera.pan right" {
    var cam = Camera.init(Vec2{ .x = 0, .y = 0 }, 1.0, 800, 600);

    // Pan right by 100 screen pixels
    cam.pan(Vec2{ .x = 100, .y = 0 });

    // Camera should move right in world space
    try expectEqual(100, cam.position.x);
    try expectEqual(0, cam.position.y);
}

test "Camera.pan down (screen space)" {
    var cam = Camera.init(Vec2{ .x = 0, .y = 0 }, 1.0, 800, 600);

    // Pan down in screen space (positive Y)
    cam.pan(Vec2{ .x = 0, .y = 100 });

    // Camera should move down in world space (negative Y due to flip)
    try expectEqual(0, cam.position.x);
    try expectEqual(-100, cam.position.y);
}

test "Camera.pan with zoom" {
    var cam = Camera.init(Vec2{ .x = 0, .y = 0 }, 2.0, 800, 600);

    // Pan by 100 screen pixels
    cam.pan(Vec2{ .x = 100, .y = 0 });

    // With 2x zoom, 100 screen pixels = 50 world units
    try expectEqual(50, cam.position.x);
}

test "Camera.zoomAt center increases zoom" {
    var cam = Camera.init(Vec2{ .x = 0, .y = 0 }, 1.0, 800, 600);
    const screen_center = Vec2{ .x = 400, .y = 300 };

    cam.zoomAt(screen_center, 0.5);

    try expectEqual(1.5, cam.zoom);
    // Position shouldn't change when zooming at center
    try expectEqual(0, cam.position.x);
    try expectEqual(0, cam.position.y);
}

test "Camera.zoomAt keeps cursor position fixed" {
    var cam = Camera.init(Vec2{ .x = 0, .y = 0 }, 1.0, 800, 600);

    // Pick a point not at center
    const cursor_screen = Vec2{ .x = 600, .y = 400 };
    const world_before = cam.screenToWorld(cursor_screen);

    // Zoom in
    cam.zoomAt(cursor_screen, 1.0); // Zoom from 1.0 to 2.0

    // Same screen position should still point to same world position
    const world_after = cam.screenToWorld(cursor_screen);

    try expectApproxEqAbs(world_before.x, world_after.x, 0.0001);
    try expectApproxEqAbs(world_before.y, world_after.y, 0.0001);
}

test "Camera.zoomAt respects min zoom" {
    var cam = Camera.init(Vec2{ .x = 0, .y = 0 }, 0.5, 800, 600);
    const cursor = Vec2{ .x = 400, .y = 300 };

    // Try to zoom below min (0.25)
    cam.zoomAt(cursor, -1.0);

    try expectEqual(0.25, cam.zoom); // Should clamp at min
}

test "Camera.zoomAt respects max zoom" {
    var cam = Camera.init(Vec2{ .x = 0, .y = 0 }, 3.5, 800, 600);
    const cursor = Vec2{ .x = 400, .y = 300 };

    // Try to zoom above max (4.0)
    cam.zoomAt(cursor, 1.0);

    try expectEqual(4.0, cam.zoom); // Should clamp at max
}

test "Camera.setViewportSize" {
    var cam = Camera.init(Vec2{ .x = 0, .y = 0 }, 1.0, 800, 600);

    cam.setViewportSize(1024, 768);

    try expectEqual(1024, cam.viewport_width);
    try expectEqual(768, cam.viewport_height);
}

