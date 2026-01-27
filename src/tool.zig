const std = @import("std");

/// Available tools in the application
pub const Tool = enum {
    selection,
    text_creation,
    text_placement, // After clicking Text button, waiting for click to place text
};
