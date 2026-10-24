"""Original, editable integer-pixel art for two Rustgrave bosses.

Every contour, plate, fold and animation pose is drawn here from integer
coordinates. No input images, tracing, resampling, web resources or model APIs.
Run with Pillow: python tools/gen_original_choir_warden.py [--check]
The contact sheets are review evidence, not game assets.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets/characters"
EVIDENCE = ROOT / "screenshots/acceptance/original-bosses/choir-warden"
W_ACTIONS = {"idle": 6, "guard": 4, "charge": 6, "sweep": 6,
             "release": 4, "hurt": 3, "broken": 4, "death": 7}
C_ACTIONS = {"idle": 6, "windup": 6, "cast": 6, "recover": 4,
             "hurt": 3, "broken": 4, "death": 7}
S_ACTIONS = {"idle": 4, "sing": 4}
W_NAME = "original_capstan_warden"
C_NAME = "original_silent_choir"

# Deliberately limited, opaque paint. Transparency is binary and never filtered.
W = dict(ink="#122632", deep="#203d48", dark="#2d555e", teal="#3c7074",
         mid="#548d89", light="#80b2a2", edge="#b2cebb", rust="#614936",
         brass="#8d7450", gold="#b29a69", ivory="#d9d5b1", white="#f2edca",
         glass="#173f50", cyan="#70d3d5", ice="#bceee3", hose="#26323d")
C = dict(ink="#211b36", deep="#34213f", dark="#4b2d57", purple="#67416f",
         mid="#85618c", light="#a98aaa", waxdark="#b6adac", wax="#d9d3c9",
         white="#f0e9d4", pale="#fff3d3", brassdark="#6f563f", brass="#ad8a56",
         gold="#d3b77b", flame="#efbc72", core="#fff0b0", void="#141a2b")


class Pixels:
    def __init__(self, size, palette):
        self.image = Image.new("RGBA", size)
        self.d = ImageDraw.Draw(self.image)
        self.p = palette

    def col(self, c):
        return self.p.get(c, c)

    def box(self, b, c, outline=None, width=1):
        self.d.rectangle(tuple(map(int, b)), self.col(c),
                         self.col(outline) if outline else None, width)

    def poly(self, points, c, outline=None, width=1):
        pts = [(int(x), int(y)) for x, y in points]
        self.d.polygon(pts, fill=self.col(c))
        if outline:
            self.d.line(pts + [pts[0]], self.col(outline), width, joint="curve")

    def line(self, points, c, width=1):
        self.d.line([(int(x), int(y)) for x, y in points], self.col(c), width)

    def oval(self, b, c, outline=None, width=1):
        self.d.ellipse(tuple(map(int, b)), self.col(c),
                       self.col(outline) if outline else None, width)

    def dot(self, x, y, c):
        self.d.point((int(x), int(y)), self.col(c))


def chain(p, points, color="gold", step=5):
    """Alternating open chain links along an integer path."""
    length = 0.0
    next_at = 0.0
    for a, b in zip(points, points[1:]):
        seg = math.dist(a, b)
        while next_at <= length + seg:
            k = (next_at - length) / max(seg, 1)
            x, y = (round(a[j] + (b[j] - a[j]) * k) for j in (0, 1))
            if round(next_at / step) % 2:
                p.oval((x-2, y-3, x+2, y+3), "ink", color)
                p.dot(x-1, y-1, "ivory" if p.p is W else "white")
            else:
                p.oval((x-3, y-2, x+3, y+2), "ink", color)
            next_at += step
        length += seg


def anchor(p, x, y, tilt=0):
    # The anchor is a hand-forged asymmetric tool, not a weapon silhouette crop.
    p.oval((x-4, y-11, x+4, y-3), "deep", "gold")
    p.line([(x, y-5), (x+tilt, y+15)], "ink", 7)
    p.line([(x-1, y-4), (x+tilt-1, y+15)], "brass", 3)
    p.line([(x-7, y+1), (x+7, y+1)], "ink", 5)
    p.line([(x-7, y), (x+7, y)], "light", 2)
    p.poly([(x-14, y+7), (x-11, y+17), (x+tilt, y+23),
            (x+12, y+16), (x+15, y+6), (x+8, y+12),
            (x+8, y+15), (x+tilt, y+18), (x-7, y+14), (x-8, y+10)],
           "dark", "ink", 2)
    p.line([(x-12, y+9), (x-9, y+16), (x+tilt, y+20),
            (x+10, y+15), (x+13, y+9)], "light", 2)
    p.dot(x+tilt, y+21, "edge")


def winch(p, dy, turn, slump=0):
    # Back-mounted horizontal capstan, exposed drum coils and two end bearings.
    y = 35 + dy + slump
    p.poly([(25, y+13), (38, y+32), (47, y+31), (39, y+9)], "dark", "ink", 2)
    p.poly([(81, y+8), (78, y+30), (87, y+33), (96, y+13)], "dark", "ink", 2)
    p.box((19, y-5, 103, y+16), "ink")
    p.box((28, y-8, 93, y+17), "brassdark" if "brassdark" in p.p else "rust")
    p.box((31, y-6, 91, y+14), "dark")
    p.box((32, y-4, 91, y+1), "light")
    p.box((32, y+10, 91, y+14), "deep")
    for x in range(34 + turn % 5, 91, 5):
        p.line([(x, y-3), (x-3, y+9), (x-2, y+13)], "gold", 2)
        p.dot(x+1, y-3, "ivory")
    for x in (23, 97):
        p.oval((x-10, y-12, x+9, y+21), "ink")
        p.oval((x-8, y-10, x+7, y+19), "brass")
        p.oval((x-5, y-7, x+5, y+16), "dark")
        p.oval((x-3, y-4, x+3, y+12), "mid", "ink")
        p.box((x-1, y, x+1, y+7), "ivory")
        for py in (y-7, y+15):
            p.dot(x, py, "white")
    p.line([(15, y+6), (12, y+6), (12, y+15)], "ink", 5)
    p.line([(15, y+5), (12, y+5), (12, y+14)], "gold", 2)
    # Distinct chain bights hang behind the shoulder plates.
    chain(p, [(25, y+16), (22, y+30), (29, y+38), (35, y+26)], "brass", 5)
    chain(p, [(98, y+15), (102, y+28), (94, y+34)], "brass", 5)


def gauntlet(p, shoulder, elbow, hand, raised=False):
    p.line([shoulder, elbow, hand], "ink", 13)
    p.line([shoulder, elbow], "dark", 9)
    p.line([(shoulder[0]-2, shoulder[1]-2), (elbow[0]-2, elbow[1]-2)], "mid", 3)
    p.oval((elbow[0]-6, elbow[1]-5, elbow[0]+6, elbow[1]+5), "teal", "ink")
    p.line([elbow, hand], "mid", 9)
    p.line([(elbow[0]+2, elbow[1]-1), (hand[0]+2, hand[1]-1)], "light", 2)
    x, y = hand
    p.poly([(x-7, y-5), (x+4, y-6), (x+7, y-1), (x+5, y+6),
            (x-5, y+6), (x-8, y+2)], "teal", "ink")
    p.line([(x-4, y-4), (x+3, y-4)], "edge", 2)
    for dx in (-3, 0, 3):
        p.line([(x+dx, y+2), (x+dx, y+5)], "deep")


def warden(action, i):
    p = Pixels((128, 112), W)
    bob = [0, 0, -1, -1, 0, 1][i % 6] if action == "idle" else 0
    crouch = 0
    hx = 0
    turn = i
    left = ((37, 69), (29, 80), (33, 88))
    right = ((84, 68), (91, 78), (99, 83))
    ax, ay = 106, 82
    if action == "guard":
        crouch = 2 + i % 2
        left = ((37, 71), (40, 78), (56, 76))
        right = ((84, 70), (83, 81), (71, 77))
        ax, ay = 101, 82
    elif action == "charge":
        crouch = [1, 2, 3, 3, 2, 2][i]
        hx = -2
        right = ((82, 70), (87-i, 55-i), (88-i*2, 44-i))
        left = ((37, 70), (30, 79), (37, 85))
        ax, ay = 102-i*2, 44-i
        turn = i*2
    elif action == "sweep":
        crouch = [2, 1, 0, 2, 3, 2][i]
        hx = [0, 2, 3, 2, 1, 0][i]
        right = ((84, 69), (94, 71+i), (106, 76+i*2))
        ax, ay = 107, [63, 67, 73, 77, 79, 80][i]
        left = ((38, 70), (34, 78), (43, 83))
        turn = i*4
    elif action == "release":
        crouch = [2, 1, 0, 0][i]
        left = ((37, 70), (27, 77), (24, 85))
        right = ((84, 68), (93, 72), (99, 74))
        ax, ay = 105, 81
        turn = i*3
    elif action == "hurt":
        hx = [-3, -5, -2][i]
        crouch = [1, 4, 2][i]
        right = ((82, 71), (88, 78), (91, 85))
    elif action == "broken":
        crouch = [7, 8, 7, 8][i]
        hx = -3
        left = ((37, 76), (30, 86), (33, 95))
        right = ((84, 76), (91, 86), (92, 94))
        ax, ay = 106, 82
    elif action == "death":
        crouch = [3, 7, 10, 12, 13, 14, 14][i]
        hx = -min(i*2, 7)
        left = ((37, 73+min(i, 7)), (28, 88), (35, 101))
        right = ((84, 73+min(i, 7)), (91, 89), (98, 101))
        ax, ay = 108, 82
    dy = bob + crouch
    winch(p, bob, turn, min(crouch, 18))
    # Reinforced pressure suit legs: segmented knees, overlapping boots, rivets.
    for x, off in ((42, 0), (72, 2)):
        top = min(86+dy, 99)
        p.poly([(x-7, top-5), (x+9, top-4), (x+10, 98),
                (x+7, 104), (x-9, 104), (x-10, 96)], "deep", "ink", 2)
        p.box((x-7, min(top, 96), x+8, 98), "teal")
        p.line([(x-5, min(top+2, 97)), (x+5, min(top+2, 97))], "light", 2)
        p.poly([(x-9, 98), (x+8, 98), (x+12+off, 101),
                (x+12+off, 106), (x-11, 106), (x-11, 102)], "dark", "ink")
        p.line([(x-8, 100), (x+7, 100), (x+10+off, 102)], "light", 2)
        p.line([(x-10, 105), (x+11+off, 105)], "brass", 2)
        p.dot(x+6, 103, "ivory")
    # Left rear arm is drawn behind the chest.
    gauntlet(p, *left)
    # Barrel chest, layered shoulder yoke, copper seamwork and service hatch.
    p.poly([(43, 58+dy), (75, 57+dy), (88, 67+dy), (85, 87+dy),
            (75, 94+min(dy, 8)), (42, 93+min(dy, 8)), (32, 83+dy), (33, 68+dy)], "deep", "ink", 2)
    p.poly([(42, 61+dy), (74, 60+dy), (82, 70+dy), (78, 87+dy),
            (44, 88+dy), (37, 79+dy)], "teal")
    p.poly([(38, 66+dy), (45, 65+dy), (47, 87+dy), (41, 88+dy)], "light")
    p.poly([(76, 64+dy), (80, 69+dy), (76, 88+dy), (71, 89+dy)], "brass")
    p.line([(47, 88+dy), (72, 88+dy)], "gold", 2)
    p.box((52, 85+dy, 66, 90+dy), "ink")
    p.box((55, 86+dy, 63, 89+dy), "brass")
    # Two non-symmetric pauldron shells make the diving silhouette broad.
    for x, yy in ((34, 62+dy), (79, 61+dy)):
        p.poly([(x-8, yy+3), (x-3, yy-2), (x+9, yy-2), (x+15, yy+4),
                (x+13, yy+13), (x-8, yy+12)], "dark", "ink", 2)
        p.line([(x-5, yy+2), (x+8, yy+1), (x+12, yy+5)], "light", 2)
        p.line([(x-5, yy+9), (x+10, yy+9)], "mid", 2)
        p.dot(x-4, yy+5, "ivory")
        p.dot(x+9, yy+6, "gold")
    # Ivory analogue pressure dial has a different needle in each state.
    gy = min(76+dy, 96)
    p.oval((49, gy-9, 68, gy+9), "ink")
    p.oval((51, gy-7, 66, gy+7), "brass")
    p.oval((53, gy-5, 64, gy+5), "ivory")
    for x, yy in ((55, gy-3), (59, gy-4), (63, gy-2)):
        p.dot(x, yy, "deep")
    needle = (62, gy-3) if action not in ("broken", "death") else (55, gy+2)
    p.line([(58, gy+1), needle], "deep")
    p.dot(58, gy+1, "cyan")
    # Ribbed breathing hose returns from chest to the helmet's rear port.
    p.line([(42, 79+dy), (35, 77+dy), (34, 58+dy), (43+hx, 53+dy)], "ink", 5)
    p.line([(42, 78+dy), (36, 75+dy), (36, 58+dy), (43+hx, 54+dy)], "brass", 2)
    for y in range(59+dy, 74+dy, 3):
        p.line([(34, y), (38, y)], "light")
    # Bolted rounded diving helmet, side-on glass grille and tiny forehead gauge.
    hy = min(40+dy, 68)
    x = 59+hx
    p.box((x-14, hy+20, x+17, hy+25), "ink")
    p.line([(x-12, hy+21), (x+15, hy+21)], "gold", 3)
    p.poly([(x-16, hy+5), (x-10, hy-1), (x+10, hy-2), (x+18, hy+4),
            (x+21, hy+16), (x+15, hy+23), (x-12, hy+22), (x-18, hy+15)], "dark", "ink", 2)
    p.poly([(x-14, hy+5), (x-8, hy+1), (x+9, hy), (x+15, hy+4),
            (x+14, hy+7), (x-12, hy+8)], "light")
    p.line([(x-15, hy+11), (x-14, hy+17), (x-9, hy+20)], "mid", 2)
    p.poly([(x, hy+7), (x+15, hy+6), (x+18, hy+11), (x+16, hy+18),
            (x+1, hy+19), (x-2, hy+14)], "brass", "ink")
    p.poly([(x+2, hy+9), (x+13, hy+8), (x+15, hy+11), (x+13, hy+16),
            (x+2, hy+17)], "glass")
    p.line([(x+3, hy+10), (x+12, hy+9)], "ice")
    for dx in (4, 8, 12):
        p.line([(x+dx, hy+11), (x+dx, hy+16)], "cyan")
    p.oval((x-10, hy+9, x-3, hy+16), "ink", "gold")
    p.dot(x-7, hy+12, "cyan")
    for dx, yy in ((-11, 4), (-13, 18), (10, 3), (17, 17)):
        p.box((x+dx, hy+yy, x+dx+1, hy+yy+1), "ivory")
    # Exposed cold pressure vent: teal light comes from baked pixels, not a tint.
    p.box((72, min(78+dy, 95), 79, min(84+dy, 101)), "ink")
    for xx in (73, 76):
        p.line([(xx, min(79+dy, 96)), (xx, min(83+dy, 100))], "cyan")
    chain(p, [(89, 52+min(dy, 12)), (97, 64+min(dy, 12)), right[-1], (ax, ay-7)], "gold")
    anchor(p, ax, ay, -2 if action == "charge" else 1)
    gauntlet(p, *right)
    if action in ("release", "broken", "death"):
        for n in range(3):
            vx = 33+n*9+(i+n) % 3
            vy = 54+dy-n*6-(i*3) % 7
            p.poly([(vx, vy+4), (vx-3, vy), (vx-1, vy-5), (vx+3, vy-7),
                    (vx+1, vy-2), (vx+4, vy+2)], "ice" if n == 0 else "mid")
    if action == "broken":
        p.line([(54+hx, hy+2), (57+hx, hy+8), (54+hx, hy+13)], "ink")
        p.dot(52+i*3, 46-i, "ice")
    if action == "sweep":
        # A few crisp movement fragments, not an opaque attack overlay.
        p.line([(113-i, 63+i*3), (119-i, 65+i*3)], "cyan")
        p.line([(107, 91+i), (113, 92+i)], "light")
    return p.image


def candle(p, x, y, length, flicker, broken=False):
    p.box((x-3, y, x+3, y+length), "ink")
    p.box((x-2, y, x+2, y+length-1), "wax")
    p.line([(x-2, y+1), (x-2, y+length-2)], "white")
    p.line([(x+2, y+3), (x+2, y+length-2)], "waxdark")
    p.box((x-1, y+1, x+1, y+2), "pale")
    p.line([(x+1, y+3), (x+1, y+6+(flicker % 3))], "white")
    if not broken:
        lean = [-1, 0, 1, 0][flicker % 4]
        p.poly([(x, y-1), (x-3, y-4), (x-1+lean, y-9),
                (x+lean, y-12+(flicker % 2)), (x+2, y-7), (x+3, y-4)], "flame")
        p.poly([(x, y-2), (x-1, y-5), (x+lean, y-8), (x+1, y-4)], "core")
    else:
        p.line([(x, y-1), (x-1, y-4), (x+1, y-7)], "mid")


def sleeve(p, shoulder, elbow, hand, baton=False):
    sx, sy = shoulder
    ex, ey = elbow
    hx, hy = hand
    p.poly([(sx-4, sy-4), (sx+5, sy-3), (ex+5, ey-2), (hx+4, hy+3),
            (hx-3, hy+8), (ex-7, ey+8)], "deep", "ink", 2)
    p.line([(sx-3, sy-1), (ex-3, ey+3), (hx-2, hy+5)], "mid", 2)
    p.line([(ex+3, ey), (hx+3, hy+2)], "brass", 2)
    p.poly([(hx-4, hy), (hx+3, hy-1), (hx+5, hy+3),
            (hx+3, hy+5), (hx-4, hy+4)], "wax", "ink")
    p.line([(hx-2, hy), (hx+2, hy)], "white")
    for dx in (-1, 1, 3):
        p.line([(hx+dx, hy+2), (hx+dx+1, hy+5)], "waxdark")
    if baton:
        p.line([(hx+2, hy+2), (hx+9, hy-15)], "ink", 3)
        p.line([(hx+2, hy+1), (hx+9, hy-16)], "gold")
        p.dot(hx+9, hy-16, "pale")


def choir(action, i):
    p = Pixels((96, 144), C)
    bob = [0, -1, -1, 0, 1, 0][i % 6] if action == "idle" else 0
    bow = 0
    cx = 48
    left = ((34, 66), (24, 77), (25, 88))
    right = ((62, 65), (71, 70), (73, 72))
    hem = 113
    if action == "windup":
        right = ((62, 65), (72, 58-i*2), (71, 49-i*3))
        left = ((34, 66), (25, 59-i), (22, 52-i*2))
        bob = -min(i//2, 2)
    elif action == "cast":
        right = ((62, 65), (73, 64+i), (79, 58+i*2))
        left = ((34, 66), (24, 68-i), (14+i, 62-i*2))
        hem = 113+[0, 1, 2, 1, 0, -1][i]
    elif action == "recover":
        right = ((62, 65), (72, 72+i), (76, 73+i*3))
        left = ((34, 66), (23, 74+i), (20+i, 78+i*2))
        bow = [0, 1, 1, 0][i]
    elif action == "hurt":
        cx = [46, 44, 46][i]
        bow = [2, 4, 2][i]
        right = ((60, 68), (71, 74), (76, 84))
        left = ((32, 69), (23, 77), (22, 88))
    elif action == "broken":
        bow = [8, 9, 8, 9][i]
        right = ((62, 70), (70, 81), (66, 92))
        left = ((34, 70), (26, 82), (30, 93))
    elif action == "death":
        bow = [3, 9, 15, 23, 32, 39, 43][i]
        right = ((62, min(65+bow, 103)), (73, 102), (79, 110))
        left = ((34, min(66+bow, 104)), (23, 104), (19, 111))
    dy = bob + bow
    crown_y = 35+min(dy, 56)
    # Open organ pipes behind the hood, nine different lengths and flared lips.
    for j, x in enumerate(range(29, 70, 5)):
        top = 37+abs(j-4)*3+min(dy, 50)
        end = min(88+dy, 114)
        p.box((x-2, top, x+2, end), "ink")
        p.box((x-1, top+2, x+1, end-1), "brassdark")
        p.line([(x-1, top+3), (x-1, end-2)], "gold")
        p.box((x-3, top, x+3, top+2), "brass")
        p.box((x-1, top+3, x+1, top+6), "void")
        p.dot(x, top+7, "white")
    # Bell-shaped liturgical vestments; asymmetrical long stoles are wax-white.
    sy = min(62+dy, 103)
    p.poly([(cx-15, sy), (cx+14, sy-1), (cx+20, min(84+dy, 109)),
            (cx+27, hem-4), (cx+18, hem+2), (cx+9, hem),
            (cx, hem+3), (cx-10, hem+1), (cx-22, hem+3), (cx-27, hem-2),
            (cx-19, min(82+dy, 109))], "deep", "ink", 2)
    p.poly([(cx-13, sy+2), (cx-4, sy+2), (cx-10, hem-3), (cx-22, hem)], "purple")
    p.poly([(cx+1, sy+1), (cx+13, sy+2), (cx+23, hem-4),
            (cx+12, hem), (cx+7, hem-7)], "dark")
    p.line([(cx-14, sy+5), (cx-17, hem-6)], "mid", 2)
    p.line([(cx+14, sy+5), (cx+20, hem-7)], "mid", 2)
    p.poly([(cx-10, sy), (cx-5, sy+1), (cx-8, hem-9), (cx-14, hem-6)], "waxdark")
    p.line([(cx-9, sy+3), (cx-11, hem-10)], "white", 2)
    p.poly([(cx+6, sy+1), (cx+10, sy+1), (cx+15, hem-7), (cx+10, hem-9)], "wax")
    p.line([(cx+8, sy+3), (cx+12, hem-12)], "white")
    p.line([(cx-23, hem-3), (cx-10, hem-1), (cx, hem),
            (cx+12, hem-3), (cx+23, hem-6)], "brass", 2)
    for x in range(cx-19, cx+21, 8):
        p.line([(x, hem-9), (x, hem-6)], "gold")
        p.dot(x-1, hem-8, "gold")
    # The conductor's torso is a rib keyboard, not a ghost face or eye pair.
    ky = min(69+dy, 100)
    p.poly([(cx-9, ky-4), (cx+8, ky-4), (cx+10, min(ky+23, 116)),
            (cx, min(ky+26, 117)), (cx-11, min(ky+22, 116))], "ink", "brass")
    for n in range(7):
        yy = ky+n*3
        if yy >= 116:
            break
        p.line([(cx-7, yy), (cx+7, yy)], "white" if action == "cast" and (n+i) % 3 else "wax", 2)
        if n not in (2, 6):
            p.box((cx+1, yy, cx+6, yy+1), "deep")
        p.dot(cx-8, yy, "gold")
    sleeve(p, *left)
    sleeve(p, *right, baton=action not in ("broken", "death"))
    # High folded collar and an entirely faceless hood (void remains featureless).
    hy = min(45+dy, 95)
    p.poly([(cx-17, hy+17), (cx-10, hy+14), (cx, hy+20), (cx+10, hy+13),
            (cx+17, hy+16), (cx+11, hy+28), (cx, hy+24), (cx-12, hy+27)], "waxdark", "ink")
    p.line([(cx-15, hy+18), (cx-10, hy+22), (cx, hy+22), (cx+12, hy+17)], "white", 2)
    p.poly([(cx, hy-8), (cx+10, hy-2), (cx+14, hy+10), (cx+10, hy+20),
            (cx, hy+25), (cx-12, hy+19), (cx-14, hy+8), (cx-9, hy-3)], "wax", "ink", 2)
    p.line([(cx-9, hy), (cx-11, hy+9), (cx-8, hy+17)], "white", 2)
    p.poly([(cx, hy-3), (cx+7, hy+2), (cx+9, hy+12), (cx+5, hy+18),
            (cx-1, hy+21), (cx-7, hy+15), (cx-8, hy+6), (cx-5, hy+1)], "void")
    p.line([(cx+9, hy+2), (cx+12, hy+12), (cx+9, hy+18)], "waxdark")
    # Branching candelabrum grows from a brass headband, with five candles.
    p.line([(cx-11, hy-4), (cx+11, hy-4)], "ink", 5)
    p.line([(cx-10, hy-5), (cx+10, hy-5)], "gold", 2)
    p.poly([(cx-4, hy-8), (cx, hy-13), (cx+4, hy-8), (cx, hy-4)], "brass", "ink")
    for n, x in enumerate((25, 37, 48, 59, 71)):
        height = (6, 12, 16, 11, 6)[n]
        yy = crown_y - height + (1 if action == "broken" and n % 2 else 0)
        p.line([(cx, hy-7), (x, crown_y+4), (x, yy+8)], "ink", 4)
        p.line([(cx, hy-8), (x, crown_y+3), (x, yy+7)], "brass", 2)
        p.box((x-4, yy+7, x+4, yy+9), "gold")
        candle(p, x, yy, 8, i+n, action == "death" and i > n)
    # Tiny floating wax flecks use different paths; no blur or alpha glow baked in.
    if action in ("windup", "cast", "broken"):
        for n in range(3):
            x = 16+n*30+((i+n) % 3)-1
            y = 45+n*12-(i*3) % 11
            p.box((x, y, x+1, y+2), "white" if action == "cast" else "gold")
    if action == "death":
        for n in range(i+1):
            x = 24+n*7
            y = 105+(n+i) % 8
            p.poly([(x, y), (x+4, y-2), (x+7, y+3), (x+1, y+4)], "waxdark", "ink")
    return p.image


def cantor(variant, action, i):
    p = Pixels((40, 64), C)
    bob = [0, -1, 0, 1][i] if action == "idle" else 0
    open_ = action == "sing"
    x = 20
    y = 30+bob
    # Three independently drawn reliquaries: trefoil, twin pipes, and a censer.
    if variant == 0:
        p.poly([(10, y+1), (30, y+1), (34, y+16), (30, y+26),
                (23, y+29), (19, y+27), (10, y+29), (6, y+20)], "deep", "ink")
        p.poly([(12, y+4), (17, y+2), (15, y+25), (10, y+27)], "purple")
        p.poly([(24, y+2), (29, y+4), (31, y+23), (26, y+26)], "waxdark")
        p.oval((9, y-7, 30, y+15), "wax", "ink")
        p.line([(12, y-2), (12, y+8)], "white", 2)
        p.oval((15, y+1, 25, y+(13 if open_ else 8)), "void", "brass")
        p.line([(13, y+17), (27, y+17)], "brass", 2)
        for cx in (12, 20, 28):
            candle(p, cx, y-10-(4 if cx == 20 else 0), 7, i+cx)
    elif variant == 1:
        p.poly([(10, y), (29, y), (32, y+27), (25, y+30),
                (20, y+25), (13, y+30), (7, y+25)], "dark", "ink")
        p.line([(11, y+10), (10, y+24), (14, y+27)], "mid", 2)
        for cx in (14, 25):
            p.box((cx-5, y-9, cx+5, y+19), "ink")
            p.box((cx-4, y-7, cx+4, y+16), "wax")
            p.box((cx-2, y-4, cx+2, y+(12 if open_ else 7)), "void")
            p.line([(cx-4, y-5), (cx-4, y+12)], "white")
            p.box((cx-5, y-11, cx+5, y-8), "gold")
            candle(p, cx, y-15, 5, i+cx)
        p.line([(11, y+21), (28, y+21)], "gold", 2)
        p.poly([(18, y+16), (20, y+13), (22, y+16), (20, y+19)], "brass")
    else:
        # Hanging chain crown and broad censer jaw distinguish the high cantor.
        chain(p, [(6, y-6), (12, y-13), (20, y-15), (29, y-12), (34, y-4)], "brass", 4)
        p.poly([(7, y), (12, y-7), (27, y-7), (33, y), (30, y+18),
                (25, y+24), (14, y+24), (8, y+17)], "waxdark", "ink")
        p.poly([(11, y), (15, y-4), (25, y-4), (29, y), (27, y+15),
                (23, y+18), (15, y+18)], "wax")
        for cx in (14, 20, 26):
            p.box((cx-1, y+2, cx+1, y+(14 if open_ else 9)), "void")
            p.dot(cx, y+15, "gold")
        p.poly([(11, y+21), (28, y+21), (25, y+27), (20, y+30), (15, y+27)], "brassdark", "ink")
        p.line([(13, y+22), (26, y+22)], "gold", 2)
        candle(p, 20, y-16, 10, i)
    if open_:
        p.line([(6, y+10), (4-i % 2, y+7), (5, y+3)], "gold")
        p.line([(34, y+10), (36+i % 2, y+7), (35, y+3)], "white")
        p.dot(9+i*2, y+26-i, "white")
    return p.image


def checker(size, cell=8):
    image = Image.new("RGBA", size, "#1e2937")
    d = ImageDraw.Draw(image)
    for y in range(0, size[1], cell):
        for x in range(0, size[0], cell):
            if (x//cell+y//cell) % 2:
                d.rectangle((x, y, x+cell-1, y+cell-1), fill="#253343")
    return image


def contact(name, actions, frames, scale=2):
    w, h = next(iter(frames.values()))[0].size
    cols = max(actions.values())
    cw, ch = w*scale+14, h*scale+22
    image = checker((cols*cw+100, len(actions)*ch+36))
    d = ImageDraw.Draw(image)
    d.text((10, 10), f"ORIGINAL PIXEL ART / {name} / native {w}x{h} / nearest {scale}x", fill="#e8e1c9")
    for row, action in enumerate(actions):
        y = 36+row*ch
        d.text((8, y+8), action, fill="#d3b77b")
        for i, frame in enumerate(frames[action]):
            x = 100+i*cw
            image.alpha_composite(frame.resize((w*scale, h*scale), Image.Resampling.NEAREST), (x, y))
            d.text((x+4, y+h*scale+2), str(i), fill="#e8e1c9")
    image.save(EVIDENCE / f"{name}-contact.png")


def overview(all_frames):
    image = checker((1536, 1100), 16)
    d = ImageDraw.Draw(image)
    d.text((24, 16), "CAPSTAN WARDEN | DIVING ARMOR / HORIZONTAL WINCH / CHAIN ANCHOR", fill="#e8e1c9")
    for n, (action, frame) in enumerate((("idle", 1), ("charge", 4), ("sweep", 2), ("broken", 1))):
        src = all_frames[W_NAME][action][frame]
        image.alpha_composite(src.resize((384, 336), Image.Resampling.NEAREST), (n*384, 36))
        d.text((n*384+24, 378), action, fill="#b2cebb")
    d.text((24, 418), "SILENT CHOIR | FACELESS ORGAN CONDUCTOR / CANDLE CROWN / RIB KEYBOARD", fill="#e8e1c9")
    for n, (action, frame) in enumerate((("idle", 1), ("windup", 4), ("cast", 2), ("broken", 1))):
        src = all_frames[C_NAME][action][frame]
        image.alpha_composite(src.resize((288, 432), Image.Resampling.NEAREST), (n*384+48, 440))
        d.text((n*384+24, 880), action, fill="#d3b77b")
    for n in range(3):
        src = all_frames[f"{C_NAME}/cantor_{n}"]["sing"][1]
        image.alpha_composite(src.resize((80, 128), Image.Resampling.NEAREST), (492+n*160, 924))
        d.text((488+n*160, 1060), f"cantor {n+1}", fill="#d3b77b")
    image.save(EVIDENCE / "design-overview.png")


def generate(check=False):
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    specs = [(W_NAME, W_ACTIONS, warden), (C_NAME, C_ACTIONS, choir)]
    for n in range(3):
        specs.append((f"{C_NAME}/cantor_{n}", S_ACTIONS,
                      lambda action, i, n=n: cantor(n, action, i)))
    manifest = {"provenance": "Original integer-pixel drawing from this source; no input images.",
                "generator": "tools/gen_original_choir_warden.py", "assets": []}
    all_frames = {}
    for name, actions, draw in specs:
        frames = {}
        for action, count in actions.items():
            frames[action] = []
            hashes = []
            for i in range(count):
                image = draw(action, i)
                bbox = image.getbbox()
                assert bbox and bbox[0] > 0 and bbox[1] > 0, (name, action, i, bbox)
                assert bbox[2] < image.width and bbox[3] < image.height, (name, action, i, bbox)
                assert set(image.getchannel("A").tobytes()) <= {0, 255}
                rel = Path(name) / action / f"{action}_{i}.png"
                target = ASSETS / rel
                if check:
                    assert target.exists(), target
                    old = Image.open(target).convert("RGBA")
                    assert old.size == image.size and old.tobytes() == image.tobytes(), target
                else:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    image.save(target, optimize=True)
                digest = hashlib.sha256(image.tobytes()).hexdigest()
                hashes.append(digest)
                manifest["assets"].append({"path": "assets/characters/"+rel.as_posix(),
                                           "size": list(image.size), "bbox": list(bbox),
                                           "pixel_sha256": digest})
                frames[action].append(image)
            assert len(set(hashes)) >= min(3, count), (name, action, "insufficient pose variation")
        all_frames[name] = frames
        contact(name.replace("/", "-"), actions, frames, 3 if "/" in name else 2)
        if not check:
            (ASSETS / name / "authorship.json").write_text(json.dumps({
                "generator": "tools/gen_original_choir_warden.py", "external_inputs": [],
                "method": "project-original integer pixel contours and joint poses",
                "actions": actions, "palette": W if name == W_NAME else C,
                "frames": [entry for entry in manifest["assets"]
                           if entry["path"].startswith("assets/characters/"+name+"/")]
            }, indent=2)+"\n", encoding="utf-8")
    overview(all_frames)
    (EVIDENCE / "asset-manifest.json").write_text(json.dumps(manifest, indent=2)+"\n", encoding="utf-8")
    print(json.dumps({"mode": "check" if check else "generate", "frames": len(manifest["assets"]),
                      "contact_sheets": 5, "overview": str(EVIDENCE / "design-overview.png")}, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify exact reproducibility without writing game assets")
    generate(parser.parse_args().check)
