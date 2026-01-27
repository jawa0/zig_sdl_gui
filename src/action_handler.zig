const std = @import("std");
const action = @import("action.zig");
const camera = @import("camera.zig");
const math = @import("math.zig");
const color_scheme = @import("color_scheme.zig");
const tool = @import("tool.zig");
const text_buffer = @import("text_buffer.zig");

const Action = action.Action;
const ActionParams = action.ActionParams;
const Camera = camera.Camera;
const Vec2 = math.Vec2;
const SchemeType = color_scheme.SchemeType;
const Tool = tool.Tool;
const ResizeHandle = action.ResizeHandle;
pub const TextBuffer = text_buffer.TextBuffer;

/// Maximum number of elements that can be selected at once
pub const MAX_SELECTED: usize = 256;

/// A set of selected element IDs with O(n) operations.
/// Suitable for small selection sets typical in UI applications.
pub const SelectionSet = struct {
    ids: [MAX_SELECTED]u32 = undefined,
    count: usize = 0,

    /// Check if an element is in the selection set
    pub fn contains(self: *const SelectionSet, element_id: u32) bool {
        for (self.ids[0..self.count]) |id| {
            if (id == element_id) return true;
        }
        return false;
    }

    /// Add an element to the selection set (if not already present)
    pub fn add(self: *SelectionSet, element_id: u32) void {
        if (self.contains(element_id)) return;
        if (self.count >= MAX_SELECTED) return;
        self.ids[self.count] = element_id;
        self.count += 1;
    }

    /// Remove an element from the selection set
    pub fn remove(self: *SelectionSet, element_id: u32) void {
        for (self.ids[0..self.count], 0..) |id, i| {
            if (id == element_id) {
                // Swap with last element and reduce count
                self.ids[i] = self.ids[self.count - 1];
                self.count -= 1;
                return;
            }
        }
    }

    /// Toggle an element's presence in the selection set
    pub fn toggle(self: *SelectionSet, element_id: u32) void {
        if (self.contains(element_id)) {
            self.remove(element_id);
        } else {
            self.add(element_id);
        }
    }

    /// Clear all selections
    pub fn clear(self: *SelectionSet) void {
        self.count = 0;
    }

    /// Replace selection with a single element
    pub fn selectOnly(self: *SelectionSet, element_id: u32) void {
        self.count = 1;
        self.ids[0] = element_id;
    }

    /// Get the number of selected elements
    pub fn len(self: *const SelectionSet) usize {
        return self.count;
    }

    /// Check if selection is empty
    pub fn isEmpty(self: *const SelectionSet) bool {
        return self.count == 0;
    }

    /// Get the primary selected element (first in set, for single-element operations)
    pub fn primary(self: *const SelectionSet) ?u32 {
        if (self.count == 0) return null;
        return self.ids[0];
    }

    /// Get slice of all selected element IDs
    pub fn items(self: *const SelectionSet) []const u32 {
        return self.ids[0..self.count];
    }
};

/// Text editing state
pub const TextEditState = struct {
    is_editing: bool = false,
    world_pos: Vec2 = Vec2{ .x = 0, .y = 0 },
    buffer: TextBuffer = TextBuffer.init(),

    /// Element ID being edited (null if creating new text)
    editing_element_id: ?u32 = null,

    /// Set when editing finishes with non-empty text that should be added to scene
    should_create_element: bool = false,
    /// Set when editing finishes and we should update an existing element
    should_update_element: bool = false,
    finished_text_buffer: [text_buffer.MAX_BUFFER_SIZE]u8 = undefined,
    finished_text_len: usize = 0,
    finished_world_pos: Vec2 = Vec2{ .x = 0, .y = 0 },
    finished_element_id: ?u32 = null,

    /// Start editing with a fresh buffer (creating new text)
    pub fn startEditing(self: *TextEditState, pos: Vec2) void {
        self.is_editing = true;
        self.world_pos = pos;
        self.buffer.clear();
        self.editing_element_id = null;
    }

    /// Start editing an existing text element
    pub fn startEditingElement(self: *TextEditState, element_id: u32, pos: Vec2, existing_text: []const u8) void {
        self.is_editing = true;
        self.world_pos = pos;
        self.editing_element_id = element_id;
        self.buffer.clear();
        self.buffer.insert(existing_text);
        // Position cursor at end
        self.buffer.cursorToBufferEnd();
    }

    /// Finish editing and prepare for element creation/update if buffer has content
    pub fn finishEditing(self: *TextEditState) void {
        self.should_create_element = false;
        self.should_update_element = false;

        if (self.buffer.hasContent()) {
            const text = self.buffer.getText();
            @memcpy(self.finished_text_buffer[0..text.len], text);
            self.finished_text_len = text.len;
            self.finished_world_pos = self.world_pos;

            if (self.editing_element_id) |elem_id| {
                // Updating existing element
                self.should_update_element = true;
                self.finished_element_id = elem_id;
            } else {
                // Creating new element
                self.should_create_element = true;
            }
        } else if (self.editing_element_id != null) {
            // Text was cleared - mark for deletion by setting update with empty
            self.should_update_element = true;
            self.finished_element_id = self.editing_element_id;
            self.finished_text_len = 0;
        }

        self.is_editing = false;
        self.editing_element_id = null;
    }
};

