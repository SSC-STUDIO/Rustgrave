#!/usr/bin/env python3
"""Bake the title's living props' metal into textures.

title_crucible.gd and title_sword_chain.gd draw their iron and steel as flat
draw_rect fills at runtime, which read as clean vector shapes against the grimy
pixel hall (the same complaint the hammer had). This bakes the static metal into
PNGs. Rotation is never applied to a texture (it smears pixel art): the crucible
gets five pre-tilted frames, and the runtime picks the nearest one.

Outputs:
  crucible_tilt.png  five pose frames, 40x40 each, pivot at (20, 11) so the
                     runtime can place frame origin at the trolley hook (PIVOT_Y).
                     Frame i is the cup tilted to i * 22.5 degrees (0..90).
  sword_blade.png    one greatsword: ring, grip, guard and blade, 16x64, origin at
                     the hook. Name marks stay runtime-drawn (their colour follows
                     the furnace).

Run:  py -3 tools/gen_title_props.py
"""
from __future__ import annotations

import math
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT_DIR = os.path.join(ROOT, "assets", "title")

OUTLINE = (0x0B, 0x09, 0x10, 255)
IRON_DARK = (0x24, 0x1C, 0x22, 255)
IRON = (0x3C, 0x34, 0x3C, 255)
IRON_LIGHT = (0x6A, 0x5A, 0x5E, 255)
RUST_A = (0x33, 0x18, 0x0E, 255)
RUST_B = (0x4A, 0x24, 0x12, 255)
STEEL = (0x8A, 0x8F, 0x9A, 255)
STEEL_LIGHT = (0xB9, 0xBE, 0xC8, 255)
STEEL_DARK = (0x55, 0x5B, 0x68, 255)

# crucible geometry, from title_crucible.gd (CUP is the untilted cup). The pivot sits at
# the canvas centre so the cup stays inside 40x40 through the whole 0..90 degree tilt.
CUP = [(-11.0, -2.0), (11.0, -2.0), (8.0, 16.0), (-8.0, 16.0)]
PIVOT = (20.0, 16.0)
TILT_FRAMES = 5


def _hash(x: int, y: int) -> float:
    h = abs((x * 73856093) ^ (y * 19349663) ^ 0x3C5A)
    return (h % 1000) / 1000.0


def _rotate(p: tuple[float, float], angle: float) -> tuple[float, float]:
    c, s = math.cos(angle), math.sin(angle)
    return (p[0] * c - p[1] * s, p[0] * s + p[1] * c)


def _grime(px, w: int, h: int, x0: int, y0: int, x1: int, y1: int, density: float) -> None:
    """2px-grid rust speckle + sparse dark pitting inside a rect (baked, deterministic)."""
    for y in range(y0 + 1, y1 - 1, 2):
        for x in range(x0 + 1, x1 - 1, 2):
            v = _hash(x, y)
            if v < density * 0.5:
                _put(px, w, h, x, y, RUST_A)
            elif v < density:
                _put(px, w, h, x, y, RUST_B)
                _put(px, w, h, x + 1, y, RUST_A)
            elif v > 0.94:
                _put(px, w, h, x, y, IRON_DARK)


def _put(px, w: int, h: int, x: int, y: int, col) -> None:
    if 0 <= x < w and 0 <= y < h:
        px[x, y] = col


def _inside(poly: list[tuple[float, float]], x: float, y: float) -> bool:
    """Even-odd point-in-polygon test for the cup silhouette."""
    inside = False
    n = len(poly)
    for i in range(n):
        (x0, y0), (x1, y1) = poly[i], poly[(i + 1) % n]
        if (y0 > y) != (y1 > y):
            if x < (x1 - x0) * (y - y0) / (y1 - y0) + x0:
                inside = not inside
    return inside


def _fill_poly(px, w: int, h: int, pts: list[tuple[float, float]], col) -> None:
    """Scanline fill of a polygon in integer pixel space (no antialiasing)."""
    ys = [p[1] for p in pts]
    for y in range(int(math.floor(min(ys))), int(math.ceil(max(ys))) + 1):
        xs: list[float] = []
        for i in range(len(pts)):
            (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % len(pts)]
            if (y0 <= y + 0.5 < y1) or (y1 <= y + 0.5 < y0):
                t = (y + 0.5 - y0) / (y1 - y0)
                xs.append(x0 + t * (x1 - x0))
        xs.sort()
        for i in range(0, len(xs) - 1, 2):
            for x in range(int(round(xs[i])), int(round(xs[i + 1]))):
                _put(px, w, h, x, y, col)


