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

    // Create instruction text at origin
    const base_font_size: f32 = 16.0;
    const instruction_text = "Double-click on a blank piece of canvas to start typing text.";

    // Get text dimensions at base font size
    _ = c.TTF_SetFontSize(font, @intFromFloat(base_font_size));
    var text_w: c_int = 0;
    var text_h: c_int = 0;
    _ = c.TTF_SizeText(font, instruction_text, &text_w, &text_h);

    // Center the text at origin
    const text_x = -@as(f32, @floatFromInt(text_w)) / 2.0;
    _ = try scene_graph.addTextLabel(
        instruction_text,
        Vec2{ .x = text_x, .y = 0 },
        base_font_size,
        colors.text,
        .world,
        font,
    );

    // Add sample text elements at various positions
    _ = try scene_graph.addTextLabel(
        "text one",
        Vec2{ .x = -150, .y = 120 },
        base_font_size,
        colors.text,
        .world,
        font,
    );

    _ = try scene_graph.addTextLabel(
        "text two",
        Vec2{ .x = 100, .y = -80 },
        base_font_size,
        colors.text,
        .world,
        font,
    );

    _ = try scene_graph.addTextLabel(
        "text three",
        Vec2{ .x = -50, .y = -200 },
        base_font_size,
        colors.text,
        .world,
        font,
    );

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
                    // Check for shift modifier
                    const mod_state = c.SDL_GetModState();
                    const shift_held = (mod_state & c.KMOD_SHIFT) != 0;

                    // Check for handle click on union bounding box (works for single or multi-select)
                    var handle_clicked = false;
                    const selected_ids_for_handles = action_mgr.selection.items();

                    if (selected_ids_for_handles.len > 0) {
                        // Calculate union bounding box of all selected elements
                        var union_min_x: f32 = std.math.floatMax(f32);
                        var union_min_y: f32 = std.math.floatMax(f32);
                        var union_max_x: f32 = -std.math.floatMax(f32);
                        var union_max_y: f32 = -std.math.floatMax(f32);

                        for (selected_ids_for_handles) |sel_id| {
                            if (scene_graph.findElement(sel_id)) |elem| {
                                const bbox = elem.bounding_box;
                                union_min_x = @min(union_min_x, bbox.x);
                                union_min_y = @min(union_min_y, bbox.y);
                                union_max_x = @max(union_max_x, bbox.x + bbox.w);
                                union_max_y = @max(union_max_y, bbox.y + bbox.h);
                            }
                        }

                        // Convert union bounds to screen space
                        const union_world_top_left = Vec2{ .x = union_min_x, .y = union_max_y };
                        const screen_pos = cam.worldToScreen(union_world_top_left);
                        const screen_w = (union_max_x - union_min_x) * cam.zoom;
                        const screen_h = (union_max_y - union_min_y) * cam.zoom;

                        const handle_hit_size: f32 = 12.0;

                        // Helper to check if point is in handle
                        const isInHandle = struct {
                            fn check(px: f32, py: f32, hx: f32, hy: f32, size: f32) bool {
                                const half = size / 2.0;
                                return px >= hx - half and px <= hx + half and
                                    py >= hy - half and py <= hy + half;
                            }
                        }.check;

                        // Test each corner handle
                        var clicked_handle: ?action.ResizeHandle = null;
                        if (isInHandle(click_x, click_y, screen_pos.x, screen_pos.y, handle_hit_size)) {
                            clicked_handle = .top_left;
                        } else if (isInHandle(click_x, click_y, screen_pos.x + screen_w, screen_pos.y, handle_hit_size)) {
                            clicked_handle = .top_right;
                        } else if (isInHandle(click_x, click_y, screen_pos.x, screen_pos.y + screen_h, handle_hit_size)) {
                            clicked_handle = .bottom_left;
                        } else if (isInHandle(click_x, click_y, screen_pos.x + screen_w, screen_pos.y + screen_h, handle_hit_size)) {
                            clicked_handle = .bottom_right;
                        }

                        if (clicked_handle) |resize_handle| {
                            // Start resize operation
                            action_mgr.resize.is_resizing = true;
                            action_mgr.resize.handle = resize_handle;
                            action_mgr.resize.start_world_pos = cam.screenToWorld(Vec2{ .x = click_x, .y = click_y });
                            action_mgr.resize.last_scale_factor = 1.0;

                            // Store union bounding box
                            action_mgr.resize.union_start_min_x = union_min_x;
                            action_mgr.resize.union_start_min_y = union_min_y;
                            action_mgr.resize.union_start_max_x = union_max_x;
                            action_mgr.resize.union_start_max_y = union_max_y;

                            // Calculate opposite corner of union bbox
                            switch (resize_handle) {
                                .top_left => {
                                    action_mgr.resize.opposite_corner = Vec2{ .x = union_max_x, .y = union_min_y };
                                },
                                .top_right => {
                                    action_mgr.resize.opposite_corner = Vec2{ .x = union_min_x, .y = union_min_y };
                                },
                                .bottom_left => {
                                    action_mgr.resize.opposite_corner = Vec2{ .x = union_max_x, .y = union_max_y };
                                },
                                .bottom_right => {
                                    action_mgr.resize.opposite_corner = Vec2{ .x = union_min_x, .y = union_max_y };
                                },
                            }

                            // Store per-element start states
                            action_mgr.resize.element_count = 0;
                            for (selected_ids_for_handles) |sel_id| {
                                if (scene_graph.findElement(sel_id)) |elem| {
                                    if (action_mgr.resize.element_count < action_handler.MAX_RESIZE_ELEMENTS) {
                                        var state = &action_mgr.resize.element_states[action_mgr.resize.element_count];
                                        state.element_id = sel_id;
                                        state.start_pos = elem.transform.position;
                                        state.start_bbox_x = elem.bounding_box.x;
                                        state.start_bbox_y = elem.bounding_box.y;
                                        state.start_bbox_w = elem.bounding_box.w;
                                        state.start_bbox_h = elem.bounding_box.h;
                                        if (elem.element_type == .text_label) {
                                            state.start_font_size = elem.data.text_label.font_size;
                                        } else if (elem.element_type == .rectangle) {
                                            state.start_rect_width = elem.data.rectangle.width;
                                            state.start_rect_height = elem.data.rectangle.height;
                                        }
                                        action_mgr.resize.element_count += 1;
                                    }
                                }
                            }

                            // Legacy single-element fields for compatibility
                            if (selected_ids_for_handles.len == 1) {
                                if (scene_graph.findElement(selected_ids_for_handles[0])) |elem| {
                                    action_mgr.resize.element_id = selected_ids_for_handles[0];
                                    action_mgr.resize.element_start_pos = elem.transform.position;
                                    action_mgr.resize.element_start_scale = elem.transform.scale;
                                    action_mgr.resize.start_bbox_width = elem.bounding_box.w;
                                    action_mgr.resize.start_bbox_height = elem.bounding_box.h;
                                    if (elem.element_type == .text_label) {
                                        action_mgr.resize.element_start_font_size = elem.data.text_label.font_size;
                                    }
                                }
                            }

                            handle_clicked = true;
                        } else {
                            // Not on handle, check if clicking within the union bounding box
                            const world_pos = cam.screenToWorld(Vec2{ .x = click_x, .y = click_y });

                            // Calculate union bounding box in world space
                            var drag_union_min_x: f32 = std.math.floatMax(f32);
                            var drag_union_min_y: f32 = std.math.floatMax(f32);
                            var drag_union_max_x: f32 = -std.math.floatMax(f32);
                            var drag_union_max_y: f32 = -std.math.floatMax(f32);

                            for (selected_ids_for_handles) |sel_id| {
                                if (scene_graph.findElement(sel_id)) |elem| {
                                    const bbox = elem.bounding_box;
                                    drag_union_min_x = @min(drag_union_min_x, bbox.x);
                                    drag_union_min_y = @min(drag_union_min_y, bbox.y);
                                    drag_union_max_x = @max(drag_union_max_x, bbox.x + bbox.w);
                                    drag_union_max_y = @max(drag_union_max_y, bbox.y + bbox.h);
                                }
                            }

                            // Check if click is within union bounding box
                            if (world_pos.x >= drag_union_min_x and world_pos.x <= drag_union_max_x and
                                world_pos.y >= drag_union_min_y and world_pos.y <= drag_union_max_y)
                            {
                                if (shift_held) {
                                    // Shift+click within selection: toggle the clicked element
                                    if (scene_graph.hitTest(click_x, click_y, &cam)) |hit_id| {
                                        _ = action_mgr.handle(action.ActionParams{ .select_element = action.SelectParams{
                                            .element_id = hit_id,
                                            .toggle = true,
                                        } }, &cam);
                                    }
                                    handle_clicked = true;
                                } else {
                                    // Normal click: start dragging all selected elements
                                    const alt_held = (mod_state & c.KMOD_ALT) != 0;
                                    action_mgr.drag.is_dragging = true;
                                    action_mgr.drag.start_world_pos = world_pos;
                                    action_mgr.drag.alt_held = alt_held;
                                    action_mgr.drag.has_moved = false;
                                    action_mgr.drag.cloned = false;

                                    // Store all element start positions
                                    action_mgr.drag.element_count = 0;
                                    for (selected_ids_for_handles) |sel_id| {
                                        if (scene_graph.findElement(sel_id)) |elem| {
                                            if (action_mgr.drag.element_count < action_handler.MAX_DRAG_ELEMENTS) {
                                                var state = &action_mgr.drag.element_states[action_mgr.drag.element_count];
                                                state.element_id = sel_id;
                                                state.start_pos = elem.transform.position;
                                                state.start_bbox_x = elem.bounding_box.x;
                                                state.start_bbox_y = elem.bounding_box.y;
                                                action_mgr.drag.element_count += 1;
                                            }
                                        }
                                    }

                                    handle_clicked = true;
                                }
                            }
                        }
                    }

                    // If no handle was clicked, do normal hit test
                    if (!handle_clicked) {
                        if (scene_graph.hitTest(click_x, click_y, &cam)) |hit_id| {
                            // Element was clicked - select it (with toggle if shift held)
                            _ = action_mgr.handle(action.ActionParams{ .select_element = action.SelectParams{
                                .element_id = hit_id,
                                .toggle = shift_held,
                            } }, &cam);

                            // Only start dragging if not shift+clicking (shift is for selection only)
                            if (!shift_held) {
                                const alt_held = (mod_state & c.KMOD_ALT) != 0;
                                const world_pos = cam.screenToWorld(Vec2{ .x = click_x, .y = click_y });
                                action_mgr.drag.is_dragging = true;
                                action_mgr.drag.start_world_pos = world_pos;
                                action_mgr.drag.alt_held = alt_held;
                                action_mgr.drag.has_moved = false;
                                action_mgr.drag.cloned = false;

                                // Store the clicked element's position for dragging
                                action_mgr.drag.element_count = 0;
                                if (scene_graph.findElement(hit_id)) |elem| {
                                    var state = &action_mgr.drag.element_states[0];
                                    state.element_id = hit_id;
                                    state.start_pos = elem.transform.position;
                                    state.start_bbox_x = elem.bounding_box.x;
                                    state.start_bbox_y = elem.bounding_box.y;
                                    action_mgr.drag.element_count = 1;
                                }
                            }
                        } else {
                            // Empty space clicked - start drag-select
                            const world_pos = cam.screenToWorld(Vec2{ .x = click_x, .y = click_y });
                            action_mgr.drag_select.is_active = true;
                            action_mgr.drag_select.start_world = world_pos;
                            action_mgr.drag_select.current_world = world_pos;

                            // Clear selection unless shift is held (shift preserves existing selection)
                            if (!shift_held) {
                                action_mgr.selection.clear();
                            }
                        }
                    }
                }
            }

            // Handle mouse motion for dragging/resizing
            if (event.type == c.SDL_MOUSEMOTION) {
                const mouse_x = @as(f32, @floatFromInt(event.motion.x));
                const mouse_y = @as(f32, @floatFromInt(event.motion.y));

                if (action_mgr.drag.is_dragging) {
                    // Calculate drag delta in world space
                    const current_world = cam.screenToWorld(Vec2{ .x = mouse_x, .y = mouse_y });
                    const delta = Vec2{
                        .x = current_world.x - action_mgr.drag.start_world_pos.x,
                        .y = current_world.y - action_mgr.drag.start_world_pos.y,
                    };

                    // Check if this is actual movement (not just Alt+click)
                    const has_actual_movement = @abs(delta.x) > 0.1 or @abs(delta.y) > 0.1;

                    // Alt+drag clone: clone elements on first actual movement
                    if (action_mgr.drag.alt_held and !action_mgr.drag.cloned and has_actual_movement) {
                        action_mgr.drag.cloned = true;
                        action_mgr.drag.has_moved = true;

                        // Clone all dragged elements and update drag state to track clones
                        var new_count: usize = 0;
                        for (action_mgr.drag.element_states[0..action_mgr.drag.element_count]) |*elem_state| {
                            if (scene_graph.cloneElement(elem_state.element_id)) |maybe_new_id| {
                                if (maybe_new_id) |new_id| {
                                    // Update selection: remove original, add clone
                                    action_mgr.selection.remove(elem_state.element_id);
                                    action_mgr.selection.add(new_id);

                                    // Update drag state to track the clone instead
                                    if (scene_graph.findElement(new_id)) |new_elem| {
                                        elem_state.element_id = new_id;
                                        elem_state.start_pos = new_elem.transform.position;
                                        elem_state.start_bbox_x = new_elem.bounding_box.x;
                                        elem_state.start_bbox_y = new_elem.bounding_box.y;
                                        new_count += 1;
                                    }
                                }
                            } else |_| {
                                // Clone failed, keep original
                                new_count += 1;
                            }
                        }
                    }

                    if (has_actual_movement) {
                        action_mgr.drag.has_moved = true;
                    }

                    // Move all selected elements by the same delta (rigid body movement)
                    for (action_mgr.drag.element_states[0..action_mgr.drag.element_count]) |elem_state| {
                        if (scene_graph.findElement(elem_state.element_id)) |elem| {
                            elem.transform.position = Vec2{
                                .x = elem_state.start_pos.x + delta.x,
                                .y = elem_state.start_pos.y + delta.y,
                            };
                            // Update bbox position (dimensions stay the same - authoritative!)
                            elem.bounding_box.x = elem_state.start_bbox_x + delta.x;
                            elem.bounding_box.y = elem_state.start_bbox_y + delta.y;
                        }
                    }
                } else if (action_mgr.resize.is_resizing) {
                    // Multi-select resize with opposite corner as anchor
                    const handle_world = cam.screenToWorld(Vec2{ .x = mouse_x, .y = mouse_y });

                    // Calculate new union bbox dimensions from handle to opposite corner
                    const orig_union_w = action_mgr.resize.union_start_max_x - action_mgr.resize.union_start_min_x;
                    const orig_union_h = action_mgr.resize.union_start_max_y - action_mgr.resize.union_start_min_y;

                    const new_width = @abs(handle_world.x - action_mgr.resize.opposite_corner.x);
                    const new_height = @abs(handle_world.y - action_mgr.resize.opposite_corner.y);

                    // Calculate independent scale factors for width and height
                    var width_scale = if (orig_union_w > 0.001) new_width / orig_union_w else 1.0;
                    var height_scale = if (orig_union_h > 0.001) new_height / orig_union_h else 1.0;

                    // Clamp scales to reasonable range
                    width_scale = @max(0.1, @min(10.0, width_scale));
                    height_scale = @max(0.1, @min(10.0, height_scale));

                    // Uniform scale (maintains aspect ratio)
                    var uniform_scale = @max(width_scale, height_scale);

                    // Add hysteresis to uniform scale to prevent oscillation
                    const scale_change = @abs(uniform_scale - action_mgr.resize.last_scale_factor);
                    const min_scale_change = 0.005 * action_mgr.resize.last_scale_factor;
                    if (scale_change < min_scale_change) {
                        uniform_scale = action_mgr.resize.last_scale_factor;
                    } else {
                        action_mgr.resize.last_scale_factor = uniform_scale;
                    }

                    // Check if ANY element in the selection requires uniform scaling.
                    // If so, the entire selection must scale uniformly to preserve relative positions.
                    var selection_requires_uniform = false;
                    for (action_mgr.resize.element_states[0..action_mgr.resize.element_count]) |elem_state| {
                        if (scene_graph.findElement(elem_state.element_id)) |elem| {
                            if (!elem.element_type.canScaleNonUniform()) {
                                selection_requires_uniform = true;
                                break;
                            }
                        }
                    }

                    // Apply resize to all elements in the selection
                    for (action_mgr.resize.element_states[0..action_mgr.resize.element_count]) |elem_state| {
                        if (scene_graph.findElement(elem_state.element_id)) |elem| {
                            // Use uniform scaling if ANY element in selection requires it,
                            // otherwise allow non-uniform scaling for element types that support it
                            const use_uniform = selection_requires_uniform or !elem.element_type.canScaleNonUniform();
                            const sx = if (use_uniform) uniform_scale else width_scale;
                            const sy = if (use_uniform) uniform_scale else height_scale;

                            // Scale element's bbox dimensions
                            const new_bbox_w = elem_state.start_bbox_w * sx;
                            const new_bbox_h = elem_state.start_bbox_h * sy;

                            // Calculate element's position relative to opposite corner at start
                            // bbox.x is left edge, bbox.y is bottom edge (world Y-up)
                            const start_left_offset = elem_state.start_bbox_x - action_mgr.resize.opposite_corner.x;
                            const start_bottom_offset = elem_state.start_bbox_y - action_mgr.resize.opposite_corner.y;

                            // Scale the offsets (x uses width_scale, y uses height_scale for non-uniform)
                            const new_left_offset = start_left_offset * sx;
                            const new_bottom_offset = start_bottom_offset * sy;

                            // Calculate new bbox position
                            const new_bbox_x = action_mgr.resize.opposite_corner.x + new_left_offset;
                            const new_bbox_y = action_mgr.resize.opposite_corner.y + new_bottom_offset;

                            // Update bbox
                            elem.bounding_box.x = new_bbox_x;
                            elem.bounding_box.y = new_bbox_y;
                            elem.bounding_box.w = new_bbox_w;
                            elem.bounding_box.h = new_bbox_h;

                            // Update transform position (top-left in world Y-up = x, y + h)
                            elem.transform.position = Vec2{
                                .x = new_bbox_x,
                                .y = new_bbox_y + new_bbox_h,
                            };

                            // Update element-specific properties for proper re-rendering
                            if (elem.element_type == .rectangle) {
                                // Update rectangle's actual width/height (non-uniform scaling)
                                elem.data.rectangle.width = elem_state.start_rect_width * sx;
                                elem.data.rectangle.height = elem_state.start_rect_height * sy;
                            } else if (elem.element_type == .text_label) {
                                // Text uses uniform scale to maintain aspect ratio
                                elem.data.text_label.font_size = elem_state.start_font_size * uniform_scale;
                            }
                        }
                    }
                } else if (action_mgr.drag_select.is_active) {
                    // Update drag-select rectangle and selection
                    const current_world = cam.screenToWorld(Vec2{ .x = mouse_x, .y = mouse_y });
                    action_mgr.drag_select.current_world = current_world;

                    // Get normalized bounds of the drag-select rectangle
                    const bounds = action_mgr.drag_select.getBounds();

                    // Update selection: add elements fully within rectangle, remove those that aren't
                    for (scene_graph.elements.items) |*elem| {
                        if (!elem.visible) continue;
                        if (elem.space != .world) continue; // Only select world-space elements

                        const is_within = elem.bounding_box.isFullyWithin(
                            bounds.min_x,
                            bounds.min_y,
                            bounds.max_x,
                            bounds.max_y,
                        );

                        if (is_within) {
                            action_mgr.selection.add(elem.id);
                        } else {
                            action_mgr.selection.remove(elem.id);
                        }
                    }
                }
            }

            // Handle mouse button up to end drag/resize/drag-select
            if (event.type == c.SDL_MOUSEBUTTONUP and event.button.button == c.SDL_BUTTON_LEFT) {
                if (action_mgr.drag.is_dragging) {
                    _ = action_mgr.handle(action.ActionParams{ .end_drag_element = {} }, &cam);
                } else if (action_mgr.resize.is_resizing) {
                    _ = action_mgr.handle(action.ActionParams{ .end_resize_element = {} }, &cam);
                } else if (action_mgr.drag_select.is_active) {
                    action_mgr.drag_select.is_active = false;
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

        // Render drag-select rectangle (after grid, before elements)
        if (action_mgr.drag_select.is_active) {
            const bounds = action_mgr.drag_select.getBounds();

            // Convert world bounds to screen coordinates
            const world_top_left = Vec2{ .x = bounds.min_x, .y = bounds.max_y };
            const screen_pos = cam.worldToScreen(world_top_left);
            const screen_w = (bounds.max_x - bounds.min_x) * cam.zoom;
            const screen_h = (bounds.max_y - bounds.min_y) * cam.zoom;

            const x: i32 = @intFromFloat(screen_pos.x);
            const y: i32 = @intFromFloat(screen_pos.y);
            const w: i32 = @intFromFloat(screen_w);
            const h: i32 = @intFromFloat(screen_h);

            // Draw filled rectangle (semi-transparent)
            _ = c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_BLEND);
            _ = c.SDL_SetRenderDrawColor(
                renderer,
                colors.selection_fill.r,
                colors.selection_fill.g,
                colors.selection_fill.b,
                colors.selection_fill.a,
            );
            const fill_rect = c.SDL_Rect{ .x = x, .y = y, .w = w, .h = h };
            _ = c.SDL_RenderFillRect(renderer, &fill_rect);

            // Draw border (solid, using selection border color)
            _ = c.SDL_SetRenderDrawColor(
                renderer,
                colors.border.r,
                colors.border.g,
                colors.border.b,
                colors.border.a,
            );
            _ = c.SDL_RenderDrawRect(renderer, &fill_rect);
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

        // Render selection bounding boxes for all selected elements
        const selected_ids = action_mgr.selection.items();
        const selection_color = c.SDL_Color{ .r = 100, .g = 150, .b = 255, .a = 255 }; // Blue
        const white = c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 };

        if (selected_ids.len > 0) {
            // Calculate union bounding box in SCREEN space to avoid floating-point discrepancies
            // This ensures the union edges exactly match individual element edges
            var union_screen_min_x: i32 = std.math.maxInt(i32);
            var union_screen_min_y: i32 = std.math.maxInt(i32);
            var union_screen_max_x: i32 = std.math.minInt(i32);
            var union_screen_max_y: i32 = std.math.minInt(i32);

            // First pass: calculate union in screen space and draw individual solid boxes
            for (selected_ids) |sel_id| {
                if (scene_graph.findElement(sel_id)) |elem| {
                    const world_bbox = elem.bounding_box;

                    // Draw solid selection box around each element
                    const world_top_left = Vec2{ .x = world_bbox.x, .y = world_bbox.y + world_bbox.h };
                    const screen_pos = cam.worldToScreen(world_top_left);
                    const screen_w = world_bbox.w * cam.zoom;
                    const screen_h = world_bbox.h * cam.zoom;

                    const x: i32 = @intFromFloat(screen_pos.x);
                    const y: i32 = @intFromFloat(screen_pos.y);
                    const w: i32 = @intFromFloat(screen_w);
                    const h: i32 = @intFromFloat(screen_h);

                    // Update union bounds in screen space (using exact same integers as drawing)
                    union_screen_min_x = @min(union_screen_min_x, x);
                    union_screen_min_y = @min(union_screen_min_y, y);
                    union_screen_max_x = @max(union_screen_max_x, x + w);
                    union_screen_max_y = @max(union_screen_max_y, y + h);

                    _ = c.SDL_SetRenderDrawColor(renderer, selection_color.r, selection_color.g, selection_color.b, selection_color.a);
                    var rect = c.SDL_Rect{ .x = x, .y = y, .w = w, .h = h };
                    _ = c.SDL_RenderDrawRect(renderer, &rect);
                }
            }

            // Union screen rectangle
            const ux = union_screen_min_x;
            const uy = union_screen_min_y;
            const uw = union_screen_max_x - union_screen_min_x;
            const uh = union_screen_max_y - union_screen_min_y;

            // Draw dotted rectangle around union bounds (for multi-select) or solid (for single)
            _ = c.SDL_SetRenderDrawColor(renderer, selection_color.r, selection_color.g, selection_color.b, selection_color.a);

            if (selected_ids.len > 1) {
                // Draw dotted lines for multi-select union box
                const dash_len: i32 = 6;
                const gap_len: i32 = 4;

                // Helper to draw dashed horizontal line
                const drawDashedHLine = struct {
                    fn draw(rend: *c.SDL_Renderer, x1: i32, x2: i32, y_pos: i32, dash: i32, gap: i32) void {
                        var cx = x1;
                        while (cx < x2) {
                            const end_x = @min(cx + dash, x2);
                            _ = c.SDL_RenderDrawLine(rend, cx, y_pos, end_x, y_pos);
                            cx += dash + gap;
                        }
                    }
                }.draw;

                // Helper to draw dashed vertical line
                const drawDashedVLine = struct {
                    fn draw(rend: *c.SDL_Renderer, x_pos: i32, y1: i32, y2: i32, dash: i32, gap: i32) void {
                        var cy = y1;
                        while (cy < y2) {
                            const end_y = @min(cy + dash, y2);
                            _ = c.SDL_RenderDrawLine(rend, x_pos, cy, x_pos, end_y);
                            cy += dash + gap;
                        }
                    }
                }.draw;

                // Top edge
                drawDashedHLine(renderer, ux, ux + uw - 1, uy, dash_len, gap_len);
                // Bottom edge (SDL_RenderDrawRect draws bottom at y+h-1, not y+h)
                drawDashedHLine(renderer, ux, ux + uw - 1, uy + uh - 1, dash_len, gap_len);
                // Left edge
                drawDashedVLine(renderer, ux, uy, uy + uh - 1, dash_len, gap_len);
                // Right edge (SDL_RenderDrawRect draws right at x+w-1, not x+w)
                drawDashedVLine(renderer, ux + uw - 1, uy, uy + uh - 1, dash_len, gap_len);
            }

            // Draw resize handles on the union bounding box
            const handle_size: i32 = 8;
            const handle_half: i32 = handle_size / 2;

            // Top-left handle
            var handle = c.SDL_Rect{
                .x = ux - handle_half,
                .y = uy - handle_half,
                .w = handle_size,
                .h = handle_size,
            };
            _ = c.SDL_SetRenderDrawColor(renderer, white.r, white.g, white.b, white.a);
            _ = c.SDL_RenderFillRect(renderer, &handle);
            _ = c.SDL_SetRenderDrawColor(renderer, selection_color.r, selection_color.g, selection_color.b, selection_color.a);
            _ = c.SDL_RenderDrawRect(renderer, &handle);

            // Top-right handle
            handle.x = ux + uw - handle_half;
            handle.y = uy - handle_half;
            _ = c.SDL_SetRenderDrawColor(renderer, white.r, white.g, white.b, white.a);
            _ = c.SDL_RenderFillRect(renderer, &handle);
            _ = c.SDL_SetRenderDrawColor(renderer, selection_color.r, selection_color.g, selection_color.b, selection_color.a);
            _ = c.SDL_RenderDrawRect(renderer, &handle);

            // Bottom-left handle
            handle.x = ux - handle_half;
            handle.y = uy + uh - handle_half;
            _ = c.SDL_SetRenderDrawColor(renderer, white.r, white.g, white.b, white.a);
            _ = c.SDL_RenderFillRect(renderer, &handle);
            _ = c.SDL_SetRenderDrawColor(renderer, selection_color.r, selection_color.g, selection_color.b, selection_color.a);
            _ = c.SDL_RenderDrawRect(renderer, &handle);

            // Bottom-right handle
            handle.x = ux + uw - handle_half;
            handle.y = uy + uh - handle_half;
            _ = c.SDL_SetRenderDrawColor(renderer, white.r, white.g, white.b, white.a);
            _ = c.SDL_RenderFillRect(renderer, &handle);
            _ = c.SDL_SetRenderDrawColor(renderer, selection_color.r, selection_color.g, selection_color.b, selection_color.a);
            _ = c.SDL_RenderDrawRect(renderer, &handle);
        }

        // Render text editing cursor if in edit mode
        if (action_mgr.text_edit.is_editing) {
            // Calculate the font size scaled by zoom (canonical size is 16pt at 100% zoom)
            const base_font_size: f32 = 16.0;
            const target_font_size = base_font_size * cam.zoom;
            const font_size_int: c_int = @intFromFloat(target_font_size);

            // Line spacing is slightly larger than font size for better readability
            // and to give room for the cursor to extend above/below the text
            const line_spacing = target_font_size * scene.LINE_SPACING_MULTIPLIER;

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
                        line_y += line_spacing;
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
                    cursor_y += @as(f32, @floatFromInt(line_count)) * line_spacing;
                }

                // Cursor spans the full line spacing, centered on the text.
                // This makes it visible above the mouse cursor without overlapping adjacent lines.
                const extra_spacing = line_spacing - target_font_size;
                const cursor_height: i32 = @intFromFloat(line_spacing);
                _ = c.SDL_SetRenderDrawColor(renderer, colors.text.r, colors.text.g, colors.text.b, colors.text.a);
                const cursor_y_int: i32 = @as(i32, @intFromFloat(cursor_y - extra_spacing / 2));
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
