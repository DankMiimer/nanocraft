#!/bin/bash
# build-quickmenu.sh - cross-compile the quick menu for the console.
#
# Static, for the same reason nano-clk is: the console is musl and this is a
# glibc toolchain, so a dynamic build would need the bundled loader and runtime
# the way ninecraft does. Static needs nothing at all, which is the entire point
# here - this replaces a Python menu that could not run on the factory firmware
# because that firmware ships no interpreter.
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/quickmenu.c"
if [ -d "$HERE/../opk-pe" ]; then
    DEFAULT_OUT="$HERE/../opk-pe/quickmenu"
    DEFAULT_INCLUDE="$HERE/../../ninecraft061/overlay/ninecraft/include"
else
    DEFAULT_OUT="$HERE/../opk/quickmenu"
    DEFAULT_INCLUDE="$HERE/../build/overlay/ninecraft/include"
fi
OUT="${1:-$DEFAULT_OUT}"
INPUT_INCLUDE="${NINECRAFT_INCLUDE:-$DEFAULT_INCLUDE}"

CC=arm-linux-gnueabihf-gcc
command -v "$CC" >/dev/null || { echo "no $CC - apt install gcc-arm-linux-gnueabihf"; exit 1; }

"$CC" -static -Os -Wall -Wextra -march=armv7-a -mtune=cortex-a7 -mfpu=neon-vfpv4 \
      -mfloat-abi=hard -I"$INPUT_INCLUDE" -o "$OUT" "$SRC"
arm-linux-gnueabihf-strip "$OUT" 2>/dev/null || true

echo "built: $OUT"
ls -l "$OUT"
file "$OUT"
