#!/bin/sh
# NanoCraft - Minecraft Pocket Edition 0.8.1 on the Anbernic RG Nano.
# OPK entry point.
#
# The OPK holds the launcher only. A squashfs mount is read-only, so the game,
# the GL stack, saves and settings all live under /mnt/FunKey/nanocraft/.
#
# This deliberately does NOT run "frontend set none". That writes
# /mnt/disable_frontend on the persistent vfat partition, so any launch that
# never reaches its matching restore - a SIGKILL, a crash, a flat battery -
# leaves the console booting with no launcher. GMenu2X hands the framebuffer
# over on its own when it starts an OPK, so there is nothing to take.
set -u

APP_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
DATA=/mnt/FunKey/nanocraft
LOG=$DATA/run.log
KEYMAP=/usr/local/sbin/keymap
MAIN=$$

mkdir -p "$DATA" 2>/dev/null

# The port's own runtime has to be there; nothing can substitute for it.
if [ ! -f "$DATA/ninecraft" ]; then
  {
    echo "NanoCraft's runtime is missing."
    echo "Extract the release payload into $DATA/ - it should contain:"
    echo "  ninecraft   runtime/  gl/  mesa/  egl-wrap/  lib/"
  } >> "$LOG" 2>/dev/null
  exit 1
fi

# The game is the user's own and is installed from their own APK. Run the
# installer automatically rather than making them find a shell: on a console
# with no keyboard, "put the apk on the card and launch the game" is the only
# workflow that can actually be completed on the device.
if [ ! -f "$DATA/game081/lib/armeabi-v7a/libminecraftpe.so" ]; then
  sh "$APP_DIR/install-apk.sh" >> "$LOG" 2>&1
  if [ ! -f "$DATA/game081/lib/armeabi-v7a/libminecraftpe.so" ]; then
    echo "[opk] no game installed - see $DATA/install.log" >> "$LOG"
    exit 1
  fi
fi

# --- graphics options --------------------------------------------------------
# Minecraft's own settings are the largest lever on this hardware by a wide
# margin - the MM+ port measured Low Quality alone at +189%, against single
# digits for every presentation-layer trick. They are also the thing most likely
# to be silently missing.
#
# Every performance figure quoted for this port was measured on a console whose
# options.txt had been carried over from the developer's Miyoo Mini Plus card. A
# fresh install has none of it and starts on Minecraft's defaults. The MM+
# handoff records the same lesson from the same mistake: a setting that exists
# only on the developer's machine is not a setting, it is a coincidence.
#
# Seeded ONLY when the game has never run, so it is a good default rather than a
# policy - change anything you like in game afterwards and it will stick.
set_option() {
  _f=$1; _k=$2; _v=$3
  mkdir -p "$(dirname "$_f")" 2>/dev/null
  if grep -q "^${_k}:" "$_f" 2>/dev/null; then
    sed -i "s/^${_k}:.*/${_k}:${_v}/" "$_f"
  else
    echo "${_k}:${_v}" >> "$_f"
  fi
}

GAMEOPTS="$DATA/home/storage/games/com.mojang/minecraftpe/options.txt"
if [ ! -f "$GAMEOPTS" ]; then
  set_option "$GAMEOPTS" gfx_renderdistance  3
  set_option "$GAMEOPTS" gfx_fancygraphics   0
  set_option "$GAMEOPTS" gfx_fancyskies      0
  set_option "$GAMEOPTS" gfx_animatetextures 0
  set_option "$DATA/home/options.txt" gfx_fancygraphics false
  set_option "$DATA/home/options.txt" gfx_lowquality    true
  echo "[opk] seeded performance options for a fresh install" >> "$LOG"
fi

# --- memory ------------------------------------------------------------------
# Entering a world needs about 68 MB of anonymous memory (measured: 40 MB
# resident plus 28 MB swapped) on a console with 56 MB of RAM. With the stock
# 128 MB swap partition that is fine and this does nothing but log three
# numbers. On a console with little or no swap the menus still fit and the game
# dies the moment a world loads, which is a confusing way to fail.
sh "$APP_DIR/ensure-swap.sh" "$DATA" >> "$LOG" 2>&1

