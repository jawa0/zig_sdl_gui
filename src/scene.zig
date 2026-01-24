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
}

