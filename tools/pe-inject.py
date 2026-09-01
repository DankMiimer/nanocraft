#!/usr/bin/env python3
"""Feed synthetic evdev events into Ninecraft's input FIFO.

Ninecraft's miyoo_input reads 16-byte struct input_event records from whatever
MIYOO_INPUT_DEVICE points at, so a FIFO is indistinguishable from the real
gpio_keys device. That is what makes the menus drivable over SSH.

Commands on stdin:  tap <code> [ms] | hold <code> <ms> | down <code> | up <code>
                    sleep <ms> | echo <text>
"""
import os, struct, sys, time

EV_SYN, EV_KEY, SYN_REPORT = 0, 1, 0
NAMES = {"up": 103, "down": 108, "left": 105, "right": 106,
         "a": 57, "b": 29, "x": 42, "y": 56,
         "l1": 18, "r1": 20, "l2": 15, "r2": 14,
         "start": 28, "select": 97, "menu": 1}

fifo = sys.argv[1]
fd = os.open(fifo, os.O_WRONLY)          # blocks until the game opens the read end

def pack(t, c, v):
    now = time.time(); sec = int(now)
    return struct.pack('<iiHHi', sec, int((now - sec) * 1e6), t, c, v)

def send(code, val):
    os.write(fd, pack(EV_KEY, code, val) + pack(EV_SYN, SYN_REPORT, 0))

def resolve(tok):
    return NAMES[tok.lower()] if tok.lower() in NAMES else int(tok)

for line in sys.stdin:
    p = line.split()
    if not p or p[0].startswith('#'):
        continue
    cmd = p[0]
    if cmd == 'sleep':
        time.sleep(int(p[1]) / 1000.0)
    elif cmd == 'echo':
        print(' '.join(p[1:]), flush=True)
    elif cmd == 'down':
        send(resolve(p[1]), 1)
    elif cmd == 'up':
        send(resolve(p[1]), 0)
    elif cmd in ('tap', 'hold'):
        ms = int(p[2]) if len(p) > 2 else 120
        c = resolve(p[1])
        send(c, 1); time.sleep(ms / 1000.0); send(c, 0)
        time.sleep(0.05)
    else:
        print("?? " + line.rstrip(), flush=True)
os.close(fd)
