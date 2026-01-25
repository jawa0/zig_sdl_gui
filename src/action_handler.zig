const std = @import("std");
const action = @import("action.zig");
const camera = @import("camera.zig");
const math = @import("math.zig");

const Action = action.Action;
const ActionParams = action.ActionParams;
const Camera = camera.Camera;
const Vec2 = math.Vec2;

/// Handles application actions by updating application state.
/// This provides the indirection layer between actions and their implementation.
pub const ActionHandler = struct {
    should_quit: bool = false,

    pub fn init() ActionHandler {
        return ActionHandler{};
    }

    /// Process an action and update application state accordingly.
    /// Returns true if the application should quit.
    pub fn handle(self: *ActionHandler, params: ActionParams, cam: *Camera) bool {
        switch (params) {
            .quit => {
                self.should_quit = true;
                return true;
            },

            .pan_start => {
                // Pan start is tracked in InputState, no camera update needed
            },

            .pan_move => |p| {
                cam.pan(Vec2{ .x = p.delta_x, .y = p.delta_y });
            },

            .pan_end => {
                // Pan end is tracked in InputState, no camera update needed
            },

            .zoom_in => |z| {
                const cursor_pos = Vec2{ .x = z.cursor_x, .y = z.cursor_y };
                cam.zoomAt(cursor_pos, z.delta);
            },

            .zoom_out => |z| {
                const cursor_pos = Vec2{ .x = z.cursor_x, .y = z.cursor_y };
                cam.zoomAt(cursor_pos, z.delta);
            },
        }

        return false;
    }
};
