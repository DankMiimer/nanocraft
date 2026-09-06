#!/bin/bash
# pack-pe-opk.sh - build NanoCraft_funkey-s.opk for the RG Nano.
#
# Run under WSL/Linux (mksquashfs is not a Windows tool). It stages into the
# Linux filesystem first, because a Windows drvfs mount does not carry the
# executable bit and GMenu2X silently does nothing when run.sh is not +x -- a
# failure indistinguishable from a segfault.
#
# CONVENTIONS, taken from OPKs that actually work on this console rather than
# from documentation:
#
#   - The .desktop must be <name>.funkey-s.desktop. nano/opk/pack-opk.sh asserts
#     .anbernic.desktop on the strength of rg_nano_dev_reference.md section 3,
#     but every working package on this device - PokemonEmeraldNano, WiFiGUI,
#     eduke32, sm64 - uses funkey-s, so that is what this follows.
#   - It must end in a trailing newline or GMenu2X reports "Unable to read
#     key/value pair from metadata" and the entry does nothing. Checked below.
#   - Icon=nanocraft needs nanocraft.png beside it, and IT MUST BE 32x32.
#     GMenu2X does not scale icons: it draws them at native size and clips to
#     the link slot, so a 140x140 icon shows only its top-left corner. Every
#     icon on this console that renders correctly is 32x32 - eduke32, sm64,
#     DrUm78's Overclock. (The 128x128 Pokemon icon is clipped too; it is just
#     dark in that corner so it never looked wrong.) Checked below.
#   - Games belong in "/mnt/Native games/", applications in /mnt/Applications.
#     RetroFE also wants a .png next to the .opk - and that one DOES get scaled,
#     so it should be the large artwork (120-240px is what the working ones use),
#     not the 32x32 the OPK carries.
#
# The OPK carries the launcher only. The game, the GL stack and saves live on
# /mnt/FunKey/nanocraft because a squashfs mount is read-only -- and because
# decompressing a 20 MB libGL out of squashfs on a 55 MB console would cost
# memory for nothing.
set -eu

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME=NanoCraft_funkey-s
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/nanocraft-opk.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
OUT="${1:-$SRC/../$NAME.opk}"

PAYLOAD_SCRIPTS="run.sh launch-pe-nano.sh install-apk.sh pemenu.sh ensure-memory.sh game-icon.sh"
PAYLOAD_PY=""
PAYLOAD_DATA="minecraft.key menubg.raw videobg.raw
              nanocraft.png nanocraft.funkey-s.desktop
              res240.raw res120.raw iconon.raw iconoff.raw
              gsauto.raw gsfit.raw gsstock.raw
              fov50.raw fov60.raw fov70.raw fov80.raw fov90.raw fov100.raw
              capoff.raw cap6.raw cap8.raw cap10.raw cap12.raw cap15.raw cap20.raw cap25.raw cap30.raw
              cpu1008.raw cpu1056.raw cpu1104.raw cpu1152.raw cpu1200.raw cpu1248.raw"
SENS_DATA=""
for s in $(seq 10 10 200); do SENS_DATA="$SENS_DATA sens$s.raw"; done
PAYLOAD_DATA="$PAYLOAD_DATA $SENS_DATA"
# nano-clk is a static ARM binary, not a script: it writes the CPU PLL through
# /dev/mem, which the quick menu's CPU row drives. Static so it depends on
# nothing - this console is musl and the toolchain is glibc.
PAYLOAD_BIN="nano-clk quickmenu"

# Loaded at launch by ensure-memory.sh, in this order: zram stores through
# zsmalloc and compresses through the crypto lz4 shim above the two algorithm
# modules. VERMAGIC is the kernel identity string the module loader insists on
# matching; see modules/README.md.
PAYLOAD_MODULES="lz4_compress.ko lz4_decompress.ko lz4.ko zsmalloc.ko zram.ko"
# One set per kernel flavour. The factory DrUm78 image is SMP; the console this
# port was developed on is not, and their vermagic strings differ by that word,
# so a single set cannot serve both. modules/kernels says which build gets which.
PAYLOAD_MODULE_SETS="up smp"
VERMAGIC_up="4.14.14-funkey mod_unload"
VERMAGIC_smp="4.14.14-funkey SMP mod_unload"

