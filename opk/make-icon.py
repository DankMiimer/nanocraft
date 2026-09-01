#!/usr/bin/env python3
"""Generate NanoCraft's icon.

ORIGINAL ARTWORK, ON PURPOSE. The earlier icon was scaled from the Miyoo Mini
Plus card's Minecraft-styled tile, which is fine on a private device and not
fine in a public release. Nothing here imitates Minecraft's art: no grass block,
no dirt, no logo, no typeface from the game. It is a voxel motif in a palette
chosen to look like this port's own quick menu.

Drawn in code rather than in an editor so the repo carries the source of the
icon, not just the output -- and so it can be regenerated at any size.

Pure standard library: PIL is not available here, so the PNG is encoded by hand
(zlib + four chunks). No dependencies, nothing to install.

    make-icon.py [size] [out.png]
"""
import struct
import sys
import zlib

SIZE = int(sys.argv[1]) if len(sys.argv) > 1 else 140
OUT = sys.argv[2] if len(sys.argv) > 2 else "nanocraft.png"

BG = (16, 24, 34)
PANEL = (26, 38, 56)
TOP = (126, 214, 176)      # lit face
LEFT = (58, 140, 122)      # shaded face
RIGHT = (36, 96, 92)       # darkest face
EDGE = (168, 240, 208)
SPARK = (240, 196, 96)     # the small cubes

px = [[BG for _ in range(SIZE)] for _ in range(SIZE)]


def put(x, y, c):
    if 0 <= x < SIZE and 0 <= y < SIZE:
        px[y][x] = c


def rounded_panel(x0, y0, x1, y1, r, c):
    for y in range(y0, y1):
        for x in range(x0, x1):
            dx = min(x - x0, x1 - 1 - x)
            dy = min(y - y0, y1 - 1 - y)
            if dx < r and dy < r and (r - dx) ** 2 + (r - dy) ** 2 > r * r:
                continue
            put(x, y, c)


def poly(points, c):
    """Scanline fill. Small polygons, so clarity beats cleverness."""
    ys = [p[1] for p in points]
    for y in range(int(min(ys)), int(max(ys)) + 1):
        xs = []
        n = len(points)
        for i in range(n):
            (x1, y1), (x2, y2) = points[i], points[(i + 1) % n]
            if y1 == y2:
                continue
            if min(y1, y2) <= y < max(y1, y2):
                xs.append(x1 + (y - y1) * (x2 - x1) / float(y2 - y1))
        xs.sort()
        for i in range(0, len(xs) - 1, 2):
            for x in range(int(round(xs[i])), int(round(xs[i + 1])) + 1):
                put(x, y, c)


def cube(cx, cy, a, h, top, left, right, grid=True):
    """Isometric cube: 2:1 projection, three faces, three shades."""
    b = a / 2.0
    poly([(cx, cy - h - b), (cx + a, cy - h), (cx, cy - h + b), (cx - a, cy - h)], top)
    poly([(cx - a, cy - h), (cx, cy - h + b), (cx, cy + b), (cx - a, cy)], left)
    poly([(cx + a, cy - h), (cx, cy - h + b), (cx, cy + b), (cx + a, cy)], right)
    if not grid or a < 12:
        return
    # A voxel seam down the vertical edge and along the top ridges: enough to
    # read as "made of blocks" without turning into a texture.
    for t in range(int(h + b)):
        put(int(cx), int(cy + b - t), EDGE)
    for t in range(int(a)):
        f = t / float(a)
        put(int(cx - a + t), int(cy - h - f * b + b * 0), EDGE)
        put(int(cx + a - t), int(cy - h - f * b), EDGE)


SPARK_L = (176, 132, 52)
SPARK_R = (128, 92, 34)
S = SIZE / 140.0

# GMENU2X DOES NOT SCALE ICONS. It draws them at native size and clips to the
# link slot (linkWidth=80, linkHeight=50 in the stock skin), so a 140x140 icon
# shows only its top-left corner -- which is exactly what a first attempt at
# this one did. Every icon on this console that renders correctly is 32x32:
# eduke32, sm64 and DrUm78's own Overclock. The 128x128 Pokemon icon is clipped
# too; it just happens to be dark there so nobody noticed.
#
# So 32x32 is the size that matters, and the composition has to survive it. At
# that size the trail of small cubes would be one or two pixels each, i.e.
# noise, so below 64px the icon becomes a single well-proportioned cube.
if SIZE < 64:
    m = max(1, int(SIZE * 0.03))
    rounded_panel(m, m, SIZE - m, SIZE - m, max(2, int(SIZE * 0.14)), PANEL)
    a = int(SIZE * 0.34)
    cube(SIZE // 2, int(SIZE * 0.72), a, a, TOP, LEFT, RIGHT, grid=False)
else:
    rounded_panel(int(6 * S), int(6 * S), int(134 * S), int(134 * S),
                  int(18 * S), PANEL)
    # One large cube with three shrinking companions running off to the lower
    # right -- the "nano" idea, without a word of text.
    cube(int(60 * S), int(84 * S), int(34 * S), int(34 * S), TOP, LEFT, RIGHT)
    cube(int(101 * S), int(100 * S), int(15 * S), int(15 * S), SPARK, SPARK_L, SPARK_R, grid=False)
    cube(int(116 * S), int(112 * S), int(8 * S), int(8 * S), SPARK, SPARK_L, SPARK_R, grid=False)
    cube(int(125 * S), int(120 * S), int(4 * S), int(4 * S), SPARK, SPARK_L, SPARK_R, grid=False)

raw = b"".join(b"\x00" + bytes(v for p in row for v in p) for row in px)


def chunk(tag, data):
    return (struct.pack(">I", len(data)) + tag + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))


png = (b"\x89PNG\r\n\x1a\n"
       + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
       + chunk(b"IDAT", zlib.compress(raw, 9))
       + chunk(b"IEND", b""))

with open(OUT, "wb") as f:
    f.write(png)
print("wrote %s (%dx%d, %d bytes)" % (OUT, SIZE, SIZE, len(png)))
