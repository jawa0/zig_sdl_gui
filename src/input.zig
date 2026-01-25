const std = @import("std");
const math = @import("math.zig");
const camera = @import("camera.zig");
const sdl = @import("sdl.zig");
const action = @import("action.zig");

const Vec2 = math.Vec2;
const Camera = camera.Camera;
const c = sdl.c;
const ActionParams = action.ActionParams;
const PanParams = action.PanParams;
const ZoomParams = action.ZoomParams;

pub const InputState = struct {
    mouse_x: f32 = 0,
    mouse_y: f32 = 0,
    is_dragging: bool = false,
    drag_start_x: f32 = 0,
    drag_start_y: f32 = 0,
    mouse_down_x: f32 = 0,
    mouse_down_y: f32 = 0,
    mouse_button_down: bool = false,

    const DRAG_THRESHOLD: f32 = 3.0; // pixels

    pub fn init() InputState {
        return InputState{};
    }

    /// Handle an SDL event and generate an action if applicable.
    /// Returns an action to be processed by the ActionHandler, or null if no action.
    pub fn handleEvent(self: *InputState, event: *const c.SDL_Event, cam: *const Camera) ?ActionParams {
        switch (event.type) {
            c.SDL_QUIT => return ActionParams{ .quit = {} },

            c.SDL_KEYDOWN => {
                if (event.key.keysym.scancode == c.SDL_SCANCODE_ESCAPE) {
                    return ActionParams{ .quit = {} };
                }
                if (event.key.keysym.scancode == c.SDL_SCANCODE_D) {
                    return ActionParams{ .toggle_color_scheme = {} };
                }
            },

            c.SDL_MOUSEMOTION => {
                self.mouse_x = @floatFromInt(event.motion.x);
                self.mouse_y = @floatFromInt(event.motion.y);

                if (self.mouse_button_down and !self.is_dragging) {
                    // Check if we've moved far enough to start dragging
                    const dx = self.mouse_x - self.mouse_down_x;
                    const dy = self.mouse_y - self.mouse_down_y;
                    const dist = @sqrt(dx * dx + dy * dy);

                    if (dist >= DRAG_THRESHOLD) {
                        self.is_dragging = true;
                        self.drag_start_x = self.mouse_x;
                        self.drag_start_y = self.mouse_y;
                        return ActionParams{ .pan_start = PanParams{ .delta_x = 0, .delta_y = 0 } };
                    }
                }

                if (self.is_dragging) {
                    // Pan the camera by the delta
                    const dx = self.mouse_x - self.drag_start_x;
                    const dy = self.mouse_y - self.drag_start_y;

                    // Update drag start for next frame
                    self.drag_start_x = self.mouse_x;
                    self.drag_start_y = self.mouse_y;

                    return ActionParams{ .pan_move = PanParams{ .delta_x = -dx, .delta_y = -dy } };
                }
            },

            c.SDL_MOUSEBUTTONDOWN => {
                if (event.button.button == c.SDL_BUTTON_LEFT) {
                    self.mouse_button_down = true;
                    self.mouse_down_x = @floatFromInt(event.button.x);
                    self.mouse_down_y = @floatFromInt(event.button.y);
                }
            },

            c.SDL_MOUSEBUTTONUP => {
                if (event.button.button == c.SDL_BUTTON_LEFT) {
                    self.mouse_button_down = false;
                    if (self.is_dragging) {
                        self.is_dragging = false;
                        return ActionParams{ .pan_end = {} };
                    }
                }
            },

            c.SDL_MOUSEWHEEL => {
                // Zoom at cursor position
                const zoom_delta = if (event.wheel.y > 0)
                    cam.zoom * 0.1 // Zoom in by 10%
                else if (event.wheel.y < 0)
                    -cam.zoom * 0.1 // Zoom out by 10%
                else
                    0.0;

                if (zoom_delta != 0) {
                    const zoom_params = ZoomParams{
                        .cursor_x = self.mouse_x,
                        .cursor_y = self.mouse_y,
                        .delta = zoom_delta,
                    };

                    if (event.wheel.y > 0) {
                        return ActionParams{ .zoom_in = zoom_params };
                    } else {
                        return ActionParams{ .zoom_out = zoom_params };
                    }
                }
            },

            else => {},
        }

        return null;
    }
};
