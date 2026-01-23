# zig_sdl_gui

A Zig application using SDL2 to render a double-buffered window at 60fps with FPS counter display.

## Prerequisites

### Option A: Linux / Windows WSL

#### Install Zig 0.15.2

```bash
cd ~
wget https://ziglang.org/download/0.15.2/zig-x86_64-linux-0.15.2.tar.xz
tar -xf zig-x86_64-linux-0.15.2.tar.xz
mv zig-x86_64-linux-0.15.2 ~/.local/zig
echo 'export PATH="$HOME/.local/zig:$PATH"' >> ~/.bashrc
source ~/.bashrc
rm zig-x86_64-linux-0.15.2.tar.xz
```

#### Install SDL2 and SDL2_ttf

```bash
sudo apt update
sudo apt install libsdl2-dev libsdl2-ttf-dev
```

### Option B: Native Windows

#### Install Zig 0.15.2

1. Download `zig-windows-x86_64-0.15.2.zip` from https://ziglang.org/download/
2. Extract to a directory (e.g., `C:\zig`)
3. Add to PATH: Settings > System > About > Advanced system settings > Environment Variables > Edit PATH

SDL2 and SDL2_ttf libraries are already bundled in `libs/`.

## Building and Running

### Linux / WSL

From the `zig_sdl_gui` directory:

```bash
ZIG_LOCAL_CACHE_DIR=/tmp/zig-cache zig build run
```

The cache variable is needed when building from the Windows filesystem (`/mnt/c/...`) to avoid permission issues.

For a release build:

```bash
ZIG_LOCAL_CACHE_DIR=/tmp/zig-cache zig build -Doptimize=ReleaseFast
```

### Native Windows

From Command Prompt or PowerShell in the project directory:

```
zig build run
```

For a release build:

```
zig build -Doptimize=ReleaseFast
```

The executable will be in `zig-out\bin\`. Required DLLs are automatically copied there during build.

## Controls

Press Escape or close the window to quit.

## Display Setup (WSL only)

For the GUI window to appear in WSL, you need one of:

- **WSLg** (built into Windows 11) - should work automatically
- **X server** (VcXsrv, X410, etc.) - set `DISPLAY` environment variable

To verify WSLg is working:

```bash
echo $DISPLAY
```

Should show something like `:0` or `:0.0`.
