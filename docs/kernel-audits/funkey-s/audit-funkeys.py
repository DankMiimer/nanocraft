#!/usr/bin/env python3
"""Audit a zram module set against a kernel it has not been verified on.

    ./audit-funkeys.py <reference-vmlinux> <candidate-vmlinux> [module-dir] [-o out.json]

opk/modules/kernels refuses to load anything into a kernel nobody has checked,
because the loader's vermagic test cannot tell two differently configured builds
apart and loading into the wrong one corrupts memory rather than failing. This
is the check that lets a build be added to that list. It answers two questions:

  1. does the candidate kernel export every symbol the modules import?
  2. is its export table the same SET of names as the kernel the modules were
     built and verified against?

The second matters because a console that does not set CONFIG_IKCONFIG cannot
hand over its configuration, and this is the closest available substitute: a
difference big enough to move struct page, a spinlock, a zone or the allocator
essentially always adds or removes exports as well.

Both kernels are given as decompressed images - see extract-kernel.sh. The
module directory defaults to the smp set in this repository.
"""
import argparse
import json
import pathlib
import re
import struct
import subprocess
import sys

BASE = 0xC0008000
MIN_RUN = 100
NM = "arm-linux-gnueabihf-nm"


def exports(blob):
    """Recover the kernel's export table.

    __ksymtab entries are (value, name-pointer) pairs. Keep only entries inside
    a long contiguous 8-byte-stride chain: an isolated match is a coincidence -
    a USB-audio device-name table alone resolves as dozens of plausible
    identifiers - and chains must be walked BY STRIDE rather than in sorted
    order, or a stray 4-byte-aligned hit inside a real section splits it and
    starts inventing gaps.
    """
    valid = {}
    for off in range(0, len(blob) - 8, 4):
        value, ptr = struct.unpack_from("<II", blob, off)
        start = ptr - BASE
        if not (0xC0000000 <= value < 0xD0000000 and 0 <= start < len(blob)):
            continue
        end = blob.find(b"\0", start, start + 160)
        if end < 0:
            continue
        name = blob[start:end]
        if re.fullmatch(rb"[A-Za-z_][A-Za-z0-9_]*", name):
            valid[off] = name.decode()
    names, seen = set(), set()
    for off in sorted(valid):
        if off in seen or (off - 8) in valid:
            continue
        chain, o = [], off
        while o in valid:
            chain.append(o)
            seen.add(o)
            o += 8
        if len(chain) >= MIN_RUN:
            names.update(valid[c] for c in chain)
    return names


def main():
    here = pathlib.Path(__file__).resolve().parent
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("reference", type=pathlib.Path,
                    help="vmlinux of a kernel already on the list")
    ap.add_argument("candidate", type=pathlib.Path,
                    help="vmlinux of the kernel being audited")
    ap.add_argument("modules", nargs="?", type=pathlib.Path, default=None,
                    help="directory of .ko files (default: the smp set)")
    ap.add_argument("-o", "--out", type=pathlib.Path, help="write the result as JSON")
    args = ap.parse_args()

    moddir = args.modules
    if moddir is None:
        for guess in (here / "../../opk/modules/smp", here / "../../opk-pe/modules/smp"):
            if guess.is_dir():
                moddir = guess
                break
    if moddir is None or not moddir.is_dir():
        sys.exit("cannot find the module directory; pass it as the third argument")
    kos = sorted(moddir.glob("*.ko"))
    if not kos:
        sys.exit("no .ko files in " + str(moddir))

    tables = {}
    for label, path in (("reference", args.reference), ("candidate", args.candidate)):
        blob = path.read_bytes()
        ident = re.search(rb"Linux version [ -~]{0,140}", blob)
        tables[label] = exports(blob)
        print("--- " + label + ": " + path.name)
        print("    " + (ident.group(0).decode() if ident else "(no version string)"))
        print("    " + str(len(tables[label])) + " exports")

    a, b = tables["reference"], tables["candidate"]
    print()
    print("exported by the reference kernel only: " + str(len(a - b)))
    print("exported by the candidate kernel only: " + str(len(b - a)))
    for label, rows in (("reference-only", sorted(a - b)), ("candidate-only", sorted(b - a))):
        if rows:
            print("  " + label + ": " + ", ".join(rows))

    provided, imports = set(), {}
    for ko in kos:
        for line in subprocess.check_output([NM, str(ko)], text=True).splitlines():
            n = line.split()[-1]
            if n.startswith("__ksymtab_"):
                provided.add(n[len("__ksymtab_"):])
    for ko in kos:
        out = subprocess.check_output([NM, "-u", str(ko)], text=True)
        imports[ko.name] = sorted(l.split()[-1] for l in out.splitlines() if l.split()[0] == "U")

    print()
    missing = {}
    for mod, syms in imports.items():
        gaps = [s for s in syms if s not in b and s not in provided]
        print("%-22s %3d imports, %d unresolved" % (mod, len(syms), len(gaps)))
        if gaps:
            missing[mod] = gaps
            print("    MISSING: " + ", ".join(gaps))

    if missing:
        verdict = "UNRESOLVED IMPORTS - do not add this kernel"
    elif b - a:
        verdict = "all imports resolve"
    else:
        verdict = "all imports resolve; the candidate exports nothing the reference does not"

    record = {
        "reference": args.reference.name,
        "candidate": args.candidate.name,
        "exports_reference": len(a),
        "exports_candidate": len(b),
        "exports_only_in_reference": sorted(a - b),
        "exports_only_in_candidate": sorted(b - a),
        "modules": {m: {"imports": len(s), "unresolved": missing.get(m, [])}
                    for m, s in imports.items()},
        "verdict": verdict,
    }
    if args.out:
        args.out.write_text(json.dumps(record, indent=2))
        print()
        print("wrote " + str(args.out))
    print()
    print("VERDICT: " + verdict)
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
