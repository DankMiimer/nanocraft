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
# The quick menu. A static ARM binary that ships in the package, so it does not
# matter what the console's firmware provides - the Python version it replaces
# could not run on the factory image at all, which is how a missing interpreter
# came to look like the game hanging.
MENUCMD="$APP_DIR/quickmenu"

# Seconds since boot, for stamping log lines. Ordering in this file has been
# read wrongly more than once: a line written by a signal handler can land
# anywhere relative to the loop that follows it.
now() { cut -d. -f1 /proc/uptime; }
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
# A world needs about 65 MB of anonymous memory (measured: 28 MB resident plus
# 37 MB swapped) on a console with 56 MB of RAM. ensure-memory.sh closes that
# gap with compressed RAM instead of a swap file on the card, and refuses to
# launch rather than quietly paging to flash - there is no fallback to the card,
# by design. The measurements and the sizing live in that script.
if ! sh "$APP_DIR/ensure-memory.sh" "$DATA" >> "$LOG" 2>&1; then
  echo "[opk] could not set up compressed memory - see $LOG" >> "$LOG"
  exit 1
fi

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
if [ -x "$KEYMAP" ] && "$KEYMAP" load "$KEYFILE"; then
  echo "[opk] keymap loaded from $KEYFILE" >> "$LOG"
  sleep 1
else
  # Worth saying out loud: without the remap the game receives another
  # console's key codes, and every button does the wrong thing.
  echo "[opk] KEYMAP NOT LOADED ($KEYMAP) - buttons will be wrong" >> "$LOG"
fi

# --- cleanup helpers ---------------------------------------------------------
release_memory() {
  # The firmware's own swap goes back FIRST, so that swapping off zram has
  # somewhere to put anything still held there. By this point the game has
  # exited and that is a few hundred KB, but the ordering costs nothing.
  if [ -s "$DATA/.disk-swap" ]; then
    while read -r _d; do
      [ -n "$_d" ] && swapon "$_d" 2>/dev/null
    done < "$DATA/.disk-swap"
    rm -f "$DATA/.disk-swap"
  fi
  grep -q '^/dev/zram0 ' /proc/swaps && swapoff /dev/zram0 2>/dev/null
  [ -e /sys/block/zram0/reset ] && echo 1 > /sys/block/zram0/reset 2>/dev/null
  # The modules stay loaded. They cost 97 KB of kernel memory and reloading
  # them on every launch buys nothing.
  return 0
}

# Always hand the console back at its stock clock. An overclock set from the
# quick menu is a register write with no thermal management behind it, and
# leaving it applied after the game exits would be a surprise. It does not
# survive a reboot either way.
restore_clock() {
  [ -x "$APP_DIR/nano-clk" ] && "$APP_DIR/nano-clk" --restore >/dev/null 2>&1
  # Reaching here means the console survived the session at whatever clock was
  # applied, so the saved one is trusted for next time.
  rm -f "$DATA/.clock-pending"
}

# --- remembered CPU clock -----------------------------------------------------
# Screen size, interface scale, FOV and the frame cap have always been written to
# the card and read back here. The clock was the exception: it applied at once
# and was restored to stock on exit, so it had to be dialled in again every
# launch. The quick menu now writes clock.txt and this puts it back.
#
# The stock clock is still restored when the game exits - nothing outside the
# game is left overclocked, and a reboot clears it regardless.
#
# THE GUARD MATTERS. This SoC has no thermal management and no voltage control,
# and what an individual unit tolerates is not knowable from here. A saved clock
# that hangs the console would otherwise hang it on every launch, with no way
# back except editing the card. So a marker is written before applying and
# cleared only after the game has exited normally; if it is still there at
# startup, the last run at this clock did not finish and stock is used instead.
if [ -f "$DATA/clock.txt" ] && [ -x "$APP_DIR/nano-clk" ]; then
  read SAVED_MHZ < "$DATA/clock.txt" 2>/dev/null || SAVED_MHZ=
  case "${SAVED_MHZ:-}" in ''|*[!0-9]*) SAVED_MHZ= ;; esac
  if [ -n "${SAVED_MHZ:-}" ] && [ -f "$DATA/.clock-pending" ]; then
    echo "[opk] last run at ${SAVED_MHZ} MHz did not exit cleanly - using stock" >> "$LOG"
    rm -f "$DATA/.clock-pending"
  elif [ -n "${SAVED_MHZ:-}" ]; then
    : > "$DATA/.clock-pending"
    sync
    "$APP_DIR/nano-clk" --set "$SAVED_MHZ" >> "$LOG" 2>&1
    echo "[opk] restored saved CPU clock ${SAVED_MHZ} MHz" >> "$LOG"
  fi
