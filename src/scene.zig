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

/// Line spacing multiplier for multiline text.
/// Lines are spaced at font_size * LINE_SPACING_MULTIPLIER.
/// This provides room for the text cursor to extend above/below the text
/// and improves readability of multiline text.
pub const LINE_SPACING_MULTIPLIER: f32 = 1.2;

/// Dimensions returned by drawing functions
pub const DrawDimensions = struct {
    w: i32,
    h: i32,
};

/// Bounding box in world coordinates
pub const BoundingBox = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,

    /// Test if a world-space point is inside this bounding box
    pub fn containsWorld(self: BoundingBox, world_x: f32, world_y: f32) bool {
        return world_x >= self.x and world_x <= self.x + self.w and
               world_y >= self.y and world_y <= self.y + self.h;
    }

    /// Test if this bounding box is fully contained within the given rectangle
    pub fn isFullyWithin(self: BoundingBox, min_x: f32, min_y: f32, max_x: f32, max_y: f32) bool {
        return self.x >= min_x and
            self.y >= min_y and
            self.x + self.w <= max_x and
            self.y + self.h <= max_y;
    }
};

pub const ElementType = enum {
    text_label,
    rectangle,
    // Future: circle, image, etc.

    /// Returns true if this element type can be scaled non-uniformly (independent width/height).
    /// Elements that cannot scale non-uniformly (like text) require uniform scaling to maintain
    /// their aspect ratio. When a selection contains ANY element requiring uniform scaling,
    /// the entire selection must scale uniformly to preserve relative positioning.
    pub fn canScaleNonUniform(self: ElementType) bool {
        return switch (self) {
            .rectangle => true,
            .text_label => false,
        };
    }
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
// Removed drawTextCached - now using cache.draw() directly with explicit dimensions

pub const Element = struct {
    id: u32,
    transform: Transform,
    space: CoordinateSpace,
    visible: bool,
    element_type: ElementType,
    bounding_box: BoundingBox, // World-space bounding box
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
        font: ?*c.TTF_Font,
    ) !u32 {
        const id = self.next_id;
        self.next_id += 1;

        const label = try TextLabel.init(self.allocator, text, font_size, color);

        // Calculate bounding box in world coordinates
        // Note: In world space (Y-up), text position is the TOP of the text,
        // but since Y increases upward, the text extends downward (negative Y).
        // So the bounding box bottom is at position.y - height.
        const bbox = if (font) |f| blk: {
            _ = c.TTF_SetFontSize(f, @intFromFloat(font_size));

            // Check if text contains newlines (multiline)
            const has_newline = std.mem.indexOfScalar(u8, text, '\n') != null;

            if (has_newline) {
                // Multiline text: calculate dimensions line by line
                var max_width: c_int = 0;
                var line_count: usize = 0;
                var line_start: usize = 0;

                var i: usize = 0;
                while (i <= text.len) : (i += 1) {
                    if (i == text.len or text[i] == '\n') {
                        if (i > line_start) {
                            const line = text[line_start..i];
                            var line_buf: [256]u8 = undefined;
                            const line_z = std.fmt.bufPrintZ(&line_buf, "{s}", .{line}) catch {
                                line_start = i + 1;
                                continue;
                            };

                            var line_w: c_int = 0;
                            var line_h: c_int = 0;
                            _ = c.TTF_SizeText(f, line_z.ptr, &line_w, &line_h);
                            max_width = @max(max_width, line_w);
                            line_count += 1;
                        } else {
                            // Empty line still counts
                            line_count += 1;
                        }
                        line_start = i + 1;
                    }
                }

                if (line_count == 0) line_count = 1; // At least one line

                const line_spacing = font_size * LINE_SPACING_MULTIPLIER;
                const total_height = line_spacing * @as(f32, @floatFromInt(line_count));
                break :blk BoundingBox{
                    .x = position.x,
                    .y = position.y - total_height, // Bottom of text in world space
                    .w = @floatFromInt(max_width),
                    .h = total_height,
                };
            } else {
                // Single line text: use TTF_SizeText
                var text_buf: [256]u8 = undefined;
                const null_term_text = std.fmt.bufPrintZ(&text_buf, "{s}", .{text}) catch {
                    // If text is too long, use approximate dimensions
                    const approx_h = font_size;
                    break :blk BoundingBox{
                        .x = position.x,
                        .y = position.y - approx_h, // Bottom of text in world space
                        .w = font_size * @as(f32, @floatFromInt(text.len)) * 0.6, // Approximate
                        .h = approx_h,
                    };
                };

                var text_w: c_int = 0;
                var text_h: c_int = 0;
                _ = c.TTF_SizeText(f, null_term_text.ptr, &text_w, &text_h);

                const h = @as(f32, @floatFromInt(text_h));
                break :blk BoundingBox{
                    .x = position.x,
                    .y = position.y - h, // Bottom of text in world space
                    .w = @floatFromInt(text_w),
                    .h = h,
                };
            }
        } else blk: {
            // No font available (e.g., in tests) - use approximate dimensions
            // Count lines for multiline text
            var line_count: usize = 1;
            for (text) |ch| {
                if (ch == '\n') line_count += 1;
            }
            const line_spacing = font_size * LINE_SPACING_MULTIPLIER;
            const approx_h = line_spacing * @as(f32, @floatFromInt(line_count));
            break :blk BoundingBox{
                .x = position.x,
                .y = position.y - approx_h, // Bottom of text in world space
                .w = font_size * @as(f32, @floatFromInt(text.len)) * 0.6 / @as(f32, @floatFromInt(line_count)),
                .h = approx_h,
            };
        };

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
            .bounding_box = bbox,
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

        // Calculate bounding box in world coordinates
        // Same as text: position.y is the TOP of the element in world space (Y-up)
        // The element extends downward, so bottom is at position.y - height
        const bbox = BoundingBox{
            .x = position.x,
            .y = position.y - height,  // Bottom of rectangle in world space
            .w = width,
            .h = height,
        };

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
            .bounding_box = bbox,
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

    /// Clear all elements except those with the given IDs (typically screen-space UI like FPS).
    /// Used when regenerating scene content with new colors.
    pub fn clearExcept(self: *SceneGraph, preserved_ids: []const u32) void {
        var i: usize = 0;
        while (i < self.elements.items.len) {
            const should_preserve = for (preserved_ids) |id| {
                if (self.elements.items[i].id == id) break true;
            } else false;

            if (!should_preserve) {
                self.elements.items[i].deinit(self.allocator);
                _ = self.elements.swapRemove(i);
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

    /// Update colors of scene elements (used when color scheme changes)
    /// Only updates world-space elements, leaving screen-space UI (like FPS) unchanged
    pub fn updateSceneColors(self: *SceneGraph, text_color: c.SDL_Color, rect_red: c.SDL_Color, rect_green: c.SDL_Color, rect_yellow: c.SDL_Color) void {
        _ = rect_yellow; // Currently unused, but kept for future use
        for (self.elements.items) |*elem| {
            // Only update world-space elements (not screen-space UI like FPS)
            if (elem.space != .world) continue;

            switch (elem.element_type) {
                .text_label => {
                    elem.data.text_label.color = text_color;
                    // Clear cache so it re-renders with new color
                    elem.data.text_label.cache.deinit();
                },
                .rectangle => {
                    // Update rectangle colors based on current color
                    // This is a heuristic - we update red and green rectangles
                    const current = elem.data.rectangle.color;
                    if (current.r > current.g and current.r > current.b) {
                        // Likely a "red" rectangle
                        elem.data.rectangle.color = rect_red;
                    } else if (current.g > current.r and current.g > current.b) {
                        // Likely a "green" rectangle
                        elem.data.rectangle.color = rect_green;
                    }
                    // Otherwise leave color as-is
                },
            }
        }
    }

    /// Convert screen coordinates to world coordinates using the camera
    pub fn screenToWorld(_: *SceneGraph, screen_pos: Vec2, cam: *const Camera) Vec2 {
        return cam.screenToWorld(screen_pos);
    }

    /// Convert world coordinates to screen coordinates using the camera
    pub fn worldToScreen(_: *SceneGraph, world_pos: Vec2, cam: *const Camera) Vec2 {
        return cam.worldToScreen(world_pos);
    }

    /// Update an element's bounding box (call when element moves or scales)
    /// For world-space text elements, camera parameter is needed to calculate correct dimensions
    pub fn updateElementBoundingBox(self: *SceneGraph, id: u32, font: *c.TTF_Font) void {
        const elem = self.findElement(id) orelse return;

        switch (elem.element_type) {
            .text_label => {
                const label = &elem.data.text_label;

                // Calculate font size: for world-space elements, use base size (bbox is in world units)
                // The width/height we get from TTF_SizeText will be in world-space units
                const measure_font_size = label.font_size;
                _ = c.TTF_SetFontSize(font, @intFromFloat(measure_font_size));

                // Check if text contains newlines (multiline)
                const has_newline = std.mem.indexOfScalar(u8, label.text, '\n') != null;

                if (has_newline) {
                    // Multiline text: calculate dimensions line by line
                    var max_width: c_int = 0;
                    var line_count: usize = 0;
                    var line_start: usize = 0;

                    var i: usize = 0;
                    while (i <= label.text.len) : (i += 1) {
                        if (i == label.text.len or label.text[i] == '\n') {
                            if (i > line_start) {
                                const line = label.text[line_start..i];
                                var line_buf: [256]u8 = undefined;
                                const line_z = std.fmt.bufPrintZ(&line_buf, "{s}", .{line}) catch {
                                    line_start = i + 1;
                                    continue;
                                };

                                var line_w: c_int = 0;
                                var line_h: c_int = 0;
                                _ = c.TTF_SizeText(font, line_z.ptr, &line_w, &line_h);
                                max_width = @max(max_width, line_w);
                                line_count += 1;
                            } else {
                                // Empty line still counts
                                line_count += 1;
                            }
                            line_start = i + 1;
                        }
                    }

                    if (line_count == 0) line_count = 1; // At least one line

                    const line_spacing = label.font_size * LINE_SPACING_MULTIPLIER;
                    const total_height = line_spacing * @as(f32, @floatFromInt(line_count));
                    elem.bounding_box.x = elem.transform.position.x;
                    elem.bounding_box.y = elem.transform.position.y - total_height; // Bottom in world space
                    elem.bounding_box.w = @floatFromInt(max_width);
                    elem.bounding_box.h = total_height;
                } else {
                    // Single line text: use TTF_SizeText
                    var text_buf: [256]u8 = undefined;
                    const null_term_text = std.fmt.bufPrintZ(&text_buf, "{s}", .{label.text}) catch {
                        // Use approximate dimensions if text is too long
                        const h = label.font_size;
                        elem.bounding_box.x = elem.transform.position.x;
                        elem.bounding_box.y = elem.transform.position.y - h; // Bottom in world space
                        elem.bounding_box.w = label.font_size * @as(f32, @floatFromInt(label.text.len)) * 0.6;
                        elem.bounding_box.h = h;
                        return;
                    };

                    var text_w: c_int = 0;
                    var text_h: c_int = 0;
                    _ = c.TTF_SizeText(font, null_term_text.ptr, &text_w, &text_h);

                    // Update bounding box dimensions (position stays with transform)
                    // In world space (Y-up), text extends downward from position
                    const h = @as(f32, @floatFromInt(text_h));
                    elem.bounding_box.x = elem.transform.position.x;
                    elem.bounding_box.y = elem.transform.position.y - h; // Bottom in world space
                    elem.bounding_box.w = @floatFromInt(text_w);
                    elem.bounding_box.h = h;
                }
            },
            .rectangle => {
                const rect = &elem.data.rectangle;
                const h = rect.height * elem.transform.scale.y;
                elem.bounding_box.x = elem.transform.position.x;
                elem.bounding_box.y = elem.transform.position.y - h;  // Bottom in world space
                elem.bounding_box.w = rect.width * elem.transform.scale.x;
                elem.bounding_box.h = h;
            },
        }
    }

    /// Perform hit test at screen coordinates, returns element ID if hit (top-most element wins)
    pub fn hitTest(self: *SceneGraph, screen_x: f32, screen_y: f32, cam: *const Camera) ?u32 {
        // Convert screen coordinates to world coordinates
        const world_pos = cam.screenToWorld(Vec2{ .x = screen_x, .y = screen_y });

        // Iterate backwards (top to bottom in z-order)
        var i: usize = self.elements.items.len;
        while (i > 0) {
            i -= 1;
            const elem = &self.elements.items[i];
            if (!elem.visible) continue;

            // Only hit-test world-space elements for now
            // (Screen-space elements like FPS counter shouldn't be selectable)
            if (elem.space != .world) continue;

            // Test against stored world-space bounding box
            if (elem.bounding_box.containsWorld(world_pos.x, world_pos.y)) {
                return elem.id;
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

                    // Calculate target font size for current zoom (for optimal rasterization)
                    const target_font_size: f32 = switch (elem.space) {
                        .world => label.font_size * cam.zoom,
                        .screen => label.font_size,
                    };

                    // Check if text contains newlines (multiline)
                    const has_newline = std.mem.indexOfScalar(u8, label.text, '\n') != null;

                    if (has_newline) {
                        // Multiline text: render each line separately
                        // SDL_ttf doesn't handle newlines, so we split and render line by line
                        const line_spacing = target_font_size * LINE_SPACING_MULTIPLIER;
                        const font_size_int: c_int = @intFromFloat(target_font_size);
                        _ = c.TTF_SetFontSize(font, font_size_int);

                        var line_y: f32 = screen_pos.y;
                        var line_start: usize = 0;
                        var i: usize = 0;
                        while (i <= label.text.len) : (i += 1) {
                            if (i == label.text.len or label.text[i] == '\n') {
                                // Render this line (if not empty)
                                if (i > line_start) {
                                    const line = label.text[line_start..i];
                                    var line_buf: [256]u8 = undefined;
                                    const line_z = std.fmt.bufPrintZ(&line_buf, "{s}", .{line}) catch {
                                        line_start = i + 1;
                                        line_y += line_spacing;
                                        continue;
                                    };

                                    const text_surface = c.TTF_RenderText_Blended(font, line_z.ptr, label.color);
                                    if (text_surface != null) {
                                        defer c.SDL_FreeSurface(text_surface);
                                        const text_texture = c.SDL_CreateTextureFromSurface(renderer, text_surface);
                                        if (text_texture != null) {
                                            defer c.SDL_DestroyTexture(text_texture);

                                            // Enable linear filtering and alpha blending
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
                    } else {
                        // Single-line text: use cached rendering for efficiency
                        const bbox = elem.bounding_box;
                        const dest_w: i32 = switch (elem.space) {
                            .world => @intFromFloat(bbox.w * cam.zoom),
                            .screen => @intFromFloat(bbox.w),
                        };
                        const dest_h: i32 = switch (elem.space) {
                            .world => @intFromFloat(bbox.h * cam.zoom),
                            .screen => @intFromFloat(bbox.h),
                        };

                        const x: i32 = @intFromFloat(screen_pos.x);
                        const y: i32 = @intFromFloat(screen_pos.y);

                        var text_buf: [256]u8 = undefined;
                        const null_term_text = std.fmt.bufPrintZ(&text_buf, "{s}", .{label.text}) catch continue;

                        _ = label.cache.draw(
                            renderer,
                            font,
                            null_term_text.ptr,
                            x,
                            y,
                            dest_w,
                            dest_h,
                            target_font_size,
                            label.color,
                        );
                    }
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

    const id1 = try scene.addTextLabel("Test 1", Vec2{ .x = 0, .y = 0 }, 16, white, .world, null);
    const id2 = try scene.addTextLabel("Test 2", Vec2{ .x = 10, .y = 10 }, 20, white, .screen, null);

    try expectEqual(1, id1);
    try expectEqual(2, id2);
    try expectEqual(2, scene.elements.items.len);
}

test "SceneGraph.addTextLabel stores correct data" {
    var scene = SceneGraph.init(testing.allocator);
    defer scene.deinit();

    const white = c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
    const id = try scene.addTextLabel("Hello", Vec2{ .x = 100, .y = 200 }, 24, white, .world, null);

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

    const id1 = try scene.addTextLabel("First", Vec2{ .x = 0, .y = 0 }, 16, white, .world, null);
    const id2 = try scene.addTextLabel("Second", Vec2{ .x = 10, .y = 10 }, 20, white, .world, null);

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
        _ = try scene.addTextLabel(text, Vec2{ .x = 0, .y = 0 }, 16, white, .world, null);
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
        ids[i] = try scene.addTextLabel(text, Vec2{ .x = 0, .y = 0 }, 16, white, .world, null);
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
    const id = try scene.addTextLabel("Test", Vec2{ .x = 0, .y = 0 }, 16, white, .world, null);

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

    const text_id = try scene.addTextLabel("Test", Vec2{ .x = 0, .y = 0 }, 16, white, .world, null);
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

test "BoundingBox.containsWorld - basic containment" {
    const bbox = BoundingBox{
        .x = 10,
        .y = 20,
        .w = 100,
        .h = 50,
    };

    // Points inside the box
    try expect(bbox.containsWorld(10, 20)); // Bottom-left corner
    try expect(bbox.containsWorld(110, 20)); // Bottom-right corner
    try expect(bbox.containsWorld(10, 70)); // Top-left corner
    try expect(bbox.containsWorld(110, 70)); // Top-right corner
    try expect(bbox.containsWorld(60, 45)); // Center

    // Points outside the box
    try expect(!bbox.containsWorld(9, 45)); // Left of box
    try expect(!bbox.containsWorld(111, 45)); // Right of box
    try expect(!bbox.containsWorld(60, 19)); // Below box (Y-up: smaller Y)
    try expect(!bbox.containsWorld(60, 71)); // Above box (Y-up: larger Y)
}

test "Text label bounding box in Y-up world space" {
    var scene = SceneGraph.init(testing.allocator);
    defer scene.deinit();

    const white = c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 };

    // Add text at position (100, 200) with approximate height of 16
    const id = try scene.addTextLabel("Test", Vec2{ .x = 100, .y = 200 }, 16, white, .world, null);
    const elem = scene.findElement(id).?;

    // In Y-up world space, position.y (200) should be the TOP of the text
    // The bounding box should extend downward (negative Y direction)
    // So bbox.y + bbox.h should equal position.y

    const bbox = elem.bounding_box;

    // Verify bounding box top equals element position.y
    const bbox_top = bbox.y + bbox.h;
    try expectEqual(200, bbox_top);

    // Verify bounding box bottom is below the top (smaller Y value in Y-up)
    try expect(bbox.y < bbox_top);

    // Verify the height includes line spacing: 1 * 16 * 1.2 = 19.2
    const expected_h: f32 = 16 * LINE_SPACING_MULTIPLIER;
    try expectEqual(expected_h, bbox.h);

    // Verify the bottom is at position.y - height
    const expected_bottom: f32 = 200 - expected_h;
    try expectEqual(expected_bottom, bbox.y);

    // Test hit detection: point at element position should be inside bbox
    try expect(bbox.containsWorld(100, 200));

    // Point just above element position (larger Y) should be outside
    try expect(!bbox.containsWorld(100, 201));

    // Point at bottom of text should be inside
    try expect(bbox.containsWorld(100, expected_bottom));

    // Point just below bottom (smaller Y) should be outside
    try expect(!bbox.containsWorld(100, expected_bottom - 1));
}

test "Rectangle bounding box in Y-up world space" {
    var scene = SceneGraph.init(testing.allocator);
    defer scene.deinit();

    const white = c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 };

    // Add rectangle at position (100, 200) with width=50, height=30
    const id = try scene.addRectangle(Vec2{ .x = 100, .y = 200 }, 50, 30, 2, white, .world);
    const elem = scene.findElement(id).?;

    // In Y-up world space, position.y (200) should be the TOP of the rectangle
    // The bounding box should extend downward (negative Y direction)

    const bbox = elem.bounding_box;

    // Verify bounding box top equals element position.y
    const bbox_top = bbox.y + bbox.h;
    try expectEqual(200, bbox_top);

    // Verify bounding box bottom is at position.y - height
    try expectEqual(200 - 30, bbox.y);

    // Verify dimensions
    try expectEqual(50, bbox.w);
    try expectEqual(30, bbox.h);

    // Test hit detection: point at element position (top-left corner) should be inside
    try expect(bbox.containsWorld(100, 200));

    // Point just above top (larger Y) should be outside
    try expect(!bbox.containsWorld(100, 201));

    // Point at bottom-left corner should be inside
    try expect(bbox.containsWorld(100, 170));

    // Point just below bottom (smaller Y) should be outside
    try expect(!bbox.containsWorld(100, 169));

    // Point at top-right corner should be inside
    try expect(bbox.containsWorld(150, 200));

    // Point just right of rectangle should be outside
    try expect(!bbox.containsWorld(151, 200));
}

test "Text and rectangle bounding boxes positioning" {
    var scene = SceneGraph.init(testing.allocator);
    defer scene.deinit();

    const white = c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 };

    // Create text and rectangle at the same position
    // Text uses line spacing (20 * 1.2 = 24), rectangle uses exact height (20)
    const text_id = try scene.addTextLabel("Test", Vec2{ .x = 0, .y = 100 }, 20, white, .world, null);
    const rect_id = try scene.addRectangle(Vec2{ .x = 0, .y = 100 }, 50, 20, 1, white, .world);

    const text_elem = scene.findElement(text_id).?;
    const rect_elem = scene.findElement(rect_id).?;

    // Both should have the same top (y + h) at position.y
    const text_top = text_elem.bounding_box.y + text_elem.bounding_box.h;
    const rect_top = rect_elem.bounding_box.y + rect_elem.bounding_box.h;
    try expectEqual(@as(f32, 100), text_top);
    try expectEqual(@as(f32, 100), rect_top);

    // Text uses line spacing, rectangle uses exact dimensions
    const text_expected_h: f32 = 20 * LINE_SPACING_MULTIPLIER;
    try expectEqual(text_expected_h, text_elem.bounding_box.h);
    try expectEqual(@as(f32, 20), rect_elem.bounding_box.h);

    // Bottoms differ due to line spacing
    try expectEqual(@as(f32, 100) - text_expected_h, text_elem.bounding_box.y);
    try expectEqual(@as(f32, 100 - 20), rect_elem.bounding_box.y);
}

test "Bounding box hit testing for overlapping elements" {
    var scene = SceneGraph.init(testing.allocator);
    defer scene.deinit();

    const white = c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 };

    // Create two rectangles, one overlapping the other
    // First rectangle: position (0, 100), size 50x50
    const id1 = try scene.addRectangle(Vec2{ .x = 0, .y = 100 }, 50, 50, 1, white, .world);

    // Second rectangle: position (25, 75), size 50x50 (overlaps first)
    const id2 = try scene.addRectangle(Vec2{ .x = 25, .y = 75 }, 50, 50, 1, white, .world);

    // Point at (30, 60) should be inside second rectangle only
    // Second rectangle spans x: [25, 75], y: [25, 75]
    const elem2 = scene.findElement(id2).?;
    try expect(elem2.bounding_box.containsWorld(30, 60));

    // First rectangle spans x: [0, 50], y: [50, 100]
    const elem1 = scene.findElement(id1).?;
    try expect(!elem1.bounding_box.containsWorld(30, 60));

    // Point at (40, 90) should be inside first rectangle only
    try expect(elem1.bounding_box.containsWorld(40, 90));
    try expect(!elem2.bounding_box.containsWorld(40, 90));

    // Point at (30, 70) should be inside both (overlapping region)
    try expect(elem1.bounding_box.containsWorld(30, 70));
    try expect(elem2.bounding_box.containsWorld(30, 70));
}

test "Multiline text bounding box calculation" {
    var scene = SceneGraph.init(testing.allocator);
    defer scene.deinit();

    const white = c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 };

    // Create multiline text with 3 lines at position (0, 100) with font size 16
    const multiline_text = "Line 1\nLine 2\nLine 3";
    const id = try scene.addTextLabel(multiline_text, Vec2{ .x = 0, .y = 100 }, 16, white, .world, null);
    const elem = scene.findElement(id).?;

    const bbox = elem.bounding_box;

    // With 3 lines, font_size=16, and LINE_SPACING_MULTIPLIER=1.2:
    // height = 3 * 16 * 1.2 = 57.6
    const expected_height: f32 = 3 * 16 * LINE_SPACING_MULTIPLIER;
    try expectEqual(expected_height, bbox.h);

    // Top should be at position.y (100)
    const bbox_top = bbox.y + bbox.h;
    try expectEqual(@as(f32, 100), bbox_top);

    // Bottom should be at position.y - height = 100 - 57.6 = 42.4
    const expected_bottom: f32 = 100 - expected_height;
    try expectEqual(expected_bottom, bbox.y);

    // Test hit detection at top of text
    try expect(bbox.containsWorld(0, 100));

    // Test hit detection at bottom of text (42.4)
    try expect(bbox.containsWorld(0, expected_bottom));

    // Test just below bottom (should be outside)
    try expect(!bbox.containsWorld(0, expected_bottom - 1));

    // Test just above top (should be outside)
    try expect(!bbox.containsWorld(0, 101));
}

test "Single line text vs multiline text bounding boxes" {
    var scene = SceneGraph.init(testing.allocator);
    defer scene.deinit();

    const white = c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 };

    // Create single line text
    const single_id = try scene.addTextLabel("Test", Vec2{ .x = 0, .y = 100 }, 16, white, .world, null);
    const single_elem = scene.findElement(single_id).?;

    // Create multiline text with same content but with newline
    const multi_id = try scene.addTextLabel("Test\n", Vec2{ .x = 0, .y = 100 }, 16, white, .world, null);
    const multi_elem = scene.findElement(multi_id).?;

    // Single line: height = 1 * 16 * 1.2 = 19.2
    const single_expected_h: f32 = 1 * 16 * LINE_SPACING_MULTIPLIER;
    try expectEqual(single_expected_h, single_elem.bounding_box.h);

    // Multiline with 2 lines (text + empty line after \n): height = 2 * 16 * 1.2 = 38.4
    const multi_expected_h: f32 = 2 * 16 * LINE_SPACING_MULTIPLIER;
    try expectEqual(multi_expected_h, multi_elem.bounding_box.h);

    // Both should have same top
    const single_top = single_elem.bounding_box.y + single_elem.bounding_box.h;
    const multi_top = multi_elem.bounding_box.y + multi_elem.bounding_box.h;
    try expectEqual(@as(f32, 100), single_top);
    try expectEqual(@as(f32, 100), multi_top);

    // But different bottoms
    try expectEqual(@as(f32, 100) - single_expected_h, single_elem.bounding_box.y);
    try expectEqual(@as(f32, 100) - multi_expected_h, multi_elem.bounding_box.y);
}

test "ElementType.canScaleNonUniform returns correct values" {
    // Rectangles can scale non-uniformly (stretch in width or height independently)
    try expect(ElementType.rectangle.canScaleNonUniform());

    // Text cannot scale non-uniformly (must maintain aspect ratio)
    try expect(!ElementType.text_label.canScaleNonUniform());
}

test "BoundingBox.isFullyWithin" {
    const bbox = BoundingBox{ .x = 10, .y = 20, .w = 30, .h = 40 };
    // bbox spans x: [10, 40], y: [20, 60]

    // Fully contained within larger rectangle
    try expect(bbox.isFullyWithin(0, 0, 100, 100));
    try expect(bbox.isFullyWithin(10, 20, 40, 60)); // Exactly matching bounds

    // Partially outside (left edge)
    try expect(!bbox.isFullyWithin(15, 0, 100, 100));

    // Partially outside (right edge)
    try expect(!bbox.isFullyWithin(0, 0, 35, 100));

    // Partially outside (bottom edge)
    try expect(!bbox.isFullyWithin(0, 25, 100, 100));

    // Partially outside (top edge)
    try expect(!bbox.isFullyWithin(0, 0, 100, 55));

    // Completely outside
    try expect(!bbox.isFullyWithin(100, 100, 200, 200));
}
