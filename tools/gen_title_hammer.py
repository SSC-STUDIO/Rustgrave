#!/usr/bin/env python3
"""Bake the title hammer's textures offline (body + head).

title_hammer.gd used to draw every surface as flat rects at runtime, which read
as clean vector shapes against the grimy pixel-art hall. This script renders
the same shapes to PNGs with rust, pitting, drips, chips and rivets baked in;
the runtime then just draws two textures (the arm stays code-drawn: its angle
changes every frame).

Canvas layout matches title_hammer.gd's local coordinates:
  hammer_body.png  36x56, local origin (18, 44) — anvil, pad, column, bearing
  hammer_head.png  18x14, top-left = the head's outline corner

Run:  py -3 tools/gen_title_hammer.py
"""
from __future__ import annotations

import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT_DIR = os.path.join(ROOT, "assets", "title")

OUTLINE = (0x0B, 0x09, 0x10, 255)
IRON_DARK = (0x24, 0x1C, 0x22, 255)
IRON = (0x3C, 0x34, 0x3C, 255)
IRON_LIGHT = (0x6A, 0x5A, 0x5E, 255)
RUST_A = (0x33, 0x18, 0x0E, 255)
RUST_B = (0x4A, 0x24, 0x12, 255)


def _hash(x: int, y: int) -> float:
    h = abs((x * 73856093) ^ (y * 19349663) ^ 0x5BFD9)
    return (h % 1000) / 1000.0


def _grime(px, x0: int, y0: int, x1: int, y1: int, density: float,
           w: int, h: int) -> None:
    """2px-grid rust speckle + sparse dark pitting inside a rect (baked)."""
    y = y0 + 1
    while y < y1 - 1:
        x = x0 + 1
        while x < x1 - 1:
            v = _hash(x, y)
            if v < density * 0.5:
                _put(px, x, y, RUST_A, w, h)
            elif v < density:
                _put(px, x, y, RUST_B, w, h)
                _put(px, x + 1, y, RUST_A, w, h)
            elif v > 0.94:
                _put(px, x, y, IRON_DARK, w, h)
            x += 2
        y += 2


def _put(px, x: int, y: int, col, w: int, h: int) -> None:
    if 0 <= x < w and 0 <= y < h:
        px[x, y] = col


def _rect(dr: ImageDraw.ImageDraw, x0: float, y0: float, x1: float, y1: float,
          ox: int, oy: int, col) -> None:
    # draw_rect-style: [x0, x1) x [y0, y1)
    dr.rectangle([x0 + ox, y0 + oy, x1 + ox - 1, y1 + oy - 1], fill=col)


