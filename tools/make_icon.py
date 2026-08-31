#!/usr/bin/env python3
"""Draw the Foundry launcher icon - a cog over a poured ingot - at any size.

The Venu 2 family wants two sizes (70px for the 416x416 watches, 61px for the
360x360 Venu 2S), so the artwork is described once in a 60x60 design space and
rasterised with 4x supersampling at whatever size is asked for. Pure stdlib, so
it runs anywhere the build runs.

    python3 tools/make_icon.py resources-round-416x416/drawables/launcher_icon.png 70
"""
import math
import os
import struct
import sys
import zlib

DESIGN = 60.0   # the coordinate space the shapes below are drawn in
SS = 4          # supersampling factor

BG = (0x0C, 0x0C, 0x10, 255)
COG = (0x8A, 0x93, 0x9E, 255)
COG_DARK = (0x4A, 0x50, 0x58, 255)
GOLD = (0xFF, 0xC6, 0x1E, 255)
CLEAR = (0, 0, 0, 0)

TEETH = 8
COG_CX, COG_CY = 30.0, 25.0
COG_R = 15.0        # body radius
COG_TIP = 19.5      # tooth tip radius
COG_BORE = 5.5      # the hole in the middle


def in_disc(px, py, cx, cy, r):
    return (px - cx) ** 2 + (py - cy) ** 2 <= r * r


def in_rect(px, py, x, y, w, h):
    return x <= px <= x + w and y <= py <= y + h


def in_cog(px, py):
    """The cog body plus its teeth, as one filled shape."""
    dx, dy = px - COG_CX, py - COG_CY
    dist = math.hypot(dx, dy)
    if dist <= COG_BORE:
        return False
    if dist <= COG_R:
        return True
    if dist > COG_TIP:
        return False
    # Between body and tip: inside only where a tooth is. Each tooth occupies
    # half of its slice of the circle.
    angle = math.degrees(math.atan2(dy, dx)) % (360.0 / TEETH)
    return angle < (360.0 / TEETH) * 0.5


def in_ingot(px, py):
    """A poured bar under the cog: a trapezoid, wider at the base."""
    if not 44.0 <= py <= 52.0:
        return False
    # Sides slope out by 2px over the bar's height.
    inset = 2.0 * (52.0 - py) / 8.0
    return 15.0 + inset <= px <= 45.0 - inset


def shade(px, py):
    """Colour of the design-space point (px, py), or CLEAR outside the icon."""
    if not in_disc(px, py, 30, 30, 29.5):
        return CLEAR
    if in_ingot(px, py):
        return GOLD
    if in_cog(px, py):
        # A darker lower-right gives the cog some weight without a gradient.
        return COG_DARK if (px - COG_CX) + (py - COG_CY) > 8.0 else COG
    return BG


def render(size):
    scale = DESIGN / (size * SS)
    rows = []
    for y in range(size):
        row = bytearray()
        for x in range(size):
            r = g = b = a = 0
            for sy in range(SS):
                for sx in range(SS):
                    px = (x * SS + sx + 0.5) * scale
                    py = (y * SS + sy + 0.5) * scale
                    c = shade(px, py)
                    r, g, b, a = r + c[0], g + c[1], b + c[2], a + c[3]
            n = SS * SS
            row += bytes((r // n, g // n, b // n, a // n))
        rows.append(row)
    return rows


def write_png(path, size, rows):
    raw = b"".join(b"\x00" + bytes(row) for row in rows)

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as handle:
        handle.write(png)


def main(argv):
    if len(argv) != 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    path, size = argv[1], int(argv[2])
    write_png(path, size, render(size))
    print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
