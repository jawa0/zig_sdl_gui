const std = @import("std");
const builtin = @import("builtin");

/// Attempt to read image data from the system clipboard.
/// Returns heap-allocated bytes (PNG or BMP format) suitable for IMG_Load_RW,
/// or null if no image is available.
/// Caller owns the returned memory and must free it with the same allocator.
pub fn getClipboardImageData(allocator: std.mem.Allocator) ?[]u8 {
    if (comptime builtin.os.tag == .windows) {
        return getClipboardImageWindows(allocator);
    } else if (comptime builtin.os.tag == .linux) {
        return getClipboardImageLinux(allocator);
    } else {
        return null; // macOS not supported
    }
}

// ============================================================================
// Windows implementation
// ============================================================================

const win = if (builtin.os.tag == .windows) @cImport({
    @cDefine("WIN32_LEAN_AND_MEAN", "1");
    @cInclude("windows.h");
}) else struct {};

const CF_DIB = 8;

fn getClipboardImageWindows(allocator: std.mem.Allocator) ?[]u8 {
    // Register PNG clipboard format (Chrome, Paint.NET, etc. place raw PNG bytes)
    const cf_png = win.RegisterClipboardFormatA("PNG");

    if (win.OpenClipboard(null) == 0) return null;
    defer _ = win.CloseClipboard();

    // Try PNG format first (preserves transparency, most common from browsers)
    if (cf_png != 0 and win.IsClipboardFormatAvailable(cf_png) != 0) {
        if (readClipboardFormat(allocator, cf_png)) |data| return data;
    }

    // Fall back to CF_DIB (always available when any image is on clipboard)
    if (win.IsClipboardFormatAvailable(CF_DIB) != 0) {
        return readClipboardDIB(allocator);
    }

    return null;
}

fn readClipboardFormat(allocator: std.mem.Allocator, format: c_uint) ?[]u8 {
    const handle = win.GetClipboardData(format) orelse return null;
    const size = win.GlobalSize(handle);
    if (size == 0) return null;

    const ptr: ?[*]const u8 = @ptrCast(win.GlobalLock(handle));
    if (ptr == null) return null;
    defer _ = win.GlobalUnlock(handle);

    const data = allocator.alloc(u8, size) catch return null;
    @memcpy(data, ptr.?[0..size]);
    return data;
}

fn readClipboardDIB(allocator: std.mem.Allocator) ?[]u8 {
    const handle = win.GetClipboardData(CF_DIB) orelse return null;
    const dib_size = win.GlobalSize(handle);
    if (dib_size == 0) return null;

    const dib_ptr: ?[*]const u8 = @ptrCast(win.GlobalLock(handle));
    if (dib_ptr == null) return null;
    defer _ = win.GlobalUnlock(handle);

    const dib_data = dib_ptr.?[0..dib_size];

    // Read biSize to determine header variant (typically 40 for BITMAPINFOHEADER)
    if (dib_size < 4) return null;
    const bi_size = std.mem.readInt(u32, dib_data[0..4], .little);

    // Calculate color table size
    var palette_size: usize = 0;
    if (dib_size >= bi_size) {
        // For BITMAPINFOHEADER (bi_size == 40), check biBitCount at offset 14
        if (bi_size >= 18) {
            const bit_count = std.mem.readInt(u16, dib_data[14..16], .little);
            if (bit_count <= 8) {
                // biClrUsed at offset 32
                var clr_used: u32 = 0;
                if (bi_size >= 36) {
                    clr_used = std.mem.readInt(u32, dib_data[32..36], .little);
                }
                if (clr_used == 0) {
                    clr_used = @as(u32, 1) << @intCast(bit_count);
                }
                palette_size = clr_used * 4;
            }
        }
    }

    // Construct BMP file: 14-byte BITMAPFILEHEADER + DIB data
    const bmp_header_size: usize = 14;
    const pixel_offset: u32 = @intCast(bmp_header_size + bi_size + palette_size);
    const file_size: u32 = @intCast(bmp_header_size + dib_size);

    const bmp = allocator.alloc(u8, bmp_header_size + dib_size) catch return null;

    // BITMAPFILEHEADER (14 bytes)
    bmp[0] = 'B';
    bmp[1] = 'M';
    std.mem.writeInt(u32, bmp[2..6], file_size, .little);
    std.mem.writeInt(u16, bmp[6..8], 0, .little); // reserved
    std.mem.writeInt(u16, bmp[8..10], 0, .little); // reserved
    std.mem.writeInt(u32, bmp[10..14], pixel_offset, .little);

    // Copy DIB data after header
    @memcpy(bmp[bmp_header_size..], dib_data);

    return bmp;
}

// ============================================================================
// Linux implementation
// ============================================================================

fn getClipboardImageLinux(allocator: std.mem.Allocator) ?[]u8 {
    // Try xclip first (works on X11 and WSLg)
    if (runClipboardCommand(allocator, &.{ "xclip", "-selection", "clipboard", "-target", "image/png", "-o" })) |data| {
        return data;
    }
    // Fall back to wl-paste for native Wayland
    if (runClipboardCommand(allocator, &.{ "wl-paste", "--type", "image/png" })) |data| {
        return data;
    }
    return null;
}

fn runClipboardCommand(allocator: std.mem.Allocator, argv: []const []const u8) ?[]u8 {
    var child = std.process.Child.init(argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    child.spawn() catch return null;

    // Read all stdout data (cap at 64MB to match drag-and-drop limit)
    const stdout_file = child.stdout.?;
    const data = stdout_file.readToEndAlloc(allocator, 64 * 1024 * 1024) catch {
        _ = child.wait() catch {};
        return null;
    };

    const term = child.wait() catch {
        allocator.free(data);
        return null;
    };

    // Check for successful exit
    switch (term) {
        .Exited => |code| {
            if (code != 0 or data.len == 0) {
                allocator.free(data);
                return null;
            }
            return data;
        },
        else => {
            allocator.free(data);
            return null;
        },
    }
}
