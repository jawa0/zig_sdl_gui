# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Working with Git

**IMPORTANT**: Do not commit changes until explicitly instructed by the user. Wait for the user to say "commit" or give similar explicit instruction before creating commits.

## Project Overview

A Zig application using SDL2 and SDL2_ttf to render a double-buffered window at 60fps with FPS counter. Supports Linux/WSL and native Windows. macOS support is currently broken.

## Build Commands

### Linux/WSL

```bash
# Required: Set cache directory on Linux filesystem (WSL issue with /mnt/c)
export ZIG_LOCAL_CACHE_DIR=/tmp/zig-cache
export PATH="$HOME/.local/zig:$PATH"

# Build and run
zig build run

# Build optimized release
zig build -Doptimize=ReleaseFast
```

### Native Windows

```cmd
zig build run
zig build -Doptimize=ReleaseFast
```

### macOS (Currently Broken)

```bash
# Install dependencies via Homebrew
brew install sdl2 sdl2_ttf

# Build and run (BROKEN - see Platform Notes)
zig build run

# Build optimized release
zig build -Doptimize=ReleaseFast
```

## Dependencies

- Zig 0.15.2 (Windows/Linux), Zig 0.16.0-dev (macOS - currently broken)
- SDL2:
  - Linux: `libsdl2-dev` via apt
  - macOS: `sdl2` via Homebrew (build currently broken)
  - Windows: bundled in `libs/SDL2/` (SDL2 2.30.10)
- SDL2_ttf:
  - Linux: `libsdl2-ttf-dev` via apt
  - macOS: `sdl2_ttf` via Homebrew (build currently broken)
  - Windows: bundled in `libs/SDL2_ttf/` (SDL2_ttf 2.22.0)
- JetBrains Mono font: bundled in `assets/fonts/`

## Architecture

- `build.zig` - Build configuration with cross-platform SDL2/SDL2_ttf linking (detects Windows, macOS, and Linux)
- `src/main.zig` - Main entry point with SDL2 render loop and FPS display using `@cImport` for C interop
- `src/tool.zig` - Tool system enum (Selection, TextCreation, TextPlacement, RectanglePlacement, ArrowPlacement)
- `src/text_buffer.zig` - Reusable text buffer with cursor support (like Emacs buffers)
- `src/button.zig` - Reusable UI button component with icon support
- `src/grid.zig` - Grid rendering system with recursive subdivision and zoom-based fading
- `src/math.zig` - Math utilities including Vec2, Transform, lerp, and clamp functions
- `src/action.zig` - Action enum and parameters for input indirection
- `src/action_handler.zig` - Processes actions and updates application state, tracks current tool and selection
- `src/input.zig` - Tool-aware input handling that returns actions instead of directly manipulating state
- `src/scene.zig` - Scene graph with hit testing and bounding box calculations
- `src/color_scheme.zig` - Light and dark color scheme definitions
- `libs/SDL2/` - Windows SDL2 libraries (headers, .lib, .dll)
- `libs/SDL2_ttf/` - Windows SDL2_ttf libraries (headers, .lib, .dll)
- `assets/fonts/` - JetBrains Mono font for text rendering
- `assets/icons/` - PNG icons for toolbar buttons

The app uses SDL2's hardware-accelerated renderer with vsync for double buffering. Frame timing is handled by vsync with a fallback delay loop. FPS is displayed in the top-right corner using SDL2_ttf.

## User Actions & Input System

### Tools

The application has four tools, accessible via the toolbar or keyboard:

1. **Selection Tool** - Select, move, resize, and clone elements
2. **Text Tool** - Click to place new text, enter text editing mode
3. **Rectangle Tool** - Click and drag to create rectangles
4. **Arrow Tool** - Click and drag to create arrows (start to end with arrowhead)
5. **Text Editing Mode** - Active when editing text (not a toolbar tool)

### Global Keybindings (All Platforms)

