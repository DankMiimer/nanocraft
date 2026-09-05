#!/bin/bash
# Native Linux tests. SDL_INCLUDE may point to Ninecraft's SDL/include directory.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${1:?usage: run-input-tests.sh output-directory}"
mkdir -p "$OUT"
INC=build/overlay/ninecraft/include
gcc -std=gnu11 -O2 -Wall -Wextra -I"$INC" -Itests/stubs \
    -I"${SDL_INCLUDE:-/usr/include/SDL2}" -ffunction-sections -fdata-sections \
    tests/input_sensitivity_test.c -Wl,--gc-sections -o "$OUT/input-test"
"$OUT/input-test"
gcc -std=gnu11 -O2 -Wall -Wextra -Wno-format-truncation -I"$INC" \
    tests/quickmenu_test.c -Wl,--wrap=open -o "$OUT/menu-test"
DATA="$(mktemp -d)"
trap 'rmdir "$DATA"' EXIT
"$OUT/menu-test" "$DATA"
if [ -f "$OUT/sens200.raw" ]; then
    python3 tests/quickmenu_events_test.py "$OUT"
fi