# The rendered menu is a build product and is not committed, so a fresh clone
# will not have it. Say so plainly instead of failing on a bare `cp`.
if [ ! -f "$SRC/menubg.raw" ] || [ ! -f "$SRC/videobg.raw" ]; then
  echo "ERROR: the rendered quick menu is missing."
  echo
  echo "It is generated, not committed. Put a copy of Raster Forge Regular at"
  echo "  $SRC/menufont.ttf"
  echo "then run:"
  echo "  ./make-menu-bg.sh"
  echo
  echo "Any TTF works if you would rather use your own; the menu text is baked"
  echo "into a bitmap at build time because the console has no font engine."
  exit 1
fi

for f in $PAYLOAD_SCRIPTS $PAYLOAD_PY $PAYLOAD_DATA $PAYLOAD_BIN; do
  cp "$SRC/$f" "$STAGE/"
done

# The zram modules. 97 KB, and the difference between a world loading in RAM and
# a world loading off the SD card. kernel.config and README.md travel with them
# because they are GPLv2 kernel code and the build has to stay reproducible.
mkdir -p "$STAGE/modules"
for f in kernels README.md; do
  if [ ! -f "$SRC/modules/$f" ]; then
    echo "ERROR: modules/$f is missing."
    echo "       See modules/README.md for how these are built."
    exit 1
  fi
  cp "$SRC/modules/$f" "$STAGE/modules/"
done
for set in $PAYLOAD_MODULE_SETS; do
  mkdir -p "$STAGE/modules/$set"
  for f in $PAYLOAD_MODULES kernel.config; do
    if [ ! -f "$SRC/modules/$set/$f" ]; then
      echo "ERROR: modules/$set/$f is missing."
      echo "       See modules/README.md for how these are built."
      exit 1
    fi
    cp "$SRC/modules/$set/$f" "$STAGE/modules/$set/"
  done
done

# Every kernel named in the whitelist must have the set it points at.
while IFS= read -r line; do
  case "$line" in ''|'#'*) continue ;; esac
  case "$line" in *'|'*) ;; *) continue ;; esac
  want=${line##*|}
  if [ ! -d "$STAGE/modules/$want" ]; then
    echo "ERROR: modules/kernels points at set \"$want\", which is not shipped."
    exit 1
  fi
done < "$SRC/modules/kernels"

# A module built for a different kernel does not misbehave, it simply refuses to
# load - and it would do so on the console, at launch, in front of the user.
# Catch it here instead. The string is what the loader itself compares.
for set in $PAYLOAD_MODULE_SETS; do
  eval "want=\$VERMAGIC_$set"
  for f in $PAYLOAD_MODULES; do
    if ! grep -qa "vermagic=$want" "$STAGE/modules/$set/$f"; then
      echo "ERROR: modules/$set/$f is not built for \"$want\"."
      echo "       Rebuild it against that kernel and re-run the export audit;"
      echo "       see modules/README.md."
      exit 1
    fi
  done
done

# Every value strip the quick menu can blit must be present and whole. A missing
# one would leave the CPU or screen row blank at exactly the moment someone is
# trying to read what it is set to.
for f in res240.raw res120.raw iconon.raw iconoff.raw gsauto.raw gsfit.raw gsstock.raw \
         fov50.raw fov60.raw fov70.raw fov80.raw fov90.raw fov100.raw \
         capoff.raw cap6.raw cap8.raw cap10.raw cap12.raw cap15.raw cap20.raw cap25.raw cap30.raw \
         cpu1008.raw cpu1056.raw cpu1104.raw \
         cpu1152.raw cpu1200.raw cpu1248.raw $SENS_DATA; do
  if [ "$(wc -c < "$STAGE/$f")" -ne 2736 ]; then
    echo "ERROR: $f is $(wc -c < "$STAGE/$f") bytes, expected 2736."
    echo "       Rebuild the strips with ./make-menu-bg.sh"
    exit 1
  fi
done

# Both shipped binaries touch the console directly - nano-clk writes clock
# registers, quickmenu owns the framebuffer and the buttons - so confirm the
# architecture here rather than discovering on the console that they will not
# execute. Static matters as much as ARM: this is a glibc toolchain and the
# console is musl, so a dynamic build would need the bundled runtime.
for b in nano-clk quickmenu; do
  case "$(file -b "$STAGE/$b" 2>/dev/null)" in
    *"ARM"*"statically linked"*) : ;;
    *) echo "ERROR: $b is not a static ARM binary:"
       file -b "$STAGE/$b"
       echo "       Rebuild it with ../src/build-${b#nano-}.sh"
       exit 1 ;;
  esac