| Action | Keybinding | Notes |
|--------|------------|-------|
| Pan Canvas | Scroll wheel / Trackpad scroll | Moves the view |
| Zoom In/Out | Ctrl + Scroll | Zooms centered on cursor |
| Toggle Color Scheme | D | Light/dark mode (when not editing) |
| Toggle Grid | G | Show/hide grid (when not editing) |
| Toggle Bounding Boxes | B | Debug visualization (when not editing) |
| Cancel Tool | Escape | Returns to Selection tool |
| Close Window | Window close button | Exits application |

### Selection Tool

| Action | Input | Notes |
|--------|-------|-------|
| Select element | Click on element | Replaces selection |
| Add/remove from selection | Shift + Click | Toggle selection |
| Drag-select | Click + drag on empty canvas | Select elements in rectangle |
| Move element(s) | Drag selected element | Moves all selected |
| Clone element(s) | Alt + Drag | Creates copies on first move |
| Resize element(s) | Drag corner handles | Proportional scaling |
| Edit text | Double-click text element | Enters text editing mode |
| Create text | Double-click empty canvas | Creates new text at location |

### Text Tool (Text Placement Mode)

| Action | Input | Notes |
|--------|-------|-------|
| Place text | Click on canvas | Creates text and enters editing mode |
| Cancel | Escape | Returns to Selection tool |

### Rectangle Tool

| Action | Input | Notes |
|--------|-------|-------|
| Create rectangle | Click + drag | Draws rectangle from corner to corner |
| Cancel | Escape | Returns to Selection tool |

### Arrow Tool

| Action | Input | Notes |
|--------|-------|-------|
| Create arrow | Click + drag | Draws arrow from start to end with arrowhead |
| Cancel | Escape | Returns to Selection tool |

### Text Editing Mode

#### Basic Editing

| Action | Keybinding | Notes |
|--------|------------|-------|
| Type text | Any character key | Inserts at cursor |
| New line | Enter | Inserts line break |
| Delete backward | Backspace | Deletes character before cursor |
| Delete forward | Delete | Deletes character at cursor |
| Finish editing | Escape | Saves text, returns to Selection tool |
| Position cursor | Click within text | Moves cursor to click position |

#### Cursor Movement - All Platforms

| Action | Keybinding |
|--------|------------|
| Move left | Left Arrow |
| Move right | Right Arrow |
| Move up (previous line) | Up Arrow |
| Move down (next line) | Down Arrow |
| Beginning of line | Home |
| End of line | End |
| Beginning of buffer | Ctrl + Home |
| End of buffer | Ctrl + End |
| Beginning of line (Emacs) | Ctrl + A |
| End of line (Emacs) | Ctrl + E |

#### Cursor Movement - Windows/Linux

| Action | Keybinding |
|--------|------------|
| Previous word | Ctrl + Left Arrow |
| Next word | Ctrl + Right Arrow |

#### Cursor Movement - macOS

| Action | Keybinding |
|--------|------------|
| Previous word | Option + Left Arrow |
| Next word | Option + Right Arrow |
| Beginning of line | Cmd + Left Arrow |
| End of line | Cmd + Right Arrow |
| Beginning of buffer | Cmd + Up Arrow |
| End of buffer | Cmd + Down Arrow |

### Input Handling Architecture

- **`src/input.zig`** - `InputState` struct with `handleEvent()` method processes SDL events and returns `ActionParams`
  - Handles keyboard events, mouse motion, mouse wheel, double-click detection
  - Checks for Ctrl modifier to distinguish pan (scroll) from zoom (Ctrl+scroll)
  - Returns action parameters to be processed by `ActionHandler`
- **`src/action.zig`** - Defines `Action` enum and `ActionParams` union for action indirection
- **`src/action_handler.zig`** - `ActionHandler` struct processes actions and updates application state
  - Contains `TextEditState` with `TextBuffer` for text editing
  - Contains `BlinkAnimation` for cursor blink with restart on movement
  - Contains `SelectionSet` for multi-select support
- **`src/text_buffer.zig`** - Reusable text buffer with full cursor movement support
- **`src/main.zig`** - Main event loop coordinates input handling and action processing

### Implementation Notes

