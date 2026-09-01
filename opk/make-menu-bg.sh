#!/bin/bash
# make-menu-bg.sh - pre-render the quick menu background to raw RGB565.
#
# The device has no font engine (no PIL, and the SDL1.2 TTF stack is not
# reachable from python), so every glyph the menu shows is baked here on the
# workstation and shipped as a flat 240x240 RGB565 buffer. At runtime the menu
# blits this and draws only the things that change -- the selection cursor and
# the two value bars -- as plain rectangles. That keeps the on-device code to
# arithmetic and one memcpy.
#
# FONT: Raster Forge Regular (menufont.ttf), chosen by the project owner. Only
# the RENDERED buffer ships in the release -- the .ttf is a build input, not a
# runtime asset, so a release carries no font file.
#
# Whether the .ttf itself may be committed to the public repository depends on
# its licence, which has not been verified here. Until it is, keep it out of the
# repo and let a builder drop their own copy in beside this script; the build
# then reproduces exactly. If the licence does allow redistribution, committing
# it is a one-line change to .gitignore and makes the build self-contained.
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FONT="$HERE/menufont.ttf"
OUT="$HERE/menubg.raw"
PNG="$HERE/menubg.png"

# ffmpeg's drawtext parser eats ':' and '\', so hand it a relative filename from
# the working directory rather than an absolute Windows path.
cd "$HERE"

ffmpeg -y -hide_banner -loglevel error -f lavfi -i "color=c=0x101822:s=240x240" -vf "\
drawbox=x=0:y=0:w=240:h=30:color=0x2a3550:t=fill,\
drawtext=fontfile=menufont.ttf:text='QUICK MENU':fontcolor=0xE8E8E8:fontsize=17:x=(w-text_w)/2:y=7,\
drawtext=fontfile=menufont.ttf:text='VOLUME':fontcolor=0xE8E8E8:fontsize=15:x=18:y=52,\
drawtext=fontfile=menufont.ttf:text='BRIGHT':fontcolor=0xE8E8E8:fontsize=15:x=18:y=87,\
drawtext=fontfile=menufont.ttf:text='CLOSE GAME':fontcolor=0xE8E8E8:fontsize=15:x=18:y=126,\
drawtext=fontfile=menufont.ttf:text='SHUTDOWN':fontcolor=0xE8E8E8:fontsize=15:x=18:y=161,\
drawtext=fontfile=menufont.ttf:text='RESUME':fontcolor=0xE8E8E8:fontsize=15:x=18:y=196,\
drawtext=fontfile=menufont.ttf:text='A select   B resume':fontcolor=0x7C8AA8:fontsize=11:x=(w-text_w)/2:y=224" \
  -frames:v 1 "$PNG"

ffmpeg -y -hide_banner -loglevel error -i "$PNG" -f rawvideo -pix_fmt rgb565le "$OUT"
echo "wrote $PNG and $OUT ($(wc -c < "$OUT") bytes, expect 115200)"
