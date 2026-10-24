"""Draw Rustgrave's original bell-boss pixel art. Pillow only; no source images.

Every shape, carved mark, rivet and animation pose below is authored here.
PNG coordinates are integer pixels, RGBA, with no antialiasing/resampling.
Run with the bundled Python: python tools/gen_original_bell_bosses.py --boss hollow_bell
"""
from __future__ import annotations

import argparse
import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "assets" / "characters"
OUTLINE = "#101d25"


def poly(d, points, fill, outline=OUTLINE, width=1):
    d.polygon(points, fill=fill)
    if outline:
        d.line(points + [points[0]], fill=outline, width=width)


def rivet(d, x, y, light="#b4c4aa", dark="#293d42"):
    d.rectangle((x - 1, y - 1, x + 1, y + 1), fill=dark)
    d.point((x - 1, y - 1), fill=light)
    d.point((x, y), fill=light)


def link(d, x, y, vertical=True):
    rect = (x - 2, y - 4, x + 2, y + 4) if vertical else (x - 4, y - 2, x + 4, y + 2)
    d.rounded_rectangle(rect, radius=2, fill="#1b2e35", outline="#658380")
    d.line((x - 1, y - 2, x - 1, y + 1), fill="#adc4ad")


def save_frame(boss, action, index, image):
    folder = BASE / ("original_" + boss) / action
    folder.mkdir(parents=True, exist_ok=True)
    image.save(folder / f"{action}_{index}.png", optimize=True)


