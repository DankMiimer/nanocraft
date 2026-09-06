"""Run the real menu loop with synthetic evdev events and a file framebuffer.

Usage: python3 tests/quickmenu_events_test.py /path/to/asset-directory
The directory must contain the compiled menu-test and generated .raw assets.
"""
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import time

assets = Path(sys.argv[1]).resolve()
UP, DOWN, LEFT, RIGHT, A, B = 103, 108, 105, 106, 57, 29


def capture(fb, name):
    # Optional visual QA; event assertions below do not depend on Pillow.
    try:
        from PIL import Image
    except ImportError:
        return
    values = struct.unpack("<57600H", fb.read_bytes())
    pixels = bytes(v for p in values for v in (
        ((p >> 11) & 31) * 255 // 31, ((p >> 5) & 63) * 255 // 63, (p & 31) * 255 // 31))
    Image.frombytes("RGB", (240, 240), pixels).save(assets / name)


with tempfile.TemporaryDirectory(prefix="nanocraft-menu-") as td:
    data = Path(td)
    fb = data / "framebuffer"
    fb.write_bytes(bytes(240 * 240 * 2))
    fifo = data / "events"
    os.mkfifo(fifo)
    env = dict(os.environ, TEST_FRAMEBUFFER=str(fb), QUICKMENU_INPUT=str(fifo), MCPE_DATA=str(data))
    proc = subprocess.Popen([str(assets / "menu-test"), "--menu"], env=env)
    fd = os.open(fifo, os.O_RDWR)

    def press(key, count=1):
        for _ in range(count):
            os.write(fd, struct.pack("@llHHi", 0, 0, 1, key, 1))
            os.write(fd, struct.pack("@llHHi", 0, 0, 1, key, 0))
        time.sleep(.08)

    def saved():
        return (data / "sensitivity.txt").read_text().strip()

    try:
        deadline = time.monotonic() + 5
        while not any(fb.read_bytes()):
            assert proc.poll() is None, "menu exited before rendering"
            assert time.monotonic() < deadline, "menu did not render"
            time.sleep(.02)
        time.sleep(.05)  # initial input drain must complete
        press(UP, 4); press(A)  # RESUME -> SETTINGS -> SCREEN
        press(DOWN, 5)  # CURSOR
        capture(fb, "quick-settings-defaults.png")
        press(RIGHT); assert saved() == "100 30"
        press(LEFT, 30); assert saved() == "100 10"
        press(RIGHT, 30); assert saved() == "100 200"
        press(LEFT, 18); assert saved() == "100 20"
        press(UP); press(RIGHT); assert saved() == "110 20"
        press(LEFT); assert saved() == "100 20"
        press(DOWN); press(RIGHT); assert saved() == "100 30"
        capture(fb, "quick-settings-adjusted.png")
        assert not (data / "sensitivity.txt.tmp").exists()

        # GAME ICON, one row below CURSOR. Off unless the card says so, and the
        # direction SETS it rather than flipping it - pressing right twice must
        # not walk it back off.
        def icon():
            f = data / "game-icon.txt"
            return f.read_text().strip() if f.exists() else "(absent)"

        def icon_strip():
            # The 76x18 value strip for this row, straight out of the
            # framebuffer. Comparing pixels is what distinguishes "the row was
            # drawn from the saved setting" from "the file happens to say 1".
            raw = fb.read_bytes()
            return b"".join(raw[(y * 240 + 140) * 2:(y * 240 + 140) * 2 + 76 * 2]
                            for y in range(180, 198))

        assert icon() == "(absent)", icon()
        press(DOWN)                       # CURSOR -> GAME ICON
        press(RIGHT); assert icon() == "1", icon()
        on_pixels = icon_strip()
        press(RIGHT); assert icon() == "1", icon()
        press(LEFT);  assert icon() == "0", icon()
        off_pixels = icon_strip()
        assert on_pixels != off_pixels, "ON and OFF draw the same strip"
        press(LEFT);  assert icon() == "0", icon()
        press(RIGHT); assert icon() == "1", icon()
        assert icon_strip() == on_pixels
        capture(fb, "quick-settings-game-icon.png")
        press(B); press(B)
        assert proc.wait(timeout=3) == 0

        # A fresh menu must come up already showing ON, which only happens if it
        # read game-icon.txt at startup.
        proc = subprocess.Popen([str(assets / "menu-test"), "--menu"], env=env)
        time.sleep(.3)
        press(UP, 4); press(A); press(DOWN, 6)
        assert icon_strip() == on_pixels, "the row did not load its saved state"
        press(LEFT); assert icon() == "0", icon()
        press(B); press(B)
        assert proc.wait(timeout=3) == 0

        # A fresh invocation reads the persisted pair.
        proc = subprocess.Popen([str(assets / "menu-test"), "--menu"], env=env)
        time.sleep(.3)
        press(UP, 4); press(A); press(DOWN, 5); press(RIGHT)
        assert saved() == "100 40"
        press(B); press(B)
        assert proc.wait(timeout=3) == 0
    finally:
        os.close(fd)
        if proc.poll() is None:
            proc.terminate()
            proc.wait(timeout=3)
print("PASS: menu navigation, separate sliders, clamps, save, back/resume, relaunch persistence, and the GAME ICON row")
