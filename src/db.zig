const std = @import("std");
const scene_mod = @import("scene.zig");
const math = @import("math.zig");
const camera_mod = @import("camera.zig");
const color_scheme = @import("color_scheme.zig");
const sdl = @import("sdl.zig");
const c = sdl.c;

const sqlite = @cImport(@cInclude("sqlite3.h"));

const SceneGraph = scene_mod.SceneGraph;
const Vec2 = math.Vec2;
const Camera = camera_mod.Camera;
const SchemeType = color_scheme.SchemeType;

const SCHEMA_VERSION: i32 = 1;

pub const Database = struct {
    db: *sqlite.sqlite3,

    pub fn openOrCreate(path: [*:0]const u8) !Database {
        var db_ptr: ?*sqlite.sqlite3 = null;
        const rc = sqlite.sqlite3_open(path, &db_ptr);
        if (rc != sqlite.SQLITE_OK or db_ptr == null) {
            if (db_ptr) |p| _ = sqlite.sqlite3_close(p);
            return error.SqliteOpenFailed;
        }
        var self = Database{ .db = db_ptr.? };
        try self.ensureSchema();
        return self;
    }

    pub fn close(self: *Database) void {
        _ = sqlite.sqlite3_close(self.db);
    }

    fn ensureSchema(self: *Database) !void {
        // Check if schema_version table exists
        const check_sql = "SELECT version FROM schema_version LIMIT 1";
        var stmt: ?*sqlite.sqlite3_stmt = null;
        var rc = sqlite.sqlite3_prepare_v2(self.db, check_sql, -1, &stmt, null);
        if (rc == sqlite.SQLITE_OK) {
            defer _ = sqlite.sqlite3_finalize(stmt);
            rc = sqlite.sqlite3_step(stmt.?);
            if (rc == sqlite.SQLITE_ROW) {
                // Schema exists, check version
                const version = sqlite.sqlite3_column_int(stmt.?, 0);
                if (version != SCHEMA_VERSION) {
                    return error.UnsupportedSchemaVersion;
                }
                return; // Schema is valid
            }
        }

        // Create schema from scratch
        const create_sql =
            \\CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL);
            \\INSERT INTO schema_version VALUES (1);
            \\
            \\CREATE TABLE IF NOT EXISTS camera (
            \\    position_x REAL NOT NULL,
            \\    position_y REAL NOT NULL,
            \\    zoom REAL NOT NULL
            \\);
            \\
            \\CREATE TABLE IF NOT EXISTS settings (
            \\    key TEXT PRIMARY KEY,
            \\    value TEXT NOT NULL
            \\);
            \\
            \\CREATE TABLE IF NOT EXISTS elements (
            \\    sort_order INTEGER NOT NULL,
            \\    id INTEGER PRIMARY KEY,
            \\    type TEXT NOT NULL,
            \\    position_x REAL NOT NULL,
            \\    position_y REAL NOT NULL,
            \\    rotation REAL NOT NULL,
            \\    scale_x REAL NOT NULL,
            \\    scale_y REAL NOT NULL,
            \\    visible INTEGER NOT NULL,
            \\    color_r INTEGER, color_g INTEGER, color_b INTEGER, color_a INTEGER,
            \\    text_content TEXT,
            \\    font_size REAL,
            \\    rect_width REAL,
            \\    rect_height REAL,
            \\    border_thickness REAL,
            \\    end_offset_x REAL, end_offset_y REAL,
            \\    mid_offset_x REAL, mid_offset_y REAL,
            \\    has_midpoint INTEGER,
            \\    arrow_thickness REAL,
            \\    arrowhead_size REAL,
            \\    image_blob_id INTEGER
            \\);
            \\
            \\CREATE TABLE IF NOT EXISTS image_blobs (
            \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\    original_filename TEXT NOT NULL,
            \\    data BLOB NOT NULL
            \\);
        ;
        try self.exec(create_sql);
    }

    fn exec(self: *Database, sql: [*:0]const u8) !void {
        var err_msg: [*c]u8 = null;
        const rc = sqlite.sqlite3_exec(self.db, sql, null, null, &err_msg);
        if (err_msg != null) {
            sqlite.sqlite3_free(@ptrCast(err_msg));
        }
        if (rc != sqlite.SQLITE_OK) return error.SqliteExecFailed;
    }

    fn prepare(self: *Database, sql: [*:0]const u8) !*sqlite.sqlite3_stmt {
        var stmt: ?*sqlite.sqlite3_stmt = null;
        const rc = sqlite.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
        if (rc != sqlite.SQLITE_OK or stmt == null) return error.SqlitePrepareFailed;
        return stmt.?;
    }

    pub fn saveScene(
        self: *Database,
        scene: *SceneGraph,
        cam: *const Camera,
        scheme_type: SchemeType,
    ) !void {
        try self.exec("BEGIN TRANSACTION");
        errdefer self.exec("ROLLBACK") catch {};

        // Clear all tables
        try self.exec("DELETE FROM elements");
        try self.exec("DELETE FROM image_blobs");
        try self.exec("DELETE FROM camera");
        try self.exec("DELETE FROM settings");

        // Save camera
        {
            const stmt = try self.prepare(
                "INSERT INTO camera (position_x, position_y, zoom) VALUES (?, ?, ?)",
            );
            defer _ = sqlite.sqlite3_finalize(stmt);
            _ = sqlite.sqlite3_bind_double(stmt, 1, @floatCast(cam.position.x));
            _ = sqlite.sqlite3_bind_double(stmt, 2, @floatCast(cam.position.y));
            _ = sqlite.sqlite3_bind_double(stmt, 3, @floatCast(cam.zoom));
            _ = sqlite.sqlite3_step(stmt);
        }

        // Save color scheme
        {
            const stmt = try self.prepare(
                "INSERT INTO settings (key, value) VALUES ('color_scheme', ?)",
            );
            defer _ = sqlite.sqlite3_finalize(stmt);
            const scheme_str: [*:0]const u8 = if (scheme_type == .dark) "dark" else "light";
            _ = sqlite.sqlite3_bind_text(stmt, 1, scheme_str, -1, null);
            _ = sqlite.sqlite3_step(stmt);
        }

        // Save elements
        const insert_sql =
            \\INSERT INTO elements (
            \\    sort_order, id, type, position_x, position_y, rotation, scale_x, scale_y, visible,
            \\    color_r, color_g, color_b, color_a,
            \\    text_content, font_size,
            \\    rect_width, rect_height, border_thickness,
            \\    end_offset_x, end_offset_y, mid_offset_x, mid_offset_y,
            \\    has_midpoint, arrow_thickness, arrowhead_size,
            \\    image_blob_id
            \\) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ;

        const blob_sql = "INSERT INTO image_blobs (original_filename, data) VALUES (?, ?)";

        var sort_order: i32 = 0;
        for (scene.elements.items) |*elem| {
            // Only save world-space elements
            if (elem.space != .world) continue;

            const stmt = try self.prepare(insert_sql);
            defer _ = sqlite.sqlite3_finalize(stmt);

            _ = sqlite.sqlite3_bind_int(stmt, 1, sort_order);
            _ = sqlite.sqlite3_bind_int(stmt, 2, @intCast(elem.id));

            const type_str: [*:0]const u8 = switch (elem.element_type) {
                .text_label => "text_label",
                .rectangle => "rectangle",
                .image => "image",
                .arrow => "arrow",
            };
            _ = sqlite.sqlite3_bind_text(stmt, 3, type_str, -1, null);

            _ = sqlite.sqlite3_bind_double(stmt, 4, @floatCast(elem.transform.position.x));
            _ = sqlite.sqlite3_bind_double(stmt, 5, @floatCast(elem.transform.position.y));
            _ = sqlite.sqlite3_bind_double(stmt, 6, @floatCast(elem.transform.rotation));
            _ = sqlite.sqlite3_bind_double(stmt, 7, @floatCast(elem.transform.scale.x));
            _ = sqlite.sqlite3_bind_double(stmt, 8, @floatCast(elem.transform.scale.y));
            _ = sqlite.sqlite3_bind_int(stmt, 9, if (elem.visible) 1 else 0);

            // Type-specific fields
            switch (elem.element_type) {
                .text_label => {
                    const label = &elem.data.text_label;
                    _ = sqlite.sqlite3_bind_int(stmt, 10, @intCast(label.color.r));
                    _ = sqlite.sqlite3_bind_int(stmt, 11, @intCast(label.color.g));
                    _ = sqlite.sqlite3_bind_int(stmt, 12, @intCast(label.color.b));
                    _ = sqlite.sqlite3_bind_int(stmt, 13, @intCast(label.color.a));
                    _ = sqlite.sqlite3_bind_text(stmt, 14, @ptrCast(label.text.ptr), @intCast(label.text.len), null);
                    _ = sqlite.sqlite3_bind_double(stmt, 15, @floatCast(label.font_size));
                },
                .rectangle => {
                    const rect = &elem.data.rectangle;
                    _ = sqlite.sqlite3_bind_int(stmt, 10, @intCast(rect.color.r));
                    _ = sqlite.sqlite3_bind_int(stmt, 11, @intCast(rect.color.g));
                    _ = sqlite.sqlite3_bind_int(stmt, 12, @intCast(rect.color.b));
                    _ = sqlite.sqlite3_bind_int(stmt, 13, @intCast(rect.color.a));
                    _ = sqlite.sqlite3_bind_double(stmt, 16, @floatCast(rect.width));
                    _ = sqlite.sqlite3_bind_double(stmt, 17, @floatCast(rect.height));
                    _ = sqlite.sqlite3_bind_double(stmt, 18, @floatCast(rect.border_thickness));
                },
                .arrow => {
                    const arw = &elem.data.arrow;
                    _ = sqlite.sqlite3_bind_int(stmt, 10, @intCast(arw.color.r));
                    _ = sqlite.sqlite3_bind_int(stmt, 11, @intCast(arw.color.g));
                    _ = sqlite.sqlite3_bind_int(stmt, 12, @intCast(arw.color.b));
                    _ = sqlite.sqlite3_bind_int(stmt, 13, @intCast(arw.color.a));
                    _ = sqlite.sqlite3_bind_double(stmt, 19, @floatCast(arw.end_offset.x));
                    _ = sqlite.sqlite3_bind_double(stmt, 20, @floatCast(arw.end_offset.y));
                    _ = sqlite.sqlite3_bind_double(stmt, 21, @floatCast(arw.mid_offset.x));
                    _ = sqlite.sqlite3_bind_double(stmt, 22, @floatCast(arw.mid_offset.y));
                    _ = sqlite.sqlite3_bind_int(stmt, 23, if (arw.has_midpoint) 1 else 0);
                    _ = sqlite.sqlite3_bind_double(stmt, 24, @floatCast(arw.thickness));
                    _ = sqlite.sqlite3_bind_double(stmt, 25, @floatCast(arw.arrowhead_size));
                },
                .image => {
                    const img = &elem.data.image;

                    // Insert image blob first
                    const blob_stmt = try self.prepare(blob_sql);
                    defer _ = sqlite.sqlite3_finalize(blob_stmt);
                    _ = sqlite.sqlite3_bind_text(blob_stmt, 1, @ptrCast(img.original_filename.ptr), @intCast(img.original_filename.len), null);
                    _ = sqlite.sqlite3_bind_blob(blob_stmt, 2, @ptrCast(img.file_data.ptr), @intCast(img.file_data.len), null);
                    _ = sqlite.sqlite3_step(blob_stmt);

                    const blob_id = sqlite.sqlite3_last_insert_rowid(self.db);
                    _ = sqlite.sqlite3_bind_int64(stmt, 26, blob_id);
                    // Image dimensions stored as rect_width/rect_height
                    _ = sqlite.sqlite3_bind_double(stmt, 16, @floatCast(img.width));
                    _ = sqlite.sqlite3_bind_double(stmt, 17, @floatCast(img.height));
                },
            }

            _ = sqlite.sqlite3_step(stmt);
            sort_order += 1;
        }

        try self.exec("COMMIT");
    }

    pub fn loadScene(
        self: *Database,
        scene: *SceneGraph,
        cam: *Camera,
        renderer: *c.SDL_Renderer,
        alloc: std.mem.Allocator,
        font: ?*c.TTF_Font,
    ) !?SchemeType {
        // Load camera
        {
            const stmt = try self.prepare("SELECT position_x, position_y, zoom FROM camera LIMIT 1");
            defer _ = sqlite.sqlite3_finalize(stmt);
            if (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
                cam.position.x = @floatCast(sqlite.sqlite3_column_double(stmt, 0));
                cam.position.y = @floatCast(sqlite.sqlite3_column_double(stmt, 1));
                cam.zoom = @floatCast(sqlite.sqlite3_column_double(stmt, 2));
            }
        }

        // Load color scheme
        var scheme_type: ?SchemeType = null;
        {
            const stmt = try self.prepare("SELECT value FROM settings WHERE key = 'color_scheme'");
            defer _ = sqlite.sqlite3_finalize(stmt);
            if (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
                const val_ptr = sqlite.sqlite3_column_text(stmt, 0);
                if (val_ptr) |ptr| {
                    const val = std.mem.sliceTo(ptr, 0);
                    if (std.mem.eql(u8, val, "dark")) {
                        scheme_type = .dark;
                    } else {
                        scheme_type = .light;
                    }
                }
            }
        }

        // Load elements
        var max_id: u32 = 0;
        {
            const stmt = try self.prepare(
                \\SELECT id, type, position_x, position_y, rotation, scale_x, scale_y, visible,
                \\       color_r, color_g, color_b, color_a,
                \\       text_content, font_size,
                \\       rect_width, rect_height, border_thickness,
                \\       end_offset_x, end_offset_y, mid_offset_x, mid_offset_y,
                \\       has_midpoint, arrow_thickness, arrowhead_size,
                \\       image_blob_id
                \\FROM elements ORDER BY sort_order
            );
            defer _ = sqlite.sqlite3_finalize(stmt);

            while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
                const id: u32 = @intCast(sqlite.sqlite3_column_int(stmt, 0));
                if (id > max_id) max_id = id;

                const type_ptr = sqlite.sqlite3_column_text(stmt, 1) orelse continue;
                const elem_type = std.mem.sliceTo(type_ptr, 0);

                const pos_x: f32 = @floatCast(sqlite.sqlite3_column_double(stmt, 2));
                const pos_y: f32 = @floatCast(sqlite.sqlite3_column_double(stmt, 3));
                const position = Vec2{ .x = pos_x, .y = pos_y };
                const scale_x: f32 = @floatCast(sqlite.sqlite3_column_double(stmt, 5));
                const scale_y: f32 = @floatCast(sqlite.sqlite3_column_double(stmt, 6));

                const color_r: u8 = @intCast(sqlite.sqlite3_column_int(stmt, 8));
                const color_g: u8 = @intCast(sqlite.sqlite3_column_int(stmt, 9));
                const color_b: u8 = @intCast(sqlite.sqlite3_column_int(stmt, 10));
                const color_a: u8 = @intCast(sqlite.sqlite3_column_int(stmt, 11));
                const elem_color = c.SDL_Color{ .r = color_r, .g = color_g, .b = color_b, .a = color_a };

                if (std.mem.eql(u8, elem_type, "text_label")) {
                    const text_ptr = sqlite.sqlite3_column_text(stmt, 12) orelse continue;
                    const text_len = sqlite.sqlite3_column_bytes(stmt, 12);
                    const text_slice: []const u8 = @as([*]const u8, @ptrCast(text_ptr))[0..@intCast(text_len)];
                    const font_size: f32 = @floatCast(sqlite.sqlite3_column_double(stmt, 13));

                    const new_id = try scene.addTextLabel(text_slice, position, font_size, elem_color, .world, font);

                    // Restore original ID, scale
                    if (scene.findElement(new_id)) |elem| {
                        elem.id = id;
                        elem.transform.scale = Vec2{ .x = scale_x, .y = scale_y };
                    }
                } else if (std.mem.eql(u8, elem_type, "rectangle")) {
                    const width: f32 = @floatCast(sqlite.sqlite3_column_double(stmt, 14));
                    const height: f32 = @floatCast(sqlite.sqlite3_column_double(stmt, 15));
                    const border: f32 = @floatCast(sqlite.sqlite3_column_double(stmt, 16));

                    const new_id = try scene.addRectangle(position, width, height, border, elem_color, .world);

                    if (scene.findElement(new_id)) |elem| {
                        elem.id = id;
                        elem.transform.scale = Vec2{ .x = scale_x, .y = scale_y };
                    }
                } else if (std.mem.eql(u8, elem_type, "arrow")) {
                    const end_x: f32 = @floatCast(sqlite.sqlite3_column_double(stmt, 17));
                    const end_y: f32 = @floatCast(sqlite.sqlite3_column_double(stmt, 18));
                    const mid_x: f32 = @floatCast(sqlite.sqlite3_column_double(stmt, 19));
                    const mid_y: f32 = @floatCast(sqlite.sqlite3_column_double(stmt, 20));
                    const has_mid = sqlite.sqlite3_column_int(stmt, 21) != 0;
                    const thickness: f32 = @floatCast(sqlite.sqlite3_column_double(stmt, 22));
                    const ah_size: f32 = @floatCast(sqlite.sqlite3_column_double(stmt, 23));

                    const new_id = try scene.addArrow(position, Vec2{ .x = end_x, .y = end_y }, thickness, ah_size, elem_color, .world);

                    if (scene.findElement(new_id)) |elem| {
                        elem.id = id;
                        elem.transform.scale = Vec2{ .x = scale_x, .y = scale_y };
                        elem.data.arrow.mid_offset = Vec2{ .x = mid_x, .y = mid_y };
                        elem.data.arrow.has_midpoint = has_mid;
                        if (font) |f| scene.updateElementBoundingBox(id, f);
                    }
                } else if (std.mem.eql(u8, elem_type, "image")) {
                    const blob_id = sqlite.sqlite3_column_int64(stmt, 24);
                    const img_w: f32 = @floatCast(sqlite.sqlite3_column_double(stmt, 14));
                    const img_h: f32 = @floatCast(sqlite.sqlite3_column_double(stmt, 15));

                    // Load image blob
                    const blob_stmt = try self.prepare("SELECT original_filename, data FROM image_blobs WHERE id = ?");
                    defer _ = sqlite.sqlite3_finalize(blob_stmt);
                    _ = sqlite.sqlite3_bind_int64(blob_stmt, 1, blob_id);

                    if (sqlite.sqlite3_step(blob_stmt) == sqlite.SQLITE_ROW) {
                        const fname_ptr = sqlite.sqlite3_column_text(blob_stmt, 0);
                        const fname_len = sqlite.sqlite3_column_bytes(blob_stmt, 0);
                        const blob_ptr = sqlite.sqlite3_column_blob(blob_stmt, 1);
                        const blob_len = sqlite.sqlite3_column_bytes(blob_stmt, 1);

                        if (blob_ptr != null and blob_len > 0) {
                            const blob_data: [*]const u8 = @ptrCast(blob_ptr.?);

                            // Create texture from blob
                            const rw = c.SDL_RWFromConstMem(@ptrCast(blob_data), @intCast(blob_len));
                            if (rw) |rwops| {
                                if (c.IMG_Load_RW(rwops, 1)) |surface| {
                                    defer c.SDL_FreeSurface(surface);
                                    if (c.SDL_CreateTextureFromSurface(renderer, surface)) |texture| {
                                        _ = c.SDL_SetTextureScaleMode(texture, c.SDL_ScaleModeLinear);
                                        _ = c.SDL_SetTextureBlendMode(texture, c.SDL_BLENDMODE_BLEND);

                                        // Copy blob data for persistence
                                        const file_data = try alloc.dupe(u8, blob_data[0..@intCast(blob_len)]);
                                        errdefer alloc.free(file_data);

                                        // Copy filename
                                        var filename: []const u8 = "";
                                        if (fname_ptr) |fp| {
                                            filename = try alloc.dupe(u8, @as([*]const u8, @ptrCast(fp))[0..@intCast(fname_len)]);
                                        } else {
                                            filename = try alloc.dupe(u8, "unknown");
                                        }

                                        scene.image_textures.append(alloc, texture) catch {
                                            c.SDL_DestroyTexture(texture);
                                            alloc.free(file_data);
                                            alloc.free(filename);
                                            continue;
                                        };

                                        const new_id = try scene.addImage(texture, position, img_w, img_h, file_data, filename, .world);

                                        if (scene.findElement(new_id)) |elem| {
                                            elem.id = id;
                                            elem.transform.scale = Vec2{ .x = scale_x, .y = scale_y };
                                            if (font) |f| scene.updateElementBoundingBox(new_id, f);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Restore next_id
        scene.next_id = max_id + 1;

        return scheme_type;
    }
};
