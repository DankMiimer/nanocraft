#!/usr/bin/env python3
"""In-game quick menu for the RG Nano Minecraft PE port.

WHY THIS EXISTS. On this OS the power-button menu is not an OS service -- it is
drawn by whatever app is in the foreground. fkgpiod answers KEY_POWER with
`powerdown schedule 0.1`, which signals the registered foreground process and
then cuts power 100 ms later unless that process cancels it. GMenu2X's menu is
GMenu2X catching that signal. A game that ignores it just gets switched off
mid-session, so the menu has to be provided here or not at all.

TWO THINGS MAKE IT POSSIBLE, and both are arranged by run.sh before this runs:

  1. The game is launched with MIYOO_NO_GRAB=1. Normally Ninecraft takes an
     exclusive EVIOCGRAB on /dev/input/event0, which would leave no way for a
     second process to read the buttons. With the grab released, THIS process
     grabs instead -- so while the menu is up the game receives no input at all
     and no stale presses queue up behind it.
  2. The game is SIGSTOPped. It repaints /dev/fb0 every frame, so anything drawn
     over it would survive about 130 ms. Frozen, the panel holds still and the
     menu owns the screen.

NO FONT ENGINE IS USED. The device has no PIL and no reachable TTF stack from
python, so every glyph is pre-rendered into menubg.raw (240x240 RGB565) by
make-menu-bg.sh on the workstation. Everything that changes -- the cursor and
the two bars -- is drawn here as rectangles.

Exit codes are the action for run.sh: 0 resume, 2 close game, 3 shut down.
"""
import fcntl
import mmap
import os
import select
import struct
import subprocess
import sys

W, H, BPP = 240, 240, 2
FBSIZE = W * H * BPP
EVIOCGRAB = 0x40044590
EV_KEY = 1

# Codes as this port's fkgpiod keymap emits them (see minecraft.key).
K_UP, K_DOWN, K_LEFT, K_RIGHT, K_A, K_B = 103, 108, 105, 106, 57, 29

HERE = os.path.dirname(os.path.abspath(__file__))
IDLE_TIMEOUT = 90.0          # never leave the console wedged in the menu

VOLUME, BRIGHT, CLOSE, SHUTDOWN, RESUME = range(5)
ROW_TOP = [48, 83, 122, 157, 192]
ROW_H = 24
BAR_X, BAR_W, BAR_H = 112, 112, 12


def rgb(r, g, b):
    return ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)


C_CURSOR = rgb(120, 220, 120)
C_BAR_BG = rgb(35, 45, 68)
C_BAR_FG = rgb(120, 220, 120)
C_BAR_ED = rgb(140, 155, 185)


