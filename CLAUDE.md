# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A Zig application using SDL2 and SDL2_ttf to render a double-buffered window at 60fps with FPS counter. Supports both Linux/WSL and native Windows.

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

## Dependencies

- Zig 0.15.2
- SDL2:
  - Linux: `libsdl2-dev` via apt
  - Windows: bundled in `libs/SDL2/` (SDL2 2.30.10)
- SDL2_ttf:
  - Linux: `libsdl2-ttf-dev` via apt
  - Windows: bundled in `libs/SDL2_ttf/` (SDL2_ttf 2.22.0)
- JetBrains Mono font: bundled in `assets/fonts/`

## Architecture

- `build.zig` - Build configuration with cross-platform SDL2/SDL2_ttf linking (detects Windows vs Linux)
- `src/main.zig` - Main entry point with SDL2 render loop and FPS display using `@cImport` for C interop
- `libs/SDL2/` - Windows SDL2 libraries (headers, .lib, .dll)
- `libs/SDL2_ttf/` - Windows SDL2_ttf libraries (headers, .lib, .dll)
- `assets/fonts/` - JetBrains Mono font for text rendering

The app uses SDL2's hardware-accelerated renderer with vsync for double buffering. Frame timing is handled by vsync with a fallback delay loop. FPS is displayed in the top-right corner using SDL2_ttf.

## Platform Notes

### WSL
When building on Windows filesystem (`/mnt/c/...`), Zig's cache has permission issues. Always set `ZIG_LOCAL_CACHE_DIR=/tmp/zig-cache` before building, or work from the Linux filesystem (`~/...`).

For GUI display, ensure WSLg is working or use an X server.

### Windows
Required DLLs (SDL2.dll, SDL2_ttf.dll) are automatically copied to `zig-out/bin/` during build.