/// Per-element state at drag start (for multi-select drag)
pub const ElementDragState = struct {
    element_id: u32 = 0,
    start_pos: Vec2 = Vec2{ .x = 0, .y = 0 },
    start_bbox_x: f32 = 0,
    start_bbox_y: f32 = 0,
};

/// Maximum elements in a drag operation
pub const MAX_DRAG_ELEMENTS: usize = 256;

/// Drag operation state
pub const DragState = struct {
    is_dragging: bool = false,
    start_world_pos: Vec2 = Vec2{ .x = 0, .y = 0 },

    // Per-element start states for multi-select drag
    element_states: [MAX_DRAG_ELEMENTS]ElementDragState = undefined,
    element_count: usize = 0,

    // Alt+drag clone support
    alt_held: bool = false, // Whether Alt was held when drag started
    has_moved: bool = false, // Whether actual movement has occurred
    cloned: bool = false, // Whether elements have been cloned

    // Legacy single-element fields (kept for compatibility)
    element_id: u32 = 0,
    element_start_pos: Vec2 = Vec2{ .x = 0, .y = 0 },
};

/// Per-element state at resize start (for multi-select resize)
pub const ElementResizeState = struct {
    element_id: u32 = 0,
    start_pos: Vec2 = Vec2{ .x = 0, .y = 0 },
    start_bbox_x: f32 = 0,
    start_bbox_y: f32 = 0,
    start_bbox_w: f32 = 0,
    start_bbox_h: f32 = 0,
    start_font_size: f32 = 16,
    // Rectangle-specific start dimensions
    start_rect_width: f32 = 0,
    start_rect_height: f32 = 0,
};

/// Maximum elements in a resize operation
pub const MAX_RESIZE_ELEMENTS: usize = 256;

/// Resize operation state
pub const ResizeState = struct {
    is_resizing: bool = false,
    handle: ResizeHandle = .top_left,
    start_world_pos: Vec2 = Vec2{ .x = 0, .y = 0 },
    opposite_corner: Vec2 = Vec2{ .x = 0, .y = 0 }, // World position of opposite corner (anchor point)

    // Union bounding box at resize start
    union_start_min_x: f32 = 0,
    union_start_min_y: f32 = 0,
    union_start_max_x: f32 = 0,
    union_start_max_y: f32 = 0,

    // Per-element start states
    element_states: [MAX_RESIZE_ELEMENTS]ElementResizeState = undefined,
    element_count: usize = 0,

    last_scale_factor: f32 = 1.0, // Track last applied scale to prevent oscillation

    // Legacy single-element fields (kept for compatibility)
    element_id: u32 = 0,
    element_start_pos: Vec2 = Vec2{ .x = 0, .y = 0 },
    element_start_scale: Vec2 = Vec2{ .x = 1, .y = 1 },
    element_start_font_size: f32 = 16,
    start_bbox_width: f32 = 0,
    start_bbox_height: f32 = 0,
};

