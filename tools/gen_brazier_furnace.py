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

from PIL import Image, ImageDraw

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
    # The runtime uses only these rows. Draw a real iron bowl and curved legs,
    # instead of retaining the furnace's bright triangular painted fire cradle.
    dr = ImageDraw.Draw(im)
    dr.rectangle((0,60,31,95),fill=(0,0,0,0))
    dr.polygon([(2,70),(29,70),(26,79),(22,82),(9,82),(5,79)],fill='#120f15')
    dr.polygon([(4,72),(27,72),(24,78),(21,80),(10,80),(7,77)],fill='#4d3632')
    dr.line([(5,74),(9,79),(21,79),(25,75)],fill='#6d4938')
    dr.line([(8,78),(12,81),(21,81)],fill='#241b21')
    dr.ellipse((3,68,28,74),fill='#241b21')
    dr.ellipse((5,69,26,73),fill='#5b3021')
    # Separated charcoal facets and tiny orange cracks: no broad white patch.
    for x,y in [(7,71),(12,70),(17,72),(22,70)]:
        dr.polygon([(x-2,y),(x,y-1),(x+2,y),(x+1,y+1),(x-1,y+1)],fill='#281817')
        dr.point((x+1,y),fill='#ae4e26')
    dr.line((4,73,27,73),fill='#95633f')
    for x in (8,15,23):
        dr.point((x,76),fill='#b47a4c');dr.point((x,77),fill='#251c22')
    for points in [[(9,81),(8,86),(6,91),(4,94)],[(22,81),(23,86),(25,91),(27,94)]]:
        dr.line(points,fill='#16121a',width=3)
        dr.line([(x,y) for x,y in points],fill='#5a4140')
    dr.line((6,88,25,88),fill='#211a22',width=2)
    dr.rectangle((2,94,9,95),fill='#32272b')
    dr.rectangle((23,94,30,95),fill='#32272b')
    dr.line((3,94,8,94),fill='#795040');dr.line((24,94,29,94),fill='#795040')
    # Keep the unused chimney and the redrawn bowl on one 16-colour ramp.
    palette = [tuple(bytes.fromhex(c)) for c in (
        '120f15','241b21','4d3632','6d4938','281817','ae4e26','95633f','b47a4c',
        '251c22','16121a','5a4140','211a22','32272b','795040','c57e4d','8f4424')]
    mapping = {}
    for y in range(im.height):
        for x in range(im.width):
            old = px[x,y]
            if not old[3]:
                continue
            if old not in mapping:
                closest = min(palette, key=lambda p: sum((p[i]-old[i])**2 for i in range(3)))
                mapping[old] = closest + (255,)
            px[x,y] = mapping[old]
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    im.save(OUT)
    print(f"  brazier_furnace.png  {im.width}x{im.height}  flame pixels cut: {cut}")


if __name__ == "__main__":
    main()