# --- controls ----------------------------------------------------------------
# The binary is the Miyoo Mini Plus build and reads /dev/input/event0 expecting
# that console's evdev codes. fkgpiod is what turns GPIO into the uinput
# keyboard, so remapping it at the source costs nothing at runtime and needs no
# rebuild. See minecraft.key for the off-by-one in its config parser.
#
# The menu trigger lives on the writable partition rather than in the OPK,
# because fkgpiod runs it from a COMMAND mapping and the keymap outlives the
# squashfs mount. Refreshed from the package every launch so the OPK stays the
# source of truth.
cp -f "$APP_DIR/pemenu.sh" "$DATA/pemenu.sh" 2>/dev/null
chmod +x "$DATA/pemenu.sh" 2>/dev/null

KEYFILE="$APP_DIR/minecraft.key"
[ -f "$DATA/minecraft.key" ] && KEYFILE="$DATA/minecraft.key"
[ -x "$KEYMAP" ] && "$KEYMAP" load "$KEYFILE" && sleep 1

# --- cleanup helpers ---------------------------------------------------------
release_swap() {
  [ -f "$DATA/.swap-loop" ] || return 0
  _l=$(cat "$DATA/.swap-loop" 2>/dev/null)
  [ -n "$_l" ] || return 0
  swapoff "$_l" 2>/dev/null
  losetup -d "$_l" 2>/dev/null
  rm -f "$DATA/.swap-loop"
  # The backing file stays: creating it is the slow part, and reusing it makes
  # every later launch instant.
}

# Always hand the console back at its stock clock. An overclock set from the
# quick menu is a register write with no thermal management behind it, and
# leaving it applied after the game exits would be a surprise. It does not
# survive a reboot either way.
restore_clock() {
  [ -x "$APP_DIR/nano-clk" ] && "$APP_DIR/nano-clk" --restore >/dev/null 2>&1
}

# --- starting the game -------------------------------------------------------
# In a function because the quick menu can ask for a restart, which is how a
# screen-size change is applied: the size is read by the game at startup and
# cannot be changed in a running process.
GAME=
start_game() {
  # 240x240 is native and the default. 120x120 buys about 4 fps but clips the
  # hotbar, because Minecraft scales its GUI to the render size. Only those two
  # divide the panel cleanly; anything between them shimmers.
  W=240; H=240
  [ -f "$DATA/resolution.txt" ] && read W H < "$DATA/resolution.txt" 2>/dev/null
  case "$W" in ''|*[!0-9]*) W=240; H=240 ;; esac
  case "$H" in ''|*[!0-9]*) W=240; H=240 ;; esac
  echo "[opk] starting at ${W}x${H}" >> "$LOG"

  # MIYOO_NO_GRAB=1 is what makes the quick menu possible. Ninecraft would
  # otherwise take an exclusive EVIOCGRAB on /dev/input/event0 and no other
  # process could read the buttons. Releasing it costs nothing here: the grab
  # exists to keep a front end from also seeing input, and no front end is
  # running while an OPK has the screen.
  MCPE_DATA="$DATA" NINECRAFT_WIDTH="$W" NINECRAFT_HEIGHT="$H" MIYOO_NO_GRAB=1 \
    sh "$APP_DIR/launch-pe-nano.sh" "$DATA/game081" >> "$LOG" 2>&1 &
  GAME=$!

  # Diagnostic hook: inert unless a diagnostic build sets NANOCRAFT_DIAG=1. A
  # crash's program counter means nothing on its own; resolved against the
  # process's memory map it names the library that faulted. REFRESH the map
  # rather than keeping the first one - libraries are added as the game starts,
  # so an early capture contains only the loader and ninecraft and any later
  # fault resolves to nothing.
  if [ "${NANOCRAFT_DIAG:-0}" = 1 ]; then
    ( n=0
      while [ $n -lt 3600 ] && kill -0 "$GAME" 2>/dev/null; do
        P=$(pgrep -f '[l]d-linux-armhf' 2>/dev/null | head -1)
        if [ -n "$P" ] && [ -r "/proc/$P/maps" ]; then
          cat "/proc/$P/maps"   > "$DATA/diag-maps.txt.new" 2>/dev/null &&
            mv -f "$DATA/diag-maps.txt.new" "$DATA/diag-maps.txt" 2>/dev/null
          cat "/proc/$P/status" > "$DATA/diag-status.txt" 2>/dev/null
          echo "$P" > "$DATA/diag-pid.txt" 2>/dev/null
        fi
        sleep 3
        n=$(( n + 3 ))
      done ) >/dev/null 2>&1 &
  fi
}

