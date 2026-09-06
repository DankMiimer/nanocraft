"""Audit the shipped SMP zram modules against the FunKey S kernel from issue #2.

Export tables are read out of the decompressed images. Entries are (value,
name-pointer) pairs; isolated matches are coincidence - a USB-audio name table
produces dozens - so only entries inside a long contiguous 8-byte-stride chain
are kept. Chains are walked by stride, not by sorted order, because a stray
4-byte-aligned match inside a real section would otherwise split it.
"""
import json, pathlib, re, struct, subprocess

home = pathlib.Path.home()
BASE = 0xC0008000
MIN_RUN = 100
KERNELS = {"rgnano-factory": home/"stock2/vmlinux",
           "funkey-s": home/"nanocraft-zram/funkeys/try_6814.bin"}


def scan(blob):
    valid = {}
    for off in range(0, len(blob) - 8, 4):
        value, ptr = struct.unpack_from("<II", blob, off)
        s = ptr - BASE
        if not (0xC0000000 <= value < 0xD0000000 and 0 <= s < len(blob)):
            continue
        end = blob.find(b"\0", s, s + 160)
        if end < 0:
            continue
        name = blob[s:end]
        if re.fullmatch(rb"[A-Za-z_][A-Za-z0-9_]*", name):
            valid[off] = name.decode()
    seen, names, runs = set(), set(), []
    for off in sorted(valid):
        if off in seen or (off - 8) in valid:
            continue
        chain = []
        o = off
        while o in valid:
            chain.append(o); seen.add(o); o += 8
        if len(chain) >= MIN_RUN:
            runs.append(len(chain))
            names.update(valid[c] for c in chain)
    return names, sorted(runs, reverse=True), len(valid)


tables = {}
for label, path in KERNELS.items():
    names, runs, loose = scan(path.read_bytes())
    tables[label] = names
    print(f"{label:16} {len(names):5} exports in {len(runs)} sections "
          f"(largest {runs[:4]}); {loose - len(names)} isolated matches discarded")

a, b = tables["rgnano-factory"], tables["funkey-s"]
print(f"\nexported only by the verified RG Nano kernel: {len(a - b)}")
print(f"exported only by the tester's FunKey S kernel: {len(b - a)}")
for label, rows in (("verified-only", sorted(a - b)), ("tester-only", sorted(b - a))):
    if rows:
        print(f"  {label}: {', '.join(rows)}")

MODDIR = pathlib.Path("/mnt/c/Programmering/SBC/MIYOO Mini Plus/minecraft-bedrock/nano/opk-pe/modules/smp")
NM = "arm-linux-gnueabihf-nm"
provided, imports = set(), {}
for mod in sorted(MODDIR.glob("*.ko")):
    for line in subprocess.check_output([NM, str(mod)], text=True).splitlines():
        n = line.split()[-1]
        if n.startswith("__ksymtab_"):
            provided.add(n[len("__ksymtab_"):])
for mod in sorted(MODDIR.glob("*.ko")):
    out = subprocess.check_output([NM, "-u", str(mod)], text=True)
    imports[mod.name] = sorted(l.split()[-1] for l in out.splitlines() if l.split()[0] == "U")

print()
missing = {}
for mod, syms in imports.items():
    gaps = [s for s in syms if s not in b and s not in provided]
    print(f"{mod:22} {len(syms):3} imports, {len(gaps)} unresolved")
    if gaps:
        missing[mod] = gaps
        print("    MISSING:", ", ".join(gaps))

verdict = "UNRESOLVED IMPORTS" if missing else (
    "all imports resolve; the tester's kernel exports nothing the verified one does not"
    if not (b - a) else "all imports resolve")
record = {
    "kernel": "4.14.14-funkey #1 SMP Sun Jan 18 03:45:29 CET 2026",
    "console": "FunKey S, FunKey-OS 2.3.0 - issue #2, badcats72",
    "image": "nanocraft-kernel.zImage, LZO payload at offset 6814, vmlinux 9662464 bytes",
    "build_string": "gcc 10.2.0 (Buildroot 2020.11-341-g1f59bd3b48), same builder and day as the verified kernel",
    "exports_rgnano_factory": len(a), "exports_funkey_s": len(b),
    "exports_only_in_rgnano": sorted(a - b), "exports_only_in_funkey_s": sorted(b - a),
    "modules": {m: {"imports": len(s), "unresolved": missing.get(m, [])} for m, s in imports.items()},
    "verdict": verdict,
}
(home/"nanocraft-zram/funkeys/audit-funkeys.json").write_text(json.dumps(record, indent=2))
print("\nVERDICT:", verdict)