def _body() -> None:
    w, h, ox, oy = 36, 56, 18, 44
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    px = img.load()
    # pad
    _rect(dr, -18, -3, 18, 0, ox, oy, IRON_DARK)
    _rect(dr, -18, -3, 18, -2, ox, oy, IRON)
    # anvil: block, throat, waist, face + top highlight, horn
    _rect(dr, -11, -14, 11, -3, ox, oy, OUTLINE)
    _rect(dr, -7, -6, 7, -3, ox, oy, IRON)
    _rect(dr, -4, -10, 4, -6, ox, oy, IRON)
    _rect(dr, -10, -13, 10, -10, ox, oy, IRON)
    _rect(dr, -10, -13, 10, -12, ox, oy, IRON_LIGHT)
    _rect(dr, -14, -13, -10, -11, ox, oy, IRON)
    _rect(dr, -16, -12, -14, -11, ox, oy, IRON)
    # column + bearing
    _rect(dr, 15, -42, 19, 0, ox, oy, IRON_DARK)
    _rect(dr, 15, -42, 16, 0, ox, oy, IRON)
    _rect(dr, 13, -44, 21, -39, ox, oy, IRON)
    _rect(dr, 13, -44, 21, -43, ox, oy, IRON_LIGHT)
    # diagonal brace (draw_line width 2 in the runtime)
    dr.line([15 + ox, -16 + oy, 9 + ox, 0 + oy], fill=IRON_DARK, width=2)
    # grime (vertical faces rust harder than the top faces)
    _grime(px, -10 + ox, -12 + oy, 10 + ox, -4 + oy, 0.16, w, h)
    _grime(px, -6 + ox, -9 + oy, 6 + ox, -6 + oy, 0.22, w, h)
    _grime(px, -17 + ox, -3 + oy, 17 + ox, -1 + oy, 0.24, w, h)
    _grime(px, 15 + ox, -41 + oy, 19 + ox, 0 + oy, 0.18, w, h)
    _grime(px, 13 + ox, -43 + oy, 21 + ox, -39 + oy, 0.20, w, h)
    # rust drips under the bearing, running down the column
    for dx, top, length in [(16, -39, 9), (18, -39, 16)]:
        for y in range(top, top + length):
            _put(px, dx + ox, y + oy, RUST_A, w, h)
            if _hash(dx, y) > 0.6:
                _put(px, dx + 1 + ox, y + oy, RUST_B, w, h)
    # anvil rivets
    for rx, ry in [(-9, -12), (7, -12)]:
        _rect(dr, rx, ry, rx + 2, ry + 2, ox, oy, IRON_DARK)
    # Long forged planes and worn edges are readable at 1x; surface speckles alone
    # made the machine look like a flat rectangle under the title's light wash.
    dr.line((8,32,26,32),fill='#8a7270')
    dr.line((9,33,25,33),fill='#58464a')
    dr.polygon([(23,34),(28,33),(28,39),(23,40)],fill='#231c25')
    dr.line((14,36,14,39),fill='#7c5b4b')
    dr.line((10,41,26,41),fill='#665154')
    dr.line((12,43,27,43),fill='#17131b')
    for y in (10,25,37):
        dr.line((33,y,35,y),fill='#817074')
        dr.line((33,y+2,35,y+2),fill='#17131b')
    img.save(os.path.join(OUT_DIR, "hammer_body.png"))
    print(f"  hammer_body.png  {w}x{h}")


def _head() -> None:
    w, h = 18, 14
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    px = img.load()
    # outline shell + iron face + top highlight + bright striking band
    _rect(dr, 0, 0, 18, 14, 0, 0, OUTLINE)
    _rect(dr, 1, 1, 17, 13, 0, 0, IRON)
    _rect(dr, 1, 1, 17, 2, 0, 0, IRON_LIGHT)
    _rect(dr, 2, 11, 16, 13, 0, 0, IRON_LIGHT)
    # the head is the biggest flat face: moderate grime + a rusted striking edge
    _grime(px, 1, 1, 17, 12, 0.15, w, h)
    for x in range(1, 17):
        if _hash(x, 99) < 0.55:
            _put(px, x, 12, RUST_B, w, h)
        if _hash(x, 77) < 0.30:
            _put(px, x, 11, RUST_A, w, h)
    # chipped corners
    _rect(dr, 1, 1, 3, 3, 0, 0, IRON_DARK)
    _rect(dr, 15, 11, 17, 13, 0, 0, IRON_DARK)
    # two rivet pairs on the face
    for rx, ry in [(4, 3), (12, 3)]:
        _rect(dr, rx, ry, rx + 2, ry + 2, 0, 0, IRON_DARK)
        _rect(dr, rx, ry, rx + 1, ry + 1, 0, 0, IRON_LIGHT)
    # Bevels, deep side plane, face stamp and two scored striking edges.
    dr.polygon([(2,1),(14,1),(16,3),(3,3)],fill='#79656b')
    dr.polygon([(15,3),(17,2),(17,12),(15,11)],fill='#211b25')
    dr.line((3,4,3,9),fill='#57444d')
    dr.line((2,10,14,10),fill='#221923')
    dr.line((3,11,13,11),fill='#917469')
    dr.line((4,12,12,12),fill='#675052')
    dr.line([(8,5),(10,6),(8,7),(10,8)],fill='#201821')
    for x in (5,11): dr.point((x,11),fill='#b88b64')
    img.save(os.path.join(OUT_DIR, "hammer_head.png"))
    print(f"  hammer_head.png  {w}x{h}")


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    _body()
    _head()


if __name__ == "__main__":
    main()