def hollow_bell(action, frame, hot):
    im = Image.new("RGBA", (160, 336))
    d = ImageDraw.Draw(im)
    active = 2 <= frame <= 3 and action not in ("idle", "stagger")
    swing = [-2, -1, 2, 3, 1, 0][frame % 6] if action == "pendulum" else 0
    pulse = (frame % 3) - 1
    cx = 80 + swing
    top, bottom = 140, 257
    dark, mid, shine = "#243d45", "#496b6b", "#9bb3a0"
    # The suspension is a forged double chain, anchored to an ornamented yoke.
    poly(d, [(57, 10), (103, 10), (109, 17), (105, 25), (55, 25), (51, 17)], dark)
    d.line((57, 13, 103, 13), fill=shine)
    for x in (58, 70, 90, 102):
        rivet(d, x, 19)
    for y in range(30, 126, 9):
        link(d, 75, y, (y // 9) % 2 == 0)
        link(d, 85, y, (y // 9) % 2 != 0)
    # Crown loop and segmented shoulder, not a helmet or a humanoid head.
    d.ellipse((cx - 13, 118, cx + 13, 145), fill=OUTLINE, outline=shine, width=2)
    d.ellipse((cx - 7, 123, cx + 7, 139), fill=(0, 0, 0, 0), outline=mid, width=2)
    poly(d, [(cx - 24, 137), (cx - 31, 147), (cx + 31, 147), (cx + 24, 137)], mid)
    d.line((cx - 23, 139, cx + 23, 139), fill=shine, width=2)
    # Hollow flared bell with irregular casting edges and a thick internal lip.
    body = [(cx - 30, top + 6), (cx + 30, top + 6), (cx + 35, 171),
            (cx + 40, 201), (cx + 47, 232), (cx + 58, 252), (cx + 57, 265),
            (cx - 58, 265), (cx - 59, 252), (cx - 48, 234), (cx - 40, 201),
            (cx - 35, 171)]
    poly(d, body, dark, width=2)
    poly(d, [(cx - 27, 150), (cx - 6, 149), (cx - 8, 247), (cx - 51, 250),
             (cx - 38, 211)], mid, None)
    poly(d, [(cx - 24, 151), (cx - 17, 151), (cx - 22, 210), (cx - 43, 248),
             (cx - 49, 250), (cx - 33, 206)], "#678d83", None)
    poly(d, [(cx + 4, 150), (cx + 24, 151), (cx + 33, 204), (cx + 48, 247),
             (cx + 21, 249)], "#385451", None)
    d.line((cx + 28, 155, cx + 34, 205, cx + 51, 248), fill="#5b7770", width=2)
    # Patina clusters, edge nicks, cast seams. These stay on the metal facets.
    for i in range(45):
        y = 158 + (i * 19) % 83
        x = cx - 28 + (i * 29) % 55
        if abs(x - cx) > 13 or y < 165:
            col = ["#608e7d", "#2d5053", "#73957e"][i % 3]
            d.line((x, y, x + (i % 3), y + 1), fill=col)
    # Two decorated mould bands, with tiny recessed triangular cast ornaments.
    for y, half in ((164, 34), (230, 46)):
        d.rectangle((cx - half, y, cx + half, y + 5), fill="#1b3037")
        d.line((cx - half, y, cx + half, y), fill=shine)
        d.line((cx - half + 2, y + 4, cx + half - 2, y + 4), fill="#718e7c")
        for x in range(cx - half + 5, cx + half - 2, 8):
            d.line((x, y + 1, x + 2, y + 3, x + 4, y + 1), fill="#65877b")
    # Inset name tablets: original angular cipher strokes, not borrowed text.
    for offset, length in ((-19, 38), (0, 48), (19, 38)):
        x, y = cx + offset, 176 if offset else 172
        poly(d, [(x - 6, y), (x + 6, y), (x + 7, y + length - 4),
                 (x + 3, y + length), (x - 6, y + length - 2)], "#182d35", "#77968a")
        rivet(d, x, y + 3, shine)
        for mark in range(4 if offset else 6):
            gy = y + 9 + mark * 5
            d.line((x - 2, gy, x + 2, gy, x + 2, gy + 2, x - 1, gy + 3),
                   fill="#9eb6a0" if (frame + mark) % 4 else "#688c80")
    # The big fractured face is asymmetrical and branches around the tablets.
    crack = [(cx + 12, 149), (cx + 8, 167), (cx + 14, 179), (cx + 9, 193),
             (cx + 15, 208), (cx + 10, 222), (cx + 18, 238), (cx + 16, 254)]
    d.line(crack, fill="#0b2029", width=5 if hot else 3)
    if hot:
        d.line(crack, fill="#d66d36", width=3)
        d.line(crack, fill="#ffd68a" if pulse else "#fff1b8", width=1)
        d.line((cx + 14, 179, cx + 26, 184, cx + 31, 180), fill="#ee9860", width=2)
        d.line((cx + 10, 222, cx + 28, 215, cx + 35, 217), fill="#ffb46b", width=2)
        # Phase two opens physical triangular missing pieces at the rim.
        poly(d, [(cx + 11, 257), (cx + 17, 247), (cx + 23, 263)], "#ffb56a", OUTLINE)
    # Elliptical inner opening and engraved thick rolled lip.
    d.ellipse((cx - 56, bottom - 7, cx + 56, bottom + 10), fill="#0d2028", outline="#8da18a", width=2)
    d.arc((cx - 53, bottom - 4, cx + 53, bottom + 10), 0, 180, fill="#355455", width=3)
    d.line((cx - 52, 263, cx + 52, 263), fill="#b1b89b")
    for x in range(cx - 49, cx + 50, 14):
        rivet(d, x, 256)
    # The clapper is a separate sprite aligned to the real WeakHurtbox below.
    # Only the short internal socket is part of the shell.
    d.rectangle((cx - 4, 251, cx + 4, 269), fill="#2b4448", outline=shine)
    if action == "chain_pull":
        for side in (-1, 1):
            for j in range(6 if active else 3):
                link(d, cx + side * (16 + j * 7), 267 + int(math.sin(j) * 4), False)
    elif action == "toll_wave" and active:
        for offset in (0, 5):
            d.arc((cx - 65 - offset, 202 - offset, cx + 65 + offset, 277 + offset),
                  15, 165, fill="#b2dfca" if not hot else "#ffca7c", width=1)
    elif action == "bell_drop":
        for side in (-1, 1):
            for j in range(3):
                x = cx + side * (48 + j * 7)
                y = 186 + j * 15 + (10 if active else 0)
                d.line((x, y, x, y + 12), fill="#759f9a")
    if action == "stagger":
        for dx, dy in [(-44, 179), (43, 205), (-57, 238)]:
            d.line((cx + dx - 2, dy, cx + dx + 2, dy), fill="#e4ecbd")
            d.line((cx + dx, dy - 2, cx + dx, dy + 2), fill="#e4ecbd")
    return im


def hollow_hammer(frame, hot):
    im = Image.new("RGBA", (40, 64))
    d = ImageDraw.Draw(im)
    for y in range(3, 35, 7):
        link(d, 20, y, y % 2 == 0)
    poly(d, [(11, 33), (29, 33), (35, 40), (33, 53), (27, 58), (12, 58),
             (6, 51), (5, 41)], "#46666a", width=2)
    poly(d, [(8, 41), (13, 36), (27, 36), (31, 41), (26, 45), (12, 45)], "#9db7a5")
    d.line((9, 46, 10, 52, 15, 55, 26, 55, 30, 51), fill="#79978a")
    for x in (12, 28):
        rivet(d, x, 48)
    # A concentric brass boss marks the actual attackable clapper.
    d.ellipse((15, 43, 25, 53), fill="#483f31", outline="#d5b469")
    d.ellipse((18, 46, 22, 50), fill="#ffe7a1" if hot or frame % 2 else "#cbe0ad")
    d.point((20, 45), fill="#fff8cb")
    return im


def generate_hollow_bell():
    actions = {"idle": 4, "pendulum": 6, "chain_pull": 6, "bell_drop": 6,
               "toll_wave": 6, "stagger": 4}
    for hot in (False, True):
        prefix = "hot_" if hot else ""
        for action, count in actions.items():
            for frame in range(count):
                image = hollow_bell(action, frame, hot)
                # Tiny suspension/body sway is drawn into the frame, not a hitbox change.
                if action in ("idle", "stagger") and frame % 2:
                    shifted = Image.new("RGBA", image.size)
                    shifted.alpha_composite(image, (1 if frame == 1 else -1, 0))
                    image = shifted
                save_frame("hollow_bell", prefix + action, frame, image)
        for frame in range(4):
            save_frame("hollow_bell", prefix + "hammer", frame, hollow_hammer(frame, hot))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--boss", choices=["hollow_bell"], default="hollow_bell")
    parser.parse_args()
    generate_hollow_bell()
    print("Drew original HollowBell pixel frames from shapes; no source images read.")


if __name__ == "__main__":
    main()
