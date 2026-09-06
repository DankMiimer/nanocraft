#!/bin/bash
set -euo pipefail
SP=/mnt/c/Users/mads1/AppData/Local/Temp/claude/C--Programmering-SBC-RG-Nano/9c06575b-6f49-47c7-bea5-12672209988a/scratchpad
SRC="$SP/tester/1.0.11 - Nanocraft Funkey S DrUm78 OS"
LAB=$HOME/nanocraft-zram/funkeys
mkdir -p "$LAB"
cp "$SRC/nanocraft-kernel.zImage" "$LAB/zImage"
cp "$SRC/nanocraft-kernel.txt" "$LAB/kernel-report.txt"
command -v lzop >/dev/null && echo "lzop present" || echo "NO lzop"
python3 - <<'PY'
import pathlib
lab = pathlib.Path.home() / "nanocraft-zram/funkeys"
blob = (lab / "zImage").read_bytes()
magic = bytes([0x89]) + b"LZO\x00\r\n\x1a\n"
i = blob.find(magic)
print("zImage bytes:", len(blob), "| lzo payload at:", i)
if i >= 0:
    (lab / "payload.lzo").write_bytes(blob[i:])
PY
if [ -s "$LAB/payload.lzo" ]; then
  lzop -d -f -o "$LAB/vmlinux" "$LAB/payload.lzo" 2>&1 | tail -2 || true
  ls -l "$LAB/vmlinux" 2>/dev/null || echo "decompress produced nothing"
fi