- Tool system:
  - Five tools: Selection (default), TextCreation, TextPlacement, RectanglePlacement, ArrowPlacement
  - Toolbar with icon buttons for Selection, Text, Rectangle, and Arrow tools
  - Current tool tracked in ActionHandler (current_tool field)
  - Double-click on blank canvas or text element enters text editing
  - Escape returns to Selection tool from any other tool
- Selection system:
  - Multi-select support with SelectionSet (up to 256 elements)
  - Shift+click to add/remove from selection
  - Drag-select (marquee) to select elements within rectangle
  - Hit testing: checks bounding boxes of all elements at click position
  - Z-order: elements later in list are on top, hit-tested first (backward iteration)
  - Blue bounding box drawn for selected elements
  - Union bounding box with resize handles for multi-select
- Element manipulation:
  - Drag to move selected elements
  - Alt+drag to clone elements (creates copies on first movement)
  - Corner handles for proportional resizing
  - Resize scales all selected elements uniformly
- Bounding boxes:
  - Calculated dynamically based on element type and camera zoom
  - Text labels: use TTF_SizeText to get dimensions
  - Rectangles: use width/height (supports non-uniform scaling)
  - All calculations in world coordinates, converted to screen for rendering
- Zoom is cursor-centered: the point under the cursor stays fixed during zoom operations
- Pan uses trackpad/mouse wheel scroll (configurable speed: 20 pixels per scroll unit)
- Ctrl modifier distinguishes between pan (no Ctrl) and zoom (with Ctrl)
- Zoom range is constrained to 1%-10,000% (0.01x to 100x, enforced in `camera.zig`)
- Text editing system:
  - TextBuffer with full cursor support (4096 character limit)
  - Cursor movement: char, word, line, buffer start/end
  - Platform-aware keybindings (Ctrl on Windows/Linux, Cmd/Option on macOS)
  - Click within text to position cursor
  - Double-click existing text to edit it (cursor at end)
  - Cursor blink resets on any cursor movement for immediate feedback
  - Double-click detection: 500ms window, 5px tolerance
  - SDL_StartTextInput/SDL_StopTextInput called when entering/exiting edit mode
  - Text positioned in world space at click location
  - On exit (Escape): creates/updates scene element if text is non-empty
  - Whitespace-only text does not create an element
- Grid system: Recursive subdivision with zoom-based fading
  - Base spacing: 150 world units for major divisions (~6 per screen height at zoom 1.0)
  - Minor divisions: 5 per major division (30, 6, 1.2, ... world units)
  - Fade logic: Grid lines fade in from background color to grid color as zoom increases
  - Fade thresholds: Lines invisible below 20px spacing, fully visible at 100px spacing
  - Color interpolation: Uses linear interpolation (lerp) between background and grid colors
  - Recursive rendering: Renders from finest to coarsest levels for proper blending
  - Performance: Only renders visible grid lines, stops when spacing exceeds viewport by 10x
- Window resize updates FPS/status line position to stay anchored to right edge
- Color scheme changes update element colors in place and clear text caches for re-render

## Platform Notes

### WSL
When building on Windows filesystem (`/mnt/c/...`), Zig's cache has permission issues. Always set `ZIG_LOCAL_CACHE_DIR=/tmp/zig-cache` before building, or work from the Linux filesystem (`~/...`).

For GUI display, ensure WSLg is working or use an X server.

**File drag-and-drop does not work** in the WSL build. WSLg windows are not native Win32 windows (they are composited via RDP), so they cannot receive Win32 OLE drag-and-drop events from Windows File Explorer. This is a WSLg limitation, not a code bug. Use the native Windows build for drag-and-drop.

### Windows
Required DLLs (SDL2.dll, SDL2_ttf.dll) are automatically copied to `zig-out/bin/` during build.

### macOS
**CURRENTLY BROKEN**: Zig 0.16.0-dev has compatibility issues with macOS SDK headers. The `TargetConditionals.h` header fails with "unknown compiler" error during `@cImport` of SDL headers, even with attempted workarounds defining `__clang__` and `__GNUC__` macros. Tested on macOS 13.2 Ventura with Xcode SDK 13.3.

The build system supports both Apple Silicon (`/opt/homebrew`) and Intel (`/usr/local`) Homebrew installations when/if this is resolved.
