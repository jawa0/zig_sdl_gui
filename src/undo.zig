const std = @import("std");
const scene_mod = @import("scene.zig");
const math = @import("math.zig");
const sdl = @import("sdl.zig");

const c = sdl.c;
const Vec2 = math.Vec2;
const Transform = math.Transform;
const Element = scene_mod.Element;
const ElementType = scene_mod.ElementType;
const CoordinateSpace = scene_mod.CoordinateSpace;
const BoundingBox = scene_mod.BoundingBox;
const SceneGraph = scene_mod.SceneGraph;
const TextLabel = scene_mod.TextLabel;
const Rectangle = scene_mod.Rectangle;
const Arrow = scene_mod.Arrow;
const Image = scene_mod.Image;

pub const MAX_HISTORY: usize = 50;

// ============================================================================
// Image data store — avoids duplicating large image blobs across snapshots
// ============================================================================

/// Stored image blob data, keyed by element ID in the UndoHistory's store.
pub const ImageBlobEntry = struct {
    file_data: []const u8,
    original_filename: []const u8,
    texture: *c.SDL_Texture,
};

// ============================================================================
// Element snapshot — value-type copy of an Element
// ============================================================================

pub const ElementSnapshot = struct {
    id: u32,
    element_type: ElementType,
    transform: Transform,
    space: CoordinateSpace,
    visible: bool,
    bounding_box: BoundingBox,
    data: ElementSnapshotData,
};

pub const ElementSnapshotData = union(ElementType) {
    text_label: TextSnapshotData,
    rectangle: RectSnapshotData,
    image: ImageSnapshotData,
    arrow: ArrowSnapshotData,
};

pub const TextSnapshotData = struct {
    text: []const u8, // Owned clone
    font_size: f32,
    color: c.SDL_Color,
};

pub const RectSnapshotData = struct {
    width: f32,
    height: f32,
    border_thickness: f32,
    color: c.SDL_Color,
};

pub const ArrowSnapshotData = struct {
    end_offset: Vec2,
    mid_offset: Vec2,
    has_midpoint: bool,
    thickness: f32,
    arrowhead_size: f32,
    color: c.SDL_Color,
};

pub const ImageSnapshotData = struct {
    blob_element_id: u32, // Key into image_data_store
    width: f32,
    height: f32,
};

// ============================================================================
// Scene snapshot — all world-space elements at a point in time
// ============================================================================

pub const SceneSnapshot = struct {
    elements: []ElementSnapshot,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *SceneSnapshot) void {
        for (self.elements) |*elem_snap| {
            switch (elem_snap.element_type) {
                .text_label => self.allocator.free(elem_snap.data.text_label.text),
                else => {},
            }
        }
        self.allocator.free(self.elements);
    }
};

// ============================================================================
// Undo history manager
// ============================================================================

