#!/usr/bin/env python3
"""Generate the molten river's drifting current overlay (seamless in x).

pit_river.png is a static slab; this overlay adds bright veins that the game
scrolls slowly across it (uv.x wrap) so the melt reads as flowing. Threads are
sums of integer-wavenumber sines, so the left and right edges meet exactly.

Run:  py -3 tools/gen_river_current.py
"""
from __future__ import annotations

import math
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "assets", "title", "river_current.png")

W, H = 704, 40            # same canvas as pit_river.png — shares its transform
THREADS = 22

# ember ramp for the veins (rgba)
HOT = (255, 214, 120)
MID = (255, 150, 50)
DEEP = (232, 96, 28)


def _thread_y(x: float, base: float, k1: int, p1: float, a1: float,
              k2: int, p2: float, a2: float) -> float:
    t = 2.0 * math.pi * x / W
    return base + a1 * math.sin(k1 * t + p1) + a2 * math.sin(k2 * t + p2)


def main() -> None:
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = out.load()
    rng = 1337

    def rand() -> float:
        nonlocal rng
        rng = (rng * 1103515245 + 12345) & 0x7FFFFFFF
        return rng / float(0x7FFFFFFF)

    for _ in range(THREADS):
        base = 6.0 + rand() * (H - 12.0)
        k1 = 1 + int(rand() * 4)
        k2 = 3 + int(rand() * 6)
        p1, p2 = rand() * 6.283, rand() * 6.283
        a1 = 1.0 + rand() * 2.4
        a2 = 0.4 + rand() * 1.0
        thick = 1 if rand() < 0.7 else 2
        # brightness wanders along the thread (periodic, so the seam matches)
        kb = 2 + int(rand() * 5)
        pb = rand() * 6.283
        for x in range(W):
            glow = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(kb * 2.0 * math.pi * x / W + pb))
            y = _thread_y(x, base, k1, p1, a1, k2, p2, a2)
            iy = int(round(y))
            for dy in range(thick):
                yy = iy + dy
                if 0 <= yy < H:
                    shade = glow * (1.0 if dy == 0 else 0.55)
                    col = HOT if shade > 0.75 else (MID if shade > 0.45 else DEEP)
                    alpha = int(min(1.0, shade) * 200)
                    old = px[x, yy]
                    if alpha > old[3]:
                        px[x, yy] = (col[0], col[1], col[2], alpha)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    out.save(OUT)
    print(f"  river_current.png  {out.width}x{out.height}  seamless-x, {THREADS} threads")


if __name__ == "__main__":
    main()
