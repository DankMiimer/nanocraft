#!/usr/bin/env python3
"""Turn a play.log into a replayable input script.

miyoo_input logs every physical event with SDL_GetTicks() attached:

    miyoo-input: physical code=103 down at=26016

so a session is already a recording - this just recovers the timing deltas and
emits commands pe-inject.py understands. Replaying through the FIFO reproduces
the same session for benchmarking, without a human holding the console.

    mkreplay.py play.log [start_ms] > session.rep
"""
import re, sys

LINE = re.compile(r"physical code=(\d+) (down|up) at=(\d+)")

log = sys.argv[1]
skip_before = int(sys.argv[2]) if len(sys.argv) > 2 else 0

events = []
for line in open(log, errors="replace"):
    m = LINE.search(line)
    if m:
        code, act, t = int(m.group(1)), m.group(2), int(m.group(3))
        if t >= skip_before:
            events.append((t, code, act))

if not events:
    sys.exit("no input events in %s" % log)

prev = events[0][0]
print("# replay of %s: %d events over %.1fs"
      % (log, len(events), (events[-1][0] - events[0][0]) / 1000.0))
for t, code, act in events:
    gap = t - prev
    if gap > 0:
        print("sleep %d" % gap)
    print("%s %d" % (act, code))
    prev = t