fi

# --- loopback -----------------------------------------------------------------
# Pressing Play opens the world/server list, and 0.8.1 answers that by asking
# RakNet to broadcast for LAN games. On a console with no network interface at
# all that path faults - RakPeer::Ping dereferences a null - and the game dies
# about eight seconds in, leaving the last frame on the panel. It never happened
# on the console this port was developed on because that one has a WiFi dongle.
#
# Loopback costs nothing and exists on every kernel; bringing it up gives the
# socket layer something real to answer with. Logged either way, because if the
# crash survives this it rules the theory out rather than leaving it hanging.
if [ -x /sbin/ifconfig ]; then
  /sbin/ifconfig lo up 2>/dev/null
  echo "[opk] interfaces: $(/sbin/ifconfig 2>/dev/null | awk '/^[a-z]/ {printf "%s ", $1}')" >> "$LOG"
elif [ -x /sbin/ip ]; then
  /sbin/ip link set lo up 2>/dev/null
  echo "[opk] interfaces: $(/sbin/ip -o link 2>/dev/null | awk '{printf "%s ", $2}')" >> "$LOG"
else
  echo "[opk] no ifconfig or ip on this firmware" >> "$LOG"
fi

# --- experiment hook ----------------------------------------------------------
# A plain KEY=VALUE file on the card, applied to the game's environment if it is
# present. It exists so a setting can be A/B tested on the console without
# rebuilding and reinstalling the package for every idea - which on a console
# with no network is otherwise a card swap per attempt.
#
# set -a exports what the file defines, because launch-pe-nano.sh reads these
# from the environment and every value it takes is written as ${VAR:-default}.
if [ -f "$DATA/env.txt" ]; then
  set -a
  . "$DATA/env.txt"
  set +a
  echo "[opk] env.txt applied: $(tr '
' ' ' < "$DATA/env.txt")" >> "$LOG"
fi

