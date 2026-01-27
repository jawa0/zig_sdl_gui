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

/// Drag operation state
pub const DragState = struct {
    is_dragging: bool = false,
    element_id: u32 = 0,
    start_world_pos: Vec2 = Vec2{ .x = 0, .y = 0 },
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

/// Maximum number of elements that can be selected at once
const MAX_SELECTED: usize = 256;

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
    selected_ids: [MAX_SELECTED]u32 = undefined,
    selected_count: usize = 0,
    drag: DragState = DragState{},
    resize: ResizeState = ResizeState{},

    pub fn init() ActionHandler {
        return ActionHandler{};
    }

    /// Check if an element is selected
    pub fn isSelected(self: *const ActionHandler, element_id: u32) bool {
        for (self.selected_ids[0..self.selected_count]) |id| {
            if (id == element_id) return true;
        }
        return false;
    }

    /// Add an element to selection (if not already selected)
    pub fn addToSelection(self: *ActionHandler, element_id: u32) void {
        if (self.isSelected(element_id)) return;
        if (self.selected_count >= MAX_SELECTED) return;
        self.selected_ids[self.selected_count] = element_id;
        self.selected_count += 1;
    }

    /// Remove an element from selection
    pub fn removeFromSelection(self: *ActionHandler, element_id: u32) void {
        for (self.selected_ids[0..self.selected_count], 0..) |id, i| {
            if (id == element_id) {
                // Swap with last element and reduce count
                self.selected_ids[i] = self.selected_ids[self.selected_count - 1];
                self.selected_count -= 1;
                return;
            }
        }
    }

    /// Clear all selections
    pub fn clearSelection(self: *ActionHandler) void {
        self.selected_count = 0;
    }

    /// Get the primary selected element (first in selection, for single-element operations)
    pub fn getPrimarySelection(self: *const ActionHandler) ?u32 {
        if (self.selected_count == 0) return null;
        return self.selected_ids[0];
    }

    /// Get slice of all selected element IDs
    pub fn getSelectedIds(self: *const ActionHandler) []const u32 {
        return self.selected_ids[0..self.selected_count];
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
                    if (self.isSelected(sel.element_id)) {
                        self.removeFromSelection(sel.element_id);
                    } else {
                        self.addToSelection(sel.element_id);
                    }
                } else {
                    // Normal click: replace selection with this element
                    self.clearSelection();
                    self.addToSelection(sel.element_id);
                }
            },

            .deselect_all => {
                self.clearSelection();
            },

            .begin_drag_element => |drag| {
                if (self.getPrimarySelection()) |elem_id| {
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
                if (self.getPrimarySelection()) |elem_id| {
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
