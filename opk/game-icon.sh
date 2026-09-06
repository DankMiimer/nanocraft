#!/bin/sh
# game-icon.sh - optionally show the game's own icon in the front end, taken
# from the copy of the game the owner supplied.
#
# WHY THIS IS NOT SHIPPED AS AN ICON. The launcher icon inside Minecraft's APK
# is Mojang's artwork and "Minecraft" is their trademark. Putting it in the OPK
# would mean this project distributing their art, and using their logo as this
# software's identity - two different problems, and the first one breaks the
# promise the release notes make in every version: no game files are included.
#
# Doing it HERE is a different act. Nothing is distributed: the image is copied
# on the owner's own console, out of the APK they legally obtained and already
# installed, onto their own SD card. It is off by default and it is reversible.
# That is the same principle the rest of the port runs on - you supply the game,
# and it is unpacked on your device.
#
# TURN IT ON:  echo 1 > /mnt/FunKey/nanocraft/game-icon.txt
# TURN IT OFF: echo 0 > /mnt/FunKey/nanocraft/game-icon.txt   (or delete it)
#
# Off restores the icon this port ships, which is kept beside the game the first
# time this runs. Nothing is lost either way.
#
#   game-icon.sh [data-dir]
set -u

DATA=${1:-/mnt/FunKey/nanocraft}
SETTING=$DATA/game-icon.txt
BACKUP=$DATA/icon-original.png
STATE=$DATA/.icon-state

# The front end's artwork sits beside the .opk on the data partition, which is
# writable. The icon INSIDE the .opk cannot be changed on the console at all -
# it is a read-only squashfs and there is no mksquashfs here - so a front end
# that uses that one (gmenu2x) will keep showing the shipped icon. RetroFE, the
# default here, uses this file.
ART="/mnt/Native games/NanoCraft_funkey-s.png"

want=0
[ -f "$SETTING" ] && read want < "$SETTING" 2>/dev/null
case "$want" in 1|yes|on|true) want=1 ;; *) want=0 ;; esac

have=shipped
[ -f "$STATE" ] && read have < "$STATE" 2>/dev/null

[ -f "$ART" ] || exit 0                 # no front end artwork here; nothing to do
[ "$want" = 1 ] && [ "$have" = game ] && exit 0
[ "$want" = 0 ] && [ "$have" = shipped ] && exit 0

if [ "$want" = 1 ]; then
  # Biggest first: the front end scales this, so a 512x512 source stays sharp.
  # These are the paths in an extracted 0.8.1 APK; a different build that does
  # not have them simply leaves the icon alone.
  src=
  for c in "$DATA/game081/res/drawable/iconx.png" \
           "$DATA/game081/assets/app/ios/icons/mcpe_ios_icon.png" \
           "$DATA/game081/assets/app/ios/icons/Icon@2x.png"; do
    if [ -f "$c" ]; then src=$c; break; fi
  done
  if [ -z "$src" ]; then
    echo "[icon] game-icon.txt is on, but no icon was found in your installed game"
    exit 0
  fi
  # Keep the shipped icon before overwriting it, once, so "off" can put it back.
  if [ ! -f "$BACKUP" ] && ! cp "$ART" "$BACKUP" 2>/dev/null; then
    echo "[icon] could not keep a copy of the shipped icon; leaving it alone"
    exit 0
  fi
  if cp "$src" "$ART" 2>/dev/null; then
    sync
    echo "game" > "$STATE" 2>/dev/null
    echo "[icon] front-end icon taken from your own game files ($src)"
  else
    echo "[icon] could not write $ART; is the card read-only?"
  fi
else
  if [ -f "$BACKUP" ] && cp "$BACKUP" "$ART" 2>/dev/null; then
    sync
    echo "shipped" > "$STATE" 2>/dev/null
    echo "[icon] restored the icon this port ships"
  elif [ ! -f "$BACKUP" ]; then
    # Never turned on, or the backup was removed. Nothing to restore, and
    # claiming otherwise would be worse than saying so.
    echo "shipped" > "$STATE" 2>/dev/null
  else
    echo "[icon] could not restore $ART"
  fi
fi
