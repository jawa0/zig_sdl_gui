const std = @import("std");
const math = @import("math.zig");
const camera = @import("camera.zig");
const sdl = @import("sdl.zig");

const Vec2 = math.Vec2;
const Camera = camera.Camera;
const c = sdl.c;

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

    /// Handle an SDL event and update camera accordingly.
    /// Returns true if the application should quit.
    pub fn handleEvent(self: *InputState, event: *const c.SDL_Event, cam: *Camera) bool {
        switch (event.type) {
            c.SDL_QUIT => return true,

            c.SDL_KEYDOWN => {
                if (event.key.keysym.scancode == c.SDL_SCANCODE_ESCAPE) {
                    return true;
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
                    }
                }

                if (self.is_dragging) {
                    // Pan the camera by the delta
                    const dx = self.mouse_x - self.drag_start_x;
                    const dy = self.mouse_y - self.drag_start_y;

                    cam.pan(Vec2{ .x = -dx, .y = -dy });

                    // Update drag start for next frame
                    self.drag_start_x = self.mouse_x;
                    self.drag_start_y = self.mouse_y;
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
                    self.is_dragging = false;
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
                    const cursor_pos = Vec2{ .x = self.mouse_x, .y = self.mouse_y };
                    cam.zoomAt(cursor_pos, zoom_delta);
                }
            },

            else => {},
        }

        return false;
    }
};
