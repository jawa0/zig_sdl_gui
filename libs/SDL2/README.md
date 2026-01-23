# SDL2 Windows Libraries

This directory contains SDL2 2.30.10 development libraries for native Windows builds.

## Contents

- `include/SDL2/` - SDL2 header files
- `lib/x64/` - 64-bit Windows libraries (SDL2.lib, SDL2.dll, SDL2main.lib)
- `LICENSE.txt` - SDL2 license (zlib)

## Usage

The build system automatically:
1. Links against these libraries when building for Windows
2. Copies SDL2.dll to the output directory (`zig-out/bin/`)

No manual setup required.

## Updating SDL2

To update to a newer version:

1. Download `SDL2-devel-x.xx.x-VC.zip` from https://github.com/libsdl-org/SDL/releases
2. Replace contents of `include/SDL2/` with new headers
3. Replace contents of `lib/x64/` with new libraries
4. Update `LICENSE.txt` if needed
