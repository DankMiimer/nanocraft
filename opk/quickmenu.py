#!/usr/bin/env python3
"""In-game quick menu for the RG Nano NanoCraft port.

WHY THIS EXISTS. On this OS the power-button menu is not an OS service -- it is
drawn by whatever app is in the foreground. fkgpiod answers the button with
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
python, so every glyph is pre-rendered by make-menu-bg.sh on the workstation:
menubg.raw and videobg.raw for the two pages' layouts, res240.raw/res120.raw for
the screen settings and gsauto/gsfit/gs11.raw for the interface scales.
Everything that changes -- the cursor and the bars -- is drawn here as
rectangles.

TWO PAGES. The main list, and a video page reached from its VIDEO row. Both
video settings are read by the game at startup and so need a restart, which is
why they share a page and a single footer saying so.

Exit codes are the action for run.sh:
    0 resume, 2 close game, 3 shut down, 4 restart the game
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
DATA = os.environ.get("MCPE_DATA", "/mnt/FunKey/nanocraft")
RESFILE = os.path.join(DATA, "resolution.txt")
GSFILE = os.path.join(DATA, "guiscale.txt")
IDLE_TIMEOUT = 90.0          # never leave the console wedged in the menu

# CLOSE is labelled "FORCE CLOSE" on screen, and the name is accurate: it sends
# SIGTERM and then SIGKILL. Minecraft autosaves as it goes, but anything since
# the last autosave is lost. Quitting through the game's own pause menu
# (L+START) is the route that saves first.
VOLUME, BRIGHT, CPU, VIDEO, RESTART, CLOSE, SHUTDOWN, RESUME = range(8)

# The video page, reached from the VIDEO row. SCREEN lives here rather than on
# the main list because both rows are the same kind of setting, both are read by
# the game only at startup, and one footer can say so for both. It also keeps
# the main list at eight rows, which is what the 240-pixel panel holds.
V_SCREEN, V_GUISCALE, V_BACK = range(3)
MAIN, VIDEO_PAGE = 0, 1
PAGE_ROWS = (8, 3)

ROW_TOP = [34, 58, 82, 106, 130, 154, 178, 202]
ROW_H = 22
BAR_X, BAR_W, BAR_H = 118, 106, 11
VAL_X, VAL_W, VAL_H = 140, 76, 18

# Only these two divide the 240x240 panel cleanly; anything between shimmers.
# 120x120 is the default -- about 11.9 fps against 7.8 -- and run.sh assumes the
# same when resolution.txt is absent. Keep the two in step: a menu that shows
# 240x240 while the game launches at 120x120 is worse than no row at all.
SIZES = [240, 120]
DEFAULT_SIZE = 120

# Interface scale, passed to the launcher as NINECRAFT_GUI_SCALE.
#
# Ninecraft lays the interface out at a scale it computes from the window size
# and floors at 1.0. That floor is 62 pixels too generous at 120x120, where the
# 182-pixel hotbar loses both ends -- so the port's launcher takes a scale from
# the environment and will go below 1.0 when told to.
#
#   auto  shrink only as far as the hotbar needs. Changes nothing at 240x240,
#         where there is already room, and fixes 120x120.
#   fit   size the interface to the hotbar in both directions, so it also grows
#         into the spare room at 240x240. Larger there, identical to auto at
#         120x120, and never clipped at either. The default, because it is the
#         one setting that suits both screen sizes.
#   1.0   stock Ninecraft: one interface pixel per rendered pixel. Crisp, and
#         clipped at 120x120. Kept as the way back to the original look, and
#         shown as STOCK because that is what it is.
SCALES = ["auto", "fit", "1.0"]
DEFAULT_SCALE = "fit"
SCALE_STRIP = {"auto": "gsauto.raw", "fit": "gsfit.raw", "1.0": "gsstock.raw"}

# The CPU ladder, 48 MHz per step from stock, as reported by `nano-clk --list`.
# It stops at 1248: the V3s is specified at 1.2 GHz, there is no thermal
# management on this SoC, and what an individual unit tolerates is not knowable
# from here. nano-clk itself refuses to go further without --force, which this
# menu never passes.
CLOCKS = [1008, 1056, 1104, 1152, 1200, 1248]
NANOCLK = os.path.join(HERE, "nano-clk")


def rgb(r, g, b):
    return ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)


C_CURSOR = rgb(120, 220, 120)
C_BAR_BG = rgb(35, 45, 68)
C_BAR_FG = rgb(120, 220, 120)
C_BAR_ED = rgb(140, 155, 185)


def read_size():
    """Current render width, defaulting the way run.sh does when the file is
    absent -- which is the state every fresh install is in."""
    try:
        with open(RESFILE) as f:
            w = int(f.read().split()[0])
        if w in SIZES:
            return w
    except Exception:
        pass
    return DEFAULT_SIZE


def write_size(w):
    try:
        os.makedirs(DATA, exist_ok=True)
        with open(RESFILE, "w") as f:
            f.write("%d %d\n" % (w, w))
        return True
    except OSError:
        return False


def read_guiscale():
    """Current interface scale, defaulting to the one that always fits."""
    try:
        with open(GSFILE) as f:
            v = f.read().split()[0]
        if v in SCALES:
            return v
    except Exception:
        pass
    return DEFAULT_SCALE


def write_guiscale(v):
    try:
        os.makedirs(DATA, exist_ok=True)
        with open(GSFILE, "w") as f:
            f.write("%s\n" % v)
        return True
    except OSError:
        return False


def read_clock():
    """Current CPU MHz, or None if the tool is missing or /dev/mem is refused."""
    try:
        out = subprocess.run([NANOCLK], capture_output=True, timeout=8).stdout.decode()
    except Exception:
        return None
    for line in out.splitlines():
        if "CPU CLOCK:" in line:
            try:
                return int(line.split("CPU CLOCK:")[1].split()[0])
            except (IndexError, ValueError):
                return None
    return None


def set_clock(mhz):
    """Apply a clock. Unlike the screen size this takes effect immediately -- it
    is a register write, not something the game reads at startup."""
    try:
        subprocess.run([NANOCLK, "--set", str(mhz)], capture_output=True, timeout=15)
    except Exception:
        pass
    return read_clock()


class Screen:
    def __init__(self):
        self.f = open("/dev/fb0", "r+b", buffering=0)
        # The panel's virtual buffer is 240x720 (triple buffered) but the port
        # never pans, so the visible frame is always the first 240x240.
        self.m = mmap.mmap(self.f.fileno(), FBSIZE, mmap.MAP_SHARED,
                           mmap.PROT_READ | mmap.PROT_WRITE)
        self.bg = [self._load("menubg.raw", FBSIZE),
                   self._load("videobg.raw", FBSIZE)]
        strip = VAL_W * VAL_H * BPP
        self.val = {w: self._load("res%d.raw" % w, strip) for w in SIZES}
        self.clkval = {m: self._load("cpu%d.raw" % m, strip) for m in CLOCKS}
        self.gsval = {v: self._load(SCALE_STRIP[v], strip) for v in SCALES}

    @staticmethod
    def _load(name, size):
        try:
            with open(os.path.join(HERE, name), "rb") as f:
                data = f.read(size)
            return data if len(data) == size else None
        except OSError:
            return None

    def blit_bg(self, page):
        if self.bg[page]:
            self.m[0:FBSIZE] = self.bg[page]

    def blit(self, data, x, y, w, h):
        """Copy a small pre-rendered strip in, row by row."""
        if not data:
            return
        for row in range(h):
            dst = ((y + row) * W + x) * BPP
            src = row * w * BPP
            self.m[dst:dst + w * BPP] = data[src:src + w * BPP]

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
    page = MAIN
    sel = RESUME
    vol = get_pct("volume")
    bri = get_pct("brightness")
    size = read_size()
    gscale = read_guiscale()
    clock = read_clock()

    scr = Screen()
    # The device path is overridable so the menu can be driven from a FIFO for
    # testing, the same way miyoo_input honours MIYOO_INPUT_DEVICE. Unset in
    # normal use, where it is the console's own buttons.
    dev = os.environ.get("QUICKMENU_INPUT", "/dev/input/event0")
    fd = os.open(dev, os.O_RDONLY)
    grabbed = False
    try:
        fcntl.ioctl(fd, EVIOCGRAB, 1)
        grabbed = True
    except OSError:
        if "QUICKMENU_INPUT" not in os.environ:
            # The game still holds the grab -- without MIYOO_NO_GRAB=1 there is
            # no way to read input here. Give the screen back rather than hang.
            os.close(fd)
            scr.close()
            return 0
        # A FIFO cannot be grabbed; that is expected when driving it for a test.

    # Drop anything already queued so the press that opened the menu, or a
    # button still held from gameplay, cannot immediately pick an item.
    while select.select([fd], [], [], 0)[0]:
        try:
            os.read(fd, 4096)
        except OSError:
            break

    def draw():
        scr.blit_bg(page)
        vy = (ROW_H - VAL_H) // 2
        if page == MAIN:
            scr.bar(ROW_TOP[VOLUME], vol)
            scr.bar(ROW_TOP[BRIGHT], bri)
            if clock is not None:
                scr.blit(scr.clkval.get(clock), VAL_X, ROW_TOP[CPU] + vy,
                         VAL_W, VAL_H)
        else:
            scr.blit(scr.val.get(size), VAL_X, ROW_TOP[V_SCREEN] + vy,
                     VAL_W, VAL_H)
            scr.blit(scr.gsval.get(gscale), VAL_X, ROW_TOP[V_GUISCALE] + vy,
                     VAL_W, VAL_H)
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
                sel = (sel - 1) % PAGE_ROWS[page]
                dirty = True
            elif code == K_DOWN:
                sel = (sel + 1) % PAGE_ROWS[page]
                dirty = True
            elif code in (K_LEFT, K_RIGHT):
                step = 10 if code == K_RIGHT else -10
                if page == VIDEO_PAGE:
                    if sel == V_SCREEN:
                        # Only two settings, so either direction toggles. Both
                        # rows here are written immediately and read by the game
                        # only at startup, which is what the footer says and
                        # what the main list's RESTART row is for.
                        size = SIZES[1] if size == SIZES[0] else SIZES[0]
                        write_size(size)
                        dirty = True
                    elif sel == V_GUISCALE:
                        # Wraps rather than stopping at the ends: three values,
                        # and a wrap is fewer presses than walking back.
                        i = SCALES.index(gscale) if gscale in SCALES else 0
                        i = (i + (1 if code == K_RIGHT else -1)) % len(SCALES)
                        gscale = SCALES[i]
                        write_guiscale(gscale)
                        dirty = True
                elif sel == VOLUME:
                    vol = max(0, min(100, vol + step))
                    set_pct("volume", vol)
                    dirty = True
                elif sel == BRIGHT:
                    bri = max(0, min(100, bri + step))
                    set_pct("brightness", bri)
                    dirty = True
                elif sel == CPU and clock is not None:
                    # Applies at once: this is a register write, not something
                    # the game reads at startup. Steps along the ladder rather
                    # than jumping, so a console that cannot hold a clock fails
                    # at the smallest increment past what it can do.
                    try:
                        i = CLOCKS.index(clock)
                    except ValueError:
                        i = 0
                    i = max(0, min(len(CLOCKS) - 1, i + (1 if code == K_RIGHT else -1)))
                    clock = set_clock(CLOCKS[i]) or clock
                    dirty = True
            elif code == K_A:
                if page == VIDEO_PAGE:
                    if sel == V_BACK:
                        page, sel = MAIN, VIDEO
                        dirty = True
                    continue
                if sel == VIDEO:
                    page, sel = VIDEO_PAGE, V_SCREEN
                    dirty = True
                    continue
                if sel == RESTART:
                    action = 4
                elif sel == CLOSE:
                    action = 2
                elif sel == SHUTDOWN:
                    action = 3
                elif sel == RESUME:
                    action = 0
                else:
                    continue
                break
            elif code == K_B:
                # B is "back" on the video page and "resume" on the main one,
                # which is the same gesture either way: leave where you are.
                if page == VIDEO_PAGE:
                    page, sel = MAIN, VIDEO
                    dirty = True
                    continue
                action = 0
                break
        else:
            if dirty:
                draw()
            continue
        break

    if grabbed:
        try:
            fcntl.ioctl(fd, EVIOCGRAB, 0)
        except OSError:
            pass
    os.close(fd)
    scr.close()
    return action


if __name__ == "__main__":
    sys.exit(main())