class Screen:
    def __init__(self):
        self.f = open("/dev/fb0", "r+b", buffering=0)
        # The panel's virtual buffer is 240x720 (triple buffered) but the port
        # never pans, so the visible frame is always the first 240x240.
        self.m = mmap.mmap(self.f.fileno(), FBSIZE, mmap.MAP_SHARED,
                           mmap.PROT_READ | mmap.PROT_WRITE)
        with open(os.path.join(HERE, "menubg.raw"), "rb") as bg:
            self.bg = bg.read(FBSIZE)

    def blit_bg(self):
        self.m[0:FBSIZE] = self.bg

    def rect(self, x, y, w, h, color):
        if w <= 0 or h <= 0:
            return
        x, y = max(0, x), max(0, y)
        w, h = min(w, W - x), min(h, H - y)
        row = struct.pack("<H", color) * w
        for yy in range(y, y + h):
            off = (yy * W + x) * BPP
            self.m[off:off + w * BPP] = row

    def cursor(self, y_center):
        # A solid triangle, drawn as a stack of rows -- cheaper than any glyph
        # and unambiguous at this size.
        for i in range(9):
            hgt = 2 * (9 - i) - 1
            self.rect(5 + i, y_center - hgt // 2, 1, hgt, C_CURSOR)

    def bar(self, top, pct):
        y = top + (ROW_H - BAR_H) // 2
        self.rect(BAR_X, y, BAR_W, BAR_H, C_BAR_BG)
        self.rect(BAR_X, y, BAR_W, 1, C_BAR_ED)
        self.rect(BAR_X, y + BAR_H - 1, BAR_W, 1, C_BAR_ED)
        self.rect(BAR_X, y, 1, BAR_H, C_BAR_ED)
        self.rect(BAR_X + BAR_W - 1, y, 1, BAR_H, C_BAR_ED)
        fill = int((BAR_W - 4) * max(0, min(100, pct)) / 100.0)
        self.rect(BAR_X + 2, y + 2, fill, BAR_H - 4, C_BAR_FG)

    def close(self):
        try:
            self.m.close()
            self.f.close()
        except Exception:
            pass


def run(*args):
    try:
        return subprocess.run(args, capture_output=True, timeout=8).stdout.decode().strip()
    except Exception:
        return ""


def get_pct(what):
    out = run("/usr/local/sbin/" + what, "get")
    try:
        return max(0, min(100, int(out)))
    except ValueError:
        return 50


def set_pct(what, value):
    # `set` rather than `up`/`down`: the up/down wrappers post an on-screen
    # notification that would paint over this menu.
    run("/usr/local/sbin/" + what, "set", str(value))


def main():
    sel = RESUME
    vol = get_pct("volume")
    bri = get_pct("brightness")

    scr = Screen()
    fd = os.open("/dev/input/event0", os.O_RDONLY)
    try:
        fcntl.ioctl(fd, EVIOCGRAB, 1)
    except OSError:
        # The game still holds the grab -- without MIYOO_NO_GRAB=1 there is no
        # way to read input here. Give the screen back rather than hang.
        os.close(fd)
        scr.close()
        return 0

    # Drop anything already queued so the press that opened the menu, or a
    # button still held from gameplay, cannot immediately pick an item.
    while select.select([fd], [], [], 0)[0]:
        try:
            os.read(fd, 4096)
        except OSError:
            break

    def draw():
        scr.blit_bg()
        scr.bar(ROW_TOP[VOLUME], vol)
        scr.bar(ROW_TOP[BRIGHT], bri)
        scr.cursor(ROW_TOP[sel] + ROW_H // 2)

    draw()
    action = 0
    while True:
        if not select.select([fd], [], [], IDLE_TIMEOUT)[0]:
            break                                   # idle: resume the game
        try:
            data = os.read(fd, 16 * 64)
        except OSError:
            break
        dirty = False
        for i in range(0, len(data) - 15, 16):
            _, _, typ, code, val = struct.unpack("<iiHHi", data[i:i + 16])
            if typ != EV_KEY or val != 1:
                continue
            if code == K_UP:
                sel = (sel - 1) % 5
                dirty = True
            elif code == K_DOWN:
                sel = (sel + 1) % 5
                dirty = True
            elif code in (K_LEFT, K_RIGHT):
                step = 10 if code == K_RIGHT else -10
                if sel == VOLUME:
                    vol = max(0, min(100, vol + step))
                    set_pct("volume", vol)
                    dirty = True
                elif sel == BRIGHT:
                    bri = max(0, min(100, bri + step))
                    set_pct("brightness", bri)
                    dirty = True
            elif code == K_A:
                if sel == CLOSE:
                    action = 2
                elif sel == SHUTDOWN:
                    action = 3
                elif sel == RESUME:
                    action = 0
                else:
                    continue
                break
            elif code == K_B:
                action = 0
                break
        else:
            if dirty:
                draw()
            continue
        break

    try:
        fcntl.ioctl(fd, EVIOCGRAB, 0)
    except OSError:
        pass
    os.close(fd)
    scr.close()
    return action


if __name__ == "__main__":
    sys.exit(main())
