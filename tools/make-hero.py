#!/usr/bin/env python3
"""Compose docs/img/hero.png for the README from the app icon.

There is no App Store or simulator screenshot in this repository yet, so the
hero is the icon tools/make-icon.py draws, on the page's own canvas colour,
beside the app's name and its four tabs. Replace it with a screenshot when one
exists; nothing else reads this file.

    python3 tools/make-hero.py          (needs Pillow)
"""
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
ICON = os.path.join(ROOT, "IMPKT", "Assets.xcassets", "AppIcon.appiconset", "icon-1024.png")
OUT = os.path.join(ROOT, "docs", "img", "hero.png")

W, H = 1600, 720
CANVAS = (0xF5, 0xF5, 0xF7)        # Color.pageCanvas in IMPKTApp.swift
INK = (0x1D, 0x1D, 0x1F)
INK2 = (0x3A, 0x3A, 0x3C)
MUTED = (0x8A, 0x8A, 0x8E)
RED = (0xC4, 0x1E, 0x3A)           # Color.impktRed


def font(size, bold=False):
    """A system sans. HelveticaNeue.ttc carries several faces; pick by name."""
    ttc = "/System/Library/Fonts/HelveticaNeue.ttc"
    want = "Bold" if bold else "Regular"
    for i in range(16):
        try:
            f = ImageFont.truetype(ttc, size, index=i)
        except OSError:
            break
        if f.getname()[1] == want:
            return f
    fallback = "/System/Library/Fonts/Supplemental/Arial%s.ttf" % (" Bold" if bold else "")
    return ImageFont.truetype(fallback, size)


def rounded_icon(size, radius):
    icon = Image.open(ICON).convert("RGB").resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(icon, (0, 0), mask)
    return out


def main():
    img = Image.new("RGB", (W, H), CANVAS)
    draw = ImageDraw.Draw(img)

    # The icon with a soft shadow, the way a home screen shows it.
    size, radius = 400, 90
    x0, y0 = 130, (H - size) // 2
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((x0, y0 + 14, x0 + size, y0 + size + 14), radius=radius,
                                             fill=(0, 0, 0, 46))
    shadow = shadow.filter(ImageFilter.GaussianBlur(22))
    img.paste(shadow, (0, 0), shadow)
    img.paste(rounded_icon(size, radius), (x0, y0), rounded_icon(size, radius))

    # Name, one line of what it is, and the tabs.
    x = 640
    draw.text((x, 150), "impkt-ios", font=font(96, bold=True), fill=INK)
    body = font(34)
    for i, line in enumerate(["The IMPKT pilot page on an iPhone, with",
                              "CoreBluetooth underneath it and firmware",
                              "updates over Nordic DFU from the phone."]):
        draw.text((x, 290 + i * 46), line, font=body, fill=INK2)

    tabs = ["Test", "Leaderboard", "Devices", "Profile"]
    tab_font = font(26)
    tx, ty = x, 470
    for i, name in enumerate(tabs):
        colour = RED if i == 0 else MUTED
        draw.text((tx, ty), name, font=tab_font, fill=colour)
        tx += draw.textlength(name, font=tab_font) + 44
        if i < len(tabs) - 1:
            draw.ellipse((tx - 27, ty + 14, tx - 21, ty + 20), fill=MUTED)

    draw.text((x, 600), "Icon drawn by tools/make-icon.py from the brand mark. No screenshot yet.",
              font=font(22), fill=MUTED)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.save(OUT, optimize=True)
    print("wrote %s, %d bytes" % (OUT, os.path.getsize(OUT)))


if __name__ == "__main__":
    main()
