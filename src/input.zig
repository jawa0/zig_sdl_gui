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

    const PAN_SPEED: f32 = 20.0; // pixels per scroll unit

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
                // Track cursor position for zoom operations
                self.mouse_x = @floatFromInt(event.motion.x);
                self.mouse_y = @floatFromInt(event.motion.y);
            },

            c.SDL_MOUSEWHEEL => {
                const mod_state = c.SDL_GetModState();
                const ctrl_pressed = (mod_state & c.KMOD_CTRL) != 0;

                if (ctrl_pressed) {
                    // Ctrl + scroll: Zoom at cursor position
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
                } else {
                    // Scroll without Ctrl: Pan the canvas
                    const delta_x = @as(f32, @floatFromInt(event.wheel.x)) * PAN_SPEED;
                    const delta_y = @as(f32, @floatFromInt(event.wheel.y)) * PAN_SPEED;

                    if (delta_x != 0 or delta_y != 0) {
                        return ActionParams{ .pan_move = PanParams{ .delta_x = delta_x, .delta_y = -delta_y } };
                    }
                }
            },

            else => {},
        }

        return null;
    }
};