# --- optional memory trace ----------------------------------------------------
# Off unless $DATA/memtrace exists, so it costs one test for everybody else.
#
# It exists because the interesting failure on this hardware leaves a picture on
# the screen and no exit code to read: the game dies, nothing repaints, and the
# console has to be power-cycled. Anything not written and synced before that is
# gone. So this writes as it goes, and does not depend on any later step - the
# diagnostic build's own crash section never runs if the console is powered off
# while it is still waiting for the game.
#
# POSIX shell only. The factory firmware ships no Python.
if [ -f "$DATA/memtrace" ]; then
  # Make the kernel print faulting addresses. The diagnostic build does this
  # too, but the normal build is what people actually run.
  echo 1 > /proc/sys/kernel/print-fatal-signals 2>/dev/null
  (
    TRACE=$DATA/memtrace.log
    KLOG=$DATA/memtrace-dmesg.txt
    TLOG=$DATA/memtrace-threads.txt
    MLOG=$DATA/memtrace-maps.txt
    echo "# t state avail_kb free_kb zram_orig_kb zram_ram_kb rss_kb vmswap_kb SigIgn SigCgt pgrp found game alive" > "$TRACE"
    t=0
    gpid=
    while kill -0 "$MAIN" 2>/dev/null; do
      # Look every tick rather than caching the pid. Caching meant that if the
      # game's pid ever changed - a fork, a re-exec - the tracer went on
      # watching a pid that no longer existed and reported it gone, while the
      # real process carried on running. Every "it exits after ten seconds"
      # reading came from that.
      gpid=
      for c in /proc/[0-9]*/cmdline; do
        if tr '\000' ' ' < "$c" 2>/dev/null | grep -q '/nanocraft/ninecraft'; then
          gpid=$(echo "$c" | cut -d/ -f3)
          break
        fi
      done 2>/dev/null
      state=none
      rss=0
      vmswap=0
      sigign=-
      sigcgt=-
      pgrp=-
      if [ -n "$gpid" ] && [ -r "/proc/$gpid/stat" ]; then
        state=$(awk '{print $3}' "/proc/$gpid/stat" 2>/dev/null)
        # Field 5 is the process group. If it matches the launcher's, a signal
        # sent to the group reaches the game whatever the launcher intended.
        pgrp=$(awk '{print $5}' "/proc/$gpid/stat" 2>/dev/null)
        rss=$(awk '/^VmRSS:/ {print $2}' "/proc/$gpid/status" 2>/dev/null)
        vmswap=$(awk '/^VmSwap:/ {print $2}' "/proc/$gpid/status" 2>/dev/null)
        # SIGUSR1 is signal 10, so bit 9 - mask 0x200. Ignored means the
        # launcher's `trap "" USR1` survived exec; caught means the game
        # installed its own handler afterwards and undid it.
        sigign=$(awk '/^SigIgn:/ {print $2}' "/proc/$gpid/status" 2>/dev/null)
        sigcgt=$(awk '/^SigCgt:/ {print $2}' "/proc/$gpid/status" 2>/dev/null)
      elif [ -n "$gpid" ]; then
        state=gone
      fi
      avail=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
      free=$(awk '/^MemFree:/ {print $2}' /proc/meminfo)
      if [ -r /sys/block/zram0/mm_stat ]; then
        set -- $(cat /sys/block/zram0/mm_stat)
        zo=$(( $1 / 1024 )); zr=$(( $3 / 1024 ))
      else
        zo=0; zr=0
      fi
      # $GAME is run.sh's own child pid, in scope here because this is a
      # subshell of it. Recording both it and the pid found by scanning /proc
      # settles whether they are the same process - the trace has said "gone"
      # while run.sh went on waiting, and both cannot be right.
      if kill -0 "${GAME:-}" 2>/dev/null; then galive=y; else galive=n; fi
      echo "$t ${state:-?} $avail $free $zo $zr ${rss:-0} ${vmswap:-0} ${sigign:--} ${sigcgt:--} ${pgrp:--} found=${gpid:--} game=${GAME:-none} alive=$galive" >> "$TRACE"
      # A process in state S is blocked on something, and wchan names what. The
      # game runs eight threads and the blocked one need not be the leader, so
      # dump them all. Overwritten each tick: the copy that matters is the last
      # one before the console is powered off.
      if [ -n "$gpid" ] && [ -d "/proc/$gpid/task" ]; then
        {
          echo "t=$t  pid=$gpid"
          for tk in /proc/"$gpid"/task/*; do
            tid=${tk##*/}
            tst=$(awk '{print $3}' "$tk/stat" 2>/dev/null)
            twc=$(cat "$tk/wchan" 2>/dev/null)
            # comm names the thread - llvmpipe-0, an audio thread, a chunk
            # builder - which is the difference between counting blocked threads
            # and knowing which part of the port is stuck.
            tnm=$(cat "$tk/comm" 2>/dev/null)
            # syscall is "nr arg0 arg1 ... sp pc". For a futex wait arg0 is the
            # address being waited on, so threads queued on the SAME address are
            # queued on the same lock - which is what names the deadlock rather
            # than just proving there is one.
            tsc=$(cat "$tk/syscall" 2>/dev/null)
            echo "  tid=$tid name=${tnm:-?} state=${tst:-?} wchan=${twc:-?}"
            echo "      syscall=${tsc:-unavailable}"
          done
        } > "$TLOG" 2>/dev/null
      fi

      # The map, captured in the SAME tick as the thread dump. Addresses move
      # with ASLR, so a map from another run resolves nothing - and the blocked
      # program counters are the whole question: which library the deadlocked
      # threads are parked in.
      if [ -n "$gpid" ] && [ -r "/proc/$gpid/maps" ]; then
        cat "/proc/$gpid/maps" > "$MLOG" 2>/dev/null
      fi

      # The kernel ring buffer carries the fatal-signal line with the faulting
      # address. Rewrite it every tick rather than reading it once at the end,
      # because there may be no end.
      dmesg > "$KLOG" 2>/dev/null
      sync
      t=$(( t + 1 ))
      sleep 1
    done
  ) >/dev/null 2>&1 &
