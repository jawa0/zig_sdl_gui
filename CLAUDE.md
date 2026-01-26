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
- `src/grid.zig` - Grid rendering system with configurable major/minor divisions
- `src/action.zig` - Action enum and parameters for input indirection
- `src/action_handler.zig` - Processes actions and updates application state
- `src/input.zig` - Input handling that returns actions instead of directly manipulating state
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
7. **Resize Window** - Change window dimensions

### Current Input Bindings

| Action | Input Binding | Implementation |
|--------|--------------|----------------|
| Quit Application | Escape key or window close | `input.zig:31-33` |
| Toggle Color Scheme | D key | `input.zig:34-36` |
| Toggle Grid | G key | `input.zig:37-39` |
| Pan Canvas | Trackpad/mouse wheel scroll | `input.zig:67-73` |
| Zoom In at Cursor | Ctrl + scroll up | `input.zig:56-65` |
| Zoom Out at Cursor | Ctrl + scroll down | `input.zig:56-65` |
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

- Zoom is cursor-centered: the point under the cursor stays fixed during zoom operations
- Pan uses trackpad/mouse wheel scroll (configurable speed: 20 pixels per scroll unit)
- Ctrl modifier distinguishes between pan (no Ctrl) and zoom (with Ctrl)
- Zoom range is constrained to 25%-400% (enforced in `camera.zig`)
- Grid spacing: 150 world units for major divisions (~6 per screen height at zoom 1.0), grid is square
- Grid rendering: dynamically calculated based on visible world bounds, drawn with SDL_RenderDrawLine
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
