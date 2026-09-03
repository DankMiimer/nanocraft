#!/bin/bash
# make-diag-bg.sh - render the diagnostic's "finished" screen to raw RGB565.
#
# The tester is holding a console, not reading a terminal, so the run has to end
# by saying on the screen that it worked and where the file is. Same technique
# as the quick menu: the console has no font engine, so the text is baked here.
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

ffmpeg -y -hide_banner -loglevel error -f lavfi -i "color=c=0x101822:s=240x240" -vf "\
drawbox=x=0:y=0:w=240:h=34:color=0x2a3550:t=fill,\
drawtext=fontfile=menufont.ttf:text='REPORT SAVED':fontcolor=0x7ED6B0:fontsize=17:x=(w-text_w)/2:y=9,\
drawtext=fontfile=menufont.ttf:text='Send this file:':fontcolor=0xE8E8E8:fontsize=12:x=14:y=56,\
drawtext=fontfile=menufont.ttf:text='/mnt/FunKey/':fontcolor=0xF0C460:fontsize=12:x=14:y=80,\
drawtext=fontfile=menufont.ttf:text='nanocraft/':fontcolor=0xF0C460:fontsize=12:x=14:y=98,\
drawtext=fontfile=menufont.ttf:text='nanocraft-report.txt':fontcolor=0xF0C460:fontsize=12:x=14:y=116,\
drawtext=fontfile=menufont.ttf:text='It contains no':fontcolor=0x9AA8C0:fontsize=11:x=14:y=150,\
drawtext=fontfile=menufont.ttf:text='personal data and':fontcolor=0x9AA8C0:fontsize=11:x=14:y=166,\
drawtext=fontfile=menufont.ttf:text='was sent nowhere.':fontcolor=0x9AA8C0:fontsize=11:x=14:y=182,\
drawtext=fontfile=menufont.ttf:text='Thank you':fontcolor=0x7ED6B0:fontsize=13:x=(w-text_w)/2:y=212" \
  -frames:v 1 diagbg.png

ffmpeg -y -hide_banner -loglevel error -i diagbg.png -f rawvideo -pix_fmt rgb565le diagbg.raw
echo "wrote diagbg.png and diagbg.raw ($(wc -c < diagbg.raw) bytes, expect 115200)"