/// Drag-select (marquee selection) state
pub const DragSelectState = struct {
    is_active: bool = false,
    start_world: Vec2 = Vec2{ .x = 0, .y = 0 },
    current_world: Vec2 = Vec2{ .x = 0, .y = 0 },

    /// Get the normalized rectangle bounds (min/max regardless of drag direction)
    pub fn getBounds(self: *const DragSelectState) struct { min_x: f32, min_y: f32, max_x: f32, max_y: f32 } {
        return .{
            .min_x = @min(self.start_world.x, self.current_world.x),
            .min_y = @min(self.start_world.y, self.current_world.y),
            .max_x = @max(self.start_world.x, self.current_world.x),
            .max_y = @max(self.start_world.y, self.current_world.y),
        };
    }
};

/// Rectangle creation state (click and drag to create rectangle)
pub const RectangleCreateState = struct {
    is_active: bool = false,
    start_world: Vec2 = Vec2{ .x = 0, .y = 0 },
    current_world: Vec2 = Vec2{ .x = 0, .y = 0 },

    /// Get the normalized rectangle bounds (min/max regardless of drag direction)
    pub fn getBounds(self: *const RectangleCreateState) struct { min_x: f32, min_y: f32, max_x: f32, max_y: f32 } {
        return .{
            .min_x = @min(self.start_world.x, self.current_world.x),
            .min_y = @min(self.start_world.y, self.current_world.y),
            .max_x = @max(self.start_world.x, self.current_world.x),
            .max_y = @max(self.start_world.y, self.current_world.y),
        };
    }
};