pub const UndoHistory = struct {
    undo_stack: [MAX_HISTORY]?SceneSnapshot = [_]?SceneSnapshot{null} ** MAX_HISTORY,
    redo_stack: [MAX_HISTORY]?SceneSnapshot = [_]?SceneSnapshot{null} ** MAX_HISTORY,
    undo_count: usize = 0,
    redo_count: usize = 0,
    allocator: std.mem.Allocator,

    /// Persistent store for image blob data, keyed by element ID.
    /// Entries are never removed (freed on UndoHistory.deinit).
    image_data_store: std.AutoHashMap(u32, ImageBlobEntry),

    /// Tracks the highest next_id ever seen, to prevent ID reuse on restore.
    max_id_ever: u32 = 0,

    /// Pending snapshot for multi-frame operations (drag, resize, etc.).
    /// Captured at operation start, committed at operation end.
    pending_snapshot: ?SceneSnapshot = null,

    pub fn init(allocator: std.mem.Allocator) UndoHistory {
        return .{
            .allocator = allocator,
            .image_data_store = std.AutoHashMap(u32, ImageBlobEntry).init(allocator),
        };
    }

    pub fn deinit(self: *UndoHistory) void {
        for (&self.undo_stack) |*slot| {
            if (slot.*) |*snap| snap.deinit();
        }
        for (&self.redo_stack) |*slot| {
            if (slot.*) |*snap| snap.deinit();
        }
        if (self.pending_snapshot) |*snap| snap.deinit();

        // Free all image blob store entries
        var it = self.image_data_store.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.file_data);
            self.allocator.free(entry.value_ptr.original_filename);
        }
        self.image_data_store.deinit();
    }

    // ========================================================================
    // Snapshot capture
    // ========================================================================

    /// Capture a snapshot of all world-space elements in the scene.
    pub fn captureSnapshot(self: *UndoHistory, scene_graph: *const SceneGraph) !SceneSnapshot {
        // Track max ID
        self.max_id_ever = @max(self.max_id_ever, scene_graph.next_id);

        // Count world-space elements
        var count: usize = 0;
        for (scene_graph.elements.items) |*elem| {
            if (elem.space == .world) count += 1;
        }

        const snapshots = try self.allocator.alloc(ElementSnapshot, count);
        errdefer self.allocator.free(snapshots);

        var i: usize = 0;
        for (scene_graph.elements.items) |*elem| {
            if (elem.space != .world) continue;

            snapshots[i] = .{
                .id = elem.id,
                .element_type = elem.element_type,
                .transform = elem.transform,
                .space = elem.space,
                .visible = elem.visible,
                .bounding_box = elem.bounding_box,
                .data = switch (elem.element_type) {
                    .text_label => .{
                        .text_label = .{
                            .text = try self.allocator.dupe(u8, elem.data.text_label.text),
                            .font_size = elem.data.text_label.font_size,
                            .color = elem.data.text_label.color,
                        },
                    },
                    .rectangle => .{
                        .rectangle = .{
                            .width = elem.data.rectangle.width,
                            .height = elem.data.rectangle.height,
                            .border_thickness = elem.data.rectangle.border_thickness,
                            .color = elem.data.rectangle.color,
                        },
                    },
                    .arrow => .{
                        .arrow = .{
                            .end_offset = elem.data.arrow.end_offset,
                            .mid_offset = elem.data.arrow.mid_offset,
                            .has_midpoint = elem.data.arrow.has_midpoint,
                            .thickness = elem.data.arrow.thickness,
                            .arrowhead_size = elem.data.arrow.arrowhead_size,
                            .color = elem.data.arrow.color,
                        },
                    },
                    .image => blk: {
                        // Ensure image data is in the store
                        try self.ensureImageInStore(elem.id, &elem.data.image);
                        break :blk .{
                            .image = .{
                                .blob_element_id = elem.id,
                                .width = elem.data.image.width,
                                .height = elem.data.image.height,
                            },
                        };
                    },
                },
            };
            i += 1;
        }

        return .{
            .elements = snapshots,
            .allocator = self.allocator,
        };
    }

    /// Ensure an image element's blob data is in the store.
    fn ensureImageInStore(self: *UndoHistory, element_id: u32, img: *const Image) !void {
        if (self.image_data_store.contains(element_id)) return;
        try self.image_data_store.put(element_id, .{
            .file_data = try self.allocator.dupe(u8, img.file_data),
            .original_filename = try self.allocator.dupe(u8, img.original_filename),
            .texture = img.texture,
        });
    }

    // ========================================================================
    // Stack management
    // ========================================================================

    /// Push a snapshot onto the undo stack. Clears the redo stack.
    fn pushUndo(self: *UndoHistory, snapshot: SceneSnapshot) void {
        self.clearRedoStack();

        // If full, discard oldest entry and shift
        if (self.undo_count >= MAX_HISTORY) {
            if (self.undo_stack[0]) |*oldest| oldest.deinit();
            var j: usize = 0;
            while (j < MAX_HISTORY - 1) : (j += 1) {
                self.undo_stack[j] = self.undo_stack[j + 1];
            }
            self.undo_stack[MAX_HISTORY - 1] = null;
            self.undo_count -= 1;
        }

        self.undo_stack[self.undo_count] = snapshot;
        self.undo_count += 1;
    }

    fn clearRedoStack(self: *UndoHistory) void {
        for (&self.redo_stack) |*slot| {
            if (slot.*) |*snap| {
                snap.deinit();
                slot.* = null;
            }
        }
        self.redo_count = 0;
    }

    // ========================================================================
    // Multi-frame operation support
    // ========================================================================

    /// Begin a multi-frame operation. Captures scene state BEFORE the operation.
    /// If already in an operation, this is a no-op.
    pub fn beginOperation(self: *UndoHistory, scene_graph: *const SceneGraph) void {
        if (self.pending_snapshot != null) return;
        self.pending_snapshot = self.captureSnapshot(scene_graph) catch return;
    }

    /// End a multi-frame operation. Commits the pending snapshot to the undo stack.
    pub fn endOperation(self: *UndoHistory) void {
        if (self.pending_snapshot) |snap| {
            self.pushUndo(snap);
            self.pending_snapshot = null;
        }
    }

    /// Cancel a multi-frame operation without committing to the undo stack.
    pub fn cancelOperation(self: *UndoHistory) void {
        if (self.pending_snapshot) |*snap| {
            snap.deinit();
            self.pending_snapshot = null;
        }
    }

    // ========================================================================
    // Atomic operation support
    // ========================================================================

    /// Record the scene state before an atomic (single-frame) operation.
    /// Captures current state and pushes to undo stack, clears redo stack.
    pub fn recordAtomicBefore(self: *UndoHistory, scene_graph: *const SceneGraph) void {
        const snapshot = self.captureSnapshot(scene_graph) catch return;
        self.pushUndo(snapshot);
    }

    // ========================================================================
    // Undo / Redo
    // ========================================================================

    /// Perform undo: restore scene from top of undo stack, push current to redo.
    /// Returns true if undo was performed.
    pub fn undo(self: *UndoHistory, scene_graph: *SceneGraph) bool {
        if (self.undo_count == 0) return false;

        // Capture current state for redo
        const current = self.captureSnapshot(scene_graph) catch return false;

        // Push to redo stack
        if (self.redo_count < MAX_HISTORY) {
            self.redo_stack[self.redo_count] = current;
            self.redo_count += 1;
        } else {
            var tmp = current;
            tmp.deinit();
        }

        // Pop from undo stack
        self.undo_count -= 1;
        var snapshot = self.undo_stack[self.undo_count].?;
        self.undo_stack[self.undo_count] = null;

        // Restore scene
        self.restoreScene(scene_graph, &snapshot);
        snapshot.deinit();

        return true;
    }

    /// Perform redo: restore scene from top of redo stack, push current to undo.
    /// Returns true if redo was performed.
    pub fn redo(self: *UndoHistory, scene_graph: *SceneGraph) bool {
        if (self.redo_count == 0) return false;

        // Capture current state for undo (don't clear redo!)
        const current = self.captureSnapshot(scene_graph) catch return false;
        self.undo_stack[self.undo_count] = current;
        self.undo_count += 1;

        // Pop from redo stack
        self.redo_count -= 1;
        var snapshot = self.redo_stack[self.redo_count].?;
        self.redo_stack[self.redo_count] = null;

        // Restore scene
        self.restoreScene(scene_graph, &snapshot);
        snapshot.deinit();

        return true;
    }

    // ========================================================================
    // Scene restore
    // ========================================================================

    /// Replace all world-space elements with those from the snapshot.
    /// Screen-space elements (FPS counter, etc.) are preserved.
    fn restoreScene(self: *UndoHistory, scene_graph: *SceneGraph, snapshot: *const SceneSnapshot) void {
        // Remove all world-space elements
        var i: usize = 0;
        while (i < scene_graph.elements.items.len) {
            if (scene_graph.elements.items[i].space == .world) {
                scene_graph.elements.items[i].deinit(scene_graph.allocator);
                _ = scene_graph.elements.swapRemove(i);
            } else {
                i += 1;
            }
        }

        // Rebuild from snapshot
        for (snapshot.elements) |*elem_snap| {
            const element = self.elementFromSnapshot(scene_graph.allocator, elem_snap) catch continue;
            scene_graph.elements.append(scene_graph.allocator, element) catch continue;
        }

        // Set next_id to avoid collisions
        scene_graph.next_id = self.max_id_ever;
    }

    /// Reconstruct an Element from a snapshot.
    fn elementFromSnapshot(self: *const UndoHistory, allocator: std.mem.Allocator, snap: *const ElementSnapshot) !Element {
        var element = Element{
            .id = snap.id,
            .transform = snap.transform,
            .space = snap.space,
            .visible = snap.visible,
            .element_type = snap.element_type,
            .bounding_box = snap.bounding_box,
            .data = undefined,
        };

        switch (snap.element_type) {
            .text_label => {
                const td = &snap.data.text_label;
                element.data = .{
                    .text_label = try TextLabel.init(allocator, td.text, td.font_size, td.color),
                };
            },
            .rectangle => {
                const rd = &snap.data.rectangle;
                element.data = .{
                    .rectangle = Rectangle.init(rd.width, rd.height, rd.border_thickness, rd.color),
                };
            },
            .arrow => {
                const ad = &snap.data.arrow;
                element.data = .{
                    .arrow = Arrow{
                        .end_offset = ad.end_offset,
                        .mid_offset = ad.mid_offset,
                        .has_midpoint = ad.has_midpoint,
                        .thickness = ad.thickness,
                        .arrowhead_size = ad.arrowhead_size,
                        .color = ad.color,
                    },
                };
            },
            .image => {
                const id = &snap.data.image;
                const blob = self.image_data_store.get(id.blob_element_id) orelse return error.ImageBlobNotFound;
                const file_data_copy = try allocator.dupe(u8, blob.file_data);
                errdefer allocator.free(file_data_copy);
                const filename_copy = try allocator.dupe(u8, blob.original_filename);
                element.data = .{
                    .image = Image{
                        .texture = blob.texture,
                        .width = id.width,
                        .height = id.height,
                        .file_data = file_data_copy,
                        .original_filename = filename_copy,
                    },
                };
            },
        }

        return element;
    }

    pub fn canUndo(self: *const UndoHistory) bool {
        return self.undo_count > 0;
    }

    pub fn canRedo(self: *const UndoHistory) bool {
        return self.redo_count > 0;
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "UndoHistory init and deinit" {
    var history = UndoHistory.init(testing.allocator);
    defer history.deinit();

    try testing.expect(!history.canUndo());
    try testing.expect(!history.canRedo());
    try testing.expectEqual(@as(usize, 0), history.undo_count);
    try testing.expectEqual(@as(usize, 0), history.redo_count);
}

test "SceneSnapshot deinit frees text" {
    const allocator = testing.allocator;
    const text = try allocator.dupe(u8, "hello");

    var snap = SceneSnapshot{
        .elements = try allocator.alloc(ElementSnapshot, 1),
        .allocator = allocator,
    };
    snap.elements[0] = .{
        .id = 1,
        .element_type = .text_label,
        .transform = Transform.init(.{ .x = 0, .y = 0 }, 0, .{ .x = 1, .y = 1 }),
        .space = .world,
        .visible = true,
        .bounding_box = .{ .x = 0, .y = 0, .w = 10, .h = 10 },
        .data = .{
            .text_label = .{
                .text = text,
                .font_size = 16,
                .color = .{ .r = 0, .g = 0, .b = 0, .a = 255 },
            },
        },
    };

    snap.deinit(); // Should not leak
}

test "beginOperation and endOperation" {
    var history = UndoHistory.init(testing.allocator);
    defer history.deinit();

    // Simulate begin without a real scene graph — we test the pending_snapshot logic
    try testing.expectEqual(@as(?SceneSnapshot, null), history.pending_snapshot);

    // Create a fake empty snapshot manually
    history.pending_snapshot = SceneSnapshot{
        .elements = try testing.allocator.alloc(ElementSnapshot, 0),
        .allocator = testing.allocator,
    };

    try testing.expect(history.pending_snapshot != null);

    // endOperation pushes to undo stack
    history.endOperation();

    try testing.expectEqual(@as(?SceneSnapshot, null), history.pending_snapshot);
    try testing.expectEqual(@as(usize, 1), history.undo_count);
    try testing.expect(history.canUndo());
}

test "cancelOperation discards pending" {
    var history = UndoHistory.init(testing.allocator);
    defer history.deinit();

    history.pending_snapshot = SceneSnapshot{
        .elements = try testing.allocator.alloc(ElementSnapshot, 0),
        .allocator = testing.allocator,
    };

    history.cancelOperation();

    try testing.expectEqual(@as(?SceneSnapshot, null), history.pending_snapshot);
    try testing.expectEqual(@as(usize, 0), history.undo_count);
}

test "pushUndo clears redo stack" {
    var history = UndoHistory.init(testing.allocator);
    defer history.deinit();

    // Simulate a redo entry
    history.redo_stack[0] = SceneSnapshot{
        .elements = try testing.allocator.alloc(ElementSnapshot, 0),
        .allocator = testing.allocator,
    };
    history.redo_count = 1;

    // Push to undo should clear redo
    history.pushUndo(SceneSnapshot{
        .elements = try testing.allocator.alloc(ElementSnapshot, 0),
        .allocator = testing.allocator,
    });

    try testing.expectEqual(@as(usize, 1), history.undo_count);
    try testing.expectEqual(@as(usize, 0), history.redo_count);
}

test "undo stack overflow discards oldest" {
    var history = UndoHistory.init(testing.allocator);
    defer history.deinit();

    // Fill the undo stack
    for (0..MAX_HISTORY) |_| {
        history.pushUndo(SceneSnapshot{
            .elements = try testing.allocator.alloc(ElementSnapshot, 0),
            .allocator = testing.allocator,
        });
    }
    try testing.expectEqual(MAX_HISTORY, history.undo_count);

    // Push one more — should discard oldest
    history.pushUndo(SceneSnapshot{
        .elements = try testing.allocator.alloc(ElementSnapshot, 0),
        .allocator = testing.allocator,
    });
    try testing.expectEqual(MAX_HISTORY, history.undo_count);
}
