"""Draw the default player, the Ember Knight, as original 1x pixel animation.

Pillow only; no source images. A small 2D rig (torso / helm / two-bone limbs /
greatsword / tattered cape) is posed per frame and rasterised without
antialiasing. Canvas, frame counts and foot point match the previous default
knight (120x80, body centre x=54, soles on y=79) so SkinCatalog offsets,
combat timing and the opening cinematic stay valid.

    python tools/gen_ember_knight.py            # writes assets/characters/player_ember_knight
    python tools/gen_ember_knight.py --sheet out.png   # also a 4x contact sheet
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "characters" / "player_ember_knight"
W, H = 120, 80
CX, GROUND = 54, 79

PAL = {
    "ink": "#15151e", "deep": "#252732", "shade": "#3b414b", "steel": "#697578",
    "edge": "#a5b3ac", "white": "#d2d6be", "rust": "#7c4134", "copper": "#b7734b",
    "gold": "#dcaa62", "cloth": "#392735", "fold": "#593542", "red": "#923f38",
    "ember": "#e46f39", "hot": "#ffe0a0",
}
P = PAL
THIGH, SHIN, UPPER, FORE, BLADE = 7, 7, 5, 6, 34


def v(ang, length):
    """0 deg points down, positive turns toward the facing (+x)."""
    a = math.radians(ang)
    return (math.sin(a) * length, math.cos(a) * length)


def add(a, b):
    return (a[0] + b[0], a[1] + b[1])


def rot(p, lean):
    a = math.radians(lean)
    return (p[0] * math.cos(a) - p[1] * math.sin(a), p[0] * math.sin(a) + p[1] * math.cos(a))


def ri(p):
    return (int(round(p[0])), int(round(p[1])))


def capsule(d, p0, p1, w, fill, hi=None):
    p0, p1 = ri(p0), ri(p1)
    for width, col in ((w + 2, P["ink"]), (w, fill)):
        d.line([p0, p1], fill=col, width=width)
        r = (width - 1) / 2
        for p in (p0, p1):
            d.ellipse((p[0] - r, p[1] - r, p[0] + r, p[1] + r), fill=col)
    if hi and w >= 3:
        dx, dy = p1[0] - p0[0], p1[1] - p0[1]
        n = math.hypot(dx, dy) or 1.0
        off = (-dy / n, dx / n) if dy * -1 + dx >= 0 else (dy / n, -dx / n)
        off = (round(off[0] * (w // 2 - 0.4)), round(off[1] * (w // 2 - 0.4)))
        d.line([add(p0, off), add(p1, off)], fill=hi, width=1)


def ik(shoulder, target, l1, l2, bend=1):
    dx, dy = target[0] - shoulder[0], target[1] - shoulder[1]
    dist = max(1e-3, min(math.hypot(dx, dy), l1 + l2 - 0.01))
    a = math.atan2(dy, dx)
    c = (l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist)
    b = math.acos(max(-1.0, min(1.0, c)))
    e = a + b * bend
    elbow = (shoulder[0] + math.cos(e) * l1, shoulder[1] + math.sin(e) * l1)
    hand = (shoulder[0] + math.cos(a) * dist, shoulder[1] + math.sin(a) * dist)
    return elbow, hand


def leg_points(root, hip_ang, knee):
    knee_p = add(root, v(hip_ang, THIGH))
    ankle = add(knee_p, v(hip_ang - knee, SHIN))
    return knee_p, ankle


def draw_leg(d, root, hip_ang, knee, front):
    base, hi = (P["steel"], P["edge"]) if front else (P["shade"], P["steel"])
    knee_p, ankle = leg_points(root, hip_ang, knee)
    capsule(d, root, knee_p, 4, base, hi)
    capsule(d, knee_p, ankle, 3, base, hi)
    k = ri(knee_p)
    d.point(k, fill=P["copper"] if front else P["rust"])
    a = ri(ankle)
    d.rectangle((a[0] - 2, a[1] - 1, a[0] + 3, a[1] + 2), fill=P["ink"])
    d.rectangle((a[0] - 1, a[1], a[0] + 2, a[1] + 1), fill=P["deep"] if not front else P["shade"])
    d.point((a[0] + 2, a[1]), fill=P["rust"])


def draw_arm(d, shoulder, elbow, hand, front):
    base, hi = (P["steel"], P["edge"]) if front else (P["shade"], P["steel"])
    capsule(d, shoulder, elbow, 3, base, hi)
    capsule(d, elbow, hand, 3, base, hi)
    h = ri(hand)
    d.rectangle((h[0] - 1, h[1] - 1, h[0] + 1, h[1] + 1), fill=P["ink"])
    d.point(h, fill=P["copper"] if front else P["rust"])


def draw_sword(d, grip, ang, hot=False):
    dvec = v(ang, 1.0)
    perp = (-dvec[1], dvec[0])
    guard = add(grip, (dvec[0] * 2, dvec[1] * 2))
    pommel = add(grip, (-dvec[0] * 4, -dvec[1] * 4))
    capsule(d, pommel, guard, 2, P["rust"])
    d.point(ri(pommel), fill=P["gold"])
    g0 = add(guard, (perp[0] * 3.5, perp[1] * 3.5))
    g1 = add(guard, (-perp[0] * 3.5, -perp[1] * 3.5))
    capsule(d, g0, g1, 2, P["gold"])
    base = add(guard, (dvec[0], dvec[1]))
    tip = add(guard, (dvec[0] * BLADE, dvec[1] * BLADE))
    shoulder = add(guard, (dvec[0] * (BLADE - 7), dvec[1] * (BLADE - 7)))
    poly = [add(base, (perp[0] * 2.6, perp[1] * 2.6)), add(shoulder, (perp[0] * 2.6, perp[1] * 2.6)), tip,
            add(shoulder, (-perp[0] * 2.2, -perp[1] * 2.2)), add(base, (-perp[0] * 2.2, -perp[1] * 2.2))]
    d.polygon([ri(p) for p in poly], fill=P["steel"], outline=P["ink"])
    # Cutting edge (perp side) catches the light; the spine is serrated and rusted.
    e0, e1 = add(base, (perp[0] * 1.6, perp[1] * 1.6)), add(shoulder, (perp[0] * 1.6, perp[1] * 1.6))
    d.line([ri(e0), ri(e1), ri(add(tip, (-dvec[0] * 2, -dvec[1] * 2)))], fill=P["hot"] if hot else P["edge"])
    d.line([ri(add(base, (perp[0] * 0.2, perp[1] * 0.2))), ri(add(shoulder, (perp[0] * 0.2, perp[1] * 0.2)))],
           fill=P["shade"])
    for i in range(3, BLADE - 8, 4):
        s = add(guard, (dvec[0] * i - perp[0] * 2.2, dvec[1] * i - perp[1] * 2.2))
        d.point(ri(s), fill=P["ink"])
        d.point(ri(add(s, (perp[0], perp[1]))), fill=P["rust"])
    for i in (9, 17):
        d.point(ri(add(guard, (dvec[0] * i - perp[0] * 0.6, dvec[1] * i - perp[1] * 0.6))), fill=P["rust"])
    if hot:
        for i in range(6, BLADE - 4, 6):
            d.point(ri(add(guard, (dvec[0] * i + perp[0] * 0.8, dvec[1] * i + perp[1] * 0.8))), fill=P["ember"])
    return tip


def draw_cape(d, neck, back_sh, hip, sway, lift, flutter):
    top = [add(back_sh, (-1, -1)), add(neck, (1, 0))]
    s, l = sway, lift
    tail = [
        add(hip, (1 + s * 0.3, 7 + l * 0.4)),
        add(hip, (-2 + s * 0.6, 12 + l * 0.7 + flutter)),
        add(hip, (-4 + s * 0.8, 9 + l * 0.8)),
        add(hip, (-6 + s, 14 + l - flutter)),
        add(hip, (-8 + s * 1.1, 10 + l)),
        add(hip, (-9 + s * 1.15, 13 + l * 1.05 + flutter)),
        add(hip, (-9 + s * 0.9, 4 + l * 0.6)),
        add(back_sh, (-5 + s * 0.4, 3 + l * 0.2)),
    ]
    pts = [ri(p) for p in top + tail]
    d.polygon(pts, fill=P["fold"], outline=P["ink"])
    d.line([ri(add(back_sh, (-3 + s * 0.2, 2))), ri(add(hip, (-5 + s * 0.8, 8 + l * 0.8)))], fill=P["cloth"])
    d.line([ri(add(neck, (-1, 2))), ri(add(hip, (-1 + s * 0.4, 6 + l * 0.5)))], fill=P["cloth"])
    d.line([ri(add(back_sh, (-4 + s * 0.3, 3))), ri(add(hip, (-8 + s * 0.95, 5 + l * 0.6)))], fill=P["red"])


def draw_torso(d, hip, lean):
    def T(x, y):
        return ri(add(hip, rot((x, y), lean)))
    body = [T(-4, 0), T(4, 0), T(5, -6), T(6, -11), T(4, -13), T(-4, -13), T(-6, -11), T(-5, -6)]
    d.polygon(body, fill=P["shade"], outline=P["ink"])
    chest = [T(0, -2), T(4, -2), T(5, -7), T(5, -11), T(3, -12), T(0, -12)]
    d.polygon(chest, fill=P["steel"])
    d.line([T(1, -11), T(4, -11)], fill=P["edge"])
    d.line([T(4, -10), T(4, -5)], fill=P["edge"])
    d.point(T(2, -8), fill=P["rust"])
    d.point(T(3, -6), fill=P["rust"])
    d.point(T(-2, -9), fill=P["deep"])
    # Ember core behind a cracked breastplate: the knight's burning heart.
    d.point(T(1, -9), fill=P["ember"])
    d.point(T(2, -9), fill=P["hot"])
    d.line([T(-4, -1), T(4, -1)], fill=P["copper"], width=1)
    d.line([T(-4, -2), T(4, -2)], fill=P["rust"], width=1)
    d.point(T(2, -1), fill=P["gold"])
    tab = [T(0, 0), T(3, 0), T(4, 6), T(2, 8), T(0, 6)]
    d.polygon(tab, fill=P["red"], outline=P["ink"])
    d.line([T(1, 1), T(2, 6)], fill=P["fold"])


def draw_head(d, neck, lean, tilt=0):
    c = add(neck, rot((1, -4), lean + tilt))
    x, y = ri(c)
    d.rectangle((x - 4, y - 3, x + 4, y + 4), fill=P["ink"])
    d.rectangle((x - 3, y - 4, x + 3, y + 4), fill=P["ink"])
    d.rectangle((x - 3, y - 3, x + 3, y + 3), fill=P["steel"])
    d.line([(x - 2, y - 3), (x + 2, y - 3)], fill=P["edge"])
    d.line([(x + 3, y - 2), (x + 3, y + 1)], fill=P["edge"])
    d.rectangle((x - 3, y + 2, x - 1, y + 3), fill=P["shade"])
    # Visor slit with embers glowing through it.
    d.line([(x, y), (x + 3, y)], fill=P["ink"])
    d.point((x + 1, y), fill=P["ember"])
    d.point((x + 2, y), fill=P["hot"])
    d.point((x + 2, y + 2), fill=P["ink"])
    d.point((x - 2, y - 1), fill=P["rust"])
    # A short rust-red crest swept back like a dying flame.
    d.line([(x - 1, y - 5), (x - 4, y - 6), (x - 6, y - 4)], fill=P["ink"], width=3)
    d.line([(x - 1, y - 5), (x - 4, y - 6), (x - 6, y - 4)], fill=P["red"], width=1)
    d.point((x - 2, y - 6), fill=P["ember"])


def draw_pauldron(d, shoulder):
    x, y = ri(shoulder)
    d.ellipse((x - 4, y - 3, x + 4, y + 3), fill=P["ink"])
    d.ellipse((x - 3, y - 2, x + 3, y + 2), fill=P["steel"])
    d.line([(x - 2, y - 2), (x + 2, y - 2)], fill=P["edge"])
    d.point((x, y), fill=P["copper"])
    d.point((x - 2, y + 1), fill=P["rust"])
    d.point((x + 2, y + 1), fill=P["deep"])


def draw_arc(d, center, r, a0, a1, strong=True):
    if a0 == a1:
        return
    steps = max(4, int(abs(a1 - a0) / 6))
    pts = [ri(add(center, v(a0 + (a1 - a0) * i / steps, r))) for i in range(steps + 1)]
    inner = [ri(add(center, v(a0 + (a1 - a0) * i / steps, r - 3))) for i in range(steps + 1)]
    if strong:
        d.line(pts, fill=P["white"], width=3)
        d.line(inner, fill=P["edge"], width=1)
        d.line(pts[len(pts) // 2:], fill=P["hot"], width=1)
    else:
        d.line(pts[len(pts) // 2:], fill=P["edge"], width=1)


def sparks(d, p, frame):
    x, y = ri(p)
    for i, (dx, dy) in enumerate(((-4, -3), (3, -5), (6, -2), (-2, -6), (8, -4))):
        k = 1 + frame % 2
        d.point((x + dx * k // 1, y + dy * k // 1), fill=P["hot"] if i % 2 else P["ember"])


def render(pose):
    lean = pose.get("lean", 4)
    fl, bl = pose.get("fl", (8, 10)), pose.get("bl", (-8, 6))
    # Place the hip so the lowest sole rests on the ground row.
    lowest = max(leg_points((0, 0), *fl)[1][1], leg_points((0, 0), *bl)[1][1])
    hip = (CX + pose.get("bx", 0), GROUND - 2 - lowest - pose.get("air", 0) + pose.get("by", 0))
    neck = add(hip, rot((0, -13), lean))
    f_sh, b_sh = add(hip, rot((2, -12), lean)), add(hip, rot((-3, -12), lean))
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    draw_cape(d, neck, b_sh, hip, pose.get("sway", 0), pose.get("lift", 0), pose.get("flutter", 0))
    grip = pose.get("grip")
    sword = pose.get("sword")
    if grip is not None:
        g = add(hip, grip)
        b_el, b_hand = ik(b_sh, g, UPPER, FORE, -1)
    else:
        ba = pose.get("ba", (-8, 25))
        b_el = add(b_sh, v(ba[0], UPPER))
        b_hand = add(b_el, v(ba[0] + ba[1], FORE))
    draw_arm(d, b_sh, b_el, b_hand, False)
    draw_leg(d, add(hip, rot((-1, 0), lean)), *bl, front=False)
    if grip is not None and pose.get("behind"):
        draw_sword(d, g, sword, pose.get("hot", False))
    draw_leg(d, add(hip, rot((1, 0), lean)), *fl, front=True)
    draw_torso(d, hip, lean)
    draw_head(d, neck, lean, pose.get("tilt", 0))
    draw_pauldron(d, add(f_sh, (0, 0)))
    if grip is not None:
        f_el, f_hand = ik(f_sh, g, UPPER, FORE, 1)
    else:
        fa = pose.get("fa", (12, 30))
        f_el = add(f_sh, v(fa[0], UPPER))
        f_hand = add(f_el, v(fa[0] + fa[1], FORE))
    tip = None
    if grip is not None and not pose.get("behind"):
        tip = draw_sword(d, g, sword, pose.get("hot", False))
    draw_arm(d, f_sh, f_el, f_hand, True)
    if pose.get("arc"):
        a0, a1, strong = pose["arc"]
        draw_arc(d, f_sh, BLADE - 4, a0, a1, strong)
    if pose.get("sparks") is not None and tip is not None:
        sparks(d, tip, pose["sparks"])
    spin = pose.get("spin", 0)
    if spin:
        pivot = pose.get("pivot", (CX, GROUND))
        im = im.rotate(spin, resample=Image.NEAREST, center=pivot)
    return im


def wave(i, n, phase=0.0):
    return math.sin(2 * math.pi * (i / n + phase))


def idle():
    out = []
    for i in range(10):
        s = wave(i, 10)
        out.append(dict(lean=3, by=1 if s < -0.3 else 0, sway=-1 + s, flutter=round(s),
                        fa=(14 + 3 * s, 32), ba=(-6 - 2 * s, 24)))
    return out


def run():
    out = []
    for i in range(10):
        s, c = wave(i, 10), wave(i, 10, 0.25)
        fl = (34 * s, 18 + 40 * max(0.0, -s))
        bl = (-34 * s, 18 + 40 * max(0.0, s))
        out.append(dict(lean=12, by=-1 if abs(c) > 0.7 else 0, fl=fl, bl=bl, sway=-6 - 2 * c,
                        lift=-2 - abs(c) * 2, flutter=round(c), fa=(-30 * s, 60), ba=(30 * s, 55)))
    return out


def jump():
    return [
        dict(lean=8, fl=(10, 6), bl=(-14, 4), ba=(-40, 30), fa=(-20, 40), sway=-2, lift=2),
        dict(lean=6, air=4, fl=(50, 80), bl=(-5, 60), ba=(-60, 40), fa=(150, 20), sway=-3, lift=3),
        dict(lean=4, air=5, fl=(40, 70), bl=(0, 50), ba=(-50, 50), fa=(130, 30), sway=-4, lift=1),
    ]


def fall():
    return [dict(lean=2, air=2, fl=(24, 30), bl=(-16, 10), ba=(-120, 30), fa=(110, 30),
                 sway=-2, lift=-5 - i, flutter=(-1, 0, 1)[i]) for i in range(3)]


def jump_fall():
    return [dict(lean=4, air=3, fl=(36, 50), bl=(-6, 30), ba=(-80, 40), fa=(120, 30), sway=-3, lift=-2),
            dict(lean=3, air=2, fl=(28, 34), bl=(-12, 14), ba=(-110, 30), fa=(112, 30), sway=-2, lift=-4)]


def dash():
    return [dict(lean=30, fl=(40, 20), bl=(-45, 10), fa=(-60, 20), ba=(-70, 10), sway=-12, lift=-6, flutter=f)
            for f in (0, 1)]


def roll():
    out = []
    for i in range(12):
        out.append(dict(lean=45, air=6, fl=(80, 120), bl=(60, 110), fa=(80, 90), ba=(60, 90),
                        sway=-2, lift=-6, spin=-30 * i, pivot=(CX, 68)))
    return out


def turn():
    return [dict(lean=2, sway=s, fa=(f, 30), ba=(b, 24)) for s, f, b in ((-1, 6, -2), (1, 0, 0), (0, 10, -4))]


def hurt():
    return [dict(lean=-14, tilt=-10, fl=(20, 20), bl=(-4, 10), fa=(-40, 50), ba=(-60, 40), sway=4, lift=-3)]


def death():
    out = [
        dict(lean=-10, tilt=-8, fl=(16, 16), bl=(-6, 8), fa=(-30, 40), ba=(-50, 30), sway=3, lift=-2),
        dict(lean=-18, tilt=-12, fl=(22, 24), bl=(-4, 12), fa=(-50, 40), ba=(-70, 30), sway=4, lift=-3),
        dict(lean=-6, tilt=-4, fl=(30, 50), bl=(-10, 40), fa=(10, 20), ba=(-10, 20), sway=2),
        dict(lean=14, tilt=10, fl=(60, 100), bl=(-20, 90), fa=(20, 10), ba=(10, 10), sway=0, lift=2),
        dict(lean=24, tilt=14, fl=(70, 120), bl=(-30, 110), fa=(10, 0), ba=(0, 0), sway=1, lift=3),
        dict(lean=30, tilt=16, fl=(72, 125), bl=(-34, 115), fa=(4, 0), ba=(-4, 0), sway=1, lift=3),
    ]
    k = dict(out[-1])
    for ang in (-25, -55, -80, -90):
        f = dict(k)
        f.update(spin=ang, pivot=(CX + 6, GROUND), lift=4)
        out.append(f)
    return out


def attack1():
    st = dict(fl=(24, 16), bl=(-18, 8))
    return [
        dict(st, lean=-4, grip=(-4, -18), sword=200, behind=True, sway=2),
        dict(st, lean=14, grip=(9, -10), sword=95, arc=(200, 95, True), hot=True, sway=-5),
        dict(st, lean=18, grip=(8, -4), sword=50, arc=(110, 50, False), sway=-6),
        dict(st, lean=8, grip=(5, -8), sword=70, sway=-3),
    ]


def attack2():
    st = dict(fl=(26, 20), bl=(-20, 10))
    return [
        dict(st, lean=6, grip=(-3, -6), sword=-60, behind=True, sway=-1),
        dict(st, lean=4, grip=(-2, -8), sword=-80, behind=True, sway=0),
        dict(st, lean=12, grip=(8, -12), sword=110, arc=(-70, 110, True), hot=True, sway=-6),
        dict(st, lean=10, grip=(7, -16), sword=150, arc=(60, 150, False), sway=-6),
        dict(st, lean=8, grip=(5, -14), sword=160, sway=-4),
        dict(st, lean=6, grip=(4, -9), sword=80, sway=-2),
    ]


def attack_combo():
    st = dict(fl=(26, 24), bl=(-22, 12))
    return [
        dict(st, lean=0, grip=(0, -14), sword=160, sway=0),
        dict(st, lean=-6, grip=(-3, -20), sword=200, behind=True, sway=2),
        dict(st, lean=-8, by=1, grip=(-4, -22), sword=215, behind=True, sway=3),
        dict(st, lean=10, grip=(8, -14), sword=120, arc=(215, 120, True), hot=True, sway=-5),
        dict(st, lean=22, by=2, grip=(11, -4), sword=78, arc=(150, 78, True), hot=True, sway=-7),
        dict(st, lean=24, by=3, grip=(11, 0), sword=75, sparks=0, hot=True, sway=-7, lift=-2),
        dict(st, lean=24, by=3, grip=(11, 0), sword=75, sparks=1, sway=-6, lift=-1),
        dict(st, lean=16, by=2, grip=(8, -4), sword=72, sway=-4),
        dict(st, lean=10, by=1, grip=(6, -8), sword=80, sway=-2),
        dict(st, lean=6, grip=(4, -9), sword=75, sway=-1),
    ]


ACTIONS = {
    "idle": idle, "run": run, "jump": jump, "fall": fall, "jump_fall": jump_fall,
    "dash": dash, "roll": roll, "turn": turn, "hurt": hurt, "death": death,
    "attack1": attack1, "attack2": attack2, "attack_combo": attack_combo,
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sheet", default="")
    args = ap.parse_args()
    frames_meta, rows = [], []
    for action, fn in ACTIONS.items():
        folder = OUT / action
        folder.mkdir(parents=True, exist_ok=True)
        row = []
        for i, pose in enumerate(fn()):
            im = render(pose)
            path = folder / f"{action}_{i}.png"
            im.save(path, optimize=True)
            frames_meta.append({"action": action, "frame": i, "size": [W, H],
                                "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
            row.append(im)
        rows.append(row)
    meta = {
        "artist": "Original Rustgrave project drawing authored in the accompanying source",
        "generator": "tools/gen_ember_knight.py",
        "inputs": [],
        "method": "posed 2D rig rasterised as integer pixels; no sampled reference assets; transparent RGBA",
        "palette": PAL,
        "frames": frames_meta,
    }
    (OUT / "authorship.json").write_text(json.dumps(meta, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    if args.sheet:
        cols = max(len(r) for r in rows)
        sheet = Image.new("RGBA", (cols * W, len(rows) * H), (44, 38, 46, 255))
        for y, r in enumerate(rows):
            for x, im in enumerate(r):
                sheet.alpha_composite(im, (x * W, y * H))
        sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST).save(args.sheet)
    print("frames", len(frames_meta))


if __name__ == "__main__":
    main()