# Ninecraft does not necessarily honour SIGTERM, and a "close game" that leaves
# the game running is worse than not offering it. Ask politely, then insist.
stop_game() {
  kill -TERM "$GAME" 2>/dev/null
  i=0
  while [ $i -lt 12 ] && kill -0 "$GAME" 2>/dev/null; do
    sleep 0.25
    i=$((i + 1))
  done
  kill -KILL "$GAME" 2>/dev/null
}

# --- quick menu --------------------------------------------------------------
# THE MENU IS DRAWN BY THE FOREGROUND APP, NOT BY THE OS. fkgpiod answers the
# power button with `powerdown schedule 0.1`, which sends SIGUSR1 to the
# registered foreground process - this script, recorded by opkrun via
# `pid record` - and then powers the console off 100 ms later unless something
# cancels it. GMenu2X's power menu is GMenu2X catching that signal. An app that
# ignores it simply gets cut off mid-session.
#
# The same trap serves both triggers: the power button, and L+FN, which fkgpiod
# routes here through pemenu.sh. L+FN is the safer of the two - a power press
# starts a 100 ms countdown that this has to win.
MENUFLAG=/tmp/nanocraft.menu
RESTART_REQUESTED=0
on_power() {
  # Cancel first and ask questions later. Inline pkill rather than
  # `powerdown handle`, which would fork a second shell to do exactly this.
  pkill -f "powerdown schedule" 2>/dev/null

  # A second press while the menu is already up must only cancel that new
  # shutdown, never stack another menu on top of the first.
  [ -f "$MENUFLAG" ] && return
  : > "$MENUFLAG"

  # Freeze the game so it stops repainting /dev/fb0, then let the menu grab the
  # buttons and own the screen.
  kill -STOP "$GAME" 2>/dev/null
  MCPE_DATA="$DATA" /usr/bin/python3 "$APP_DIR/quickmenu.py" >> "$LOG" 2>&1
  rc=$?
  rm -f "$MENUFLAG"
  kill -CONT "$GAME" 2>/dev/null
  case "$rc" in
    2) stop_game ;;
    3) stop_game
       restore_clock
       /usr/local/sbin/powerdown now ;;
    4) RESTART_REQUESTED=1
       stop_game ;;
    *) : ;;
  esac
}
trap on_power USR1

# --- lifecycle ---------------------------------------------------------------
# Restore the console's normal state however this ends. A trap alone is not
# enough - it does not run on SIGKILL, and a console left holding NanoCraft's
# keymap has an unusable front end. This watches THIS SCRIPT rather than the
# game, because the game legitimately comes and goes across a restart.
( while kill -0 "$MAIN" 2>/dev/null; do sleep 5; done
  [ -x "$KEYMAP" ] && "$KEYMAP" default
  release_swap
  restore_clock ) >/dev/null 2>&1 &

RC=0
while : ; do
  RESTART_REQUESTED=0
  start_game

  # WAIT IN A LOOP, because `wait` returns as soon as a trapped signal has been
  # handled - it does not resume. With a bare `wait` the first menu press fell
  # straight through to the exit path, leaving the game running with no
  # lifecycle owner: the registered PID for the power signal was dead, so the
  # menu never opened again and nothing restored the keymap. That is the whole
  # reason the quick menu used to work exactly once per launch.
  while kill -0 "$GAME" 2>/dev/null; do
    wait "$GAME"
    RC=$?
  done

  [ "$RESTART_REQUESTED" = 1 ] || break
  echo "[opk] restarting at the new screen size" >> "$LOG"
done

[ -x "$KEYMAP" ] && "$KEYMAP" default
release_swap
restore_clock
echo "[opk] exit rc=$RC" >> "$LOG"
exit "$RC"
