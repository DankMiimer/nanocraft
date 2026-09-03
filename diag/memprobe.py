#!/usr/bin/env python3
"""How much memory can this console actually give a process?

Entering a world needs about 68 MB of anonymous memory on hardware with 56 MB of
RAM, so it depends on swap. This asks the question directly, without running the
game: allocate and TOUCH memory a megabyte at a time until it fails, and report
how far it got.

Touching matters. Linux overcommits, so an untouched allocation proves nothing;
the pages must be written to be real.

Deliberately capped and deliberately gentle: it stops at the target, releases
everything immediately, and never pushes the system to the point of thrashing
the way an uncapped test would.

    memprobe.py [target-MB]
"""
import os
import sys

TARGET = int(sys.argv[1]) if len(sys.argv) > 1 else 80
CHUNK = 1024 * 1024


def meminfo(key):
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                if line.startswith(key + ":"):
                    return int(line.split()[1]) // 1024
    except OSError:
        pass
    return -1


print("  target:    %d MB (a world needs about 68 MB)" % TARGET)
print("  before:    RAM avail %d MB, swap free %d MB"
      % (meminfo("MemAvailable"), meminfo("SwapFree")))

blocks = []
got = 0
err = None
try:
    for i in range(TARGET):
        b = bytearray(CHUNK)
        # Touch every page so the kernel has to back it with something real.
        for off in range(0, CHUNK, 4096):
            b[off] = 1
        blocks.append(b)
        got += 1
except MemoryError:
    err = "MemoryError"
except Exception as e:                      # noqa: BLE001 - report anything
    err = "%s: %s" % (type(e).__name__, e)

print("  allocated: %d MB%s" % (got, "" if err is None else "  (stopped: %s)" % err))
print("  during:    RAM avail %d MB, swap free %d MB"
      % (meminfo("MemAvailable"), meminfo("SwapFree")))

del blocks

if got >= TARGET:
    print("  VERDICT:   OK - this console can supply a world's working set")
elif got >= 68:
    print("  VERDICT:   TIGHT - reached %d MB, enough for a world but with"
          " little headroom" % got)
else:
    print("  VERDICT:   TOO LITTLE - stopped at %d MB, below the ~68 MB a world"
          " needs." % got)
    print("             This alone would explain menus working and Play failing.")