done

# menubg.raw and videobg.raw are flat 240x240 RGB565 buffers built by
# make-menu-bg.sh. Refuse to ship a truncated one: a short read would leave the
# quick menu half drawn over a frozen game, which is the worst possible moment
# to discover it.
for f in menubg.raw videobg.raw; do
  if [ "$(wc -c < "$STAGE/$f")" -ne 115200 ]; then
    echo "ERROR: $f is $(wc -c < "$STAGE/$f") bytes, expected 115200."
    echo "       Rebuild it with ./make-menu-bg.sh"
    exit 1
  fi
done

# The icon must be 32x32 or GMenu2X shows one corner of it. Read the PNG header
# rather than trusting the file: this bug ships silently and looks like a broken
# package rather than a wrong image size.
ICON_WH=$(python3 -c "
import struct,sys
d=open(sys.argv[1],'rb').read(32)
w,h=struct.unpack('>II',d[16:24]); print('%dx%d'%(w,h))" "$STAGE/nanocraft.png")
if [ "$ICON_WH" != "32x32" ]; then
  echo "ERROR: nanocraft.png is $ICON_WH, must be 32x32 - GMenu2X clips, it does"
  echo "       not scale. Regenerate with: python make-icon.py 32 nanocraft.png"
  exit 1
fi

chmod 755 $(for f in $PAYLOAD_SCRIPTS $PAYLOAD_PY $PAYLOAD_BIN; do echo "$STAGE/$f"; done)
chmod 644 $(for f in $PAYLOAD_DATA; do echo "$STAGE/$f"; done)

# CRLF anywhere in a shell script is a syntax error on busybox ash, and the
# symptom - a one second black screen and a return to the menu - looks exactly
# like a segfault. Strip rather than trust.
sed -i 's/\r$//' $(for f in $PAYLOAD_SCRIPTS $PAYLOAD_PY; do echo "$STAGE/$f"; done) \
                 "$STAGE/minecraft.key" "$STAGE/nanocraft.funkey-s.desktop"

DESK="$STAGE/nanocraft.funkey-s.desktop"
if [ -n "$(tail -c 1 "$DESK")" ]; then
  echo "ERROR: $DESK does not end in a newline - GMenu2X would ignore it."
  exit 1
fi
for s in $PAYLOAD_SCRIPTS; do sh -n "$STAGE/$s"; done

# The menu reads these at startup and draws nothing where one is missing, so a
# short or absent strip is a blank row on the console rather than an error.
for f in menubg.raw videobg.raw; do
  if [ "$(wc -c < "$STAGE/$f")" -ne 115200 ]; then
    echo "ERROR: $f is $(wc -c < "$STAGE/$f") bytes, expected 115200."
    exit 1
  fi
done
echo "ok: .desktop ends with a newline, scripts parse, both menu pages are intact"

# Nothing Minecraft, nothing personal, ever. Fail the build rather than trust
# the file list above.
if find "$STAGE" -iname "*.apk" -o -iname "*libminecraftpe*" -o -iname "*.log" | grep -q .; then
  echo "ERROR: forbidden content staged into the OPK."
  find "$STAGE" -iname "*.apk" -o -iname "*libminecraftpe*" -o -iname "*.log"
  exit 1
fi

mksquashfs "$STAGE" "$OUT" -all-root -noappend -no-exports -no-xattrs -comp gzip >/dev/null
echo "built: $OUT  ($(wc -c < "$OUT") bytes)"
unsquashfs -l "$OUT" | tail -12
