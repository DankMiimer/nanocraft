#!/bin/bash
# pack-diag-opk.sh - build NanoCraftDiag_funkey-s.opk.
#
# A diagnostic build of NanoCraft. It plays the game exactly as the normal
# package does, and wraps that run in a battery of probes, writing everything to
# ONE file the tester can send. It transmits nothing.
#
# Shipped separately rather than as a mode of the normal package so that:
#   - nobody runs diagnostics by accident,
#   - the normal package stays exactly what was released and verified,
#   - the tester can delete it afterwards and be certain it is gone.
#
# Same packaging rules as pack-pe-opk.sh: .funkey-s suffix, trailing newline on
# the .desktop, 32x32 icon because GMenu2X clips rather than scales.
set -eu

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME=NanoCraftDiag_funkey-s
STAGE=$HOME/.nanocraftdiag-opk-stage
OUT=$HOME/$NAME.opk

# The game half must be byte-identical to the shipping package, or the
# diagnostic would be measuring something the tester does not actually run.
GAME_SCRIPTS="run.sh launch-pe-nano.sh install-apk.sh pemenu.sh ensure-memory.sh"
GAME_DATA="minecraft.key menubg.raw videobg.raw res240.raw res120.raw
           gsauto.raw gsfit.raw gsstock.raw
           fov50.raw fov60.raw fov70.raw fov80.raw fov90.raw fov100.raw
           capoff.raw cap6.raw cap8.raw cap10.raw cap12.raw cap15.raw cap20.raw cap25.raw cap30.raw
           cpu1008.raw cpu1056.raw cpu1104.raw cpu1152.raw cpu1200.raw cpu1248.raw"
GAME_PY=""
# The 20 sensitivity strips belong to the same quick menu binary as the rest.
# Listing them separately, the way pack-pe-opk.sh does, keeps the two lists
# visibly the same shape - a strip missing from only this one would give the
# diagnostic build a SETTINGS page the shipping build does not have.
for s in $(seq 10 10 200); do GAME_DATA="$GAME_DATA sens$s.raw"; done
GAME_BIN="nano-clk quickmenu"
DIAG_SCRIPTS="diagnose.sh"
DIAG_PY=""
DIAG_AWK="resolve-fault.awk"
DIAG_DATA="diagbg.raw"

# The game half sits beside this script in the working tree and one directory
# over in the published one. Find it rather than assuming, so that "byte
# identical to the shipping package" holds in both.
GAME_SRC="$SRC"
[ -f "$GAME_SRC/run.sh" ] || GAME_SRC="$SRC/../opk"

rm -rf "$STAGE"; mkdir -p "$STAGE"
for f in $GAME_SCRIPTS $GAME_PY $GAME_DATA $GAME_BIN; do
  cp "$GAME_SRC/$f" "$STAGE/"
done
for f in $DIAG_SCRIPTS $DIAG_PY $DIAG_AWK $DIAG_DATA; do
  cp "$SRC/$f" "$STAGE/"
done

# ensure-memory.sh refuses to launch without these, so the diagnostic build
# needs them for exactly the same reason the normal one does.
mkdir -p "$STAGE/modules"
cp -r "$GAME_SRC"/modules/. "$STAGE/modules/"

for f in menubg.raw videobg.raw diagbg.raw; do
  if [ "$(wc -c < "$STAGE/$f")" -ne 115200 ]; then
    echo "ERROR: $f is $(wc -c < "$STAGE/$f") bytes, expected 115200."
    echo "       Rebuild with ./make-menu-bg.sh and ./make-diag-bg.sh"
    exit 1
  fi
done

python3 "$SRC/make-icon.py" 32 "$STAGE/nanocraftdiag.png" diag
cat > "$STAGE/nanocraftdiag.funkey-s.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=NanoCraft Diag
Comment=Runs NanoCraft and writes a diagnostic report
Exec=diagnose.sh
Icon=nanocraftdiag
Categories=games
Terminal=false
StartupNotify=true
EOF

chmod 755 $(for f in $GAME_SCRIPTS $GAME_PY $GAME_BIN $DIAG_SCRIPTS $DIAG_PY; do echo "$STAGE/$f"; done)
chmod 644 $(for f in $GAME_DATA $DIAG_DATA; do echo "$STAGE/$f"; done) \
          "$STAGE/nanocraftdiag.png" "$STAGE/nanocraftdiag.funkey-s.desktop"

sed -i 's/\r$//' $(for f in $GAME_SCRIPTS $GAME_PY $DIAG_SCRIPTS $DIAG_PY; do echo "$STAGE/$f"; done) \
                 "$STAGE/minecraft.key" "$STAGE/nanocraftdiag.funkey-s.desktop"

DESK="$STAGE/nanocraftdiag.funkey-s.desktop"
if [ -n "$(tail -c 1 "$DESK")" ]; then
  echo "ERROR: $DESK does not end in a newline - GMenu2X would ignore it."
  exit 1
fi
for s in $GAME_SCRIPTS $DIAG_SCRIPTS; do sh -n "$STAGE/$s"; done
python3 -c "import ast, sys
for f in sys.argv[1:]:
    ast.parse(open(f).read())
print('ok: scripts parse, .desktop ends with a newline, screens are intact')" \
  $(for f in $GAME_PY $DIAG_PY; do echo "$STAGE/$f"; done)

ICON_WH=$(python3 -c "
import struct, sys
d = open(sys.argv[1], 'rb').read(32)
w, h = struct.unpack('>II', d[16:24]); print('%dx%d' % (w, h))" "$STAGE/nanocraftdiag.png")
[ "$ICON_WH" = "32x32" ] || { echo "ERROR: icon is $ICON_WH, must be 32x32"; exit 1; }

# The diagnostic must never carry game content either.
if find "$STAGE" -iname '*.apk' -o -iname '*libminecraftpe*' -o -iname '*.log' | grep -q .; then
  echo "ERROR: forbidden content staged into the diagnostic OPK."
  exit 1
fi
# And it must contain nothing that can transmit, which is the promise this build
# makes to the person running it. Comments are stripped first: an early version
# of this check flagged its own explanation of why it exists.
python3 - "$STAGE" <<'PY'
import os, re, sys
stage = sys.argv[1]
# Command position only - start of line or after a shell separator.
CMD = re.compile(r"(?:^|[;&|(]\s*|\$\(\s*)(curl|wget|nc|netcat|telnet|ftp|tftp"
                 r"|scp|sftp|ssh|rsync|socket|urlopen|urlretrieve)\b")
URL = re.compile(r"https?://|\bAF_INET\b|\bsocket\.socket\b")
bad = []
for name in sorted(os.listdir(stage)):
    if not name.endswith((".sh", ".py")):
        continue
    path = os.path.join(stage, name)
    for n, line in enumerate(open(path, errors="replace"), 1):
        code = re.sub(r"(^|\s)#.*$", "", line).strip()
        if not code:
            continue
        if CMD.search(code) or URL.search(code):
            bad.append("%s:%d: %s" % (name, n, code[:90]))
if bad:
    print("ERROR: the diagnostic contains something that could transmit:")
    for b in bad:
        print("  " + b)
    sys.exit(1)
print("ok: no game content, and nothing in it can transmit")
PY

rm -f "$OUT"
mksquashfs "$STAGE" "$OUT" -all-root -noappend -no-exports -no-xattrs -comp gzip >/dev/null
cp "$OUT" "$SRC/../$NAME.opk"
echo "built: $SRC/../$NAME.opk  ($(wc -c < "$OUT") bytes)"
unsquashfs -l "$OUT" | tail -14
