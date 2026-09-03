#!/usr/bin/env python3
"""Turn a kernel fault dump into "which library faulted, and where".

A segfault's program counter is meaningless on its own. Resolved against the
process's own /proc/PID/maps it names the mapped file and the offset inside it,
which is the difference between "it crashes when I press Play" and "it faults in
libminecraftpe.so+0x1234".

Needs /proc/sys/kernel/print-fatal-signals set to 1 BEFORE the crash. On this
kernel that produces, in dmesg:

    potentially unexpected fatal signal 11.
    CPU: 0 PID: 5636 Comm: python3 ...
    pc : [<b6ef9c70>]    lr : [<0000feff>]    psr: 60000010

Verified end to end on an RG Nano: a deliberate NULL dereference resolved to
libc.so+0x65c70, which is correct.

    resolve-fault.py <dmesg-file> <maps-file>
"""
import re
import sys

PC = re.compile(r"pc\s*:\s*\[<([0-9a-fA-F]+)>\]")
LR = re.compile(r"lr\s*:\s*\[<([0-9a-fA-F]+)>\]")
SIG = re.compile(r"potentially unexpected fatal signal (\d+)")
COMM = re.compile(r"PID:\s*(\d+)\s+Comm:\s*(\S+)")
MAP = re.compile(
    r"^([0-9a-f]+)-([0-9a-f]+)\s+(\S{4})\s+([0-9a-f]+)\s+\S+\s+\d+\s*(.*)$")


def load_maps(path):
    out = []
    try:
        with open(path, errors="replace") as f:
            for line in f:
                m = MAP.match(line.strip())
                if m:
                    out.append((int(m.group(1), 16), int(m.group(2), 16),
                                m.group(3), int(m.group(4), 16),
                                m.group(5).strip()))
    except OSError:
        pass
    return out


def resolve(addr, maps):
    for lo, hi, perms, off, name in maps:
        if lo <= addr < hi:
            return lo, perms, off, name
    return None


def main():
    dmesg_path = sys.argv[1] if len(sys.argv) > 1 else "/dev/null"
    maps_path = sys.argv[2] if len(sys.argv) > 2 else "/dev/null"

    try:
        dm = open(dmesg_path, errors="replace").read()
    except OSError:
        print("  (no dmesg capture)")
        return

    sig = SIG.search(dm)
    comm = COMM.search(dm)
    pc = PC.search(dm)
    lr = LR.search(dm)

    if not sig and not pc:
        print("  No fatal-signal record in dmesg.")
        print("  Either the game did not crash, or print-fatal-signals was off")
        print("  when it did, or the ring buffer wrapped.")
        return

    if sig:
        n = int(sig.group(1))
        name = {4: "SIGILL", 6: "SIGABRT", 7: "SIGBUS", 8: "SIGFPE",
                11: "SIGSEGV"}.get(n, "signal %d" % n)
        print("  Fatal signal: %s (%d)" % (name, n))
    if comm:
        print("  Process:      %s (pid %s)" % (comm.group(2), comm.group(1)))

    maps = load_maps(maps_path)
    if not maps:
        print("  No usable memory map was captured, so the address below")
        print("  cannot be attributed to a library.")

    # libminecraftpe.so does NOT appear as a file in the map: Ninecraft loads it
    # with a bundled Android linker that maps it by hand, so the game's code
    # lands in ANONYMOUS executable memory. Without accounting for that, a fault
    # in the game - the single most interesting outcome - would report only
    # "anonymous". The game's text segment is by far the largest anonymous
    # executable region, so it is identifiable by size.
    anon_exec = [(lo, hi) for lo, hi, perms, off, name in maps
                 if perms.startswith("r-x") and not name]
    biggest = max((hi - lo, lo, hi) for lo, hi in anon_exec) if anon_exec else None

    for label, m in (("PC", pc), ("LR", lr)):
        if not m:
            continue
        addr = int(m.group(1), 16)
        hit = resolve(addr, maps) if maps else None
        if hit:
            base, perms, fileoff, name = hit
            if name:
                print("  %s  0x%08x  ->  %s+0x%x  [%s]"
                      % (label, addr, name, addr - base + fileoff, perms))
            else:
                size = 0
                for lo, hi in anon_exec:
                    if lo <= addr < hi:
                        size = hi - lo
                        break
                guess = ""
                if biggest and biggest[1] <= addr < biggest[2]:
                    guess = "  <-- very likely libminecraftpe.so (the game)"
                elif perms.startswith("r-x"):
                    guess = "  (anonymous executable memory)"
                print("  %s  0x%08x  ->  anonymous+0x%x  [%s, %d kB region]%s"
                      % (label, addr, addr - base, perms, size // 1024, guess))
        else:
            note = ""
            if addr < 0x1000:
                note = "   (a null-pointer dereference)"
            print("  %s  0x%08x  ->  not in any mapped region%s" % (label, addr, note))

    if biggest:
        print()
        print("  Largest anonymous executable region: 0x%08x-0x%08x (%d kB)"
              % (biggest[1], biggest[2], biggest[0] // 1024))
        print("  That is where the game's own code lives - it has no filename")
        print("  because Ninecraft's Android linker maps it by hand.")

    print()
    print("  How to read this: a fault in the largest anonymous executable")
    print("  region is the game's own code; inside swrast_dri.so or libGL is the")
    print("  software renderer; inside libEGL.so.1 is this port's presenter;")
    print("  inside libc/libpthread is usually the caller's bug, not libc's.")


if __name__ == "__main__":
    main()
