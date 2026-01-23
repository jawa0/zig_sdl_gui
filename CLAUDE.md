# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A Zig application using SDL2 to render a double-buffered window at 60fps. Currently a blank canvas that can be extended with custom rendering.

## Build Commands

```bash
# Required: Set cache directory on Linux filesystem (WSL issue with /mnt/c)
export ZIG_LOCAL_CACHE_DIR=/tmp/zig-cache
export PATH="$HOME/.local/zig:$PATH"

# Build
zig build

# Build and run
zig build run

# Build optimized release
zig build -Doptimize=ReleaseFast
```

## Dependencies

- Zig 0.15.2 (installed at `~/.local/zig`)
- SDL2 (`libsdl2-dev` on Ubuntu)

## Architecture

- `build.zig` - Build configuration, links SDL2 via system library
- `src/main.zig` - Main entry point with SDL2 render loop using `@cImport` for C interop

The app uses SDL2's hardware-accelerated renderer with vsync for double buffering. Frame timing is handled by vsync with a fallback delay loop.

## WSL Notes

When building on Windows filesystem (`/mnt/c/...`), Zig's cache has permission issues. Always set `ZIG_LOCAL_CACHE_DIR=/tmp/zig-cache` before building, or work from the Linux filesystem (`~/...`).

For GUI display, ensure WSLg is working or use an X server.