fi

# --- starting the game -------------------------------------------------------
# In a function because the quick menu can ask for a restart, which is how a
# screen-size change is applied: the size is read by the game at startup and
# cannot be changed in a running process.
GAME=
ENDED_BY_MENU=0
start_game() {
  # 120x120 is the default: it renders in a quarter of the pixels for about
  # 11.9 fps against 240x240's 7.8, and the reason it was not the default before
  # -- a hotbar with both ends cut off -- is fixed. The cost is now only a soft
  # 2x upscale. 240x240 is native and sharper, and is one row away in the quick
  # menu. Those are the only two sizes that divide the panel cleanly; anything
  # between them shimmers.
  W=120; H=120
  [ -f "$DATA/resolution.txt" ] && read W H < "$DATA/resolution.txt" 2>/dev/null
  case "$W" in ''|*[!0-9]*) W=120; H=120 ;; esac
  case "$H" in ''|*[!0-9]*) W=120; H=120 ;; esac

  # Interface scale, from the quick menu's video page. Ninecraft floors its GUI
  # scale at 1.0, and a 182-pixel hotbar does not fit in 120; the patched
  # launcher will go below that floor. "fit" sizes the interface to the hotbar
  # whichever way it has to go, so it is the setting that suits both screen
  # sizes rather than only the default one. Anything the launcher cannot parse
  # it ignores, but keep the obvious junk out.
  GS=fit
  [ -f "$DATA/guiscale.txt" ] && read GS < "$DATA/guiscale.txt" 2>/dev/null
  case "$GS" in ''|*[!0-9a-z.]*) GS=fit ;; esac

  # Field of view, also from the video page. The game has no FOV setting; the
  # launcher rewrites the base angle inside GameRenderer::getFov, which is where
  # setupCamera gets the projection from. 70 is the stock angle and asking for
  # it patches nothing, so an untouched console stays exactly as it was.
  FOV=70
  [ -f "$DATA/fov.txt" ] && read FOV < "$DATA/fov.txt" 2>/dev/null
  case "$FOV" in ''|*[!0-9]*) FOV=70 ;; esac

  # Frame cap, read by the framebuffer presenter rather than by the game. 0 is
  # off, which is how this port behaved before the cap existed. A cap does not
  # speed anything up; it evens out a rate that swings roughly 7 to 18 fps by
  # holding early frames back, and sleeps the difference.
  FPSCAP=0
  [ -f "$DATA/fpscap.txt" ] && read FPSCAP < "$DATA/fpscap.txt" 2>/dev/null
  case "$FPSCAP" in ''|*[!0-9]*) FPSCAP=0 ;; esac
  echo "[opk] t=$(now) starting at ${W}x${H} gui=$GS fov=$FOV cap=$FPSCAP" >> "$LOG"

  # MIYOO_NO_GRAB=1 is what makes the quick menu possible. Ninecraft would
  # otherwise take an exclusive EVIOCGRAB on /dev/input/event0 and no other
  # process could read the buttons. Releasing it costs nothing here: the grab
  # exists to keep a front end from also seeing input, and no front end is
  # running while an OPK has the screen.
  MCPE_DATA="$DATA" NINECRAFT_WIDTH="$W" NINECRAFT_HEIGHT="$H" \
    NINECRAFT_GUI_SCALE="$GS" NINECRAFT_FOV="$FOV" FBEGL_FPS_CAP="$FPSCAP" \
    MIYOO_NO_GRAB=1 \
    sh "$APP_DIR/launch-pe-nano.sh" "$DATA/game081" >> "$LOG" 2>&1 &
  GAME=$!
  echo "[opk] t=$(now) game pid=$GAME" >> "$LOG"

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
  ENDED_BY_MENU=1
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
  # Logged because it is the difference between the game dying on its own
  # and the console asking it to stop, and the exit code alone cannot say
  # which: SIGUSR1 arriving here is the power or menu button.
  echo "[opk] t=$(now) SIGUSR1 received - power/menu button" >> "$LOG"
  # Cancel first and ask questions later. Inline pkill rather than
  # `powerdown handle`, which would fork a second shell to do exactly this.
  pkill -f "powerdown schedule" 2>/dev/null

  # A second press while the menu is already up must only cancel that new
  # shutdown, never stack another menu on top of the first.
  [ -f "$MENUFLAG" ] && return
  : > "$MENUFLAG"

  # Do not freeze the game unless there is really a menu to put in front of it.
  # Stopping it blanks nothing - the last frame stays on the panel - so a menu
  # that then fails to appear is indistinguishable from the console hanging.
  if [ ! -x "$MENUCMD" ]; then
    echo "[opk] no quick menu available ($MENUCMD) - button ignored" >> "$LOG"
    rm -f "$MENUFLAG"
    return
  fi

  # Freeze the game so it stops repainting /dev/fb0, then let the menu grab the
  # buttons and own the screen.
  kill -STOP "$GAME" 2>/dev/null
  MCPE_DATA="$DATA" "$MENUCMD" >> "$LOG" 2>&1
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
  release_memory
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
    _st=$?
    # `wait` also returns when a trapped signal has been handled, with
    # 128+signum, which is not the game's status at all. Believing it produced a
    # log line saying the game had been killed by SIGUSR1 on every run where the
    # menu was opened - and sent a debugging session after a signal that the
    # game demonstrably ignores. Only take the status once the game has gone.
    kill -0 "$GAME" 2>/dev/null || RC=$_st
  done
  # The game's TRUE status, written by the wrapper subshell the moment it
  # returns. $RC cannot be trusted: `wait` also returns when a trapped signal is
  # handled, with 128+signum, and that artifact has been reported as the game's
  # exit code on every run where the power button was pressed.
  # 128+n means signal n killed it: 139 is a segfault, 137 a kill, 138 SIGUSR1.
  # `wait` also returns when a trapped signal is handled, with 128+signum, so
  # $RC is only the game's own status when we did not end it ourselves. Saying
  # which is which matters: a bare 139 in this log is a segfault worth chasing,
  # and for a long time an artifact was being reported as one.
  if [ "$ENDED_BY_MENU" = 1 ]; then
    echo "[opk] t=$(now) game closed from the menu" >> "$LOG"
  else
    echo "[opk] t=$(now) game ended on its own, status=$RC" >> "$LOG"
  fi

  [ "$RESTART_REQUESTED" = 1 ] || break
  echo "[opk] restarting at the new screen size" >> "$LOG"
done

[ -x "$KEYMAP" ] && "$KEYMAP" default
release_memory
restore_clock
echo "[opk] exit rc=$RC" >> "$LOG"
exit "$RC"
