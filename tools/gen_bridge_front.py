#!/usr/bin/env python3
"""Cut the bridge's front railing band into its own overlay texture.

bridge.png rows 9-25 are the near-side railing (top rail, posts, mid rail);
the deck surface starts at row 26 where the knight's feet rest. Drawing this
band again IN FRONT of the actors grounds them behind the railing instead of
floating over it.

Run:  py -3 tools/gen_bridge_front.py
"""
from __future__ import annotations

import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(ROOT, "assets", "title", "bridge.png")
OUT = os.path.join(ROOT, "assets", "title", "bridge_front.png")

# Railing band: everything above the deck plate (deck top row = 26).
RAIL_TOP, RAIL_BOTTOM = 0, 26


def main() -> None:
    src = Image.open(SRC).convert("RGBA")
    out = Image.new("RGBA", src.size, (0, 0, 0, 0))
    band = src.crop((0, RAIL_TOP, src.width, RAIL_BOTTOM))
    out.paste(band, (0, RAIL_TOP))
    out.save(OUT)
    print(f"  bridge_front.png  {out.width}x{out.height}  rail rows {RAIL_TOP}..{RAIL_BOTTOM - 1}")


if __name__ == "__main__":
    main()
