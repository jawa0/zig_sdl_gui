# zig_sdl_gui

A Zig application using SDL2 to render a double-buffered window at 60fps.

## Prerequisites (Windows 11 WSL)

### Install Zig 0.15.2

```bash
cd ~
wget https://ziglang.org/download/0.15.2/zig-x86_64-linux-0.15.2.tar.xz
tar -xf zig-x86_64-linux-0.15.2.tar.xz
mv zig-x86_64-linux-0.15.2 ~/.local/zig
echo 'export PATH="$HOME/.local/zig:$PATH"' >> ~/.bashrc
source ~/.bashrc
rm zig-x86_64-linux-0.15.2.tar.xz
```

### Install SDL2

```bash
sudo apt update
sudo apt install libsdl2-dev
```

## Building

Ensure Zig is in your PATH (if you followed the installation above, restart your terminal or run `source ~/.bashrc`).

When building from the Windows filesystem (`/mnt/c/...`), set the cache directory to avoid permission issues:

```bash
export ZIG_LOCAL_CACHE_DIR=/tmp/zig-cache
zig build
```

For a release build:

```bash
zig build -Doptimize=ReleaseFast
```

## Running

```bash
export ZIG_LOCAL_CACHE_DIR=/tmp/zig-cache
zig build run
```

Press Escape or close the window to quit.

### Display Setup

For the GUI window to appear in WSL, you need one of:

- **WSLg** (built into Windows 11) - should work automatically
- **X server** (VcXsrv, X410, etc.) - set `DISPLAY` environment variable

To verify WSLg is working:

```bash
echo $DISPLAY
```

Should show something like `:0` or `:0.0`.
