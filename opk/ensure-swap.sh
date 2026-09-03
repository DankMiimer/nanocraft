#!/bin/sh
# ensure-swap.sh - make sure this console has enough swap to load a world.
#
# WHY, IN NUMBERS. Measured on an RG Nano:
#
#   title screen   RSS 37 MB + 5 MB swapped
#   in a world     RSS 40 MB + 28 MB swapped   = ~68 MB of anonymous memory
#   console RAM    56 MB total, ~41 MB of it available to the game
#
# So entering a world needs roughly 27 MB more than RAM alone can give, on any
# console of this class. With the stock 128 MB swap partition that is a
# non-issue and this script does nothing. On a system with little or no swap,
# the game reaches its menus perfectly -- they fit -- and then dies the moment a
# world loads, which is a genuinely confusing way to fail.
#
# It therefore acts ONLY when swap is actually short. On a correctly provisioned
# console it costs one read of /proc/meminfo.
#
# /mnt is vfat and Linux will not swapon a file on vfat, because vfat cannot
# give a stable block mapping. A loop device over that file can, which is the
# route used here. Note the OPK is itself a loop-mounted squashfs, so /dev/loop0
# is taken while the game runs and a second device has to be found or created.
#
#   ensure-swap.sh <data-dir> [min-swap-MB] [create-MB]
# Prints the loop device it enabled, if any, so the caller can undo it.
set -u

DATA=${1:-/mnt/FunKey/nanocraft}
MIN_MB=${2:-64}
MAKE_MB=${3:-128}
SWAPFILE=$DATA/nanocraft.swap
STATE=$DATA/.swap-loop

kb()   { awk -v k="$1" '$1 == k":" { print $2 }' /proc/meminfo; }
mb()   { echo $(( $(kb "$1") / 1024 )); }

MEM_TOTAL=$(mb MemTotal)
MEM_AVAIL=$(mb MemAvailable)
SWAP_TOTAL=$(mb SwapTotal)

# Always report. Even when this script does nothing, these three numbers turn a
# future "it crashes when I press Play" into a diagnosis.
echo "[mem] RAM ${MEM_TOTAL} MB total, ${MEM_AVAIL} MB available; swap ${SWAP_TOTAL} MB"

if [ "$SWAP_TOTAL" -ge "$MIN_MB" ]; then
  echo "[mem] swap is sufficient (>= ${MIN_MB} MB), nothing to do"
  exit 0
fi

echo "[mem] swap is short: ${SWAP_TOTAL} MB < ${MIN_MB} MB needed to load a world"
echo "[mem] providing ${MAKE_MB} MB of swap in $SWAPFILE"

# --- the backing file ---------------------------------------------------------
WANT=$(( MAKE_MB * 1024 * 1024 ))
HAVE=$(wc -c < "$SWAPFILE" 2>/dev/null || echo 0)
if [ "$HAVE" != "$WANT" ]; then
  rm -f "$SWAPFILE"
  # fallocate is instant where it works; dd is the fallback and takes a while on
  # an SD card, which is why the file is kept between launches.
  if ! fallocate -l "$WANT" "$SWAPFILE" 2>/dev/null; then
    echo "[mem] fallocate unavailable, writing the file (this takes a minute)"
    dd if=/dev/zero of="$SWAPFILE" bs=1048576 count="$MAKE_MB" 2>/dev/null
  fi
  if [ "$(wc -c < "$SWAPFILE" 2>/dev/null || echo 0)" != "$WANT" ]; then
    echo "[mem] could not create the swap file - is the card full?"
    rm -f "$SWAPFILE"
    exit 1
  fi
fi

# --- a free loop device -------------------------------------------------------
# /dev/loop0 is the running OPK. Only that one exists on a stock image, so make
# another if needed; /dev is devtmpfs, so this does not persist and is remade
# each launch.
LOOP=
i=1
while [ $i -lt 8 ]; do
  dev=/dev/loop$i
  [ -e "$dev" ] || mknod "$dev" b 7 "$i" 2>/dev/null
  if [ -e "$dev" ] && ! losetup -a 2>/dev/null | grep -q "^$dev:"; then
    LOOP=$dev
    break
  fi
  i=$(( i + 1 ))
done

if [ -z "$LOOP" ]; then
  echo "[mem] no free loop device available"
  exit 1
fi

if ! losetup "$LOOP" "$SWAPFILE" 2>/dev/null; then
  echo "[mem] losetup $LOOP failed"
  exit 1
fi

if ! mkswap "$LOOP" >/dev/null 2>&1 || ! swapon "$LOOP" 2>/dev/null; then
  echo "[mem] could not enable swap on $LOOP"
  losetup -d "$LOOP" 2>/dev/null
  exit 1
fi

echo "$LOOP" > "$STATE"
echo "[mem] swap enabled on $LOOP; total now $(mb SwapTotal) MB"
exit 0
