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
5. **Resize Window** - Change window dimensions

### Current Input Bindings

| Action | Input Binding | Implementation |
|--------|--------------|----------------|
| Quit Application | Escape key or window close | `input.zig:30, 32-35` |
| Pan Canvas | Left mouse button drag | `input.zig:55-65` |
| Zoom In at Cursor | Mouse wheel up | `input.zig:83-96` |
| Zoom Out at Cursor | Mouse wheel down | `input.zig:83-96` |
| Resize Window | Drag window edges/corners | `main.zig:205-210` |

### Input Handling Architecture

- **`src/input.zig`** - `InputState` struct with `handleEvent()` method processes most SDL events
  - Handles keyboard (Escape), mouse motion, mouse buttons, mouse wheel
  - Maintains drag state with 3-pixel threshold before panning starts
  - Applies camera transformations directly via `Camera` API
- **`src/main.zig`** - Main event loop also handles window-specific events (resize)
- **Future**: Plan to add action enum and indirection layer to separate actions from bindings, enabling:
  - Rebindable controls
  - Action scripting support

### Implementation Notes

- Zoom is cursor-centered: the point under the cursor stays fixed during zoom operations
- Pan uses drag detection with 3-pixel threshold to distinguish clicks from drags
- Zoom range is constrained to 25%-400% (enforced in `camera.zig`)
- Window resize updates FPS/status line position to stay anchored to right edge

## Platform Notes

### WSL
When building on Windows filesystem (`/mnt/c/...`), Zig's cache has permission issues. Always set `ZIG_LOCAL_CACHE_DIR=/tmp/zig-cache` before building, or work from the Linux filesystem (`~/...`).

For GUI display, ensure WSLg is working or use an X server.

### Windows
Required DLLs (SDL2.dll, SDL2_ttf.dll) are automatically copied to `zig-out/bin/` during build.

### macOS
**CURRENTLY BROKEN**: Zig 0.16.0-dev has compatibility issues with macOS SDK headers. The `TargetConditionals.h` header fails with "unknown compiler" error during `@cImport` of SDL headers, even with attempted workarounds defining `__clang__` and `__GNUC__` macros. Tested on macOS 13.2 Ventura with Xcode SDK 13.3.

The build system supports both Apple Silicon (`/opt/homebrew`) and Intel (`/usr/local`) Homebrew installations when/if this is resolved.
