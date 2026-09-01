#!/bin/sh
# install-apk.sh - turn a user-supplied Pocket Edition APK into a playable game
# directory under /mnt/FunKey/nanocraft/game081/.
#
# WHY THIS EXISTS: no Minecraft files ship with NanoCraft and none ever can. The
# owner supplies their own legally obtained armeabi-v7a APK, drops it on the
# card, and this extracts it unchanged. Nothing is patched or repacked --
# Ninecraft loads the original library straight out of the extraction.
#
# Ported from the MM+ port's install-pe-apk.sh. The differences are that this
# console has no `prompt` dialog binary, so everything reports through the log,
# and that only 0.8.1 is accepted because that is what NanoCraft targets.
#
# Exit: 0 = a game is installed and ready, 1 = nothing installed.
set -u

DATA=${NANOCRAFT_DATA:-/mnt/FunKey/nanocraft}
APKDIR=${NANOCRAFT_APKDIR:-$DATA/apk}
DEST=$DATA/game081
LOG=$DATA/install.log

: > "$LOG" 2>/dev/null
mkdir -p "$APKDIR" 2>/dev/null

say() {
  echo "$*"
  echo "$*" >> "$LOG" 2>/dev/null
}

# --- find candidate APKs ------------------------------------------------------
# The documented drop folder, plus the card root, which is where a file copied
# from a PC most often lands.
set --
for f in "$APKDIR"/*.apk "$APKDIR"/*.APK /mnt/*.apk /mnt/*.APK; do
  [ -f "$f" ] && set -- "$@" "$f"
done

if [ "$#" = 0 ]; then
  say "No Minecraft APK found."
  say ""
  say "NanoCraft ships NO game files. You supply your own copy of"
  say "Minecraft Pocket Edition 0.8.1 (armeabi-v7a, 32-bit)."
  say ""
  say "Put the .apk in:  $APKDIR/"
  say "(the root of the card also works), then launch NanoCraft again."
  exit 1
fi

APK=$1
say "Using $(basename "$APK")"

# --- unwrap if necessary ------------------------------------------------------
# Scratch goes on the card, not /tmp: /tmp is RAM-backed here and an inner APK
# runs to 10-16 MB on a console with 55 MB of RAM.
WORK=$DATA/.work.$$
mkdir -p "$WORK" || exit 1
INNER=$APK

if ! unzip -l "$APK" 2>/dev/null | grep -q "lib/armeabi-v7a/libminecraftpe.so"; then
  if unzip -l "$APK" 2>/dev/null | grep -q "assets/applications/package.apk"; then
    say "Wrapper APK detected, extracting the inner package."
    unzip -p "$APK" assets/applications/package.apk > "$WORK/inner.apk" 2>/dev/null
    INNER=$WORK/inner.apk
  fi
fi

if ! unzip -l "$INNER" 2>/dev/null | grep -q "lib/armeabi-v7a/libminecraftpe.so"; then
  say "That APK has no armeabi-v7a game library."
  say "The RG Nano is 32-bit ARM, so an arm64 or x86 APK cannot run."
  rm -rf "$WORK"
  exit 1
fi

# --- identify the version -----------------------------------------------------
# The binary manifest stores strings as UTF-16, so dropping NUL bytes turns it
# back into something greppable.
VER=$(unzip -p "$INNER" AndroidManifest.xml 2>/dev/null | tr -d '\000' \
      | grep -oE '0\.[0-9]{1,2}\.[0-9]{1,2}' | head -1)
say "Manifest version: ${VER:-unknown}"

if [ "$VER" != "0.8.1" ]; then
  say "NanoCraft targets Pocket Edition 0.8.1 and this APK reports"
  say "${VER:-an unknown version}. Other versions are not supported here."
  rm -rf "$WORK"
  exit 1
fi

# --- extract ------------------------------------------------------------------
say "Installing 0.8.1 - this takes a minute and the screen will not move."
rm -rf "$DEST"
mkdir -p "$DEST" || { rm -rf "$WORK"; exit 1; }

if ! unzip -q -o "$INNER" -d "$DEST" 2>>"$LOG"; then
  say "Extraction failed. The card may be full, or the APK may be damaged."
  rm -rf "$WORK" "$DEST"
  exit 1
fi
rm -rf "$WORK"

if [ ! -f "$DEST/lib/armeabi-v7a/libminecraftpe.so" ]; then
  say "The game library is missing after extraction. The APK may be damaged."
  rm -rf "$DEST"
  exit 1
fi

say "Installed. $(du -sh "$DEST" 2>/dev/null | cut -f1) extracted to game081/."
exit 0
