const std = @import("std");
const math = @import("math.zig");
const camera = @import("camera.zig");
const scene = @import("scene.zig");
const input = @import("input.zig");
const text_cache = @import("text_cache.zig");
const sdl = @import("sdl.zig");

const Vec2 = math.Vec2;
const Camera = camera.Camera;
const SceneGraph = scene.SceneGraph;
const InputState = input.InputState;
const c = sdl.c;

const WINDOW_WIDTH = 1400;
const WINDOW_HEIGHT = 900;
const TARGET_FPS = 60;
const FRAME_TIME_MS: u32 = 1000 / TARGET_FPS;
const FPS_UPDATE_INTERVAL_MS: u32 = 500;

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
    const window = c.SDL_CreateWindow(
        "Zig SDL2 GUI - Scene Graph",
        c.SDL_WINDOWPOS_CENTERED,
        c.SDL_WINDOWPOS_CENTERED,
        WINDOW_WIDTH,
        WINDOW_HEIGHT,
        c.SDL_WINDOW_SHOWN,
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

    // Enable linear filtering for better scaled text quality
    _ = c.SDL_SetHint(c.SDL_HINT_RENDER_SCALE_QUALITY, "1");

    // Load font (initial size doesn't matter much, we'll resize as needed)
    const font = c.TTF_OpenFont("assets/fonts/JetBrainsMono-Regular.ttf", 16) orelse {
        std.debug.print("Font loading failed: {s}\n", .{c.TTF_GetError()});
        return error.FontLoadFailed;
    };
    defer c.TTF_CloseFont(font);

    const white = c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 };

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

    // Initialize input state
    var input_state = InputState.init();

    // Create test text lines in world space (centered vertically around origin)
    const base_font_size: f32 = 16.0;
    const line_text = "This is a line of text.";
    const line_spacing_world: f32 = 4.0; // World-space spacing
    const border_color = c.SDL_Color{ .r = 100, .g = 150, .b = 255, .a = 255 }; // Light blue
    const border_thickness: f32 = 2.0; // World-space border thickness
    const padding: f32 = 4.0; // World-space padding around text

    // Get text dimensions at base font size for calculating rectangle size
    _ = c.TTF_SetFontSize(font, @intFromFloat(base_font_size));
    var line_text_w: c_int = 0;
    var line_text_h: c_int = 0;
    _ = c.TTF_SizeText(font, line_text, &line_text_w, &line_text_h);

    const rect_width = @as(f32, @floatFromInt(line_text_w)) + padding * 2.0;
    const rect_height = @as(f32, @floatFromInt(line_text_h)) + padding * 2.0;

    // Calculate total height needed and create lines centered around origin
    const num_lines: i32 = 40;
    const line_height_world = base_font_size + line_spacing_world;
    const total_height = @as(f32, @floatFromInt(num_lines)) * line_height_world;
    const start_y = total_height / 2.0;

    var i: i32 = 0;
    while (i < num_lines) : (i += 1) {
        const y = start_y - @as(f32, @floatFromInt(i)) * line_height_world;

        // Calculate positions for rectangle (centered around text position)
        const rect_x = -rect_width / 2.0;
        const rect_y = y - padding;

        // Add rectangle border
        _ = try scene_graph.addRectangle(
            Vec2{ .x = rect_x, .y = rect_y },
            rect_width,
            rect_height,
            border_thickness,
            border_color,
            .world,
        );

        // Add text label (offset by padding to center within rectangle)
        const text_x = -@as(f32, @floatFromInt(line_text_w)) / 2.0;
        _ = try scene_graph.addTextLabel(
            line_text,
            Vec2{ .x = text_x, .y = y },
            base_font_size,
            white,
            .world,
        );
    }

    // FPS tracking
    var frame_count: u32 = 0;
    var fps_timer: u32 = c.SDL_GetTicks();
    var current_fps: f32 = 0;
    var fps_text_buf: [64]u8 = undefined;
    var fps_element_id: ?u32 = null;

    var running = true;
    var event: c.SDL_Event = undefined;

    while (running) {
        const frame_start = c.SDL_GetTicks();

        // Handle events
        while (c.SDL_PollEvent(&event) != 0) {
            if (input_state.handleEvent(&event, &cam)) {
                running = false;
            }
        }

        // Update FPS counter
        frame_count += 1;
        const elapsed = c.SDL_GetTicks() - fps_timer;
        if (elapsed >= FPS_UPDATE_INTERVAL_MS) {
            current_fps = @as(f32, @floatFromInt(frame_count)) * 1000.0 / @as(f32, @floatFromInt(elapsed));
            frame_count = 0;
            fps_timer = c.SDL_GetTicks();

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

            // Position in top-right corner (screen space)
            const fps_x = @as(f32, @floatFromInt(WINDOW_WIDTH - text_w - 10));
            const fps_y: f32 = 10;

            fps_element_id = try scene_graph.addTextLabel(
                fps_text,
                Vec2{ .x = fps_x, .y = fps_y },
                16.0,
                white,
                .screen,
            );
        }

        // Clear screen (blank canvas - black)
        _ = c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
        _ = c.SDL_RenderClear(renderer);

        // Render all scene elements
        scene_graph.render(renderer, font, &cam);

        // Present the frame (swap buffers)
        c.SDL_RenderPresent(renderer);

        // Frame timing - cap at target FPS if vsync isn't working
        const frame_time = c.SDL_GetTicks() - frame_start;
        if (frame_time < FRAME_TIME_MS) {
            c.SDL_Delay(FRAME_TIME_MS - frame_time);
        }
    }
}
