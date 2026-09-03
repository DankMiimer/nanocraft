#!/bin/sh
# diagnose.sh - NanoCraft diagnostic build.
#
# PURPOSE: gather, in ONE run, everything needed to explain a crash on someone
# else's console, so a tester is asked once rather than five times.
#
# IT WRITES A FILE AND SENDS NOTHING. Everything below lands in
# /mnt/FunKey/nanocraft/nanocraft-report.txt, and the tester decides whether to
# share it. There is no network code here and there never will be. What it
# collects is hardware and this port's own state - no personal files, no
# credentials, no game content.
#
# WHAT IT DOES
#   1. Records the console: kernel, SoC, memory, storage, framebuffer, buttons.
#   2. Probes how much memory a process can really get (a world needs ~68 MB).
#   3. Turns on the kernel's fatal-signal reporting.
#   4. Launches the game normally. The tester plays until it crashes or quits.
#   5. Resolves any crash address against the game's memory map, naming the
#      library that faulted.
set -u

APP_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
DATA=/mnt/FunKey/nanocraft
REPORT=$DATA/nanocraft-report.txt
RUNLOG=$DATA/run.log

mkdir -p "$DATA" 2>/dev/null

say() { echo "$@" >> "$REPORT"; }
rule() { say "-------------------------------------------------------------------"; }
sec() { say ""; rule; say "$1"; rule; }
run() { say "\$ $*"; "$@" >> "$REPORT" 2>&1 || say "  (command failed or absent)"; say ""; }

: > "$REPORT"
say "NanoCraft diagnostic report"
say "Generated: $(date 2>/dev/null)"
say ""
say "This file was produced on the owner's own console by the NanoCraft"
say "diagnostic build. It contains hardware information and this port's own"
say "state. It contains no personal files, no credentials and no game content."
say "Nothing was transmitted anywhere - the file is yours to share or delete."

sec "1. CONSOLE"
run uname -a
run cat /etc/os-release
say "\$ cat /proc/cpuinfo"
grep -E 'model name|Hardware|Revision|Features|processor' /proc/cpuinfo >> "$REPORT" 2>&1
say ""
say "\$ cpu clock"
[ -x "$DATA/nano-clk" ] && "$DATA/nano-clk" >> "$REPORT" 2>&1 || say "  (nano-clk not installed)"
say ""

sec "2. MEMORY AND SWAP"
run free -m
say "\$ grep /proc/meminfo"
grep -E '^(MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapTotal|SwapFree|Committed_AS|CommitLimit)' /proc/meminfo >> "$REPORT" 2>&1
say ""
run cat /proc/swaps
say "\$ vm settings"
for f in swappiness overcommit_memory overcommit_ratio min_free_kbytes max_map_count; do
  say "  vm.$f = $(cat /proc/sys/vm/$f 2>/dev/null)"
done
say ""

sec "3. STORAGE"
run df -h
say "\$ mount (filesystem types matter: swap files do not work on vfat)"
mount | grep -E ' / | /mnt ' >> "$REPORT" 2>&1
say ""
run losetup -a
say "\$ loop devices present"
ls /dev/loop* >> "$REPORT" 2>&1
say ""

sec "4. DISPLAY"
say "\$ framebuffer geometry"
for f in virtual_size bits_per_pixel stride name; do
  say "  $f = $(cat /sys/class/graphics/fb0/$f 2>/dev/null)"
done
say "  /dev/fb0 size = $(wc -c < /dev/fb0 2>/dev/null) bytes"
say ""

sec "5. BUTTONS"
say "This port remaps buttons at the GPIO source, so the console must expose the"
say "expected set. A different button layout shows up here."
run cat /proc/bus/input/devices
say "\$ keymap currently loaded"
/usr/local/sbin/keymap save /tmp/diag-keymap.key >/dev/null 2>&1
sleep 1
cat /tmp/diag-keymap.key >> "$REPORT" 2>&1 || say "  (keymap tool unavailable)"
say ""

sec "6. NANOCRAFT INSTALL"
say "\$ ls $DATA"
ls -la "$DATA" >> "$REPORT" 2>&1
say ""
say "\$ identity of the shipped launcher and the user's game library"
for f in "$DATA/ninecraft" "$DATA/game081/lib/armeabi-v7a/libminecraftpe.so"; do
  if [ -f "$f" ]; then
    say "  $(wc -c < "$f") bytes  $(sha256sum "$f" 2>/dev/null | cut -d' ' -f1)  $f"
  else
    say "  MISSING: $f"
  fi
done
say ""
say "  reference: the tested game library is"
say "  9668996 bytes  baf9ca243fa301b7a9b4755ddc97aba1f0d35c9b1b80479980b47d6455a32677"
say ""
say "\$ install log"
tail -25 "$DATA/install.log" >> "$REPORT" 2>&1 || say "  (none)"
say ""

sec "7. MEMORY PROBE (no game running)"
say "Can a process actually obtain a world's working set on this console?"
say ""
python3 "$APP_DIR/memprobe.py" 80 >> "$REPORT" 2>&1
say ""

sec "8. GAME RUN"
say "The game now starts normally. PLAY UNTIL IT CRASHES, or quit with a long"
say "press on MENU if it does not. This report finishes itself afterwards."
say ""

# Fault reporting must be on BEFORE the crash, and the ring buffer wants
# clearing so the dump we read is definitely this run's.
echo 1 > /proc/sys/kernel/print-fatal-signals 2>/dev/null \
  && say "  kernel fatal-signal reporting: enabled" \
  || say "  kernel fatal-signal reporting: could NOT be enabled"
dmesg -c > /dev/null 2>&1
rm -f "$DATA/diag-maps.txt" "$DATA/diag-status.txt" "$DATA/diag-pid.txt"
: > "$RUNLOG"

START=$(date +%s 2>/dev/null)
NANOCRAFT_DIAG=1 sh "$APP_DIR/run.sh"
RC=$?
END=$(date +%s 2>/dev/null)

say "  exit code: $RC"
[ "$RC" = 139 ] && say "             139 = 128 + 11, i.e. SIGSEGV - the game faulted"
[ "$RC" = 137 ] && say "             137 = 128 + 9, i.e. SIGKILL - very likely the OOM killer"
[ "$RC" = 0 ]   && say "             0 = clean exit, no crash this run"
say "  ran for:   $(( ${END:-0} - ${START:-0} )) seconds"
say ""
say "\$ memory held by the game just before it ended"
grep -E '^(Vm|Threads)' "$DATA/diag-status.txt" >> "$REPORT" 2>&1 || say "  (not captured)"
say ""
say "\$ launcher and game log"
tail -40 "$RUNLOG" >> "$REPORT" 2>&1
say ""

sec "9. CRASH ATTRIBUTION"
dmesg > "$DATA/diag-dmesg.txt" 2>/dev/null
python3 "$APP_DIR/resolve-fault.py" "$DATA/diag-dmesg.txt" "$DATA/diag-maps.txt" >> "$REPORT" 2>&1
say ""
say "\$ kernel messages (tail)"
tail -30 "$DATA/diag-dmesg.txt" >> "$REPORT" 2>&1
say ""

sec "END OF REPORT"
say "Send: $REPORT"

# Leave the console as we found it.
echo 0 > /proc/sys/kernel/print-fatal-signals 2>/dev/null

# Tell the tester on the screen, since they cannot see this file from the couch.
if [ -f "$APP_DIR/diagbg.raw" ]; then
  cat "$APP_DIR/diagbg.raw" > /dev/fb0 2>/dev/null
  sleep 8
fi
exit 0
