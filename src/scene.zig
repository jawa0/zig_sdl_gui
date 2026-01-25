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

/// Dimensions returned by drawing functions
pub const DrawDimensions = struct {
    w: i32,
    h: i32,
};

pub const ElementType = enum {
    text_label,
    rectangle,
    // Future: circle, image, etc.
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

pub const Rectangle = struct {
    width: f32,
    height: f32,
    border_thickness: f32,
    color: c.SDL_Color,

    pub fn init(width: f32, height: f32, border_thickness: f32, color: c.SDL_Color) Rectangle {
        return Rectangle{
            .width = width,
            .height = height,
            .border_thickness = border_thickness,
            .color = color,
        };
    }
};

// ============================================================================
// Standalone Drawing Functions
// ============================================================================

/// Draw a rectangle outline at the specified screen position with given dimensions.
/// This is a low-level drawing function that can be called independently of the scene graph.
pub fn drawRectangleOutline(
    renderer: *c.SDL_Renderer,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    border_thickness: i32,
    color: c.SDL_Color,
) void {
    // Set draw color
    _ = c.SDL_SetRenderDrawColor(
        renderer,
        color.r,
        color.g,
        color.b,
        color.a,
    );

    // Draw multiple rectangles to achieve border thickness
    const thickness = @max(1, border_thickness);
    var i: i32 = 0;
    while (i < thickness) : (i += 1) {
        var sdl_rect = c.SDL_Rect{
            .x = x + i,
            .y = y + i,
            .w = width - i * 2,
            .h = height - i * 2,
        };
        _ = c.SDL_RenderDrawRect(renderer, &sdl_rect);
    }
}

/// Draw text using a cache at the specified screen position with given font size.
/// This is a low-level drawing function that can be called independently of the scene graph.
/// Returns the displayed dimensions if successful.
pub fn drawTextCached(
    cache: *TextCache,
    renderer: *c.SDL_Renderer,
    font: *c.TTF_Font,
    text: [*:0]const u8,
    x: i32,
    y: i32,
    font_size: f32,
    color: c.SDL_Color,
) ?DrawDimensions {
    const dims = cache.draw(renderer, font, text, x, y, font_size, color) orelse return null;
    return DrawDimensions{ .w = dims.w, .h = dims.h };
}

pub const Element = struct {
    id: u32,
    transform: Transform,
    space: CoordinateSpace,
    visible: bool,
    element_type: ElementType,
    data: union {
        text_label: TextLabel,
        rectangle: Rectangle,
    },

    pub fn deinit(self: *Element, allocator: std.mem.Allocator) void {
        switch (self.element_type) {
            .text_label => self.data.text_label.deinit(allocator),
            .rectangle => {}, // No cleanup needed for rectangles
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

    pub fn addRectangle(
        self: *SceneGraph,
        position: Vec2,
        width: f32,
        height: f32,
        border_thickness: f32,
        color: c.SDL_Color,
        space: CoordinateSpace,
    ) !u32 {
        const id = self.next_id;
        self.next_id += 1;

        const rect = Rectangle.init(width, height, border_thickness, color);

        const element = Element{
            .id = id,
            .transform = Transform{
                .position = position,
                .rotation = 0,
                .scale = Vec2{ .x = 1, .y = 1 },
            },
            .space = space,
            .visible = true,
            .element_type = .rectangle,
            .data = .{ .rectangle = rect },
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

    /// Clear all world-space elements, preserving screen-space elements
    pub fn clearWorld(self: *SceneGraph) void {
        var i: usize = 0;
        while (i < self.elements.items.len) {
            if (self.elements.items[i].space == .world) {
                self.elements.items[i].deinit(self.allocator);
                _ = self.elements.swapRemove(i);
                // Don't increment i since swapRemove fills this slot with the last element
            } else {
                i += 1;
            }
        }
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

                    // Draw the text using the standalone drawing function
                    _ = drawTextCached(
                        &label.cache,
                        renderer,
                        font,
                        null_term_text.ptr,
                        x,
                        y,
                        target_font_size,
                        label.color,
                    );
                },
                .rectangle => {
                    const rect = &elem.data.rectangle;

                    // Determine position based on coordinate space
                    const screen_pos = switch (elem.space) {
                        .world => blk: {
                            const world_pos = elem.transform.position;
                            break :blk cam.worldToScreen(world_pos);
                        },
                        .screen => blk: {
                            break :blk elem.transform.position;
                        },
                    };

                    // Determine size based on coordinate space (apply zoom to world-space elements)
                    const screen_width = switch (elem.space) {
                        .world => rect.width * cam.zoom,
                        .screen => rect.width,
                    };
                    const screen_height = switch (elem.space) {
                        .world => rect.height * cam.zoom,
                        .screen => rect.height,
                    };
                    const screen_thickness = switch (elem.space) {
                        .world => rect.border_thickness * cam.zoom,
                        .screen => rect.border_thickness,
                    };

                    // Convert to integers for SDL
                    const x: i32 = @intFromFloat(screen_pos.x);
                    const y: i32 = @intFromFloat(screen_pos.y);
                    const w: i32 = @intFromFloat(screen_width);
                    const h: i32 = @intFromFloat(screen_height);
                    const thickness: i32 = @intFromFloat(@max(1.0, screen_thickness));

                    // Draw using the standalone drawing function
                    drawRectangleOutline(renderer, x, y, w, h, thickness, rect.color);
                },
            }
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;
const expectEqual = testing.expectEqual;
const expect = testing.expect;

test "SceneGraph.init and deinit" {
    var scene = SceneGraph.init(testing.allocator);
    defer scene.deinit();

    try expectEqual(1, scene.next_id);
    try expectEqual(0, scene.elements.items.len);
}

test "SceneGraph.addTextLabel returns unique IDs" {
    var scene = SceneGraph.init(testing.allocator);
    defer scene.deinit();

    const white = c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 };

    const id1 = try scene.addTextLabel("Test 1", Vec2{ .x = 0, .y = 0 }, 16, white, .world);
    const id2 = try scene.addTextLabel("Test 2", Vec2{ .x = 10, .y = 10 }, 20, white, .screen);

    try expectEqual(1, id1);
    try expectEqual(2, id2);
    try expectEqual(2, scene.elements.items.len);
}

test "SceneGraph.addTextLabel stores correct data" {
    var scene = SceneGraph.init(testing.allocator);
    defer scene.deinit();

    const white = c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
    const id = try scene.addTextLabel("Hello", Vec2{ .x = 100, .y = 200 }, 24, white, .world);

    const elem = scene.findElement(id).?;

    try expectEqual(id, elem.id);
    try expectEqual(100, elem.transform.position.x);
    try expectEqual(200, elem.transform.position.y);
    try expectEqual(0, elem.transform.rotation);
    try expectEqual(1, elem.transform.scale.x);
    try expectEqual(1, elem.transform.scale.y);
    try expectEqual(CoordinateSpace.world, elem.space);
    try expect(elem.visible);
    try expectEqual(ElementType.text_label, elem.element_type);
    try expectEqual(24, elem.data.text_label.font_size);
    try expect(std.mem.eql(u8, "Hello", elem.data.text_label.text));
}

test "SceneGraph.findElement returns correct element" {
    var scene = SceneGraph.init(testing.allocator);
    defer scene.deinit();

    const white = c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 };

    const id1 = try scene.addTextLabel("First", Vec2{ .x = 0, .y = 0 }, 16, white, .world);
    const id2 = try scene.addTextLabel("Second", Vec2{ .x = 10, .y = 10 }, 20, white, .screen);

    const elem1 = scene.findElement(id1).?;
    const elem2 = scene.findElement(id2).?;

    try expect(std.mem.eql(u8, "First", elem1.data.text_label.text));
    try expect(std.mem.eql(u8, "Second", elem2.data.text_label.text));
}

test "SceneGraph.findElement returns null for non-existent ID" {
    var scene = SceneGraph.init(testing.allocator);
    defer scene.deinit();

    const result = scene.findElement(999);
    try expect(result == null);
}

test "SceneGraph.removeElement removes correct element" {
    var scene = SceneGraph.init(testing.allocator);
    defer scene.deinit();

    const white = c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 };

    const id1 = try scene.addTextLabel("First", Vec2{ .x = 0, .y = 0 }, 16, white, .world);
    const id2 = try scene.addTextLabel("Second", Vec2{ .x = 10, .y = 10 }, 20, white, .world);

    try expectEqual(2, scene.elements.items.len);

    const removed = scene.removeElement(id1);
    try expect(removed);
    try expectEqual(1, scene.elements.items.len);

    // id1 should not be found
    try expect(scene.findElement(id1) == null);

    // id2 should still exist
    try expect(scene.findElement(id2) != null);
}

test "SceneGraph.removeElement returns false for non-existent ID" {
    var scene = SceneGraph.init(testing.allocator);
    defer scene.deinit();

    const removed = scene.removeElement(999);
    try expect(!removed);
}

test "SceneGraph.addTextLabel allocates text copy" {
    var scene = SceneGraph.init(testing.allocator);
    defer scene.deinit();

    const white = c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 };

    // Use a stack-allocated string that will go out of scope
    {
        var text_buf: [20]u8 = undefined;
        const text = std.fmt.bufPrint(&text_buf, "Test {d}", .{42}) catch unreachable;
        _ = try scene.addTextLabel(text, Vec2{ .x = 0, .y = 0 }, 16, white, .world);
    }

    // Element should still have valid text after original goes out of scope
    const elem = scene.findElement(1).?;
    try expect(std.mem.eql(u8, "Test 42", elem.data.text_label.text));
}

test "SceneGraph multiple add/remove operations" {
    var scene = SceneGraph.init(testing.allocator);
    defer scene.deinit();

    const white = c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 };

    // Add 5 elements
    var ids: [5]u32 = undefined;
    for (0..5) |i| {
        var text_buf: [20]u8 = undefined;
        const text = std.fmt.bufPrint(&text_buf, "Element {d}", .{i}) catch unreachable;
        ids[i] = try scene.addTextLabel(text, Vec2{ .x = 0, .y = 0 }, 16, white, .world);
    }

    try expectEqual(5, scene.elements.items.len);

    // Remove elements 1 and 3 (indices 1 and 3)
    _ = scene.removeElement(ids[1]);
    _ = scene.removeElement(ids[3]);

    try expectEqual(3, scene.elements.items.len);

    // Verify remaining elements
    try expect(scene.findElement(ids[0]) != null);
    try expect(scene.findElement(ids[1]) == null);
    try expect(scene.findElement(ids[2]) != null);
    try expect(scene.findElement(ids[3]) == null);
    try expect(scene.findElement(ids[4]) != null);
}

