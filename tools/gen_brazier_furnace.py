#!/usr/bin/env python3
"""Strip the painted flame off gh_furnace.png for the title's bridge braziers.

The braziers only draw the bottom 36 rows (REGION_Y=60) of the 32x96 furnace,
and that band still contains the asset's own yellow-green painted flame
(rows ~59-69). The title now simulates the fire with particles, so the baked
flame has to go: warm pixels in that band are cut to transparent, and the bowl
gets a sparse bed of dark embers for the particle flame to sit on.

Output keeps the full 32x96 canvas so the runtime REGION_Y/REGION_H still work.

Run:  py -3 tools/gen_brazier_furnace.py
"""
from __future__ import annotations

import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(ROOT, "assets", "env", "gh_furnace.png")
OUT = os.path.join(ROOT, "assets", "title", "brazier_furnace.png")

# The painted flame lives in this row band of the source texture.
FLAME_TOP, FLAME_BOTTOM = 56, 72
# Bowl interior rows where a dark ember bed is sprinkled.
BED_TOP, BED_BOTTOM = 68, 71

COALS = [(0x3A, 0x14, 0x06, 255), (0x52, 0x1C, 0x08, 255), (0x24, 0x0C, 0x05, 255)]


def _is_painted_flame(r: int, g: int, b: int, a: int) -> bool:
    # the baked flame is bright yellow-green; the bowl's browns stay well below
    return a > 100 and r > 140 and g > 100 and b < 130


def main() -> None:
    im = Image.open(SRC).convert("RGBA")
    px = im.load()
    cut = 0
    for y in range(FLAME_TOP, FLAME_BOTTOM):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if _is_painted_flame(r, g, b, a):
                px[x, y] = (0, 0, 0, 0)
                cut += 1
    # ember bed: deterministic scatter inside the bowl
    for y in range(BED_TOP, BED_BOTTOM + 1):
        for x in range(9, 22):
            h = ((x * 73856093) ^ (y * 19349663) ^ 0x1B3F) % 1000 / 1000.0
            if h < 0.30:
                px[x, y] = COALS[int(h * 10) % len(COALS)]
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    im.save(OUT)
    print(f"  brazier_furnace.png  {im.width}x{im.height}  flame pixels cut: {cut}")


if __name__ == "__main__":
    main()
