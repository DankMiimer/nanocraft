#!/bin/sh
# ensure-memory.sh - give this console enough memory to load a world, without
# ever writing to the SD card to do it.
#
# WHY, IN NUMBERS. Measured on an RG Nano, two independent sessions:
#
#   in a world     RSS 28 MB + 37 MB swapped   = 65 MB of anonymous memory
#   console RAM    56 MB total
#
# So a world needs about 10 MB more than this hardware physically has. Earlier
# versions of this script closed that gap with a 128 MB swap file on the SD
# card. That worked, and it charged the card's finite flash endurance for every
# world load, forever.
#
# This closes it with zram instead: a compressed block device that lives in RAM.
# Pages the kernel evicts are compressed with LZ4 and kept in memory rather than
# written anywhere. Measured compression on this game's heap is 2.7:1 with about
# 1,500 identical pages deduplicated outright, so 40 MB of evicted pages occupy
# roughly 14 MB. That is the whole trick, and it is enough:
#
#   world entry    3.9 MB of MemAvailable at the worst instant, then 17 MB
#
# Thin, but it holds, and nothing touches the card.
#
# The stock kernel has no zram, so the four modules in modules/ are loaded
# first. They are built from unmodified Linux 4.14.14 configured to match this
# console's kernel; see modules/README.md. Nothing is written to the read-only
# rootfs and a reboot undoes all of it.
#
#   ensure-memory.sh <data-dir> [module-dir]
#
# Exits non-zero if RAM-only swap could not be arranged. There is no fallback to
# the SD card, by design: see the bottom of this file.
set -u

DATA=${1:-/mnt/FunKey/nanocraft}
MODDIR=${2:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/modules}

# Logical capacity of the compressed device. This is NOT an amount of RAM: it is
# how much uncompressed data the kernel may push into it. At the measured ratio
# 80 MB of pages cost about 30 MB of RAM, which is why MEM_LIMIT exists.
DISK_MB=80
# Hard ceiling on the RAM the compressed pool may hold, about 1.7x the 14.4 MB
# peak seen in testing. It is a guard rail, not a working value: it stops an
# unusually incompressible or leaking session from eating the RAM the game needs
# for itself. In normal play it is never approached.
MEM_LIMIT_MB=24

kb() { awk -v k="$1" '$1 == k":" { print $2 }' /proc/meminfo; }
mb() { echo $(( $(kb "$1") / 1024 )); }

echo "[mem] RAM $(mb MemTotal) MB total, $(mb MemAvailable) MB available; swap $(mb SwapTotal) MB"

# --- modules ------------------------------------------------------------------
# Order matters: zram stores pages through zsmalloc and compresses them through
# the crypto API's lz4 shim, which needs the two algorithm modules under it.
load_modules() {
  for m in lz4_compress lz4_decompress lz4 zsmalloc zram; do
    grep -q "^$m " /proc/modules && continue
    if [ ! -f "$MODDIR/$m.ko" ]; then
      echo "[mem] missing $MODDIR/$m.ko"
      return 1
    fi
    if ! insmod "$MODDIR/$m.ko" 2>&1; then
      # Almost always a kernel that these were not built for - a firmware
      # update, or a different console. Say which, because the fix differs.
      echo "[mem] insmod $m failed on kernel $(uname -r)"
      return 1
    fi
  done
  [ -e /sys/block/zram0 ]
}

# --- the compressed device ----------------------------------------------------
setup_zram() {
  if grep -q '^/dev/zram0 ' /proc/swaps; then
    echo "[mem] zram already active, leaving it alone"
    return 0
  fi
  # Clears anything a previous run left half-configured. Refused while the
  # device is in use, which is why the check above comes first.
  echo 1 > /sys/block/zram0/reset 2>/dev/null
  echo lz4 > /sys/block/zram0/comp_algorithm 2>/dev/null || return 1
  echo "${MEM_LIMIT_MB}M" > /sys/block/zram0/mem_limit 2>/dev/null
  echo "${DISK_MB}M" > /sys/block/zram0/disksize 2>/dev/null || return 1
  mkswap /dev/zram0 >/dev/null 2>&1 || return 1
  # Priority 100 so the kernel reaches for RAM before anything else on offer.
  swapon -p 100 /dev/zram0 2>/dev/null || swapon /dev/zram0 2>/dev/null || return 1
  echo "[mem] zram: ${DISK_MB} MB logical, lz4, ${MEM_LIMIT_MB} MB RAM ceiling"
}

# --- take the card out of the paging path -------------------------------------
# The firmware's fstab activates /dev/mmcblk0p3. Left enabled it would still be
# paged to once zram fills, which is exactly what this exists to prevent. Pages
# already there are migrated by swapoff, so this is slow only if the partition
# is in use; it is normally empty. Recorded so the exit path can put it back.
disable_disk_swap() {
  # Scan first, record second. Writing the record straight from /proc/swaps
  # meant a second run - or a relaunch after a crash that skipped the exit
  # path - overwrote it with an empty list, losing the only note of what to put
  # back. An empty scan now leaves any existing record alone.
  scan=$(awk 'NR > 1 && $1 != "/dev/zram0" { print $1 }' /proc/swaps)
  [ -n "$scan" ] && echo "$scan" > "$DATA/.disk-swap"
  for dev in $scan; do
    if swapoff "$dev" 2>/dev/null; then
      echo "[mem] disabled disk swap $dev"
    else
      echo "[mem] WARNING: could not disable $dev - the card is still in the paging path"
    fi
  done
}

# --- a 128 MB apology ---------------------------------------------------------
# Versions before this one left a swap file behind on the card. It is dead
# weight now, and 128 MB is worth reclaiming on a console whose storage is a
# memory card. Only removed when nothing is using it.
drop_legacy_swapfile() {
  [ -f "$DATA/nanocraft.swap" ] || return 0
  if losetup -a 2>/dev/null | grep -q "$DATA/nanocraft.swap"; then
    echo "[mem] legacy swap file is still attached, leaving it"
    return 0
  fi
  rm -f "$DATA/nanocraft.swap" "$DATA/.swap-loop"
  echo "[mem] removed the old 128 MB swap file from the card"
}

if load_modules && setup_zram; then
  disable_disk_swap
  drop_legacy_swapfile
  echo "[mem] swap now $(mb SwapTotal) MB, RAM-backed only"
  exit 0
fi

# --- when it cannot be done ---------------------------------------------------
# There is no fallback, and that is deliberate. Paging to the card is not a mode
# this port has any more: it is the behaviour this release exists to remove, and
# shipping a documented way back into it would be shipping it. If these modules
# will not load, the answer is to build ones that do, not to spend somebody's
# flash endurance quietly.
{
  echo "[mem] could not set up RAM-only swap on kernel $(uname -r)."
  echo "[mem] The modules in modules/ are built for one specific kernel and"
  echo "[mem] refuse to load on any other, so a firmware update or a different"
  echo "[mem] console is the usual cause."
  echo "[mem]"
  echo "[mem] Entering a world needs about 65 MB of anonymous memory and this"
  echo "[mem] console has 56 MB of RAM, so NanoCraft will not start without"
  echo "[mem] them. Rebuilding them for your kernel is documented in"
  echo "[mem] modules/README.md; it needs no firmware change."
} >&2
exit 1
