#!/bin/bash
# make-diag-bg.sh - render the diagnostic's "finished" screen to raw RGB565.
#
# The tester is holding a console, not reading a terminal, so the run has to end
# by saying on the screen that it worked and where the file is. Same technique
# as the quick menu: the console has no font engine, so the text is baked here.
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

# These consoles have no networking, so the screen has to explain the SD-card
# route rather than say "send this file" and leave the owner wondering how.
ffmpeg -y -hide_banner -loglevel error -f lavfi -i "color=c=0x101822:s=240x240" -vf "\
drawbox=x=0:y=0:w=240:h=32:color=0x2a3550:t=fill,\
drawtext=fontfile=menufont.ttf:text='REPORT SAVED':fontcolor=0x7ED6B0:fontsize=16:x=(w-text_w)/2:y=8,\
drawtext=fontfile=menufont.ttf:text='1. Power off':fontcolor=0xE8E8E8:fontsize=12:x=12:y=46,\
drawtext=fontfile=menufont.ttf:text='2. SD card into a PC':fontcolor=0xE8E8E8:fontsize=12:x=12:y=66,\
drawtext=fontfile=menufont.ttf:text='3. Copy this file from':fontcolor=0xE8E8E8:fontsize=12:x=12:y=86,\
drawtext=fontfile=menufont.ttf:text='the big partition:':fontcolor=0xE8E8E8:fontsize=12:x=12:y=104,\
drawtext=fontfile=menufont.ttf:text='nanocraft-report.txt':fontcolor=0xF0C460:fontsize=13:x=12:y=128,\
drawtext=fontfile=menufont.ttf:text='(in the root, not in':fontcolor=0x9AA8C0:fontsize=11:x=12:y=150,\
drawtext=fontfile=menufont.ttf:text='a folder)':fontcolor=0x9AA8C0:fontsize=11:x=12:y=166,\
drawtext=fontfile=menufont.ttf:text='No personal data.':fontcolor=0x9AA8C0:fontsize=11:x=12:y=190,\
drawtext=fontfile=menufont.ttf:text='Sent nowhere.':fontcolor=0x9AA8C0:fontsize=11:x=12:y=206,\
drawtext=fontfile=menufont.ttf:text='Thank you':fontcolor=0x7ED6B0:fontsize=12:x=(w-text_w)/2:y=224" \
  -frames:v 1 diagbg.png

ffmpeg -y -hide_banner -loglevel error -i diagbg.png -f rawvideo -pix_fmt rgb565le diagbg.raw
echo "wrote diagbg.png and diagbg.raw ($(wc -c < diagbg.raw) bytes, expect 115200)"
