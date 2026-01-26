# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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
- `src/tool.zig` - Tool system enum (Selection, TextCreation)
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

The app uses SDL2's hardware-accelerated renderer with vsync for double buffering. Frame timing is handled by vsync with a fallback delay loop. FPS is displayed in the top-right corner using SDL2_ttf.

## User Actions & Input System

### Current User Actions

The application currently supports these user actions:

1. **Quit Application** - Exit the application
2. **Pan Canvas** - Move the camera view around the infinite canvas
3. **Zoom In at Cursor** - Zoom in 10% centered on cursor position
4. **Zoom Out at Cursor** - Zoom out 10% centered on cursor position
5. **Toggle Color Scheme** - Switch between light and dark color schemes
6. **Toggle Grid** - Show/hide the world-space grid overlay
7. **Begin Text Edit** - Enter text editing mode at double-click location
8. **End Text Edit** - Exit text editing mode
9. **Resize Window** - Change window dimensions

### Current Input Bindings

| Action | Input Binding | Implementation |
|--------|--------------|----------------|
| Quit Application | Escape key (when not editing) or window close | `input.zig:36-42` |
| Toggle Color Scheme | D key (when not editing) | `input.zig:45-47` |
| Toggle Grid | G key (when not editing) | `input.zig:48-50` |
| Begin Text Edit | Double-click left mouse button | `input.zig:58-74` |
| End Text Edit | Escape key (while editing) | `input.zig:38` |
| Text Input | Alphanumeric keys | `main.zig:216-223` |
| New Line | Enter key | `main.zig:230-237` |
| Backspace | Backspace key | `main.zig:224-229` |
| Pan Canvas | Trackpad/mouse wheel scroll | `input.zig:86-92` |
| Zoom In at Cursor | Ctrl + scroll up | `input.zig:75-84` |
| Zoom Out at Cursor | Ctrl + scroll down | `input.zig:75-84` |
| Resize Window | Drag window edges/corners | SDL window event |

### Input Handling Architecture

- **`src/input.zig`** - `InputState` struct with `handleEvent()` method processes SDL events and returns `ActionParams`
  - Handles keyboard (Escape, D for color toggle), mouse motion, mouse wheel
  - Checks for Ctrl modifier to distinguish pan (scroll) from zoom (Ctrl+scroll)
  - Returns action parameters to be processed by `ActionHandler`
- **`src/action.zig`** - Defines `Action` enum and `ActionParams` union for action indirection
- **`src/action_handler.zig`** - `ActionHandler` struct processes actions and updates application state
- **`src/main.zig`** - Main event loop coordinates input handling and action processing

### Implementation Notes

- Tool system:
  - Two tools: Selection (default) and TextCreation
  - Current tool tracked in ActionHandler (current_tool field)
  - Tool determines mouse click behavior
  - No toolbar UI yet - will be added later
- Selection system:
  - Hit testing: checks bounding boxes of all elements at click position
  - Z-order: elements later in list are on top, hit-tested first (backward iteration)
  - Selected element ID tracked in ActionHandler (selected_element_id field)
  - Blue bounding box (2px border) drawn for selected elements
  - Selection mode: single click selects, click empty space deselects
  - Text creation mode: double-click creates text
- Bounding boxes:
  - Calculated dynamically based on element type and camera zoom
  - Text labels: use TTF_SizeText to get dimensions
  - Rectangles: use width/height scaled by zoom
  - All calculations in screen coordinates
- Zoom is cursor-centered: the point under the cursor stays fixed during zoom operations
- Pan uses trackpad/mouse wheel scroll (configurable speed: 20 pixels per scroll unit)
- Ctrl modifier distinguishes between pan (no Ctrl) and zoom (with Ctrl)
- Zoom range is constrained to 1%-10,000% (0.01x to 100x, enforced in `camera.zig`)
- Text editing system:
  - Double-click detection: 500ms window, 5px tolerance
  - Text buffer: 1024 character limit
  - Cursor rendering: vertical line that blinks every 500ms
  - SDL_StartTextInput/SDL_StopTextInput called when entering/exiting edit mode
  - Text positioned in world space at click location
  - Escape key behavior changes based on edit mode (end edit vs quit app)
  - Supports multi-line text with Enter key
  - On exit (Escape): creates persistent scene element if text is non-empty
  - Empty check: trims whitespace for validation but preserves all spaces in actual text
  - Whitespace-only text (e.g., "   ") does not create an element
  - Text with content (e.g., "  hello  ") preserves all spaces
- Grid system: Recursive subdivision with zoom-based fading
  - Base spacing: 150 world units for major divisions (~6 per screen height at zoom 1.0)
  - Minor divisions: 5 per major division (30, 6, 1.2, ... world units)
  - Fade logic: Grid lines fade in from background color to grid color as zoom increases
  - Fade thresholds: Lines invisible below 20px spacing, fully visible at 100px spacing
  - Color interpolation: Uses linear interpolation (lerp) between background and grid colors
  - Recursive rendering: Renders from finest to coarsest levels for proper blending
  - Performance: Only renders visible grid lines, stops when spacing exceeds viewport by 10x
- Window resize updates FPS/status line position to stay anchored to right edge
- Color scheme changes regenerate cached text elements to update colors

## Platform Notes

### WSL
When building on Windows filesystem (`/mnt/c/...`), Zig's cache has permission issues. Always set `ZIG_LOCAL_CACHE_DIR=/tmp/zig-cache` before building, or work from the Linux filesystem (`~/...`).

For GUI display, ensure WSLg is working or use an X server.

### Windows
Required DLLs (SDL2.dll, SDL2_ttf.dll) are automatically copied to `zig-out/bin/` during build.

### macOS
**CURRENTLY BROKEN**: Zig 0.16.0-dev has compatibility issues with macOS SDK headers. The `TargetConditionals.h` header fails with "unknown compiler" error during `@cImport` of SDL headers, even with attempted workarounds defining `__clang__` and `__GNUC__` macros. Tested on macOS 13.2 Ventura with Xcode SDK 13.3.

The build system supports both Apple Silicon (`/opt/homebrew`) and Intel (`/usr/local`) Homebrew installations when/if this is resolved.
