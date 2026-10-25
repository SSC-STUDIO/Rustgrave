#!/usr/bin/env python3
"""Bake the far-side walkway the hammer and the ghost procession stand on.

docs/title-live-scene.md §6.1 always described "对岸那条细栈桥" but nothing drew
it, so the hammer and the ghosts floated. This bakes a dim, distance-hazed iron
walkway: deck plate + thin railing + struts and two support legs that fade into
the dark below. Same 2px-grid iron language as bridge.png, two shades darker.

Canvas: 384 px wide, placed at world x=156 (the span that is not hidden behind the
furnace masses, the braziers or the bridge), deck top at texture y=5 (runtime places
the sprite so deck top lands on the actors' floor, y=241).

Run:  py -3 tools/gen_far_walkway.py
"""
from __future__ import annotations

import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "assets", "title", "far_walkway.png")

W, H = 384, 34
DECK_TOP = 5

# distance-hazed iron. The deck must sit clearly above the hall backdrop (~31,34,51),
# so it is lighter than before; the struts stay dark and recede.
EDGE = (0x6A, 0x5C, 0x6E, 255)
PLATE = (0x3A, 0x33, 0x44, 255)
RAIL = (0x4C, 0x42, 0x55, 255)
STRUT = (0x1C, 0x18, 0x26, 255)
BOLT = (0x70, 0x62, 0x74, 255)


def _hash(x: int, y: int) -> float:
    h = abs((x * 73856093) ^ (y * 19349663) ^ 0x2A71)
    return (h % 1000) / 1000.0


def main() -> None:
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = img.load()

    # railing: 1px posts every 24px + a 1px top rail (starts/ends 8px in from the caps)
    for x in range(8, W - 8, 24):
        for y in range(0, DECK_TOP):
            px[x, y] = RAIL
    for x in range(8, W - 8):
        px[x, 1] = RAIL

    # deck: top edge highlight + 3px plate, ends step back 2px (stair-step cap)
    for x in range(W):
        inset = 2 if (x < 2 or x >= W - 2) else 0
        if inset:
            continue
        px[x, DECK_TOP] = EDGE
        for y in range(DECK_TOP + 1, DECK_TOP + 4):
            px[x, y] = PLATE
    # bolts along the deck face
    for x in range(12, W - 8, 24):
        px[x, DECK_TOP + 2] = BOLT

    # under-structure: diagonal struts every 48px, fading as they drop
    for x0 in range(24, W - 24, 48):
        for step in range(14):
            x = x0 + step // 2
            y = DECK_TOP + 4 + step
            if y >= H:
                break
            fade = max(0.0, 1.0 - step / 14.0)
            col = (STRUT[0], STRUT[1], STRUT[2], int(200 * fade))
            if 0 <= x < W:
                px[x, y] = col
                if step % 3 == 0 and x + 1 < W:
                    px[x + 1, y] = col

    # two short support legs near the ends, dissolving into the dark well before the river
    for lx in (54, W - 62):
        for y in range(DECK_TOP + 4, DECK_TOP + 4 + 14):
            fade = max(0.0, 1.0 - (y - DECK_TOP - 4) / 14.0)
            a = int(220 * fade)
            if a <= 0:
                continue
            px[lx, y] = (PLATE[0], PLATE[1], PLATE[2], a)
            px[lx + 1, y] = (PLATE[0], PLATE[1], PLATE[2], a)
            if _hash(lx, y) < 0.12:
                px[lx, y] = (EDGE[0], EDGE[1], EDGE[2], a)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.save(OUT)
    print(f"  far_walkway.png  {img.width}x{img.height}  deck top at y={DECK_TOP}")


if __name__ == "__main__":
    main()
