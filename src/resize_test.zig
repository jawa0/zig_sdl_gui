const std = @import("std");
const testing = std.testing;
const math = @import("math.zig");
const action = @import("action.zig");

const Vec2 = math.Vec2;
const ResizeHandle = action.ResizeHandle;

/// Helper to simulate a bounding box
const BBox = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,

    fn topLeft(self: BBox) Vec2 {
        return Vec2{ .x = self.x, .y = self.y + self.h };
    }

    fn topRight(self: BBox) Vec2 {
        return Vec2{ .x = self.x + self.w, .y = self.y + self.h };
    }

    fn bottomLeft(self: BBox) Vec2 {
        return Vec2{ .x = self.x, .y = self.y };
    }

    fn bottomRight(self: BBox) Vec2 {
        return Vec2{ .x = self.x + self.w, .y = self.y };
    }

    fn getHandle(self: BBox, handle: ResizeHandle) Vec2 {
        return switch (handle) {
            .top_left => self.topLeft(),
            .top_right => self.topRight(),
            .bottom_left => self.bottomLeft(),
            .bottom_right => self.bottomRight(),
        };
    }

    fn getOppositeCorner(self: BBox, handle: ResizeHandle) Vec2 {
        return switch (handle) {
            .top_left => self.bottomRight(),
            .top_right => self.bottomLeft(),
            .bottom_left => self.topRight(),
            .bottom_right => self.topLeft(),
        };
    }
};

test "BBox corner positions in Y-up coordinate system" {
    // bbox.y is the bottom edge in world space (Y-up)
    // bbox.y + bbox.h is the top edge
    const bbox = BBox{ .x = 10, .y = 20, .w = 100, .h = 50 };

    try testing.expectEqual(10.0, bbox.topLeft().x); // left edge
    try testing.expectEqual(70.0, bbox.topLeft().y); // top edge = y + h

    try testing.expectEqual(110.0, bbox.topRight().x); // right edge = x + w
    try testing.expectEqual(70.0, bbox.topRight().y); // top edge

    try testing.expectEqual(10.0, bbox.bottomLeft().x); // left edge
    try testing.expectEqual(20.0, bbox.bottomLeft().y); // bottom edge = y

    try testing.expectEqual(110.0, bbox.bottomRight().x); // right edge
    try testing.expectEqual(20.0, bbox.bottomRight().y); // bottom edge
}

test "Opposite corners are correct for each handle" {
    const bbox = BBox{ .x = 0, .y = 0, .w = 100, .h = 50 };

    // Top-left opposite is bottom-right
    const tl_opposite = bbox.getOppositeCorner(.top_left);
    try testing.expectEqual(100.0, tl_opposite.x);
    try testing.expectEqual(0.0, tl_opposite.y);

    // Top-right opposite is bottom-left
    const tr_opposite = bbox.getOppositeCorner(.top_right);
    try testing.expectEqual(0.0, tr_opposite.x);
    try testing.expectEqual(0.0, tr_opposite.y);

    // Bottom-left opposite is top-right
    const bl_opposite = bbox.getOppositeCorner(.bottom_left);
    try testing.expectEqual(100.0, bl_opposite.x);
    try testing.expectEqual(50.0, bl_opposite.y);

    // Bottom-right opposite is top-left
    const br_opposite = bbox.getOppositeCorner(.bottom_right);
    try testing.expectEqual(0.0, br_opposite.x);
    try testing.expectEqual(50.0, br_opposite.y);
}

test "Resize bottom-right: handle should be at cursor" {
    // Start with bbox at origin
    const start_bbox = BBox{ .x = 0, .y = 0, .w = 100, .h = 50 };
    const handle = ResizeHandle.bottom_right;
    const opposite_corner = start_bbox.getOppositeCorner(handle); // top-left at (0, 50)

    // User drags cursor to (150, -25)
    const cursor_pos = Vec2{ .x = 150, .y = -25 };

    // Calculate desired dimensions from cursor to opposite corner
    const desired_width = @abs(cursor_pos.x - opposite_corner.x); // |150 - 0| = 150
    const desired_height = @abs(cursor_pos.y - opposite_corner.y); // |-25 - 50| = 75

    try testing.expectEqual(150.0, desired_width);
    try testing.expectEqual(75.0, desired_height);

    // Calculate scale maintaining aspect ratio
    const width_scale = desired_width / start_bbox.w; // 150/100 = 1.5
    const height_scale = desired_height / start_bbox.h; // 75/50 = 1.5
    const scale = @max(width_scale, height_scale); // 1.5

    try testing.expectEqual(1.5, scale);

    // If we could get exact scaling, new bbox would be
    const scaled_w = start_bbox.w * scale; // 150
    const scaled_h = start_bbox.h * scale; // 75

    try testing.expectEqual(150.0, scaled_w);
    try testing.expectEqual(75.0, scaled_h);

    // Position element to keep opposite corner (top-left) at (0, 50)
    // For bottom_right handle, elem.position = opposite_corner (top-left)
    const elem_pos = opposite_corner;

    // Calculate bbox
    const new_bbox = BBox{
        .x = elem_pos.x, // 0
        .y = elem_pos.y - scaled_h, // 50 - 75 = -25
        .w = scaled_w, // 150
        .h = scaled_h, // 75
    };

    // Verify opposite corner stayed fixed
    try testing.expectEqual(0.0, new_bbox.topLeft().x);
    try testing.expectEqual(50.0, new_bbox.topLeft().y);

    // Verify handle is now at cursor position
    const new_handle_pos = new_bbox.getHandle(handle);
    try testing.expectEqual(cursor_pos.x, new_handle_pos.x);
    try testing.expectEqual(cursor_pos.y, new_handle_pos.y);
}

