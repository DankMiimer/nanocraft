#!/bin/bash
# extract-kernel.sh - recover a vmlinux from a console's zImage.
#
#   ./extract-kernel.sh <nanocraft-kernel.zImage> [output-directory]
#
# ensure-memory.sh copies /boot/zImage beside the kernel report it writes when
# it refuses an unknown kernel, so this is the file a reporter sends.
#
# DrUm78's images carry an LZO payload, but NOT always at the same offset: the
# RG Nano's starts at 6432 and the FunKey S's at 6814. Both files contain the
# LZO magic at BOTH offsets - one of them is inside the decompressor stub's
# string table - so the offset has to be found by trying, not assumed. Assuming
# gives "header corrupted", which looks exactly like a truncated upload.
set -eu
IMAGE="${1:?usage: extract-kernel.sh <zImage> [output-directory]}"
OUT="${2:-$(dirname "$IMAGE")}"
mkdir -p "$OUT"

command -v lzop >/dev/null || { echo "need lzop"; exit 1; }

offsets=$(python3 - "$IMAGE" <<'PY'
import sys, pathlib
blob = pathlib.Path(sys.argv[1]).read_bytes()
magic = bytes([0x89]) + b"LZO\x00\r\n\x1a\n"
i, hits = blob.find(magic), []
while i >= 0:
    hits.append(i)
    i = blob.find(magic, i + 1)
print(" ".join(map(str, hits)))
PY
)
echo "LZO magic at: ${offsets:-none}"

for off in $offsets; do
  python3 - "$IMAGE" "$off" "$OUT/payload.lzo" <<'PY'
import sys, pathlib
blob = pathlib.Path(sys.argv[1]).read_bytes()
pathlib.Path(sys.argv[3]).write_bytes(blob[int(sys.argv[2]):])
PY
  # Do NOT gate on lzop's exit status. The payload is the head of a larger
  # file, so a successful decompression still ends with "ignoring trailing
  # garbage" and a non-zero status. Judge it by what came out instead.
  rm -f "$OUT/vmlinux"
  lzop -d -f -o "$OUT/vmlinux" "$OUT/payload.lzo" 2>/dev/null || true
  if [ -s "$OUT/vmlinux" ] && strings -a "$OUT/vmlinux" | grep -q "^Linux version "; then
    echo "decompressed from offset $off"
    ls -l "$OUT/vmlinux"
    strings -a "$OUT/vmlinux" | grep -m1 "^Linux version"
    exit 0
  fi
done
echo "no offset decompressed; is the upload complete?"
exit 1
