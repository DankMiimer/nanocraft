#!/usr/bin/env python3
"""Print evdev key events with the name Ninecraft's input layer would see.

Used to verify an fkgpiod keymap really produces the codes the MM+ binary
expects, before trusting a controls table written from theory.

Uses select() rather than a bare os.read(): a blocking read cannot honour the
deadline, so an earlier version hung forever whenever nobody pressed anything.
"""
import os, select, struct, sys, time

MIYOO = {1: "FN        esc/quit", 14: "MENU      R2 modifier", 15: "L2        start menu",
         18: "L1        place block", 20: "R1        break block", 28: "START     hotbar+",
         29: "B         look down", 42: "X         look up", 56: "Y         look left",
         57: "A         look right", 97: "SELECT    hotbar-", 103: "UP", 105: "LEFT",
         106: "RIGHT", 108: "DOWN"}

secs = int(sys.argv[1]) if len(sys.argv) > 1 else 60
fd = os.open("/dev/input/event0", os.O_RDONLY | os.O_NONBLOCK)
end = time.time() + secs
print("listening %ds - press buttons now" % secs, flush=True)
seen = []
while time.time() < end:
    r, _, _ = select.select([fd], [], [], 0.5)
    if not r:
        continue
    try:
        data = os.read(fd, 16 * 64)
    except BlockingIOError:
        continue
    for i in range(0, len(data) - 15, 16):
        _, _, typ, code, val = struct.unpack('<iiHHi', data[i:i+16])
        if typ == 1 and val in (0, 1):
            print("  code=%-4d %-22s %s" % (code, MIYOO.get(code, "UNMAPPED"),
                                            "down" if val else "up"), flush=True)
            if val == 1 and code not in seen:
                seen.append(code)
print("distinct codes pressed: %s" % seen, flush=True)
