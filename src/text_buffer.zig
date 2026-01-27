const std = @import("std");

/// Maximum buffer size for text content
pub const MAX_BUFFER_SIZE: usize = 4096;

/// A text buffer with cursor support, similar to an Emacs buffer.
/// Supports insertion, deletion, and cursor movement operations.
/// Can be reused across different text editing controls.
pub const TextBuffer = struct {
    /// The text content
    content: [MAX_BUFFER_SIZE]u8 = undefined,
    /// Number of bytes in the buffer
    len: usize = 0,
    /// Cursor position (byte index, 0 = before first char)
    cursor: usize = 0,
    /// Whether text should wrap at a certain width (false = grow bounds)
    wrap: bool = false,
    /// Wrap width in characters (only used if wrap is true)
    wrap_width: usize = 80,

    /// Initialize an empty text buffer
    pub fn init() TextBuffer {
        return TextBuffer{};
    }

    /// Initialize with wrapping enabled
    pub fn initWithWrap(width: usize) TextBuffer {
        return TextBuffer{
            .wrap = true,
            .wrap_width = width,
        };
    }

    /// Clear the buffer
    pub fn clear(self: *TextBuffer) void {
        self.len = 0;
        self.cursor = 0;
    }

    /// Get the current text content as a slice
    pub fn getText(self: *const TextBuffer) []const u8 {
        return self.content[0..self.len];
    }

    /// Insert text at the current cursor position
    pub fn insert(self: *TextBuffer, text: []const u8) void {
        const space_available = MAX_BUFFER_SIZE - self.len;
        const to_insert = @min(text.len, space_available);
        if (to_insert == 0) return;

        // Shift existing content after cursor to make room
        if (self.cursor < self.len) {
            const tail_len = self.len - self.cursor;
            // Move from end to avoid overwriting
            var i: usize = tail_len;
            while (i > 0) {
                i -= 1;
                self.content[self.cursor + to_insert + i] = self.content[self.cursor + i];
            }
        }

        // Insert the new text
        @memcpy(self.content[self.cursor..][0..to_insert], text[0..to_insert]);
        self.len += to_insert;
        self.cursor += to_insert;
    }

    /// Insert a single character at cursor position
    pub fn insertChar(self: *TextBuffer, char: u8) void {
        if (self.len >= MAX_BUFFER_SIZE) return;

        // Shift existing content after cursor
        if (self.cursor < self.len) {
            var i: usize = self.len;
            while (i > self.cursor) {
                self.content[i] = self.content[i - 1];
                i -= 1;
            }
        }

        self.content[self.cursor] = char;
        self.len += 1;
        self.cursor += 1;
    }

    /// Delete character before cursor (backspace)
    pub fn deleteBackward(self: *TextBuffer) void {
        if (self.cursor == 0) return;

        // Shift content after cursor back by one
        if (self.cursor < self.len) {
            const tail_len = self.len - self.cursor;
            for (0..tail_len) |i| {
                self.content[self.cursor - 1 + i] = self.content[self.cursor + i];
            }
        }

        self.cursor -= 1;
        self.len -= 1;
    }

    /// Delete character at cursor (delete key)
    pub fn deleteForward(self: *TextBuffer) void {
        if (self.cursor >= self.len) return;

        // Shift content after cursor back by one
        const tail_len = self.len - self.cursor - 1;
        for (0..tail_len) |i| {
            self.content[self.cursor + i] = self.content[self.cursor + 1 + i];
        }

        self.len -= 1;
    }

    /// Move cursor forward one character
    pub fn cursorForward(self: *TextBuffer) void {
        if (self.cursor < self.len) {
            self.cursor += 1;
        }
    }

    /// Move cursor backward one character
    pub fn cursorBackward(self: *TextBuffer) void {
        if (self.cursor > 0) {
            self.cursor -= 1;
        }
    }

    /// Move cursor to the beginning of the buffer
    pub fn cursorToBufferStart(self: *TextBuffer) void {
        self.cursor = 0;
    }

    /// Move cursor to the end of the buffer
    pub fn cursorToBufferEnd(self: *TextBuffer) void {
        self.cursor = self.len;
    }

    /// Find the start of the current line (position after previous newline, or 0)
    fn findLineStart(self: *const TextBuffer) usize {
        if (self.cursor == 0) return 0;

        var pos = self.cursor;
        // If cursor is right after a newline, go back one more to find previous line
        if (pos > 0 and self.content[pos - 1] == '\n') {
            pos -= 1;
        }
        // Search backwards for newline
        while (pos > 0) {
            if (self.content[pos - 1] == '\n') {
                return pos;
            }
            pos -= 1;
        }
        return 0;
    }

    /// Find the end of the current line (position of newline, or len)
    fn findLineEnd(self: *const TextBuffer) usize {
        var pos = self.cursor;
        while (pos < self.len) {
            if (self.content[pos] == '\n') {
                return pos;
            }
            pos += 1;
        }
        return self.len;
    }

    /// Move cursor to the beginning of the current line
    pub fn cursorToLineStart(self: *TextBuffer) void {
        self.cursor = self.findLineStart();
    }

    /// Move cursor to the end of the current line
    pub fn cursorToLineEnd(self: *TextBuffer) void {
        self.cursor = self.findLineEnd();
    }

    /// Get the column position within the current line (0-indexed)
    pub fn getColumn(self: *const TextBuffer) usize {
        const line_start = self.findLineStartConst();
        return self.cursor - line_start;
    }

    /// Const version of findLineStart for use in const methods
    fn findLineStartConst(self: *const TextBuffer) usize {
        if (self.cursor == 0) return 0;

        var pos = self.cursor;
        if (pos > 0 and self.content[pos - 1] == '\n') {
            pos -= 1;
        }
        while (pos > 0) {
            if (self.content[pos - 1] == '\n') {
                return pos;
            }
            pos -= 1;
        }
        return 0;
    }

    /// Move cursor to the next line, trying to maintain column position
    pub fn cursorToNextLine(self: *TextBuffer) void {
        const current_col = self.getColumn();
        const line_end = self.findLineEnd();

        // If we're at the last line, do nothing
        if (line_end >= self.len) return;

        // Move past the newline to the start of next line
        const next_line_start = line_end + 1;

        // Find the end of the next line
        var next_line_end = next_line_start;
        while (next_line_end < self.len and self.content[next_line_end] != '\n') {
            next_line_end += 1;
        }

        // Calculate target position (same column or end of line if shorter)
        const next_line_len = next_line_end - next_line_start;
        const target_col = @min(current_col, next_line_len);
        self.cursor = next_line_start + target_col;
    }

    /// Move cursor to the previous line, trying to maintain column position
    pub fn cursorToPrevLine(self: *TextBuffer) void {
        const current_col = self.getColumn();
        const line_start = self.findLineStart();

        // If we're at the first line, do nothing
        if (line_start == 0) return;

        // Find the start of the previous line
        var prev_line_start: usize = 0;
        if (line_start > 1) {
            var pos = line_start - 2; // Skip the newline before current line
            while (pos > 0) {
                if (self.content[pos - 1] == '\n') {
                    prev_line_start = pos;
                    break;
                }
                pos -= 1;
            }
        }

        // Calculate the length of the previous line
        const prev_line_end = line_start - 1; // Position of the newline
        const prev_line_len = prev_line_end - prev_line_start;

        // Calculate target position (same column or end of line if shorter)
        const target_col = @min(current_col, prev_line_len);
        self.cursor = prev_line_start + target_col;
    }

    /// Get line and column numbers (1-indexed for display)
    pub fn getLineAndColumn(self: *const TextBuffer) struct { line: usize, column: usize } {
        var line: usize = 1;
        var col: usize = 1;

        for (0..self.cursor) |i| {
            if (self.content[i] == '\n') {
                line += 1;
                col = 1;
            } else {
                col += 1;
            }
        }

        return .{ .line = line, .column = col };
    }

    /// Count total number of lines in the buffer
    pub fn getLineCount(self: *const TextBuffer) usize {
        if (self.len == 0) return 1;

        var count: usize = 1;
        for (self.content[0..self.len]) |ch| {
            if (ch == '\n') count += 1;
        }
        return count;
    }

    /// Check if buffer has any non-whitespace content
    pub fn hasContent(self: *const TextBuffer) bool {
        for (self.content[0..self.len]) |ch| {
            if (!isWhitespace(ch)) {
                return true;
            }
        }
        return false;
    }

    /// Check if a character is whitespace
    fn isWhitespace(ch: u8) bool {
        return ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r';
    }

    /// Move cursor to the beginning of the next word
    /// Skips current word (if in one), then skips whitespace to find next word
    pub fn cursorToNextWord(self: *TextBuffer) void {
        const text = self.content[0..self.len];

        // Skip non-whitespace (current word)
        while (self.cursor < self.len and !isWhitespace(text[self.cursor])) {
            self.cursor += 1;
        }

        // Skip whitespace to find start of next word
        while (self.cursor < self.len and isWhitespace(text[self.cursor])) {
            self.cursor += 1;
        }
    }

    /// Move cursor to the beginning of the previous word
    /// If in a word, moves to its start. If at start or in whitespace, finds previous word.
    pub fn cursorToPrevWord(self: *TextBuffer) void {
        if (self.cursor == 0) return;

        const text = self.content[0..self.len];

        // Move back one to get off potential word boundary
        self.cursor -= 1;

        // Skip whitespace backwards
        while (self.cursor > 0 and isWhitespace(text[self.cursor])) {
            self.cursor -= 1;
        }

        // Skip non-whitespace backwards to find start of word
        while (self.cursor > 0 and !isWhitespace(text[self.cursor - 1])) {
            self.cursor -= 1;
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "TextBuffer.init creates empty buffer" {
    const buf = TextBuffer.init();
    try testing.expectEqual(@as(usize, 0), buf.len);
    try testing.expectEqual(@as(usize, 0), buf.cursor);
    try testing.expect(!buf.wrap);
}

test "TextBuffer.initWithWrap sets wrap options" {
    const buf = TextBuffer.initWithWrap(40);
    try testing.expect(buf.wrap);
    try testing.expectEqual(@as(usize, 40), buf.wrap_width);
}

test "TextBuffer.insert adds text at cursor" {
    var buf = TextBuffer.init();
    buf.insert("Hello");

    try testing.expectEqual(@as(usize, 5), buf.len);
    try testing.expectEqual(@as(usize, 5), buf.cursor);
    try testing.expectEqualStrings("Hello", buf.getText());
}

test "TextBuffer.insert at middle" {
    var buf = TextBuffer.init();
    buf.insert("Hello World");
    buf.cursor = 5; // Position after "Hello"
    buf.insert(" Beautiful");

    try testing.expectEqualStrings("Hello Beautiful World", buf.getText());
}

test "TextBuffer.insertChar works" {
    var buf = TextBuffer.init();
    buf.insertChar('H');
    buf.insertChar('i');

    try testing.expectEqualStrings("Hi", buf.getText());
    try testing.expectEqual(@as(usize, 2), buf.cursor);
}

test "TextBuffer.insertChar at middle" {
    var buf = TextBuffer.init();
    buf.insert("ac");
    buf.cursor = 1;
    buf.insertChar('b');

    try testing.expectEqualStrings("abc", buf.getText());
}

test "TextBuffer.deleteBackward removes character before cursor" {
    var buf = TextBuffer.init();
    buf.insert("Hello");
    buf.deleteBackward();

    try testing.expectEqualStrings("Hell", buf.getText());
    try testing.expectEqual(@as(usize, 4), buf.cursor);
}

test "TextBuffer.deleteBackward at middle" {
    var buf = TextBuffer.init();
    buf.insert("Hello");
    buf.cursor = 2;
    buf.deleteBackward();

    try testing.expectEqualStrings("Hllo", buf.getText());
    try testing.expectEqual(@as(usize, 1), buf.cursor);
}

test "TextBuffer.deleteBackward at start does nothing" {
    var buf = TextBuffer.init();
    buf.insert("Hello");
    buf.cursor = 0;
    buf.deleteBackward();

    try testing.expectEqualStrings("Hello", buf.getText());
    try testing.expectEqual(@as(usize, 0), buf.cursor);
}

test "TextBuffer.deleteForward removes character at cursor" {
    var buf = TextBuffer.init();
    buf.insert("Hello");
    buf.cursor = 0;
    buf.deleteForward();

    try testing.expectEqualStrings("ello", buf.getText());
    try testing.expectEqual(@as(usize, 0), buf.cursor);
}

test "TextBuffer.deleteForward at end does nothing" {
    var buf = TextBuffer.init();
    buf.insert("Hello");
    buf.deleteForward();

    try testing.expectEqualStrings("Hello", buf.getText());
    try testing.expectEqual(@as(usize, 5), buf.cursor);
}

test "TextBuffer.cursorForward and cursorBackward" {
    var buf = TextBuffer.init();
    buf.insert("Hello");
    buf.cursor = 2;

    buf.cursorForward();
    try testing.expectEqual(@as(usize, 3), buf.cursor);

    buf.cursorBackward();
    try testing.expectEqual(@as(usize, 2), buf.cursor);
}

test "TextBuffer.cursorForward at end does nothing" {
    var buf = TextBuffer.init();
    buf.insert("Hi");
    buf.cursorForward();

    try testing.expectEqual(@as(usize, 2), buf.cursor);
}

test "TextBuffer.cursorBackward at start does nothing" {
    var buf = TextBuffer.init();
    buf.insert("Hi");
    buf.cursor = 0;
    buf.cursorBackward();

    try testing.expectEqual(@as(usize, 0), buf.cursor);
}

test "TextBuffer.cursorToBufferStart and cursorToBufferEnd" {
    var buf = TextBuffer.init();
    buf.insert("Hello");
    buf.cursor = 2;

    buf.cursorToBufferStart();
    try testing.expectEqual(@as(usize, 0), buf.cursor);

    buf.cursorToBufferEnd();
    try testing.expectEqual(@as(usize, 5), buf.cursor);
}

test "TextBuffer.cursorToLineStart and cursorToLineEnd single line" {
    var buf = TextBuffer.init();
    buf.insert("Hello World");
    buf.cursor = 5;

    buf.cursorToLineStart();
    try testing.expectEqual(@as(usize, 0), buf.cursor);

    buf.cursorToLineEnd();
    try testing.expectEqual(@as(usize, 11), buf.cursor);
}

test "TextBuffer.cursorToLineStart and cursorToLineEnd multiline" {
    var buf = TextBuffer.init();
    buf.insert("Line1\nLine2\nLine3");
    buf.cursor = 8; // In the middle of "Line2"

    buf.cursorToLineStart();
    try testing.expectEqual(@as(usize, 6), buf.cursor);

    buf.cursorToLineEnd();
    try testing.expectEqual(@as(usize, 11), buf.cursor);
}

test "TextBuffer.cursorToNextLine maintains column" {
    var buf = TextBuffer.init();
    buf.insert("Hello\nWorld\nTest");
    buf.cursor = 2; // Position at "l" in "Hello"

    buf.cursorToNextLine();
    try testing.expectEqual(@as(usize, 8), buf.cursor); // "r" in "World"

    buf.cursorToNextLine();
    try testing.expectEqual(@as(usize, 14), buf.cursor); // "s" in "Test"
}

test "TextBuffer.cursorToNextLine shorter line" {
    var buf = TextBuffer.init();
    buf.insert("Hello\nHi\nWorld");
    buf.cursor = 4; // Position near end of "Hello"

    buf.cursorToNextLine();
    try testing.expectEqual(@as(usize, 8), buf.cursor); // End of "Hi"
}

test "TextBuffer.cursorToPrevLine maintains column" {
    var buf = TextBuffer.init();
    buf.insert("Hello\nWorld\nTest");
    buf.cursor = 14; // Position at "s" in "Test"

    buf.cursorToPrevLine();
    try testing.expectEqual(@as(usize, 8), buf.cursor); // "r" in "World"

    buf.cursorToPrevLine();
    try testing.expectEqual(@as(usize, 2), buf.cursor); // "l" in "Hello"
}

test "TextBuffer.cursorToPrevLine shorter line" {
    var buf = TextBuffer.init();
    buf.insert("Hi\nHello\nWorld");
    buf.cursor = 7; // Position near end of "Hello"

    buf.cursorToPrevLine();
    try testing.expectEqual(@as(usize, 2), buf.cursor); // End of "Hi"
}

test "TextBuffer.getLineAndColumn" {
    var buf = TextBuffer.init();
    buf.insert("Hello\nWorld");
    buf.cursor = 8;

    const pos = buf.getLineAndColumn();
    try testing.expectEqual(@as(usize, 2), pos.line);
    try testing.expectEqual(@as(usize, 3), pos.column);
}

test "TextBuffer.getLineCount" {
    var buf = TextBuffer.init();
    try testing.expectEqual(@as(usize, 1), buf.getLineCount());

    buf.insert("Hello");
    try testing.expectEqual(@as(usize, 1), buf.getLineCount());

    buf.insert("\nWorld");
    try testing.expectEqual(@as(usize, 2), buf.getLineCount());

    buf.insert("\nTest");
    try testing.expectEqual(@as(usize, 3), buf.getLineCount());
}

test "TextBuffer.hasContent" {
    var buf = TextBuffer.init();
    try testing.expect(!buf.hasContent());

    buf.insert("   ");
    try testing.expect(!buf.hasContent());

    buf.insert("a");
    try testing.expect(buf.hasContent());
}

test "TextBuffer.clear resets buffer" {
    var buf = TextBuffer.init();
    buf.insert("Hello World");
    buf.cursor = 5;

    buf.clear();

    try testing.expectEqual(@as(usize, 0), buf.len);
    try testing.expectEqual(@as(usize, 0), buf.cursor);
}

test "TextBuffer newline insertion" {
    var buf = TextBuffer.init();
    buf.insert("Hello");
    buf.insertChar('\n');
    buf.insert("World");

    try testing.expectEqualStrings("Hello\nWorld", buf.getText());
    try testing.expectEqual(@as(usize, 2), buf.getLineCount());
}

test "TextBuffer.cursorToNextWord basic" {
    var buf = TextBuffer.init();
    buf.insert("hello world test");
    buf.cursor = 0;

    buf.cursorToNextWord();
    try testing.expectEqual(@as(usize, 6), buf.cursor); // start of "world"

    buf.cursorToNextWord();
    try testing.expectEqual(@as(usize, 12), buf.cursor); // start of "test"

    buf.cursorToNextWord();
    try testing.expectEqual(@as(usize, 16), buf.cursor); // end of buffer
}

test "TextBuffer.cursorToNextWord from middle of word" {
    var buf = TextBuffer.init();
    buf.insert("hello world");
    buf.cursor = 2; // in middle of "hello"

    buf.cursorToNextWord();
    try testing.expectEqual(@as(usize, 6), buf.cursor); // start of "world"
}

test "TextBuffer.cursorToNextWord multiple spaces" {
    var buf = TextBuffer.init();
    buf.insert("hello   world");
    buf.cursor = 0;

    buf.cursorToNextWord();
    try testing.expectEqual(@as(usize, 8), buf.cursor); // start of "world"
}

test "TextBuffer.cursorToNextWord with newlines" {
    var buf = TextBuffer.init();
    buf.insert("hello\nworld");
    buf.cursor = 0;

    buf.cursorToNextWord();
    try testing.expectEqual(@as(usize, 6), buf.cursor); // start of "world"
}

test "TextBuffer.cursorToPrevWord basic" {
    var buf = TextBuffer.init();
    buf.insert("hello world test");
    buf.cursor = 16; // end of buffer

    buf.cursorToPrevWord();
    try testing.expectEqual(@as(usize, 12), buf.cursor); // start of "test"

    buf.cursorToPrevWord();
    try testing.expectEqual(@as(usize, 6), buf.cursor); // start of "world"

    buf.cursorToPrevWord();
    try testing.expectEqual(@as(usize, 0), buf.cursor); // start of "hello"
}

test "TextBuffer.cursorToPrevWord from middle of word" {
    var buf = TextBuffer.init();
    buf.insert("hello world");
    buf.cursor = 8; // middle of "world"

    buf.cursorToPrevWord();
    try testing.expectEqual(@as(usize, 6), buf.cursor); // start of "world"
}

test "TextBuffer.cursorToPrevWord multiple spaces" {
    var buf = TextBuffer.init();
    buf.insert("hello   world");
    buf.cursor = 13; // end of buffer

    buf.cursorToPrevWord();
    try testing.expectEqual(@as(usize, 8), buf.cursor); // start of "world"
}

test "TextBuffer.cursorToPrevWord at start does nothing" {
    var buf = TextBuffer.init();
    buf.insert("hello");
    buf.cursor = 0;

    buf.cursorToPrevWord();
    try testing.expectEqual(@as(usize, 0), buf.cursor);
}