def _crucible_frame(angle: float) -> Image.Image:
    w = h = 40
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    # outline (1px fatter), then the iron cup, then the molten surface
    outline = [_rotate((p[0] + math.copysign(1.0, p[0]) * 1.0, p[1] + (1.0 if p[1] > 1.0 else -1.0)),
                       angle) for p in CUP]
    cup = [_rotate(p, angle) for p in CUP]
    pts_o = [(PIVOT[0] + x, PIVOT[1] + y) for x, y in outline]
    pts_c = [(PIVOT[0] + x, PIVOT[1] + y) for x, y in cup]
    _fill_poly(px, w, h, pts_o, OUTLINE)
    _fill_poly(px, w, h, pts_c, IRON)
    # rim highlight along the first edge, grime on the faces
    rx0, ry0 = pts_c[0]
    rx1, ry1 = pts_c[1]
    for t in range(0, 22):
        x = int(round(rx0 + (rx1 - rx0) * t / 21.0))
        y = int(round(ry0 + (ry1 - ry0) * t / 21.0))
        _put(px, w, h, x, y, IRON_LIGHT)
    # rust only on the iron itself: test each pixel against the cup silhouette
    for y in range(h):
        for x in range(w):
            if _inside(pts_c, x + 0.5, y + 0.5) and _hash(x, y) < 0.10:
                _put(px, w, h, x, y, RUST_A if _hash(x + 7, y + 3) < 0.5 else RUST_B)
    # molten surface sits inside the rim, drawn last so it reads as the pour's source
    surf = [_rotate(p, angle) for p in [(-9.0, 0.0), (9.0, 0.0), (7.0, 5.0), (-7.0, 5.0)]]
    _fill_poly(px, w, h, [(PIVOT[0] + x, PIVOT[1] + y) for x, y in surf], (0x4D, 0x1C, 0x17, 255))
    return img


def _crucible_strip() -> None:
    frames = []
    for i in range(TILT_FRAMES):
        angle = -(i / (TILT_FRAMES - 1)) * (math.pi * 0.5)
        frames.append(_crucible_frame(angle))
    strip = Image.new("RGBA", (40 * TILT_FRAMES, 40), (0, 0, 0, 0))
    for i, frame in enumerate(frames):
        strip.paste(frame, (40 * i, 0))
    strip.save(os.path.join(OUT_DIR, "crucible_tilt.png"))
    print(f"  crucible_tilt.png  {strip.width}x{strip.height}  ({TILT_FRAMES} frames, 40 px each)")


def _sword() -> None:
    w, h = 16, 64
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    cx = 8  # hook centre
    # ring + grip + guard (y offsets match title_sword_chain.gd _draw_sword)
    for y in range(0, 5):
        _put(px, w, h, cx - 1, y, IRON_LIGHT)
        _put(px, w, h, cx, y, IRON_LIGHT)
    for y in range(6, 6 + 52):
        for x in range(cx - 5, cx + 5):
            _put(px, w, h, x, y, OUTLINE)
    for y in range(5, 8):
        for x in range(cx - 2, cx + 2):
            _put(px, w, h, x, y, IRON_LIGHT)
    for y in range(8, 16):
        for x in range(cx - 1, cx + 1):
            _put(px, w, h, x, y, IRON)
    for x in range(cx - 8, cx + 8):
        _put(px, w, h, x, 16, IRON_LIGHT)
        _put(px, w, h, x, 17, IRON_LIGHT)
        _put(px, w, h, x, 18, IRON_LIGHT)
    # blade: steel body, bright left edge, dark right edge, grime, tip
    for y in range(19, 55):
        for x in range(cx - 4, cx + 4):
            col = STEEL
            if x == cx - 4:
                col = STEEL_LIGHT
            elif x == cx + 3:
                col = STEEL_DARK
            _put(px, w, h, x, y, col)
    _grime(px, w, h, cx - 4, 19, cx + 4, 55, 0.08)
    for y in range(55, 58):
        for x in range(cx - 2, cx + 2):
            _put(px, w, h, x, y, STEEL)
    for y in range(58, 60):
        for x in range(cx - 1, cx + 1):
            _put(px, w, h, x, y, STEEL_DARK)
    img.save(os.path.join(OUT_DIR, "sword_blade.png"))
    print(f"  sword_blade.png  {w}x{h}")


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    _crucible_strip()
    _sword()


if __name__ == "__main__":
    main()
