#!/bin/bash
# run-native-ui-gl-test.sh - exercise the native-UI compositor against a real
# software OpenGL driver.
#
# The other tests in this directory compile against stub headers, which is right
# for input and menu logic and useless for build/overlay/ninecraft/src/nano_ui.c:
# what that file asserts about is framebuffer completeness, blit filtering,
# scissor halving and the exact GL state the game is handed back afterwards, and
# only a driver can answer those. llvmpipe answers them with no GPU and no
# console, so this runs anywhere Docker does.
#
#   ./tests/run-native-ui-gl-test.sh <ninecraft-checkout> [output-directory]
#
# <ninecraft-checkout> is a recursive Ninecraft checkout - the same one
# build/Dockerfile.mm-buster is given - for its glad, ancmp, ninecraft and SDL
# headers. The test itself compiles this repository's overlay copy, not the
# checkout's, so it reports on what is committed here.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKOUT="${1:?usage: run-native-ui-gl-test.sh ninecraft-checkout [output-directory]}"
OUT="${2:-$ROOT/out-native-ui}"

CTX="$(mktemp -d)"
trap 'rm -rf "$CTX"' EXIT
for d in glad ancmp ninecraft SDL; do
    cp -al "$CHECKOUT/$d" "$CTX/$d" 2>/dev/null || cp -a "$CHECKOUT/$d" "$CTX/$d"
done
# The test's include of the compositor is relative to this repository's layout,
# so reproduce that layout inside the context rather than rewriting the path.
mkdir -p "$CTX/nanocraft/build"
cp -a "$ROOT/tests"         "$CTX/nanocraft/tests"
cp -a "$ROOT/build/overlay" "$CTX/nanocraft/build/overlay"
printf '.git\n' > "$CTX/.dockerignore"

mkdir -p "$OUT"
docker build -f "$ROOT/build/Dockerfile.native-ui-test" --target export -o "$OUT" "$CTX"
echo "rendered frame: $OUT/native-ui-frame.ppm"
