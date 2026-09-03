#!/bin/bash
# build-nanoclk.sh - cross-compile nano-clk for the console.
#
# Built STATIC on purpose. The console is musl and this is a glibc toolchain, so
# a dynamic build would need the bundled loader and runtime the way ninecraft
# does. A static binary needs nothing at all, which matters for a tool whose job
# is to touch clock registers: the fewer moving parts between "run it" and "the
# write happens", the better. It also means the quick menu can call it before or
# after the game without caring what else is mapped.
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/nano-clk.c"
OUT="$HERE/../opk-pe/nano-clk"

CC=arm-linux-gnueabihf-gcc
command -v "$CC" >/dev/null || { echo "no $CC - apt install gcc-arm-linux-gnueabihf"; exit 1; }

"$CC" -static -Os -Wall -Wextra -march=armv7-a -mtune=cortex-a7 -mfpu=neon-vfpv4 \
      -mfloat-abi=hard -o "$OUT" "$SRC"
arm-linux-gnueabihf-strip "$OUT" 2>/dev/null || true

echo "built: $OUT"
ls -l "$OUT"
file "$OUT"
