#!/usr/bin/env python3
"""Draw the app icon from the brand mark's own geometry.

The site has the bolt as an SVG in a 48x44 box and as a 180px favicon. Neither
is an app icon: Apple wants 1024x1024 with no alpha channel, and enlarging a
180px png gives soft edges that look wrong next to every other icon on a home
screen. So the two polygons are rasterised here at full size instead.

No Pillow, no ImageMagick, no headless Chrome. Pillow is not installed, and a
browser screenshot carries an alpha channel that App Store validation rejects.
A png is a zlib stream with a header, and that is short enough to write out.

    python3 tools/make-icon.py

Rewrites IMPKT/Assets.xcassets/AppIcon.appiconset/icon-1024.png.
"""

import os
import struct
import zlib

SIZE = 1024
BG   = (255, 255, 255)
RED  = (0xC4, 0x1E, 0x3A)      # --red in css/impkt.css, the brand mark's colour

# The mark, exactly as the site draws it: two parallelograms in a 48x44 box.
# <polygon points="30.8,0 47.2,0 24.6,22.5 8.2,22.5"/>
# <polygon points="22.6,21.1 39,21.1 16.4,43.6 0,43.6"/>
BOX_W, BOX_H = 48.0, 44.0
BOLTS = [
    # (top y, bottom y, x at top-left, x at bottom-left, width)
    (0.0,  22.5, 30.8, 8.2,  16.4),
    (21.1, 43.6, 22.6, 0.0,  16.4),
]

# How much of the tile the mark fills. 0.60 leaves the margin Apple's own icons
# use; filling the tile makes it look larger than everything beside it.
FILL = 0.60
SUBROWS = 4                    # vertical samples per pixel row, for smooth edges


def spans(y):
    """The x ranges the mark covers on the scanline y, in pixels, merged.

    Merged rather than summed: the two halves overlap where the bolt joins, and
    adding their coverage there would draw a darker seam across the middle.
    """
    out = []
    for top, bottom, x_top, x_bottom, w in BOLTS:
        if not (top <= y_box(y) < bottom):
            continue
        t = (y_box(y) - top) / (bottom - top)
        left = x_top + (x_bottom - x_top) * t
        out.append((to_px_x(left), to_px_x(left + w)))
    out.sort()
    merged = []
    for lo, hi in out:
        if merged and lo <= merged[-1][1]:
            merged[-1][1] = max(merged[-1][1], hi)
        else:
            merged.append([lo, hi])
    return merged


scale   = SIZE * FILL / BOX_H
draw_w  = BOX_W * scale
off_x   = (SIZE - draw_w) / 2.0
off_y   = (SIZE - BOX_H * scale) / 2.0


def y_box(y_px):
    return (y_px - off_y) / scale


def to_px_x(x_box):
    return off_x + x_box * scale


def render():
    rows = []
    for py in range(SIZE):
        cover = {}
        for s in range(SUBROWS):
            y = py + (s + 0.5) / SUBROWS
            for lo, hi in spans(y):
                first = max(0, int(lo))
                last  = min(SIZE - 1, int(hi))
                for px in range(first, last + 1):
                    part = min(px + 1.0, hi) - max(float(px), lo)
                    if part > 0:
                        cover[px] = cover.get(px, 0.0) + min(part, 1.0) / SUBROWS
        row = bytearray(bytes(BG) * SIZE)
        for px, c in cover.items():
            c = min(c, 1.0)
            i = px * 3
            for ch in range(3):
                row[i + ch] = round(BG[ch] + (RED[ch] - BG[ch]) * c)
        rows.append(bytes(row))
    return rows


def png(rows, path):
    raw = b"".join(b"\x00" + r for r in rows)      # filter 0, no prediction

    def chunk(kind, data):
        return (struct.pack(">I", len(data)) + kind + data
                + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF))

    # Colour type 2 is rgb with no alpha, which is the requirement rather than a
    # preference: an icon with an alpha channel fails App Store validation.
    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(here, "..", "IMPKT", "Assets.xcassets",
                       "AppIcon.appiconset", "icon-1024.png")
    out = os.path.normpath(out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    png(render(), out)
    print("wrote %s, %d bytes" % (out, os.path.getsize(out)))
