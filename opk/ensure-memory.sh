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
UNKNOWN_KERNEL=0

kb() { awk -v k="$1" '$1 == k":" { print $2 }' /proc/meminfo; }
mb() { echo $(( $(kb "$1") / 1024 )); }

echo "[mem] RAM $(mb MemTotal) MB total, $(mb MemAvailable) MB available"

# --- is this a kernel these modules are correct for? --------------------------
# vermagic is not enough. It encodes the version, SMP, preemption, module-unload
# and the architecture, and nothing else - so two builds of 4.14.14-funkey with
# different configurations share it exactly while disagreeing about the layout
# of struct page and the mm internals zram reaches into. insmod would accept
# that and corrupt memory rather than refuse. modules/kernels is the whitelist
# of builds somebody has actually verified; anything else is not loaded at all.
KERNEL_IDENT="$(uname -r) $(uname -v)"

kernel_set() {
  [ -f "$MODDIR/kernels" ] || return 1
  CR=$(printf '\r')
  while IFS= read -r line; do
    # Tolerate a CRLF copy. .gitattributes pins this file to LF, but a list
    # that silently matched nothing would look exactly like an unsupported
    # console, which is the worst way for this to fail.
    line=${line%"$CR"}
    case "$line" in ''|'#'*) continue ;; esac
    # "<identity>|<directory>". Split on the pipe rather than on whitespace:
    # a single-digit build day puts a double space in the identity.
    case "$line" in *'|'*) ;; *) continue ;; esac
    if [ "${line%|*}" = "$KERNEL_IDENT" ]; then
      echo "${line##*|}"
      return 0
    fi
  done < "$MODDIR/kernels"
  return 1
}

# --- modules ------------------------------------------------------------------
# Order matters: zram stores pages through zsmalloc and compresses them through
# the crypto API's lz4 shim, which needs the two algorithm modules under it.
load_modules() {
  # Nothing to check if the kernel already provides zram: the whitelist governs
  # what gets loaded, not what is already there.
  set_dir=
  if ! grep -q '^zram ' /proc/modules; then
    set_dir=$(kernel_set) || { UNKNOWN_KERNEL=1; return 1; }
    echo "[mem] kernel matches the '$set_dir' module set"
  fi
  for m in lz4_compress lz4_decompress lz4 zsmalloc zram; do
    grep -q "^$m " /proc/modules && continue
    if [ ! -f "$MODDIR/$set_dir/$m.ko" ]; then
      echo "[mem] missing $MODDIR/$set_dir/$m.ko"
      return 1
    fi
    if ! insmod "$MODDIR/$set_dir/$m.ko" 2>&1; then
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
    echo "[mem] compressed memory already active, leaving it alone"
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
      echo "[mem] took $dev out of the paging path"
    else
      echo "[mem] WARNING: could not release $dev - the card is still in the paging path"
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
    echo "[mem] the old paging file is still attached, leaving it"
    return 0
  fi
  rm -f "$DATA/nanocraft.swap" "$DATA/.swap-loop"
  echo "[mem] removed the old 128 MB paging file from the card"
}

if load_modules && setup_zram; then
  disable_disk_swap
  drop_legacy_swapfile
  echo "[mem] compressed memory ready, $(mb SwapTotal) MB"
  exit 0
fi