test "Element visibility flag" {
    var scene = SceneGraph.init(testing.allocator);
    defer scene.deinit();

    const white = c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
    const id = try scene.addTextLabel("Test", Vec2{ .x = 0, .y = 0 }, 16, white, .world);

    const elem = scene.findElement(id).?;

    // Should be visible by default
    try expect(elem.visible);

    // Test toggling visibility
    elem.visible = false;
    try expect(!elem.visible);

    elem.visible = true;
    try expect(elem.visible);
}

test "CoordinateSpace enum values" {
    try expectEqual(CoordinateSpace.world, .world);
    try expectEqual(CoordinateSpace.screen, .screen);
}

test "ElementType enum values" {
    try expectEqual(ElementType.text_label, .text_label);
    try expectEqual(ElementType.rectangle, .rectangle);
}

test "Rectangle.init" {
    const white = c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
    const rect = Rectangle.init(100, 50, 2, white);

    try expectEqual(100, rect.width);
    try expectEqual(50, rect.height);
    try expectEqual(2, rect.border_thickness);
    try expectEqual(255, rect.color.r);
}

test "SceneGraph.addRectangle returns unique ID" {
    var scene = SceneGraph.init(testing.allocator);
    defer scene.deinit();

    const white = c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
    const id = try scene.addRectangle(Vec2{ .x = 10, .y = 20 }, 100, 50, 2, white, .world);

    try expectEqual(1, id);
    try expectEqual(1, scene.elements.items.len);
}

