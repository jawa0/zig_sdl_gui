const std = @import("std");
const action = @import("action.zig");
const camera = @import("camera.zig");
const math = @import("math.zig");
const color_scheme = @import("color_scheme.zig");
const tool = @import("tool.zig");

const Action = action.Action;
const ActionParams = action.ActionParams;
const Camera = camera.Camera;
const Vec2 = math.Vec2;
const SchemeType = color_scheme.SchemeType;
const Tool = tool.Tool;
const ResizeHandle = action.ResizeHandle;

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
    text_buffer: [1024]u8 = undefined,
    text_len: usize = 0,
    cursor_pos: usize = 0, // Character position in buffer

    /// Set when editing finishes with non-empty text that should be added to scene
    should_create_element: bool = false,
    finished_text_buffer: [1024]u8 = undefined,
    finished_text_len: usize = 0,
    finished_world_pos: Vec2 = Vec2{ .x = 0, .y = 0 },
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
                if (self.text_edit.is_editing and self.text_edit.text_len > 0) {
                    const text = self.text_edit.text_buffer[0..self.text_edit.text_len];

                    // Check if text is all whitespace
                    var has_non_whitespace = false;
                    for (text) |ch| {
                        if (ch != ' ' and ch != '\t' and ch != '\n' and ch != '\r') {
                            has_non_whitespace = true;
                            break;
                        }
                    }

                    if (has_non_whitespace) {
                        // Store the text for scene element creation
                        self.text_edit.should_create_element = true;
                        @memcpy(self.text_edit.finished_text_buffer[0..self.text_edit.text_len], text);
                        self.text_edit.finished_text_len = self.text_edit.text_len;
                        self.text_edit.finished_world_pos = self.text_edit.world_pos;
                    }
                }

                // Convert screen position to world position for new edit
                const screen_pos = Vec2{ .x = edit_params.screen_x, .y = edit_params.screen_y };
                self.text_edit.world_pos = cam.screenToWorld(screen_pos);
                self.text_edit.is_editing = true;
                self.text_edit.text_len = 0;
                self.text_edit.cursor_pos = 0;
            },

            .end_text_edit => {
                // Check if we have non-empty text to create
                if (self.text_edit.text_len > 0) {
                    const text = self.text_edit.text_buffer[0..self.text_edit.text_len];

                    // Check if text is all whitespace
                    var has_non_whitespace = false;
                    for (text) |ch| {
                        if (ch != ' ' and ch != '\t' and ch != '\n' and ch != '\r') {
                            has_non_whitespace = true;
                            break;
                        }
                    }

                    if (has_non_whitespace) {
                        // Store the text for scene element creation
                        self.text_edit.should_create_element = true;
                        @memcpy(self.text_edit.finished_text_buffer[0..self.text_edit.text_len], text);
                        self.text_edit.finished_text_len = self.text_edit.text_len;
                        self.text_edit.finished_world_pos = self.text_edit.world_pos;
                    }
                }

                self.text_edit.is_editing = false;

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
