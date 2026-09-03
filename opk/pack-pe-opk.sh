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
STAGE=$HOME/.nanocraft-opk-stage
OUT=$HOME/$NAME.opk

PAYLOAD_SCRIPTS="run.sh launch-pe-nano.sh install-apk.sh pemenu.sh ensure-swap.sh"
PAYLOAD_PY="quickmenu.py"
PAYLOAD_DATA="minecraft.key menubg.raw nanocraft.png nanocraft.funkey-s.desktop
              res240.raw res120.raw
              cpu1008.raw cpu1056.raw cpu1104.raw cpu1152.raw cpu1200.raw cpu1248.raw"
# nano-clk is a static ARM binary, not a script: it writes the CPU PLL through
# /dev/mem, which the quick menu's CPU row drives. Static so it depends on
# nothing - this console is musl and the toolchain is glibc.
PAYLOAD_BIN="nano-clk"

# menubg.raw is a build product and is not committed, so a fresh clone will not
# have it. Say so plainly instead of failing on a bare `cp`.
if [ ! -f "$SRC/menubg.raw" ]; then
  echo "ERROR: menubg.raw is missing."
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

rm -rf "$STAGE"
mkdir -p "$STAGE"
for f in $PAYLOAD_SCRIPTS $PAYLOAD_PY $PAYLOAD_DATA $PAYLOAD_BIN; do
  cp "$SRC/$f" "$STAGE/"
done

# Every value strip the quick menu can blit must be present and whole. A missing
# one would leave the CPU or screen row blank at exactly the moment someone is
# trying to read what it is set to.
for f in res240.raw res120.raw cpu1008.raw cpu1056.raw cpu1104.raw \
         cpu1152.raw cpu1200.raw cpu1248.raw; do
  if [ "$(wc -c < "$STAGE/$f")" -ne 2736 ]; then
    echo "ERROR: $f is $(wc -c < "$STAGE/$f") bytes, expected 2736."
    echo "       Rebuild the strips with ./make-menu-bg.sh"
    exit 1
  fi
done

# nano-clk writes CPU clock registers, so confirm it is the right architecture
# rather than discovering on the console that it will not execute.
case "$(file -b "$STAGE/nano-clk" 2>/dev/null)" in
  *"ARM"*"statically linked"*) : ;;
  *) echo "ERROR: nano-clk is not a static ARM binary:"
     file -b "$STAGE/nano-clk"
     echo "       Rebuild it with ../src/build-nanoclk.sh"
     exit 1 ;;
esac

# menubg.raw is a flat 240x240 RGB565 buffer built by make-menu-bg.sh. Refuse to
# ship a truncated one: a short read would leave the quick menu half drawn over
# a frozen game, which is the worst possible moment to discover it.
if [ "$(wc -c < "$STAGE/menubg.raw")" -ne 115200 ]; then
  echo "ERROR: menubg.raw is $(wc -c < "$STAGE/menubg.raw") bytes, expected 115200."
  echo "       Rebuild it with ./make-menu-bg.sh"
  exit 1
fi

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
python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$STAGE/quickmenu.py"
echo "ok: .desktop ends with a newline, scripts parse, menubg.raw is intact"

# Nothing Minecraft, nothing personal, ever. Fail the build rather than trust
# the file list above.
if find "$STAGE" -iname "*.apk" -o -iname "*libminecraftpe*" -o -iname "*.log" | grep -q .; then
  echo "ERROR: forbidden content staged into the OPK."
  find "$STAGE" -iname "*.apk" -o -iname "*libminecraftpe*" -o -iname "*.log"
  exit 1
fi

rm -f "$OUT"
mksquashfs "$STAGE" "$OUT" -all-root -noappend -no-exports -no-xattrs -comp gzip >/dev/null
cp "$OUT" "$SRC/../$NAME.opk"
echo "built: $SRC/../$NAME.opk  ($(wc -c < "$OUT") bytes)"
unsquashfs -l "$OUT" | tail -12
