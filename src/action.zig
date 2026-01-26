const std = @import("std");

/// User actions that can be performed in the application.
/// This enum provides an indirection layer between input events and application behavior,
/// enabling rebindable controls and future scripting support.
pub const Action = enum {
    quit,
    pan_move,
    zoom_in,
    zoom_out,
    toggle_color_scheme,
    toggle_grid,
    toggle_bounding_boxes,
    begin_text_edit,
    end_text_edit,
    select_element,
    deselect_all,
    // Future actions can be added here without changing input handling code
};

/// Parameters for actions that require additional data
pub const ActionParams = union(Action) {
    quit: void,
    pan_move: PanParams,
    zoom_in: ZoomParams,
    zoom_out: ZoomParams,
    toggle_color_scheme: void,
    toggle_grid: void,
    toggle_bounding_boxes: void,
    begin_text_edit: TextEditParams,
    end_text_edit: void,
    select_element: SelectParams,
    deselect_all: void,
};

pub const PanParams = struct {
    delta_x: f32,
    delta_y: f32,
};

pub const ZoomParams = struct {
    cursor_x: f32,
    cursor_y: f32,
    /// Zoom factor (positive = zoom in, negative = zoom out)
    delta: f32,
};

pub const TextEditParams = struct {
    /// Screen position where double-click occurred
    screen_x: f32,
    screen_y: f32,
};

pub const SelectParams = struct {
    /// Element ID to select
    element_id: u32,
};