test "Resize top-left: handle should be at cursor" {
    const start_bbox = BBox{ .x = 0, .y = 0, .w = 100, .h = 50 };
    const handle = ResizeHandle.top_left;
    const opposite_corner = start_bbox.getOppositeCorner(handle); // bottom-right at (100, 0)

    // User drags cursor to (-50, 75)
    const cursor_pos = Vec2{ .x = -50, .y = 75 };

    const desired_width = @abs(cursor_pos.x - opposite_corner.x); // |-50 - 100| = 150
    const desired_height = @abs(cursor_pos.y - opposite_corner.y); // |75 - 0| = 75

    const width_scale = desired_width / start_bbox.w; // 1.5
    const height_scale = desired_height / start_bbox.h; // 1.5
    const scale = @max(width_scale, height_scale);

    const scaled_w = start_bbox.w * scale;
    const scaled_h = start_bbox.h * scale;

    // For top_left handle, elem.position.x = opposite.x - width, elem.position.y = opposite.y + height
    const elem_pos = Vec2{
        .x = opposite_corner.x - scaled_w, // 100 - 150 = -50
        .y = opposite_corner.y + scaled_h, // 0 + 75 = 75
    };

    const new_bbox = BBox{
        .x = elem_pos.x,
        .y = elem_pos.y - scaled_h,
        .w = scaled_w,
        .h = scaled_h,
    };

    // Verify opposite corner stayed fixed
    try testing.expectEqual(100.0, new_bbox.bottomRight().x);
    try testing.expectEqual(0.0, new_bbox.bottomRight().y);

    // Verify handle is at cursor
    const new_handle_pos = new_bbox.getHandle(handle);
    try testing.expectEqual(cursor_pos.x, new_handle_pos.x);
    try testing.expectEqual(cursor_pos.y, new_handle_pos.y);
}

test "Non-proportional resize: aspect ratio maintained with max scale" {
    const start_bbox = BBox{ .x = 0, .y = 0, .w = 100, .h = 50 };
    const handle = ResizeHandle.bottom_right;
    const opposite_corner = start_bbox.getOppositeCorner(handle);

    // User drags to make it wider but not taller (200x50 desired)
    const cursor_pos = Vec2{ .x = 200, .y = 0 };

    const desired_width = @abs(cursor_pos.x - opposite_corner.x); // 200
    const desired_height = @abs(cursor_pos.y - opposite_corner.y); // 50

    const width_scale = desired_width / start_bbox.w; // 2.0
    const height_scale = desired_height / start_bbox.h; // 1.0
    const scale = @max(width_scale, height_scale); // 2.0 (take larger to maintain aspect)

    // Both dimensions scale by 2.0
    const scaled_w = start_bbox.w * scale; // 200
    const scaled_h = start_bbox.h * scale; // 100 (not 50!)

    try testing.expectEqual(200.0, scaled_w);
    try testing.expectEqual(100.0, scaled_h);

    // The actual bbox will be 200x100, not 200x50
    // So the handle will NOT be exactly at cursor in Y dimension
    const elem_pos = opposite_corner;
    const new_bbox = BBox{
        .x = elem_pos.x,
        .y = elem_pos.y - scaled_h,
        .w = scaled_w,
        .h = scaled_h,
    };

    const new_handle_pos = new_bbox.getHandle(handle);

    // X matches cursor (width is controlling dimension)
    try testing.expectEqual(cursor_pos.x, new_handle_pos.x);

    // Y does NOT match cursor (height overshoots to maintain aspect ratio)
    try testing.expect(new_handle_pos.y != cursor_pos.y);
    try testing.expectEqual(-50.0, new_handle_pos.y); // went below 0
}

test "Font rendering divergence simulation" {
    // This test simulates what happens when font rendering doesn't scale exactly
    const start_bbox = BBox{ .x = 0, .y = 0, .w = 100, .h = 50 };
    const handle = ResizeHandle.bottom_right;
    const opposite_corner = start_bbox.getOppositeCorner(handle);

    // User drags to (150, -25)
    const cursor_pos = Vec2{ .x = 150, .y = -25 };

    const desired_width = @abs(cursor_pos.x - opposite_corner.x);
    const desired_height = @abs(cursor_pos.y - opposite_corner.y);

    // Scale would be 1.5, font size would scale by 1.5 (e.g., 16pt -> 24pt)
    // In theory, bbox should be 150x75
    // But font renders as 148x74 (slightly off due to font metrics)
    const actual_rendered_w: f32 = 148.0;
    const actual_rendered_h: f32 = 74.0;

    // Position using actual rendered dimensions
    const elem_pos = opposite_corner;
    const actual_bbox = BBox{
        .x = elem_pos.x,
        .y = elem_pos.y - actual_rendered_h,
        .w = actual_rendered_w,
        .h = actual_rendered_h,
    };

    // Handle is NOT at cursor anymore!
    const actual_handle_pos = actual_bbox.getHandle(handle);

    try testing.expect(@abs(actual_handle_pos.x - cursor_pos.x) > 0); // diverged
    try testing.expect(@abs(actual_handle_pos.y - cursor_pos.y) > 0); // diverged

    // The error is 2 pixels in x and 1 pixel in y
    try testing.expectApproxEqAbs(cursor_pos.x, actual_handle_pos.x, 2.0);
    try testing.expectApproxEqAbs(cursor_pos.y, actual_handle_pos.y, 1.0);
}
