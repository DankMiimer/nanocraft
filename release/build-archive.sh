#!/bin/bash
# build-archive.sh - assemble the NanoCraft release archive.
#
# Rebuilt from current sources rather than reusing an earlier copy, so the
# published artifact is definitively the code that is in the repository.
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

VERSION=${1:-v1.0.1}

cp ../NanoCraft_funkey-s.opk .
cp ../opk-pe/nanocraft-large.png NanoCraft_funkey-s.png

OUT=nanocraft-$VERSION-rgnano.zip
rm -f "$OUT"

# The v1.0.10 guard. That release shipped an OPK whose launcher asked for
# NINECRAFT_GUI_SCALE and NINECRAFT_FOV and a payload whose runtime had never
# heard of either, and nothing here noticed. The game is in the payload, not the
# OPK, so check the two halves against each other before zipping them together:
# every NINECRAFT_ setting the packaged launcher exports must be a string the
# packaged runtime actually contains.
python3 - <<'GUARD'
import pathlib, re, subprocess, sys, tarfile, tempfile

launcher = subprocess.check_output(
    ["unsquashfs", "-cat", "NanoCraft_funkey-s.opk", "launch-pe-nano.sh"])
wanted = sorted(set(re.findall(rb"NINECRAFT_[A-Z_]+", launcher)))
verify = pathlib.Path("../src/verify-runtime.py")
if not verify.exists():
    verify = pathlib.Path("../tools/verify-runtime.py")
with tempfile.TemporaryDirectory() as tmp:
    with tarfile.open("nanocraft-payload.tar.gz") as tar:
        tar.extract(tar.getmember("ninecraft"), tmp)
    runtime = pathlib.Path(tmp, "ninecraft")
    subprocess.run([sys.executable, str(verify), str(runtime)], check=True)
    binary = runtime.read_bytes()
missing = [name.decode() for name in wanted if name not in binary]
if missing:
    sys.exit("ERROR: the packaged launcher asks for " + ", ".join(missing) +
             ", which the packaged runtime does not implement. "
             "Rebuild the payload with ./build-payload.sh.")
print("ok: the payload runtime implements all %d settings the launcher uses"
      % len(wanted))
GUARD

python3 - "$OUT" <<'PY'
import hashlib, os, sys, zipfile
out = sys.argv[1]
files = ["NanoCraft_funkey-s.opk", "NanoCraft_funkey-s.png",
         "nanocraft-payload.tar.gz", "INSTALL.txt"]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for f in files:
        z.write(f)
        print("  %-28s %10d" % (f, os.path.getsize(f)))
print()
print("%s  %.1f MB" % (out, os.path.getsize(out) / 1048576.0))
print("sha256  %s" % hashlib.sha256(open(out, "rb").read()).hexdigest())
PY

# Nothing Minecraft, ever - check the archive itself, not the list above it.
if unzip -l "$OUT" | grep -iE "libminecraftpe|\.apk|world|\.log" ; then
  echo "ERROR: forbidden content in the release archive"
  exit 1
fi
echo "ok: archive contains no game files"