test "SceneGraph.addRectangle stores correct data" {
    var scene = SceneGraph.init(testing.allocator);
    defer scene.deinit();

    const blue = c.SDL_Color{ .r = 100, .g = 150, .b = 255, .a = 255 };
    const id = try scene.addRectangle(Vec2{ .x = 10, .y = 20 }, 100, 50, 3, blue, .screen);

    const elem = scene.findElement(id).?;

    try expectEqual(id, elem.id);
    try expectEqual(10, elem.transform.position.x);
    try expectEqual(20, elem.transform.position.y);
    try expectEqual(CoordinateSpace.screen, elem.space);
    try expect(elem.visible);
    try expectEqual(ElementType.rectangle, elem.element_type);
    try expectEqual(100, elem.data.rectangle.width);
    try expectEqual(50, elem.data.rectangle.height);
    try expectEqual(3, elem.data.rectangle.border_thickness);
    try expectEqual(100, elem.data.rectangle.color.r);
    try expectEqual(150, elem.data.rectangle.color.g);
    try expectEqual(255, elem.data.rectangle.color.b);
}

test "SceneGraph mixed elements (text and rectangles)" {
    var scene = SceneGraph.init(testing.allocator);
    defer scene.deinit();

    const white = c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
    const blue = c.SDL_Color{ .r = 100, .g = 150, .b = 255, .a = 255 };

    const text_id = try scene.addTextLabel("Test", Vec2{ .x = 0, .y = 0 }, 16, white, .world);
    const rect_id = try scene.addRectangle(Vec2{ .x = 10, .y = 20 }, 100, 50, 2, blue, .world);

    try expectEqual(2, scene.elements.items.len);

    const text_elem = scene.findElement(text_id).?;
    const rect_elem = scene.findElement(rect_id).?;

    try expectEqual(ElementType.text_label, text_elem.element_type);
    try expectEqual(ElementType.rectangle, rect_elem.element_type);
}

test "SceneGraph.removeElement works with rectangles" {
    var scene = SceneGraph.init(testing.allocator);
    defer scene.deinit();

    const white = c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 };

    const id1 = try scene.addRectangle(Vec2{ .x = 0, .y = 0 }, 50, 50, 1, white, .world);
    const id2 = try scene.addRectangle(Vec2{ .x = 10, .y = 10 }, 100, 100, 2, white, .screen);

    try expectEqual(2, scene.elements.items.len);

    const removed = scene.removeElement(id1);
    try expect(removed);
    try expectEqual(1, scene.elements.items.len);

    try expect(scene.findElement(id1) == null);
    try expect(scene.findElement(id2) != null);
}

test "Standalone drawing functions exist" {
    // Verify that standalone drawing functions are public and accessible
    // These functions can be called independently of the scene graph
    const has_draw_rect = @hasDecl(@This(), "drawRectangleOutline");
    const has_draw_text = @hasDecl(@This(), "drawTextCached");

    try expect(has_draw_rect);
    try expect(has_draw_text);
}

test "DrawDimensions type" {
    const dims = DrawDimensions{ .w = 100, .h = 50 };
    try expectEqual(100, dims.w);
    try expectEqual(50, dims.h);
}
