#!/bin/sh
# Builds the force-feedback helper for Windows (DirectInput) and Linux (SDL2).
# Needs mingw-w64 and libsdl2-dev. Output: native/bin/
set -e
cd "$(dirname "$0")"
mkdir -p bin
x86_64-w64-mingw32-gcc -O2 -o bin/ffb_helper.exe ffb_helper.c -ldinput8 -ldxguid -lws2_32 -luser32 -static
gcc -O2 -o bin/ffb_helper ffb_helper.c $(pkg-config --cflags --libs sdl2) -lm
echo "built native/bin/ffb_helper.exe and native/bin/ffb_helper"
