#!/bin/bash
# make-menu-bg.sh - pre-render the quick menu to raw RGB565.
#
# The device has no font engine (no PIL, and the SDL1.2 TTF stack is not
# reachable from python), so every glyph the menu shows is baked here on the
# workstation and shipped as flat RGB565 buffers. At runtime the menu blits
# these and draws only what changes -- the cursor and the two bars -- as plain
# rectangles. That keeps the on-device code to arithmetic and one memcpy.
#
# VALUE STRIPS. Several rows show a setting rather than a bar, and text cannot
# be drawn on the device, so every reading either row can show is baked here and
# the menu blits whichever applies: res240/res120 for the screen, one per
# interface scale, one per field of view, and one per CPU step.
#
# FONT: Raster Forge Regular (menufont.ttf), chosen by the project owner. Only
# the RENDERED buffers ship -- the .ttf is a build input, not a runtime asset,
# so a release carries no font file. Whether the .ttf may itself be committed
# depends on its licence, which is unverified; until then a builder drops their
# own copy in beside this script and the build reproduces exactly.
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

# Eight rows, 24 px apart from y=34. Keep in step with ROW_TOP in quickmenu.py.
ffmpeg -y -hide_banner -loglevel error -f lavfi -i "color=c=0x101822:s=240x240" -vf "\
drawbox=x=0:y=0:w=240:h=28:color=0x2a3550:t=fill,\
drawtext=fontfile=menufont.ttf:text='QUICK MENU':fontcolor=0xE8E8E8:fontsize=15:x=(w-text_w)/2:y=6,\
drawtext=fontfile=menufont.ttf:text='VOLUME':fontcolor=0xE8E8E8:fontsize=12:x=16:y=38,\
drawtext=fontfile=menufont.ttf:text='BRIGHT':fontcolor=0xE8E8E8:fontsize=12:x=16:y=62,\
drawtext=fontfile=menufont.ttf:text='CPU':fontcolor=0xE8E8E8:fontsize=12:x=16:y=86,\
drawtext=fontfile=menufont.ttf:text='VIDEO':fontcolor=0xE8E8E8:fontsize=12:x=16:y=110,\
drawtext=fontfile=menufont.ttf:text='>':fontcolor=0x7C8AA8:fontsize=12:x=140:y=110,\
drawtext=fontfile=menufont.ttf:text='RESTART':fontcolor=0xE8E8E8:fontsize=12:x=16:y=134,\
drawtext=fontfile=menufont.ttf:text='FORCE CLOSE':fontcolor=0xE8E8E8:fontsize=12:x=16:y=158,\
drawtext=fontfile=menufont.ttf:text='SHUTDOWN':fontcolor=0xE8E8E8:fontsize=12:x=16:y=182,\
drawtext=fontfile=menufont.ttf:text='RESUME':fontcolor=0xE8E8E8:fontsize=12:x=16:y=206" \
  -frames:v 1 menubg.png
ffmpeg -y -hide_banner -loglevel error -i menubg.png -f rawvideo -pix_fmt rgb565le menubg.raw

# --- the video page -----------------------------------------------------------
# Same row geometry, so quickmenu.py blits values and draws the cursor with the
# identical arithmetic and only the background changes. Four rows, then a
# legend, because AUTO/FIT/STOCK say nothing on their own and a bare 70 does not
# say it is the stock angle -- and the footer that used to sit under SCREEN on
# the main page, now covering every setting here.
ffmpeg -y -hide_banner -loglevel error -f lavfi -i "color=c=0x101822:s=240x240" -vf "\
drawbox=x=0:y=0:w=240:h=28:color=0x2a3550:t=fill,\
drawtext=fontfile=menufont.ttf:text='VIDEO SETTINGS':fontcolor=0xE8E8E8:fontsize=15:x=(w-text_w)/2:y=6,\
drawtext=fontfile=menufont.ttf:text='SCREEN':fontcolor=0xE8E8E8:fontsize=12:x=16:y=38,\
drawtext=fontfile=menufont.ttf:text='GUI SCALE':fontcolor=0xE8E8E8:fontsize=12:x=16:y=62,\
drawtext=fontfile=menufont.ttf:text='FOV':fontcolor=0xE8E8E8:fontsize=12:x=16:y=86,\
drawtext=fontfile=menufont.ttf:text='BACK':fontcolor=0xE8E8E8:fontsize=12:x=16:y=110,\
drawtext=fontfile=menufont.ttf:text='AUTO   hotbar always fits':fontcolor=0x7C8AA8:fontsize=10:x=16:y=144,\
drawtext=fontfile=menufont.ttf:text='FIT    bigger, still fits':fontcolor=0x7C8AA8:fontsize=10:x=16:y=158,\
drawtext=fontfile=menufont.ttf:text='STOCK  crisp, clips at 120':fontcolor=0x7C8AA8:fontsize=10:x=16:y=172,\
drawtext=fontfile=menufont.ttf:text='FOV    70 is what the game ships':fontcolor=0x7C8AA8:fontsize=10:x=16:y=190,\
drawtext=fontfile=menufont.ttf:text='all three need a restart':fontcolor=0x7C8AA8:fontsize=10:x=(w-text_w)/2:y=226" \
  -frames:v 1 videobg.png
ffmpeg -y -hide_banner -loglevel error -i videobg.png -f rawvideo -pix_fmt rgb565le videobg.raw

# --- value strips -------------------------------------------------------------
# 76x18, blitted at their row. Same background colour so they sit flush.
strip() {   # strip <outname> <text> <colour>
  ffmpeg -y -hide_banner -loglevel error -f lavfi -i "color=c=0x101822:s=76x18" -vf \
    "drawtext=fontfile=menufont.ttf:text='$2':fontcolor=$3:fontsize=12:x=0:y=2" \
    -frames:v 1 "$1.png"
  ffmpeg -y -hide_banner -loglevel error -i "$1.png" -f rawvideo -pix_fmt rgb565le "$1.raw"
}

strip res240 "240x240" 0xF0C460
strip res120 "120x120" 0xF0C460

# Interface scale. AUTO and FIT both always fit; STOCK is the one that can clip,
# so it gets the warm colour the CPU ladder uses for "past the safe setting".
# Avoid a colon in any drawtext value: ffmpeg reads it as an option separator
# even inside quotes, and silently renders only the part before it.
strip gsauto  "AUTO"  0xF0C460
strip gsfit   "FIT"   0xF0C460
strip gsstock "STOCK" 0xF0A050

# Field of view. 70 is the angle the game ships with and asking for it patches
# nothing, so it gets the calm colour the CPU ladder uses for stock and every
# other angle gets the gold the rest of this page uses for a chosen value.
strip fov70 "70" 0x9AA8C0
for f in 50 60 80 90 100; do
  strip "fov$f" "$f" 0xF0C460
done

# The CPU ladder is 48 MHz per step from stock. Stock is shown in a calm colour
# and every overclock in a warmer one, so the screen itself says when the
# console is running beyond its specification.
strip cpu1008 "1008 MHz" 0x9AA8C0
for m in 1056 1104 1152 1200 1248; do
  strip "cpu$m" "$m MHz" 0xF0A050
done

for f in menubg.raw videobg.raw; do
  echo "wrote $f ($(wc -c < "$f") bytes, expect 115200)"
done
for f in res*.raw gs*.raw fov*.raw cpu*.raw; do
  echo "  $f $(wc -c < "$f") bytes (expect $((76 * 18 * 2)))"
done
