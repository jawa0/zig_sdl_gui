const std = @import("std");
const math = @import("math.zig");
const camera = @import("camera.zig");
const text_cache = @import("text_cache.zig");
const sdl = @import("sdl.zig");

const Vec2 = math.Vec2;
const Transform = math.Transform;
const Camera = camera.Camera;
const TextCache = text_cache.TextCache;
const c = sdl.c;

pub const ElementType = enum {
    text_label,
    // Future: rectangle, circle, image, etc.
};

pub const CoordinateSpace = enum {
    world, // Affected by camera pan/zoom
    screen, // Fixed on screen (UI elements)
};

pub const TextLabel = struct {
    text: []const u8,
    font_size: f32,
    color: c.SDL_Color,
    cache: TextCache,

    pub fn init(allocator: std.mem.Allocator, text: []const u8, font_size: f32, color: c.SDL_Color) !TextLabel {
        const text_copy = try allocator.dupe(u8, text);
        return TextLabel{
            .text = text_copy,
            .font_size = font_size,
            .color = color,
            .cache = TextCache{},
        };
    }

    pub fn deinit(self: *TextLabel, allocator: std.mem.Allocator) void {
        self.cache.deinit();
        allocator.free(self.text);
    }
};

pub const Element = struct {
    id: u32,
    transform: Transform,
    space: CoordinateSpace,
    visible: bool,
    element_type: ElementType,
    data: union {
        text_label: TextLabel,
    },

    pub fn deinit(self: *Element, allocator: std.mem.Allocator) void {
        switch (self.element_type) {
            .text_label => self.data.text_label.deinit(allocator),
        }
    }
};

pub const SceneGraph = struct {
    elements: std.ArrayList(Element),
    next_id: u32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SceneGraph {
        return SceneGraph{
            .elements = std.ArrayList(Element){},
            .next_id = 1,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SceneGraph) void {
        for (self.elements.items) |*elem| {
            elem.deinit(self.allocator);
        }
        self.elements.deinit(self.allocator);
    }

    pub fn addTextLabel(
        self: *SceneGraph,
        text: []const u8,
        position: Vec2,
        font_size: f32,
        color: c.SDL_Color,
        space: CoordinateSpace,
    ) !u32 {
        const id = self.next_id;
        self.next_id += 1;

        const label = try TextLabel.init(self.allocator, text, font_size, color);

        const element = Element{
            .id = id,
            .transform = Transform{
                .position = position,
                .rotation = 0,
                .scale = Vec2{ .x = 1, .y = 1 },
            },
            .space = space,
            .visible = true,
            .element_type = .text_label,
            .data = .{ .text_label = label },
        };

        try self.elements.append(self.allocator, element);
        return id;
    }

    pub fn removeElement(self: *SceneGraph, id: u32) bool {
        for (self.elements.items, 0..) |*elem, i| {
            if (elem.id == id) {
                elem.deinit(self.allocator);
                _ = self.elements.swapRemove(i);
                return true;
            }
        }
        return false;
    }

    pub fn findElement(self: *SceneGraph, id: u32) ?*Element {
        for (self.elements.items) |*elem| {
            if (elem.id == id) {
                return elem;
            }
        }
        return null;
    }

    pub fn render(self: *SceneGraph, renderer: *c.SDL_Renderer, font: *c.TTF_Font, cam: *const Camera) void {
        for (self.elements.items) |*elem| {
            if (!elem.visible) continue;

            switch (elem.element_type) {
                .text_label => {
                    var label = &elem.data.text_label;

                    // Determine position based on coordinate space
                    const screen_pos = switch (elem.space) {
                        .world => blk: {
                            // Transform world position to screen
                            const world_pos = elem.transform.position;
                            break :blk cam.worldToScreen(world_pos);
                        },
                        .screen => blk: {
                            // Already in screen space
                            break :blk elem.transform.position;
                        },
                    };

                    // Determine font size based on coordinate space
                    const target_font_size = switch (elem.space) {
                        .world => label.font_size * cam.zoom,
                        .screen => label.font_size,
                    };

                    // Convert position to integers for SDL
                    const x: i32 = @intFromFloat(screen_pos.x);
                    const y: i32 = @intFromFloat(screen_pos.y);

                    // Ensure text is null-terminated
                    var text_buf: [256]u8 = undefined;
                    const null_term_text = std.fmt.bufPrintZ(&text_buf, "{s}", .{label.text}) catch continue;

                    // Draw the text using the cache
                    _ = label.cache.draw(
                        renderer,
                        font,
                        null_term_text.ptr,
                        x,
                        y,
                        target_font_size,
                        label.color,
                    );
                },
            }
        }
    }
};
