const std = @import("std");
const math = @import("math.zig");
const camera = @import("camera.zig");
const sdl = @import("sdl.zig");
const action = @import("action.zig");
const tool_mod = @import("tool.zig");

const Vec2 = math.Vec2;
const Camera = camera.Camera;
const c = sdl.c;
const ActionParams = action.ActionParams;
const PanParams = action.PanParams;
const ZoomParams = action.ZoomParams;
const TextEditParams = action.TextEditParams;
const SelectParams = action.SelectParams;
const Tool = tool_mod.Tool;

pub const InputState = struct {
    mouse_x: f32 = 0,
    mouse_y: f32 = 0,
    last_click_time: u32 = 0,
    last_click_x: f32 = 0,
    last_click_y: f32 = 0,

    const PAN_SPEED: f32 = 20.0; // pixels per scroll unit
    const DOUBLE_CLICK_TIME_MS: u32 = 500; // milliseconds
    const DOUBLE_CLICK_DISTANCE: f32 = 5.0; // pixels

    pub fn init() InputState {
        return InputState{};
    }

    /// Handle an SDL event and generate an action if applicable.
    /// Returns an action to be processed by the ActionHandler, or null if no action.
    /// is_editing parameter indicates if we're currently in text editing mode
    /// Note: Some events (like single clicks and double-clicks) require additional processing in main.zig for hit testing
    pub fn handleEvent(self: *InputState, event: *const c.SDL_Event, cam: *const Camera, is_editing: bool, _: Tool) ?ActionParams {
        switch (event.type) {
            c.SDL_QUIT => return ActionParams{ .quit = {} },

            c.SDL_KEYDOWN => {
                if (event.key.keysym.scancode == c.SDL_SCANCODE_ESCAPE) {
                    if (is_editing) {
                        return ActionParams{ .end_text_edit = {} };
                    }
                    // Escape no longer quits the app - use window close button instead
                }

                // Only handle these keys when not editing
                if (!is_editing) {
                    if (event.key.keysym.scancode == c.SDL_SCANCODE_D) {
                        return ActionParams{ .toggle_color_scheme = {} };
                    }
                    if (event.key.keysym.scancode == c.SDL_SCANCODE_G) {
                        return ActionParams{ .toggle_grid = {} };
                    }
                    if (event.key.keysym.scancode == c.SDL_SCANCODE_B) {
                        return ActionParams{ .toggle_bounding_boxes = {} };
                    }
                    if (event.key.keysym.scancode == c.SDL_SCANCODE_DELETE or
                        event.key.keysym.scancode == c.SDL_SCANCODE_BACKSPACE)
                    {
                        return ActionParams{ .delete_selected = {} };
                    }
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

            c.SDL_MOUSEBUTTONDOWN => {
                // Track double-clicks for text creation (works in any tool mode)
                if (event.button.button == c.SDL_BUTTON_LEFT) {
                    const click_x = @as(f32, @floatFromInt(event.button.x));
                    const click_y = @as(f32, @floatFromInt(event.button.y));
                    const current_time = c.SDL_GetTicks();

                    // Check for double-click
                    const time_since_last = current_time - self.last_click_time;
                    const dx = click_x - self.last_click_x;
                    const dy = click_y - self.last_click_y;
                    const distance = @sqrt(dx * dx + dy * dy);

                    if (time_since_last <= DOUBLE_CLICK_TIME_MS and distance <= DOUBLE_CLICK_DISTANCE) {
                        // Double-click detected - request text edit
                        // Note: main.zig will check if click is on blank canvas
                        return ActionParams{ .begin_text_edit = TextEditParams{
                            .screen_x = click_x,
                            .screen_y = click_y,
                        } };
                    }

                    // Record this click for potential future double-click
                    self.last_click_time = current_time;
                    self.last_click_x = click_x;
                    self.last_click_y = click_y;
                }
            },

            else => {},
        }

        return null;
    }
};