# --- when it cannot be done ---------------------------------------------------
# There is no fallback, and that is deliberate. Paging to the card is not a mode
# this port has any more: it is the behaviour this release exists to remove, and
# shipping a documented way back into it would be shipping it. If these modules
# will not load, the answer is to build ones that do, not to spend somebody's
# flash endurance quietly.
if [ "$UNKNOWN_KERNEL" = 1 ]; then
  # Collect everything needed to build this console a module set, into one file
  # at the root of the card where a person will actually find it. Asking someone
  # to fetch /boot/zImage by hand is not a reasonable request on a console with
  # no network and no shell - and every piece of this is already on the device.
  #
  # /proc/kallsyms is the important part: it is the running kernel's symbol
  # table, in text, which is what the export audit needs. The zImage is copied
  # beside it as a courtesy, but the audit does not require it.
  # The card root is where a person will actually look, but fall back to the
  # data directory if it is not writable - and never claim to have written a
  # file that was not written, since this message is the only instruction the
  # reporter gets.
  # Note the subshells. POSIX says a redirection error on a SPECIAL built-in -
  # and `:` is one - exits the shell, so probing writability with a bare
  # `: > file` takes the whole launcher down on a read-only card instead of
  # falling back.
  REPORT=/mnt/nanocraft-kernel.txt
  if ! ( : > "$REPORT" ) 2>/dev/null; then
    REPORT=$DATA/nanocraft-kernel.txt
    ( : > "$REPORT" ) 2>/dev/null || REPORT=
  fi
  {
    echo "NanoCraft kernel report"
    echo "Generated: $(date 2>/dev/null)"
    echo
    echo "Send this file to the NanoCraft issue tracker or Discord. It exists"
    echo "because NanoCraft refused to load its compressed-memory modules into a"
    echo "kernel nobody has verified them against, and everything needed to build"
    echo "a set for this console is below. It contains no personal files and no"
    echo "game content, and nothing was transmitted anywhere."
    echo
    echo "== add this line to opk/modules/kernels =="
    echo "$KERNEL_IDENT|<set>"
    echo
    echo "== uname -a =="
    uname -a
    echo
    echo "== /etc/os-release =="
    cat /etc/os-release 2>/dev/null
    echo
    echo "== /proc/version =="
    cat /proc/version 2>/dev/null
    echo
    echo "== vermagic the loader expects =="
    for ko in /lib/modules/"$(uname -r)"/extra/*.ko /lib/modules/"$(uname -r)"/kernel/*.ko; do
      [ -f "$ko" ] || continue
      echo "$ko: $(strings "$ko" 2>/dev/null | grep -m1 vermagic)"
    done
    echo
    echo "== memory =="
    grep -E '^(MemTotal|SwapTotal)' /proc/meminfo 2>/dev/null
    echo
    echo "== kernel configuration, if this build exposes it =="
    if [ -r /proc/config.gz ]; then
      zcat /proc/config.gz 2>/dev/null || gunzip -c /proc/config.gz 2>/dev/null
    else
      echo "(absent - CONFIG_IKCONFIG is off, which is normal)"
    fi
    echo
    echo "== /proc/kallsyms - the running kernel's symbol table =="
    cat /proc/kallsyms 2>/dev/null
  } >> "${REPORT:-/dev/null}" 2>/dev/null
  [ -n "$REPORT" ] && cp /boot/zImage "$(dirname "$REPORT")/nanocraft-kernel.zImage" 2>/dev/null
  sync

  {
    echo "[mem] this kernel is not one the bundled modules were built for:"
    echo "[mem]     $KERNEL_IDENT"
    echo "[mem]"
    echo "[mem] They are only loaded into kernels somebody has verified, because"
    echo "[mem] the loader's own check cannot tell two differently configured"
    echo "[mem] builds apart and loading into the wrong one corrupts memory"
    echo "[mem] rather than failing cleanly."
    echo "[mem]"
    echo "[mem] NanoCraft will not start without them: a world needs about 65 MB"
    echo "[mem] of anonymous memory and this console has $(mb MemTotal) MB of RAM."
    echo "[mem]"
    if [ -n "$REPORT" ] && [ -s "$REPORT" ]; then
      echo "[mem] EVERYTHING NEEDED TO FIX THIS HAS BEEN WRITTEN FOR YOU:"
      echo "[mem]     $REPORT"
      echo "[mem] Put the card in a PC and send that one file. A module set will"
      echo "[mem] be built and audited for your console; no firmware change."
    else
      echo "[mem] A report could not be written to the card. Please send the"
      echo "[mem] line above and the output of 'uname -a' instead."
    fi
  } >&2
  exit 1
fi

{
  echo "[mem] could not set up compressed memory on kernel $(uname -r)."
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