/// Handles application actions by updating application state.
/// This provides the indirection layer between actions and their implementation.
pub const ActionHandler = struct {
    should_quit: bool = false,
    scheme_type: SchemeType = .light,
    scheme_changed: bool = false,
    grid_visible: bool = true,
    bounding_boxes_visible: bool = false,
    text_edit: TextEditState = TextEditState{},
    current_tool: Tool = .selection,
    selection: SelectionSet = SelectionSet{},
    drag: DragState = DragState{},
    resize: ResizeState = ResizeState{},
    drag_select: DragSelectState = DragSelectState{},
    rect_create: RectangleCreateState = RectangleCreateState{},

    pub fn init() ActionHandler {
        return ActionHandler{};
    }

    /// Process an action and update application state accordingly.
    /// Returns true if the application should quit.
    pub fn handle(self: *ActionHandler, params: ActionParams, cam: *Camera) bool {
        // Reset flags at start of each frame
        self.scheme_changed = false;
        self.text_edit.should_create_element = false;

        switch (params) {
            .quit => {
                self.should_quit = true;
                return true;
            },

            .pan_move => |p| {
                cam.pan(Vec2{ .x = p.delta_x, .y = p.delta_y });
            },

            .zoom_in => |z| {
                const cursor_pos = Vec2{ .x = z.cursor_x, .y = z.cursor_y };
                cam.zoomAt(cursor_pos, z.delta);
            },

            .zoom_out => |z| {
                const cursor_pos = Vec2{ .x = z.cursor_x, .y = z.cursor_y };
                cam.zoomAt(cursor_pos, z.delta);
            },

            .toggle_color_scheme => {
                self.scheme_type = color_scheme.ColorScheme.toggle(self.scheme_type);
                self.scheme_changed = true;
            },

            .toggle_grid => {
                self.grid_visible = !self.grid_visible;
            },

            .toggle_bounding_boxes => {
                self.bounding_boxes_visible = !self.bounding_boxes_visible;
            },

            .begin_text_edit => |edit_params| {
                // Switch to text creation tool
                self.current_tool = .text_creation;

                // If we're already editing, finish the current text first
                if (self.text_edit.is_editing) {
                    self.text_edit.finishEditing();
                }

                // Clear selection - editing mode is separate from selection mode
                self.selection.clear();

                // Convert screen position to world position for new edit
                const screen_pos = Vec2{ .x = edit_params.screen_x, .y = edit_params.screen_y };
                self.text_edit.startEditing(cam.screenToWorld(screen_pos));
            },

            .end_text_edit => {
                self.text_edit.finishEditing();

                // Switch back to selection tool
                self.current_tool = .selection;
            },

            .select_element => |sel| {
                if (sel.toggle) {
                    // Shift+click: toggle selection
                    self.selection.toggle(sel.element_id);
                } else {
                    // Normal click: replace selection with this element
                    self.selection.selectOnly(sel.element_id);
                }
            },

            .deselect_all => {
                self.selection.clear();
            },

            .begin_drag_element => |drag| {
                if (self.selection.primary()) |elem_id| {
                    self.drag.is_dragging = true;
                    self.drag.element_id = elem_id;
                    const screen_pos = Vec2{ .x = drag.screen_x, .y = drag.screen_y };
                    self.drag.start_world_pos = cam.screenToWorld(screen_pos);
                    // element_start_pos will be set in main.zig with actual element data
                }
            },

            .drag_element => {
                // Actual position update happens in main.zig with scene graph access
            },

            .end_drag_element => {
                self.drag.is_dragging = false;
            },

            .begin_resize_element => |resize| {
                if (self.selection.primary()) |elem_id| {
                    self.resize.is_resizing = true;
                    self.resize.element_id = elem_id;
                    self.resize.handle = resize.handle;
                    const screen_pos = Vec2{ .x = resize.screen_x, .y = resize.screen_y };
                    self.resize.start_world_pos = cam.screenToWorld(screen_pos);
                    // element_start_pos, scale, and font_size will be set in main.zig
                }
            },

            .resize_element => {
                // Actual resize update happens in main.zig with scene graph access
            },

            .end_resize_element => {
                self.resize.is_resizing = false;
            },
        }

        return false;
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "SelectionSet.init is empty" {
    const set = SelectionSet{};
    try testing.expect(set.isEmpty());
    try testing.expectEqual(@as(usize, 0), set.len());
    try testing.expectEqual(@as(?u32, null), set.primary());
    try testing.expectEqual(@as(usize, 0), set.items().len);
}

test "SelectionSet.add adds element" {
    var set = SelectionSet{};
    set.add(42);

    try testing.expect(!set.isEmpty());
    try testing.expectEqual(@as(usize, 1), set.len());
    try testing.expect(set.contains(42));
    try testing.expectEqual(@as(?u32, 42), set.primary());
}

test "SelectionSet.add ignores duplicates" {
    var set = SelectionSet{};
    set.add(42);
    set.add(42);
    set.add(42);

    try testing.expectEqual(@as(usize, 1), set.len());
}

test "SelectionSet.add multiple elements" {
    var set = SelectionSet{};
    set.add(1);
    set.add(2);
    set.add(3);

    try testing.expectEqual(@as(usize, 3), set.len());
    try testing.expect(set.contains(1));
    try testing.expect(set.contains(2));
    try testing.expect(set.contains(3));
    try testing.expect(!set.contains(4));
    try testing.expectEqual(@as(?u32, 1), set.primary());
}

test "SelectionSet.remove removes element" {
    var set = SelectionSet{};
    set.add(1);
    set.add(2);
    set.add(3);

    set.remove(2);

    try testing.expectEqual(@as(usize, 2), set.len());
    try testing.expect(set.contains(1));
    try testing.expect(!set.contains(2));
    try testing.expect(set.contains(3));
}

test "SelectionSet.remove non-existent element does nothing" {
    var set = SelectionSet{};
    set.add(1);
    set.add(2);

    set.remove(99);

    try testing.expectEqual(@as(usize, 2), set.len());
}

test "SelectionSet.remove last element" {
    var set = SelectionSet{};
    set.add(42);
    set.remove(42);

    try testing.expect(set.isEmpty());
    try testing.expectEqual(@as(?u32, null), set.primary());
}

test "SelectionSet.toggle adds when not present" {
    var set = SelectionSet{};
    set.toggle(42);

    try testing.expect(set.contains(42));
    try testing.expectEqual(@as(usize, 1), set.len());
}

test "SelectionSet.toggle removes when present" {
    var set = SelectionSet{};
    set.add(42);
    set.toggle(42);

    try testing.expect(!set.contains(42));
    try testing.expect(set.isEmpty());
}

test "SelectionSet.toggle twice restores state" {
    var set = SelectionSet{};
    set.add(42);
    set.toggle(42);
    set.toggle(42);

    try testing.expect(set.contains(42));
    try testing.expectEqual(@as(usize, 1), set.len());
}

test "SelectionSet.clear removes all elements" {
    var set = SelectionSet{};
    set.add(1);
    set.add(2);
    set.add(3);

    set.clear();

    try testing.expect(set.isEmpty());
    try testing.expectEqual(@as(usize, 0), set.len());
    try testing.expect(!set.contains(1));
    try testing.expect(!set.contains(2));
    try testing.expect(!set.contains(3));
}

test "SelectionSet.selectOnly replaces selection" {
    var set = SelectionSet{};
    set.add(1);
    set.add(2);
    set.add(3);

    set.selectOnly(99);

    try testing.expectEqual(@as(usize, 1), set.len());
    try testing.expect(!set.contains(1));
    try testing.expect(!set.contains(2));
    try testing.expect(!set.contains(3));
    try testing.expect(set.contains(99));
    try testing.expectEqual(@as(?u32, 99), set.primary());
}

test "SelectionSet.selectOnly on empty set" {
    var set = SelectionSet{};
    set.selectOnly(42);

    try testing.expectEqual(@as(usize, 1), set.len());
    try testing.expect(set.contains(42));
}

test "SelectionSet.items returns correct slice" {
    var set = SelectionSet{};
    set.add(10);
    set.add(20);
    set.add(30);

    const items = set.items();
    try testing.expectEqual(@as(usize, 3), items.len);

    // Check all items are present (order may vary due to swap-remove)
    var found_10 = false;
    var found_20 = false;
    var found_30 = false;
    for (items) |id| {
        if (id == 10) found_10 = true;
        if (id == 20) found_20 = true;
        if (id == 30) found_30 = true;
    }
    try testing.expect(found_10);
    try testing.expect(found_20);
    try testing.expect(found_30);
}

test "SelectionSet.primary returns first added element" {
    var set = SelectionSet{};
    set.add(100);
    set.add(200);
    set.add(300);

    try testing.expectEqual(@as(?u32, 100), set.primary());
}

test "SelectionSet remove preserves other elements" {
    var set = SelectionSet{};
    set.add(1);
    set.add(2);
    set.add(3);
    set.add(4);
    set.add(5);

    set.remove(3);

    try testing.expectEqual(@as(usize, 4), set.len());
    try testing.expect(set.contains(1));
    try testing.expect(set.contains(2));
    try testing.expect(!set.contains(3));
    try testing.expect(set.contains(4));
    try testing.expect(set.contains(5));
}

// ============================================================================
// ElementDragState Tests
// ============================================================================

test "ElementDragState default initialization" {
    const state = ElementDragState{};

    try testing.expectEqual(@as(u32, 0), state.element_id);
    try testing.expectEqual(@as(f32, 0), state.start_pos.x);
    try testing.expectEqual(@as(f32, 0), state.start_pos.y);
    try testing.expectEqual(@as(f32, 0), state.start_bbox_x);
    try testing.expectEqual(@as(f32, 0), state.start_bbox_y);
}

test "ElementDragState custom initialization" {
    const state = ElementDragState{
        .element_id = 42,
        .start_pos = Vec2{ .x = 100, .y = 200 },
        .start_bbox_x = 50,
        .start_bbox_y = 75,
    };

    try testing.expectEqual(@as(u32, 42), state.element_id);
    try testing.expectEqual(@as(f32, 100), state.start_pos.x);
    try testing.expectEqual(@as(f32, 200), state.start_pos.y);
    try testing.expectEqual(@as(f32, 50), state.start_bbox_x);
    try testing.expectEqual(@as(f32, 75), state.start_bbox_y);
}

// ============================================================================
// ElementResizeState Tests
// ============================================================================

test "ElementResizeState default initialization" {
    const state = ElementResizeState{};

    try testing.expectEqual(@as(u32, 0), state.element_id);
    try testing.expectEqual(@as(f32, 0), state.start_pos.x);
    try testing.expectEqual(@as(f32, 0), state.start_pos.y);
    try testing.expectEqual(@as(f32, 0), state.start_bbox_x);
    try testing.expectEqual(@as(f32, 0), state.start_bbox_y);
    try testing.expectEqual(@as(f32, 0), state.start_bbox_w);
    try testing.expectEqual(@as(f32, 0), state.start_bbox_h);
    try testing.expectEqual(@as(f32, 16), state.start_font_size);
    try testing.expectEqual(@as(f32, 0), state.start_rect_width);
    try testing.expectEqual(@as(f32, 0), state.start_rect_height);
}

test "ElementResizeState for text element" {
    const state = ElementResizeState{
        .element_id = 1,
        .start_pos = Vec2{ .x = 100, .y = 150 },
        .start_bbox_x = 100,
        .start_bbox_y = 150,
        .start_bbox_w = 200,
        .start_bbox_h = 24,
        .start_font_size = 18,
        .start_rect_width = 0,
        .start_rect_height = 0,
    };

    try testing.expectEqual(@as(u32, 1), state.element_id);
    try testing.expectEqual(@as(f32, 18), state.start_font_size);
    // Text elements don't use rect dimensions
    try testing.expectEqual(@as(f32, 0), state.start_rect_width);
    try testing.expectEqual(@as(f32, 0), state.start_rect_height);
}

test "ElementResizeState for rectangle element" {
    const state = ElementResizeState{
        .element_id = 2,
        .start_pos = Vec2{ .x = 50, .y = 75 },
        .start_bbox_x = 50,
        .start_bbox_y = 75,
        .start_bbox_w = 120,
        .start_bbox_h = 80,
        .start_font_size = 16,
        .start_rect_width = 120,
        .start_rect_height = 80,
    };

    try testing.expectEqual(@as(u32, 2), state.element_id);
    // Rectangle elements use rect dimensions for non-proportional scaling
    try testing.expectEqual(@as(f32, 120), state.start_rect_width);
    try testing.expectEqual(@as(f32, 80), state.start_rect_height);
}

// ============================================================================
// DragState Tests
// ============================================================================

test "DragState default initialization" {
    const state = DragState{};

    try testing.expect(!state.is_dragging);
    try testing.expectEqual(@as(f32, 0), state.start_world_pos.x);
    try testing.expectEqual(@as(f32, 0), state.start_world_pos.y);
    try testing.expectEqual(@as(usize, 0), state.element_count);
    try testing.expect(!state.alt_held);
    try testing.expect(!state.has_moved);
    try testing.expect(!state.cloned);
}

test "DragState active drag" {
    var state = DragState{
        .is_dragging = true,
        .start_world_pos = Vec2{ .x = 500, .y = 300 },
        .element_count = 2,
    };
    state.element_states[0] = ElementDragState{
        .element_id = 1,
        .start_pos = Vec2{ .x = 100, .y = 100 },
    };
    state.element_states[1] = ElementDragState{
        .element_id = 2,
        .start_pos = Vec2{ .x = 200, .y = 150 },
    };

    try testing.expect(state.is_dragging);
    try testing.expectEqual(@as(usize, 2), state.element_count);
    try testing.expectEqual(@as(u32, 1), state.element_states[0].element_id);
    try testing.expectEqual(@as(u32, 2), state.element_states[1].element_id);
}

test "DragState alt+drag clone state" {
    var state = DragState{
        .is_dragging = true,
        .start_world_pos = Vec2{ .x = 100, .y = 100 },
        .alt_held = true,
        .has_moved = false,
        .cloned = false,
        .element_count = 1,
    };
    state.element_states[0] = ElementDragState{
        .element_id = 42,
        .start_pos = Vec2{ .x = 50, .y = 50 },
    };

    try testing.expect(state.is_dragging);
    try testing.expect(state.alt_held);
    try testing.expect(!state.has_moved);
    try testing.expect(!state.cloned);

    // Simulate clone operation
    state.has_moved = true;
    state.cloned = true;

    try testing.expect(state.has_moved);
    try testing.expect(state.cloned);
}

// ============================================================================
// ResizeState Tests
// ============================================================================

test "ResizeState default initialization" {
    const state = ResizeState{};

    try testing.expect(!state.is_resizing);
    try testing.expectEqual(ResizeHandle.top_left, state.handle);
    try testing.expectEqual(@as(f32, 0), state.start_world_pos.x);
    try testing.expectEqual(@as(f32, 0), state.start_world_pos.y);
    try testing.expectEqual(@as(usize, 0), state.element_count);
    try testing.expectEqual(@as(f32, 1.0), state.last_scale_factor);
}

test "ResizeState with union bbox" {
    const state = ResizeState{
        .is_resizing = true,
        .handle = .bottom_right,
        .union_start_min_x = 50,
        .union_start_min_y = 75,
        .union_start_max_x = 250,
        .union_start_max_y = 175,
        .element_count = 1,
    };

    try testing.expect(state.is_resizing);
    try testing.expectEqual(ResizeHandle.bottom_right, state.handle);
    // Union bbox dimensions
    const union_width = state.union_start_max_x - state.union_start_min_x;
    const union_height = state.union_start_max_y - state.union_start_min_y;
    try testing.expectEqual(@as(f32, 200), union_width);
    try testing.expectEqual(@as(f32, 100), union_height);
}

test "ResizeState multi-element resize" {
    var state = ResizeState{
        .is_resizing = true,
        .handle = .top_left,
        .opposite_corner = Vec2{ .x = 300, .y = 200 },
        .element_count = 3,
    };
    state.element_states[0] = ElementResizeState{
        .element_id = 1,
        .start_bbox_w = 100,
        .start_bbox_h = 50,
        .start_font_size = 16,
    };
    state.element_states[1] = ElementResizeState{
        .element_id = 2,
        .start_bbox_w = 80,
        .start_bbox_h = 60,
        .start_rect_width = 80,
        .start_rect_height = 60,
    };
    state.element_states[2] = ElementResizeState{
        .element_id = 3,
        .start_bbox_w = 120,
        .start_bbox_h = 40,
        .start_font_size = 24,
    };

    try testing.expectEqual(@as(usize, 3), state.element_count);
    try testing.expectEqual(@as(f32, 300), state.opposite_corner.x);
    try testing.expectEqual(@as(f32, 200), state.opposite_corner.y);
    // Verify per-element state
    try testing.expectEqual(@as(f32, 16), state.element_states[0].start_font_size);
    try testing.expectEqual(@as(f32, 80), state.element_states[1].start_rect_width);
    try testing.expectEqual(@as(f32, 24), state.element_states[2].start_font_size);
}

// ============================================================================
// DragSelectState Tests
// ============================================================================

test "DragSelectState default initialization" {
    const state = DragSelectState{};

    try testing.expect(!state.is_active);
    try testing.expectEqual(@as(f32, 0), state.start_world.x);
    try testing.expectEqual(@as(f32, 0), state.start_world.y);
    try testing.expectEqual(@as(f32, 0), state.current_world.x);
    try testing.expectEqual(@as(f32, 0), state.current_world.y);
}

test "DragSelectState.getBounds normalizes coordinates" {
    // Drag from top-right to bottom-left
    var state = DragSelectState{
        .is_active = true,
        .start_world = Vec2{ .x = 100, .y = 200 },
        .current_world = Vec2{ .x = 50, .y = 100 },
    };

    const bounds = state.getBounds();

    // Should normalize to min/max regardless of drag direction
    try testing.expectEqual(@as(f32, 50), bounds.min_x);
    try testing.expectEqual(@as(f32, 100), bounds.min_y);
    try testing.expectEqual(@as(f32, 100), bounds.max_x);
    try testing.expectEqual(@as(f32, 200), bounds.max_y);
}

test "DragSelectState.getBounds with normal drag direction" {
    // Drag from top-left to bottom-right
    var state = DragSelectState{
        .is_active = true,
        .start_world = Vec2{ .x = 10, .y = 20 },
        .current_world = Vec2{ .x = 100, .y = 200 },
    };

    const bounds = state.getBounds();

    try testing.expectEqual(@as(f32, 10), bounds.min_x);
    try testing.expectEqual(@as(f32, 20), bounds.min_y);
    try testing.expectEqual(@as(f32, 100), bounds.max_x);
    try testing.expectEqual(@as(f32, 200), bounds.max_y);
}
