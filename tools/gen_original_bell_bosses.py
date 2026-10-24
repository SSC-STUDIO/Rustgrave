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


def bell_founder(action, frame, hot, hammer=False):
    im = Image.new("RGBA", (128, 112))
    d = ImageDraw.Draw(im)
    active = 2 <= frame <= 3 and action not in ("idle", "stagger")
    windup = frame < 2 and action == "hammer_slam"
    squash = 3 if active and action == "hammer_slam" else (1 if frame % 2 else 0)
    cx, cy = 64, squash
    coal, iron, copper, light = "#161c23", "#30333a", "#8c4d36", "#d19465"
    ember = "#ffca71" if hot else "#e78c3e"
    if hammer:
        # Fully segmented forging hammer, all pivots drawn from scratch.
        # A windup lifts the head; active plants it beside the actual slam zone.
        hx, hy = (78, 20) if windup else ((105, 91) if active and action == "hammer_slam" else (98, 53))
        grip = (83, 70 + squash)
        d.line((grip, (hx, hy)), fill=OUTLINE, width=7)
        d.line((grip, (hx, hy)), fill="#9c7950", width=4)
        for i in range(1, 6):
            x = int(grip[0] + (hx - grip[0]) * i / 6)
            y = int(grip[1] + (hy - grip[1]) * i / 6)
            d.line((x - 3, y, x + 2, y + 1), fill="#dfb27b")
            d.point((x + 2, y + 2), fill="#414146")
        poly(d, [(hx - 18, hy - 13), (hx + 12, hy - 13), (hx + 18, hy - 7),
                 (hx + 18, hy + 10), (hx + 12, hy + 14), (hx - 18, hy + 12),
                 (hx - 22, hy + 7), (hx - 22, hy - 7)], iron, width=2)
        poly(d, [(hx - 18, hy - 11), (hx + 10, hy - 11), (hx + 15, hy - 7),
                 (hx + 10, hy - 4), (hx - 18, hy - 5)], "#6b6c69")
        for x in (hx - 15, hx - 3, hx + 9):
            d.rectangle((x, hy - 7, x + 3, hy + 9), fill=copper, outline=OUTLINE)
            d.line((x, hy - 5, x, hy + 6), fill=light)
            rivet(d, x + 1, hy + 2, light, coal)
        d.line((hx - 20, hy + 10, hx + 12, hy + 12), fill="#b3aaa0")
        # Inset hot forge symbol on the hammer's side, never a solid orange block.
        d.line((hx + 5, hy - 1, hx + 10, hy + 3, hx + 4, hy + 7), fill=ember)
        if hot:
            d.line((hx - 17, hy + 7, hx - 10, hy + 3, hx - 7, hy + 6), fill="#ffad58")
        return im
    # Rear bell-mould furnace: rounded cast bell silhouette with an open kiln mouth.
    poly(d, [(25, 24), (28, 17), (45, 17), (50, 25), (54, 48), (63, 65),
             (59, 75), (16, 75), (13, 65), (21, 47)], "#322c2b", width=2)
    poly(d, [(27, 25), (36, 23), (32, 59), (19, 65), (25, 44)], "#674232", None)
    d.arc((25, 10, 45, 30), 180, 360, fill="#9b714b", width=3)
    for y, left, right in ((29, 23, 49), (54, 18, 56), (68, 14, 61)):
        d.rectangle((left, y, right, y + 4), fill=coal, outline=copper)
        for x in range(left + 4, right, 8):
            rivet(d, x, y + 2, light, coal)
    d.ellipse((25, 37, 48, 60), fill="#0d131b", outline="#b37043", width=2)
    d.ellipse((30, 42, 43, 56), fill="#9b3c21")
    poly(d, [(31, 54), (33, 45), (36, 50), (38, 43), (42, 54)], ember, None)
    for x in (30, 35, 40, 45):
        d.line((x, 39, x - 2, 58), fill=coal, width=2)
    # Stagger opens the back furnace seam, phase two lifts exhaust shutters.
    if hot or action in ("mold_cast", "molten_pool"):
        for i in range(3):
            x, y = 27 + i * 6, 13 - (frame + i) % 3 * 3
            d.line((x, y, x + 2, y - 5), fill=["#b8663c", "#e59956", "#e8c189"][i])
    # Stubby splayed casting shoes, with piston ankles: low, wide centre of mass.
    for side in (-1, 1):
        x = cx + side * 18
        d.rectangle((x - 6, 84 + cy, x + 6, 99), fill=coal, outline="#775440")
        for y in (87, 91, 95):
            d.line((x - 4, y, x + 4, y), fill="#a28b70")
        poly(d, [(x - 10, 98), (x + 8, 98), (x + 12, 105), (x + 10, 110),
                 (x - 14, 110), (x - 15, 105)], iron, width=2)
        d.line((x - 10, 100, x + 6, 100, x + 9, 104), fill=light)
        for j in range(4):
            d.line((x - 11 + j * 5, 106, x - 11 + j * 5, 108), fill="#a06c43")
    # Four overlapping curved furnace armour courses. Each has its own joinery.
    for layer in range(3, -1, -1):
        y = 34 + layer * 14 + cy
        half = [29, 34, 36, 31][layer]
        poly(d, [(cx - half + 4, y), (cx + half - 5, y), (cx + half, y + 9),
                 (cx + half - 4, y + 17), (cx, y + 20), (cx - half + 2, y + 16),
                 (cx - half, y + 7)], coal, width=2)
        poly(d, [(cx - half + 5, y + 2), (cx - 4, y + 1), (cx - 8, y + 14),
                 (cx - half + 4, y + 13)], iron, None)
        d.line((cx - half + 5, y + 2, cx + half - 7, y + 2, cx + half - 2, y + 9), fill=copper, width=2)
        d.line((cx - half + 3, y + 14, cx, y + 18, cx + half - 4, y + 15), fill="#6f4736")
        for x in (cx - half + 8, cx + half - 9):
            rivet(d, x, y + 7, light, "#2b282b")
        # Grated vents expose the layered furnace, without duplicating a face.
        for x in range(cx - 12, cx + 15, 5):
            d.line((x, y + 7, x - 1, y + 12), fill=ember if hot or layer == 2 else "#914a2c", width=2)
        d.line((cx - 22, y + 6, cx - 18, y + 5, cx - 20, y + 10), fill="#73726a")
    # Integrated slit visor sits low in a shallow upper course, never a knight helmet.
    poly(d, [(46, 29 + cy), (54, 24 + cy), (76, 25 + cy), (83, 32 + cy),
             (78, 44 + cy), (49, 43 + cy)], "#3e3432", width=2)
    d.line((52, 29 + cy, 74, 29 + cy, 78, 33 + cy), fill=light)
    d.line((51, 36 + cy, 76, 36 + cy), fill="#070f18", width=3)
    for x in (54, 60, 66, 72):
        d.line((x, 35 + cy, x, 37 + cy), fill=ember)
    # Left arm: tongs with elbow ratchet. Pouring lifts and opens the jaws.
    pour = active and action in ("molten_pool", "mold_cast")
    ex, ey = (33, 61) if not pour else (20, 47)
    poly(d, [(39, 48 + cy), (46, 56 + cy), (ex + 4, ey + 9), (ex - 5, ey + 5)], iron)
    d.ellipse((ex - 5, ey - 4, ex + 5, ey + 6), fill=copper, outline=OUTLINE)
    rivet(d, ex, ey + 1, light, coal)
    d.line((ex - 2, ey + 5, ex - 5, ey + 18, ex - 11, ey + 22), fill="#9f8e74", width=3)
    d.line((ex + 3, ey + 6, ex + 5, ey + 17, ex + 10, ey + 20), fill="#9f8e74", width=3)
    # Right gripping gauntlet remains visible in front of the hammer shaft.
    poly(d, [(86, 50 + cy), (96, 56 + cy), (94, 69 + cy), (83, 78 + cy),
             (76, 71 + cy), (83, 62 + cy)], iron)
    for j in range(3):
        d.line((85 + j * 3, 66 + cy, 81 + j * 3, 72 + cy), fill=light)
    if action == "bell_shard":
        for j in range(3):
            x, y = 103 + j * 6, 30 + j * 9
            poly(d, [(x, y), (x + 4, y + 2), (x + 1, y + 7), (x - 2, y + 4)], light if active else copper)
    if hot:
        d.line((49, 49 + cy, 56, 57 + cy, 52, 66 + cy, 61, 77 + cy, 57, 88 + cy), fill="#ffb15b", width=2)
        # An armour plate actually unseats to reveal a white-hot seam in phase two.
        poly(d, [(78, 66 + cy), (88, 65 + cy), (92, 74 + cy), (82, 78 + cy)], "#8e5339", "#efb570")
    if action == "stagger":
        d.line((48, 28, 56, 34, 53, 42), fill="#ffeda4", width=2)
        d.line((76, 49, 72, 61, 78, 68), fill="#f8d08a", width=2)
    return im


def generate_bell_founder():
    actions = {"idle": 4, "hammer_slam": 6, "mold_cast": 6, "molten_pool": 6,
               "bell_shard": 6, "stagger": 4}
    for hot in (False, True):
        prefix = "hot_" if hot else ""
        for action, count in actions.items():
            for frame in range(count):
                save_frame("bell_founder", prefix + action, frame, bell_founder(action, frame, hot))
                save_frame("bell_founder", prefix + "tool_" + action, frame, bell_founder(action, frame, hot, True))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--boss", choices=["hollow_bell", "bell_founder", "all"], default="all")
    args = parser.parse_args()
    if args.boss in ("hollow_bell", "all"):
        generate_hollow_bell()
    if args.boss in ("bell_founder", "all"):
        generate_bell_founder()
    print("Drew original boss pixel frames from shapes; no source images read.")


if __name__ == "__main__":
    main()
