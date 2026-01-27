const std = @import("std");
const math = @import("math.zig");
const camera = @import("camera.zig");
const scene = @import("scene.zig");
const input = @import("input.zig");
const text_cache = @import("text_cache.zig");
const sdl = @import("sdl.zig");
const action_handler = @import("action_handler.zig");
const action = @import("action.zig");
const color_scheme = @import("color_scheme.zig");
const grid = @import("grid.zig");

const Vec2 = math.Vec2;
const Camera = camera.Camera;
const SceneGraph = scene.SceneGraph;
const InputState = input.InputState;
const ActionHandler = action_handler.ActionHandler;
const ColorScheme = color_scheme.ColorScheme;
const Grid = grid.Grid;
const c = sdl.c;

const WINDOW_WIDTH = 1400;
const WINDOW_HEIGHT = 900;
const TARGET_FPS = 60;
const FRAME_TIME_MS: u32 = 1000 / TARGET_FPS;
const FPS_UPDATE_INTERVAL_MS: u32 = 500;

/// Populate the scene graph with test content using the given color scheme.
/// Preserves elements with IDs in the preserved_ids array.
fn populateScene(scene_graph: *SceneGraph, colors: ColorScheme, font: *c.TTF_Font, preserved_ids: []const u32) !void {
    // Clear existing scene except preserved elements (e.g., FPS display)
    scene_graph.clearExcept(preserved_ids);

    // Create test text lines in world space (centered vertically around origin)
    const base_font_size: f32 = 16.0;
    const line_text = "This is a line of text.";
    const line_spacing_world: f32 = 4.0; // World-space spacing

    // Get text dimensions at base font size
    _ = c.TTF_SetFontSize(font, @intFromFloat(base_font_size));
    var line_text_w: c_int = 0;
    var line_text_h: c_int = 0;
    _ = c.TTF_SizeText(font, line_text, &line_text_w, &line_text_h);

    // Calculate total height needed and create lines centered around origin
    const num_lines: i32 = 40;
    const line_height_world = base_font_size + line_spacing_world;
    const total_height = @as(f32, @floatFromInt(num_lines)) * line_height_world;
    const start_y = total_height / 2.0;

    var i: i32 = 0;
    while (i < num_lines) : (i += 1) {
        const y = start_y - @as(f32, @floatFromInt(i)) * line_height_world;

        // Calculate positions for rectangle (centered around text position)
        // Add text label (without border rectangle)
        const text_x = -@as(f32, @floatFromInt(line_text_w)) / 2.0;
        _ = try scene_graph.addTextLabel(
            line_text,
            Vec2{ .x = text_x, .y = y },
            base_font_size,
            colors.text,
            .world,
            font,
        );
    }

    // Large red rectangle on the left
    _ = try scene_graph.addRectangle(
        Vec2{ .x = -400, .y = -150 },
        200,
        100,
        3.0,
        colors.rect_red,
        .world,
    );

    // Medium green rectangle on the right
    _ = try scene_graph.addRectangle(
        Vec2{ .x = 250, .y = -100 },
        150,
        150,
        4.0,
        colors.rect_green,
        .world,
    );

    // Small yellow rectangle near top
    _ = try scene_graph.addRectangle(
        Vec2{ .x = -50, .y = -400 },
        80,
        60,
        2.0,
        colors.rect_yellow,
        .world,
    );
}

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize SDL
    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        std.debug.print("SDL init failed: {s}\n", .{c.SDL_GetError()});
        return error.SDLInitFailed;
    }
    defer c.SDL_Quit();

    // Initialize SDL_ttf
    if (c.TTF_Init() != 0) {
        std.debug.print("TTF init failed: {s}\n", .{c.TTF_GetError()});
        return error.TTFInitFailed;
    }
    defer c.TTF_Quit();

    // Create window
    // CRITICAL: Set render scale quality BEFORE creating renderer and textures
    // "0" = nearest, "1" = linear, "2" = anisotropic, "best" = highest available
    _ = c.SDL_SetHint(c.SDL_HINT_RENDER_SCALE_QUALITY, "best");

    const window = c.SDL_CreateWindow(
        "Zig SDL2 GUI - Scene Graph",
        c.SDL_WINDOWPOS_CENTERED,
        c.SDL_WINDOWPOS_CENTERED,
        WINDOW_WIDTH,
        WINDOW_HEIGHT,
        c.SDL_WINDOW_SHOWN | c.SDL_WINDOW_RESIZABLE,
    ) orelse {
        std.debug.print("Window creation failed: {s}\n", .{c.SDL_GetError()});
        return error.WindowCreationFailed;
    };
    defer c.SDL_DestroyWindow(window);

    // Create hardware-accelerated renderer with vsync (provides double buffering)
    const renderer = c.SDL_CreateRenderer(
        window,
        -1,
        c.SDL_RENDERER_ACCELERATED | c.SDL_RENDERER_PRESENTVSYNC,
    ) orelse {
        std.debug.print("Renderer creation failed: {s}\n", .{c.SDL_GetError()});
        return error.RendererCreationFailed;
    };
    defer c.SDL_DestroyRenderer(renderer);

    // Load font (initial size doesn't matter much, we'll resize as needed)
    const font = c.TTF_OpenFont("assets/fonts/JetBrainsMono-Regular.ttf", 16) orelse {
        std.debug.print("Font loading failed: {s}\n", .{c.TTF_GetError()});
        return error.FontLoadFailed;
    };
    defer c.TTF_CloseFont(font);

    // Initialize camera at world origin with zoom 1.0
    var cam = Camera.init(
        Vec2{ .x = 0, .y = 0 },
        1.0,
        @floatFromInt(WINDOW_WIDTH),
        @floatFromInt(WINDOW_HEIGHT),
    );

    // Initialize scene graph
    var scene_graph = SceneGraph.init(allocator);
    defer scene_graph.deinit();

    // Initialize grid
    const world_grid = Grid{};

    // Initialize input state and action handler
    var input_state = InputState.init();
    var action_mgr = ActionHandler.init();

    // Get current color scheme and populate scene
    var colors = ColorScheme.get(action_mgr.scheme_type);
    const no_preserved_ids: []const u32 = &[_]u32{};
    try populateScene(&scene_graph, colors, font, no_preserved_ids);

    // Window size tracking (for handling resize)
    var window_width: c_int = WINDOW_WIDTH;
    var window_height: c_int = WINDOW_HEIGHT;

    // FPS tracking
    var frame_count: u32 = 0;
    var fps_timer: u32 = c.SDL_GetTicks();
    var current_fps: f32 = 0;
    var fps_text_buf: [64]u8 = undefined;
    var fps_element_id: ?u32 = null;
    var fps_needs_update = true; // Force initial update

    var running = true;
    var event: c.SDL_Event = undefined;

    while (running) {
        const frame_start = c.SDL_GetTicks();

        // Handle events
        while (c.SDL_PollEvent(&event) != 0) {
            // Handle text input when in editing mode
            if (action_mgr.text_edit.is_editing) {
                if (event.type == c.SDL_TEXTINPUT) {
                    // Add typed characters to buffer
                    const text = std.mem.sliceTo(&event.text.text, 0);
                    const remaining = action_mgr.text_edit.text_buffer.len - action_mgr.text_edit.text_len;
                    const to_copy = @min(text.len, remaining);
                    if (to_copy > 0) {
                        @memcpy(action_mgr.text_edit.text_buffer[action_mgr.text_edit.text_len..][0..to_copy], text[0..to_copy]);
                        action_mgr.text_edit.text_len += to_copy;
                        action_mgr.text_edit.cursor_pos = action_mgr.text_edit.text_len;
                    }
                    continue;
                }
                if (event.type == c.SDL_KEYDOWN) {
                    if (event.key.keysym.scancode == c.SDL_SCANCODE_BACKSPACE) {
                        if (action_mgr.text_edit.cursor_pos > 0) {
                            action_mgr.text_edit.cursor_pos -= 1;
                            action_mgr.text_edit.text_len -= 1;
                        }
                        continue;
                    }
                    if (event.key.keysym.scancode == c.SDL_SCANCODE_RETURN) {
                        // Add newline
                        if (action_mgr.text_edit.text_len < action_mgr.text_edit.text_buffer.len) {
                            action_mgr.text_edit.text_buffer[action_mgr.text_edit.text_len] = '\n';
                            action_mgr.text_edit.text_len += 1;
                            action_mgr.text_edit.cursor_pos = action_mgr.text_edit.text_len;
                        }
                        continue;
                    }
                }
            }

            // Handle mouse clicks based on current tool (when not editing text)
            if (!action_mgr.text_edit.is_editing and event.type == c.SDL_MOUSEBUTTONDOWN and event.button.button == c.SDL_BUTTON_LEFT) {
                const click_x = @as(f32, @floatFromInt(event.button.x));
                const click_y = @as(f32, @floatFromInt(event.button.y));

                if (action_mgr.current_tool == .selection) {
                    // Check for handle click first (if element is selected)
                    var handle_clicked = false;
                    if (action_mgr.selected_element_id) |sel_id| {
                        if (scene_graph.findElement(sel_id)) |elem| {
                            // Calculate handle positions from AUTHORITATIVE bbox
                            const world_bbox = elem.bounding_box;
                            const world_top_left = Vec2{ .x = world_bbox.x, .y = world_bbox.y + world_bbox.h };
                            const screen_pos = cam.worldToScreen(world_top_left);

                            // Screen dimensions from authoritative bbox (no font measurement!)
                            const screen_w = world_bbox.w * cam.zoom;
                            const screen_h = world_bbox.h * cam.zoom;

                            const handle_hit_size: f32 = 12.0; // Slightly larger for easier clicking

                            // Helper to check if point is in handle
                            const isInHandle = struct {
                                fn check(px: f32, py: f32, hx: f32, hy: f32, size: f32) bool {
                                    const half = size / 2.0;
                                    return px >= hx - half and px <= hx + half and
                                           py >= hy - half and py <= hy + half;
                                }
                            }.check;

                            // Test each corner handle
                            if (isInHandle(click_x, click_y, screen_pos.x, screen_pos.y, handle_hit_size)) {
                                // Top-left handle
                                _ = action_mgr.handle(action.ActionParams{ .begin_resize_element = action.ResizeParams{
                                    .screen_x = click_x,
                                    .screen_y = click_y,
                                    .handle = .top_left,
                                } }, &cam);
                                handle_clicked = true;
                            } else if (isInHandle(click_x, click_y, screen_pos.x + screen_w, screen_pos.y, handle_hit_size)) {
                                // Top-right handle
                                _ = action_mgr.handle(action.ActionParams{ .begin_resize_element = action.ResizeParams{
                                    .screen_x = click_x,
                                    .screen_y = click_y,
                                    .handle = .top_right,
                                } }, &cam);
                                handle_clicked = true;
                            } else if (isInHandle(click_x, click_y, screen_pos.x, screen_pos.y + screen_h, handle_hit_size)) {
                                // Bottom-left handle
                                _ = action_mgr.handle(action.ActionParams{ .begin_resize_element = action.ResizeParams{
                                    .screen_x = click_x,
                                    .screen_y = click_y,
                                    .handle = .bottom_left,
                                } }, &cam);
                                handle_clicked = true;
                            } else if (isInHandle(click_x, click_y, screen_pos.x + screen_w, screen_pos.y + screen_h, handle_hit_size)) {
                                // Bottom-right handle
                                _ = action_mgr.handle(action.ActionParams{ .begin_resize_element = action.ResizeParams{
                                    .screen_x = click_x,
                                    .screen_y = click_y,
                                    .handle = .bottom_right,
                                } }, &cam);
                                handle_clicked = true;
                            } else {
                                // Not on handle, check if on selected element itself (for dragging)
                                const world_pos = cam.screenToWorld(Vec2{ .x = click_x, .y = click_y });
                                if (elem.bounding_box.containsWorld(world_pos.x, world_pos.y)) {
                                    // Start dragging the element
                                    _ = action_mgr.handle(action.ActionParams{ .begin_drag_element = action.DragParams{
                                        .screen_x = click_x,
                                        .screen_y = click_y,
                                    } }, &cam);
                                    // Store element's current position
                                    action_mgr.drag.element_start_pos = elem.transform.position;
                                    handle_clicked = true;
                                }
                            }

                            // Store element state for resize
                            if (action_mgr.resize.is_resizing) {
                                action_mgr.resize.element_start_pos = elem.transform.position;
                                action_mgr.resize.element_start_scale = elem.transform.scale;
                                action_mgr.resize.last_scale_factor = 1.0; // Reset scale tracking

                                if (elem.element_type == .text_label) {
                                    action_mgr.resize.element_start_font_size = elem.data.text_label.font_size;
                                }

                                // Store AUTHORITATIVE bbox dimensions
                                action_mgr.resize.start_bbox_width = world_bbox.w;
                                action_mgr.resize.start_bbox_height = world_bbox.h;

                                // Calculate opposite corner directly in world space from bbox
                                switch (action_mgr.resize.handle) {
                                    .top_left => {
                                        // Opposite is bottom-right
                                        action_mgr.resize.opposite_corner = Vec2{
                                            .x = world_bbox.x + world_bbox.w,
                                            .y = world_bbox.y,
                                        };
                                    },
                                    .top_right => {
                                        // Opposite is bottom-left
                                        action_mgr.resize.opposite_corner = Vec2{
                                            .x = world_bbox.x,
                                            .y = world_bbox.y,
                                        };
                                    },
                                    .bottom_left => {
                                        // Opposite is top-right
                                        action_mgr.resize.opposite_corner = Vec2{
                                            .x = world_bbox.x + world_bbox.w,
                                            .y = world_bbox.y + world_bbox.h,
                                        };
                                    },
                                    .bottom_right => {
                                        // Opposite is top-left
                                        action_mgr.resize.opposite_corner = Vec2{
                                            .x = world_bbox.x,
                                            .y = world_bbox.y + world_bbox.h,
                                        };
                                    },
                                }
                            }
                        }
                    }

                    // If no handle was clicked, do normal hit test
                    if (!handle_clicked) {
                        if (scene_graph.hitTest(click_x, click_y, &cam)) |hit_id| {
                            // Element was clicked - select it and start dragging immediately
                            _ = action_mgr.handle(action.ActionParams{ .select_element = action.SelectParams{ .element_id = hit_id } }, &cam);

                            // Also start dragging so user can immediately drag after clicking
                            _ = action_mgr.handle(action.ActionParams{ .begin_drag_element = action.DragParams{
                                .screen_x = click_x,
                                .screen_y = click_y,
                            } }, &cam);

                            // Store element's current position for dragging
                            if (scene_graph.findElement(hit_id)) |elem| {
                                action_mgr.drag.element_start_pos = elem.transform.position;
                            }
                        } else {
                            // Empty space clicked - deselect all
                            _ = action_mgr.handle(action.ActionParams{ .deselect_all = {} }, &cam);
                        }
                    }
                }
            }

            // Handle mouse motion for dragging/resizing
            if (event.type == c.SDL_MOUSEMOTION) {
                const mouse_x = @as(f32, @floatFromInt(event.motion.x));
                const mouse_y = @as(f32, @floatFromInt(event.motion.y));

                if (action_mgr.drag.is_dragging) {
                    // Update element position (bbox moves with it, dimensions unchanged)
                    if (scene_graph.findElement(action_mgr.drag.element_id)) |elem| {
                        const current_world = cam.screenToWorld(Vec2{ .x = mouse_x, .y = mouse_y });
                        const delta = Vec2{
                            .x = current_world.x - action_mgr.drag.start_world_pos.x,
                            .y = current_world.y - action_mgr.drag.start_world_pos.y,
                        };
                        elem.transform.position = Vec2{
                            .x = action_mgr.drag.element_start_pos.x + delta.x,
                            .y = action_mgr.drag.element_start_pos.y + delta.y,
                        };
                        // Update bbox position (dimensions stay the same - authoritative!)
                        elem.bounding_box.x = elem.transform.position.x;
                        elem.bounding_box.y = elem.transform.position.y - elem.bounding_box.h;
                    }
                } else if (action_mgr.resize.is_resizing) {
                    // Resize with AUTHORITATIVE bbox - texture scales to fit!
                    if (scene_graph.findElement(action_mgr.resize.element_id)) |elem| {
                        // 1. Handle position = cursor (world space)
                        const handle_world = cam.screenToWorld(Vec2{ .x = mouse_x, .y = mouse_y });

                        // 2. Calculate new bbox dimensions from handle to opposite corner
                        const new_width = @abs(handle_world.x - action_mgr.resize.opposite_corner.x);
                        const new_height = @abs(handle_world.y - action_mgr.resize.opposite_corner.y);

                        // 3. Calculate scale factor to maintain aspect ratio
                        const width_scale = new_width / action_mgr.resize.start_bbox_width;
                        const height_scale = new_height / action_mgr.resize.start_bbox_height;
                        var scale_factor = @max(width_scale, height_scale);

                        // Clamp scale to reasonable range
                        scale_factor = @max(0.1, @min(10.0, scale_factor));

                        // Add hysteresis to prevent oscillation
                        const scale_change = @abs(scale_factor - action_mgr.resize.last_scale_factor);
                        const min_scale_change = 0.005 * action_mgr.resize.last_scale_factor;
                        if (scale_change < min_scale_change) {
                            scale_factor = action_mgr.resize.last_scale_factor;
                        } else {
                            action_mgr.resize.last_scale_factor = scale_factor;
                        }

                        // 4. Update AUTHORITATIVE bbox dimensions (texture will scale to fit!)
                        const bbox_width = action_mgr.resize.start_bbox_width * scale_factor;
                        const bbox_height = action_mgr.resize.start_bbox_height * scale_factor;

                        // 5. Position element to keep opposite corner fixed
                        switch (action_mgr.resize.handle) {
                            .top_left => {
                                elem.transform.position = Vec2{
                                    .x = action_mgr.resize.opposite_corner.x - bbox_width,
                                    .y = action_mgr.resize.opposite_corner.y + bbox_height,
                                };
                            },
                            .top_right => {
                                elem.transform.position = Vec2{
                                    .x = action_mgr.resize.opposite_corner.x,
                                    .y = action_mgr.resize.opposite_corner.y + bbox_height,
                                };
                            },
                            .bottom_left => {
                                elem.transform.position = Vec2{
                                    .x = action_mgr.resize.opposite_corner.x - bbox_width,
                                    .y = action_mgr.resize.opposite_corner.y,
                                };
                            },
                            .bottom_right => {
                                elem.transform.position = Vec2{
                                    .x = action_mgr.resize.opposite_corner.x,
                                    .y = action_mgr.resize.opposite_corner.y,
                                };
                            },
                        }

                        // 6. Update bbox to new dimensions and position
                        elem.bounding_box.x = elem.transform.position.x;
                        elem.bounding_box.y = elem.transform.position.y - bbox_height;
                        elem.bounding_box.w = bbox_width;
                        elem.bounding_box.h = bbox_height;

                        // 7. Update scale/size for proper re-rendering
                        if (elem.element_type == .rectangle) {
                            elem.transform.scale = Vec2{
                                .x = action_mgr.resize.element_start_scale.x * scale_factor,
                                .y = action_mgr.resize.element_start_scale.y * scale_factor,
                            };
                        } else if (elem.element_type == .text_label) {
                            // Update font_size so cache knows to re-render at new size
                            elem.data.text_label.font_size = action_mgr.resize.element_start_font_size * scale_factor;
                        }
                    }
                }
            }

            // Handle mouse button up to end drag/resize
            if (event.type == c.SDL_MOUSEBUTTONUP and event.button.button == c.SDL_BUTTON_LEFT) {
                if (action_mgr.drag.is_dragging) {
                    _ = action_mgr.handle(action.ActionParams{ .end_drag_element = {} }, &cam);
                } else if (action_mgr.resize.is_resizing) {
                    _ = action_mgr.handle(action.ActionParams{ .end_resize_element = {} }, &cam);
                }
            }

            // Generate action from input event
            if (input_state.handleEvent(&event, &cam, action_mgr.text_edit.is_editing, action_mgr.current_tool)) |action_params| {
                // Check if we're entering or leaving text edit mode to enable/disable text input
                const was_editing = action_mgr.text_edit.is_editing;

                // Special handling for begin_text_edit: only allow if not clicking on an element
                const should_process = switch (action_params) {
                    .begin_text_edit => |edit_params| blk: {
                        // Check if double-click is on an element
                        const hit_id = scene_graph.hitTest(edit_params.screen_x, edit_params.screen_y, &cam);
                        // Only begin text edit if clicking on blank canvas (no element hit)
                        break :blk hit_id == null;
                    },
                    else => true, // Process all other actions normally
                };

                // Process the action
                if (should_process) {
                    if (action_mgr.handle(action_params, &cam)) {
                        running = false;
                    }
                }

                // Enable/disable SDL text input
                const is_now_editing = action_mgr.text_edit.is_editing;
                if (!was_editing and is_now_editing) {
                    c.SDL_StartTextInput();
                } else if (was_editing and !is_now_editing) {
                    c.SDL_StopTextInput();
                }
            }

            // Handle window resize
            if (event.type == c.SDL_WINDOWEVENT) {
                if (event.window.event == c.SDL_WINDOWEVENT_SIZE_CHANGED) {
                    window_width = event.window.data1;
                    window_height = event.window.data2;
                    cam.viewport_width = @floatFromInt(window_width);
                    cam.viewport_height = @floatFromInt(window_height);
                    fps_needs_update = true;
                }
            }
        }

        // Update color scheme if it changed
        if (action_mgr.scheme_changed) {
            colors = ColorScheme.get(action_mgr.scheme_type);
            // Update colors of existing elements instead of regenerating
            scene_graph.updateSceneColors(colors.text, colors.rect_red, colors.rect_green, colors.rect_yellow);
            fps_needs_update = true; // Force FPS display update with new colors
        }

        // Create text element if editing just finished with non-empty text
        if (action_mgr.text_edit.should_create_element) {
            const text = action_mgr.text_edit.finished_text_buffer[0..action_mgr.text_edit.finished_text_len];
            _ = try scene_graph.addTextLabel(
                text,
                action_mgr.text_edit.finished_world_pos,
                16.0,
                colors.text,
                .world,
                font,
            );
            action_mgr.text_edit.should_create_element = false; // Reset flag after creating element
        }

        // Update FPS counter
        frame_count += 1;
        const elapsed = c.SDL_GetTicks() - fps_timer;
        if (elapsed >= FPS_UPDATE_INTERVAL_MS) {
            current_fps = @as(f32, @floatFromInt(frame_count)) * 1000.0 / @as(f32, @floatFromInt(elapsed));
            frame_count = 0;
            fps_timer = c.SDL_GetTicks();
            fps_needs_update = true;
        }

        // Update FPS display (when counter updates or window resizes)
        if (fps_needs_update) {
            fps_needs_update = false;

            // Update FPS display element (remove old, add new)
            if (fps_element_id) |id| {
                _ = scene_graph.removeElement(id);
            }

            const fps_text = std.fmt.bufPrintZ(&fps_text_buf, "FPS: {d:.1} | Zoom: {d:.0}% | Pos: ({d:.0}, {d:.0})", .{
                current_fps,
                cam.zoom * 100,
                cam.position.x,
                cam.position.y,
            }) catch "FPS: ---";

            // Calculate text width for right-alignment
            var text_w: c_int = 0;
            _ = c.TTF_SetFontSize(font, 16);
            _ = c.TTF_SizeText(font, fps_text.ptr, &text_w, null);

            // Position in top-right corner (screen space, anchored to right edge)
            const fps_x = @as(f32, @floatFromInt(window_width - text_w - 10));
            const fps_y: f32 = 10;

            fps_element_id = try scene_graph.addTextLabel(
                fps_text,
                Vec2{ .x = fps_x, .y = fps_y },
                16.0,
                colors.text,
                .screen,
                font,
            );
        }

        // Clear screen with current color scheme background
        _ = c.SDL_SetRenderDrawColor(renderer, colors.background.r, colors.background.g, colors.background.b, colors.background.a);
        _ = c.SDL_RenderClear(renderer);

        // Render grid (if visible)
        if (action_mgr.grid_visible) {
            world_grid.render(renderer, &cam, colors.grid, colors.background);
        }

        // Render all scene elements
        scene_graph.render(renderer, font, &cam);

        // Render debug bounding boxes if enabled
        if (action_mgr.bounding_boxes_visible) {
            const debug_color = c.SDL_Color{ .r = 255, .g = 0, .b = 0, .a = 255 }; // Red
            _ = c.SDL_SetRenderDrawColor(renderer, debug_color.r, debug_color.g, debug_color.b, debug_color.a);

            for (scene_graph.elements.items) |*elem| {
                if (!elem.visible) continue;
                if (elem.space != .world) continue; // Only show world-space bounding boxes

                // Convert world-space bounding box to screen coordinates
                // In world space (Y-up): bbox.y is bottom, bbox.y + bbox.h is top
                // For SDL rendering (Y-down): we need the top-left corner
                const world_bbox = elem.bounding_box;
                const world_top_left = Vec2{ .x = world_bbox.x, .y = world_bbox.y + world_bbox.h };
                const screen_pos = cam.worldToScreen(world_top_left);
                const screen_w = world_bbox.w * cam.zoom;
                const screen_h = world_bbox.h * cam.zoom;

                const x: i32 = @intFromFloat(screen_pos.x);
                const y: i32 = @intFromFloat(screen_pos.y);
                const w: i32 = @intFromFloat(screen_w);
                const h: i32 = @intFromFloat(screen_h);

                var rect = c.SDL_Rect{ .x = x, .y = y, .w = w, .h = h };
                _ = c.SDL_RenderDrawRect(renderer, &rect);
            }
        }

        // Render selection bounding box if an element is selected
        if (action_mgr.selected_element_id) |sel_id| {
            if (scene_graph.findElement(sel_id)) |elem| {
                // Convert world-space bounding box to screen coordinates
                // In world space (Y-up): bbox.y is bottom, bbox.y + bbox.h is top
                // For SDL rendering (Y-down): we need the top-left corner
                const world_bbox = elem.bounding_box;
                const world_top_left = Vec2{ .x = world_bbox.x, .y = world_bbox.y + world_bbox.h };
                const screen_pos = cam.worldToScreen(world_top_left);

                // Calculate screen dimensions from AUTHORITATIVE bbox
                const screen_w = world_bbox.w * cam.zoom;
                const screen_h = world_bbox.h * cam.zoom;

                const selection_color = c.SDL_Color{ .r = 100, .g = 150, .b = 255, .a = 255 }; // Blue
                const white = c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 };

                const x: i32 = @intFromFloat(screen_pos.x);
                const y: i32 = @intFromFloat(screen_pos.y);
                const w: i32 = @intFromFloat(screen_w);
                const h: i32 = @intFromFloat(screen_h);

                // Draw selection box with 1px stroke
                _ = c.SDL_SetRenderDrawColor(renderer, selection_color.r, selection_color.g, selection_color.b, selection_color.a);
                var rect = c.SDL_Rect{ .x = x, .y = y, .w = w, .h = h };
                _ = c.SDL_RenderDrawRect(renderer, &rect);

                // Draw resize handles (4 corners) - white fill with blue stroke
                const handle_size: i32 = 8;
                const handle_half: i32 = handle_size / 2;

                // Top-left handle
                var handle = c.SDL_Rect{
                    .x = x - handle_half,
                    .y = y - handle_half,
                    .w = handle_size,
                    .h = handle_size,
                };
                _ = c.SDL_SetRenderDrawColor(renderer, white.r, white.g, white.b, white.a);
                _ = c.SDL_RenderFillRect(renderer, &handle);
                _ = c.SDL_SetRenderDrawColor(renderer, selection_color.r, selection_color.g, selection_color.b, selection_color.a);
                _ = c.SDL_RenderDrawRect(renderer, &handle);

                // Top-right handle
                handle.x = x + w - handle_half;
                handle.y = y - handle_half;
                _ = c.SDL_SetRenderDrawColor(renderer, white.r, white.g, white.b, white.a);
                _ = c.SDL_RenderFillRect(renderer, &handle);
                _ = c.SDL_SetRenderDrawColor(renderer, selection_color.r, selection_color.g, selection_color.b, selection_color.a);
                _ = c.SDL_RenderDrawRect(renderer, &handle);

                // Bottom-left handle
                handle.x = x - handle_half;
                handle.y = y + h - handle_half;
                _ = c.SDL_SetRenderDrawColor(renderer, white.r, white.g, white.b, white.a);
                _ = c.SDL_RenderFillRect(renderer, &handle);
                _ = c.SDL_SetRenderDrawColor(renderer, selection_color.r, selection_color.g, selection_color.b, selection_color.a);
                _ = c.SDL_RenderDrawRect(renderer, &handle);

                // Bottom-right handle
                handle.x = x + w - handle_half;
                handle.y = y + h - handle_half;
                _ = c.SDL_SetRenderDrawColor(renderer, white.r, white.g, white.b, white.a);
                _ = c.SDL_RenderFillRect(renderer, &handle);
                _ = c.SDL_SetRenderDrawColor(renderer, selection_color.r, selection_color.g, selection_color.b, selection_color.a);
                _ = c.SDL_RenderDrawRect(renderer, &handle);
            }
        }

        // Render text editing cursor if in edit mode
        if (action_mgr.text_edit.is_editing) {
            // Calculate the font size scaled by zoom (canonical size is 16pt at 100% zoom)
            const base_font_size: f32 = 16.0;
            const target_font_size = base_font_size * cam.zoom;
            const font_size_int: c_int = @intFromFloat(target_font_size);
            const line_height = target_font_size;

            // Render the text being edited (split by newlines)
            if (action_mgr.text_edit.text_len > 0) {
                const edit_text = action_mgr.text_edit.text_buffer[0..action_mgr.text_edit.text_len];
                const screen_pos = cam.worldToScreen(action_mgr.text_edit.world_pos);
                _ = c.TTF_SetFontSize(font, font_size_int);

                // Split text by newlines and render each line
                var line_y: f32 = screen_pos.y;
                var line_start: usize = 0;
                var i: usize = 0;
                while (i <= edit_text.len) : (i += 1) {
                    if (i == edit_text.len or edit_text[i] == '\n') {
                        // Render this line (if not empty)
                        if (i > line_start) {
                            const line = edit_text[line_start..i];
                            const line_z = std.fmt.bufPrintZ(&fps_text_buf, "{s}", .{line}) catch "";

                            const text_surface = c.TTF_RenderText_Blended(font, line_z.ptr, colors.text);
                            if (text_surface != null) {
                                defer c.SDL_FreeSurface(text_surface);
                                const text_texture = c.SDL_CreateTextureFromSurface(renderer, text_surface);
                                if (text_texture != null) {
                                    defer c.SDL_DestroyTexture(text_texture);

                                    // Enable linear filtering and alpha blending for smooth scaling
                                    _ = c.SDL_SetTextureScaleMode(text_texture, c.SDL_ScaleModeLinear);
                                    _ = c.SDL_SetTextureBlendMode(text_texture, c.SDL_BLENDMODE_BLEND);

                                    var dest_rect = c.SDL_Rect{
                                        .x = @intFromFloat(screen_pos.x),
                                        .y = @intFromFloat(line_y),
                                        .w = text_surface.*.w,
                                        .h = text_surface.*.h,
                                    };
                                    _ = c.SDL_RenderCopy(renderer, text_texture, null, &dest_rect);
                                }
                            }
                        }

                        // Move to next line
                        line_y += line_height;
                        line_start = i + 1;
                    }
                }
            }

            // Render blinking cursor
            const cursor_blink_rate = 500; // ms
            const time_ms = c.SDL_GetTicks();
            if ((time_ms / cursor_blink_rate) % 2 == 0) {
                const screen_pos = cam.worldToScreen(action_mgr.text_edit.world_pos);

                // Calculate cursor position - should be at end of last line
                var cursor_x = screen_pos.x;
                var cursor_y = screen_pos.y;

                if (action_mgr.text_edit.text_len > 0) {
                    const edit_text = action_mgr.text_edit.text_buffer[0..action_mgr.text_edit.text_len];

                    // Find the last line
                    var last_line_start: usize = 0;
                    var line_count: usize = 0;
                    for (edit_text, 0..) |ch, idx| {
                        if (ch == '\n') {
                            last_line_start = idx + 1;
                            line_count += 1;
                        }
                    }

                    // Measure the last line width (with zoomed font size)
                    if (last_line_start < edit_text.len) {
                        const last_line = edit_text[last_line_start..];
                        const last_line_z = std.fmt.bufPrintZ(&fps_text_buf, "{s}", .{last_line}) catch "";
                        var text_w: c_int = 0;
                        _ = c.TTF_SetFontSize(font, font_size_int);
                        _ = c.TTF_SizeText(font, last_line_z.ptr, &text_w, null);
                        cursor_x += @floatFromInt(text_w);
                    }

                    // Position cursor at the correct line
                    cursor_y += @as(f32, @floatFromInt(line_count)) * line_height;
                }

                const cursor_height: i32 = @intFromFloat(line_height);
                _ = c.SDL_SetRenderDrawColor(renderer, colors.text.r, colors.text.g, colors.text.b, colors.text.a);
                const cursor_y_int: i32 = @intFromFloat(cursor_y);
                _ = c.SDL_RenderDrawLine(
                    renderer,
                    @intFromFloat(cursor_x),
                    cursor_y_int,
                    @intFromFloat(cursor_x),
                    cursor_y_int + cursor_height,
                );
            }
        }

        // Present the frame (swap buffers)
        c.SDL_RenderPresent(renderer);

        // Frame timing - cap at target FPS if vsync isn't working
        const frame_time = c.SDL_GetTicks() - frame_start;
        if (frame_time < FRAME_TIME_MS) {
            c.SDL_Delay(FRAME_TIME_MS - frame_time);
        }
    }
}
