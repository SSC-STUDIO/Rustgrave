"""Scenery layers of the live title scene: the far hall, mid-distance pylons, the
roof with its torn opening, the two foreground machinery masses and the bridge.

Composition (world px, the scene is 640x360 and the knight stands at x~326, y=266):

    far hall -> mid pylons -> [gears] -> bridge + knight -> chains -> roof -> masses

See gen_title_assets.py for the entry point and title_px.py for the toolkit.
"""

from __future__ import annotations

import math

import numpy as np

from title_px import (BAYER4, BRICK, EMBERGLOW, INK, IRON, MIST, NAVY, RUST, RUST_HOT, STEEL, Painter,
                      bayer_field, blur3, mask_ellipse, mask_line, mask_poly, mask_rect, pipe_fields,
                      ramp_dither, ramp_pick)

CYL = [1, 1, 2, 2, 3, 3, 4, 4, 3, 2]          # dark -> lit across a cylinder (lit side on the right)
CYL_SOFT = [1, 2, 2, 2, 3, 3, 3, 4, 3, 2]
# the hall's masses are darker than the haze they stand in: tone offset applied to every part
DIM = -0.35


# ---------------------------------------------------------------- helpers ----


def vcyl(p: Painter, x0, y0, x1, y1, ramp, *, lit="right", hoops=(), rivets=True, noise=0.8, prof=CYL, bias=0):
    """Vertical cylinder/tank. Hoops are y positions of 4px bands."""
    m = mask_rect(p.w, p.h, x0, y0, x1, y1)
    xs = np.arange(p.w, dtype=np.float32)[None, :].repeat(p.h, 0)
    v = (xs + 0.5 - (x0 + x1) / 2.0) / max((x1 - x0) / 2.0, 1.0)
    if lit == "left":
        v = -v
    p.profile(m, v, prof, ramp, noise=noise, bias=bias)
    for hy in hoops:
        band = mask_rect(p.w, p.h, x0, hy, x1, hy + 4)
        p.profile(band, v, prof, ramp, bias=bias - 1, noise=0.0)
        p.flat(mask_rect(p.w, p.h, x0 + 1, hy - 1, x1 - 1, hy), ramp[min(3, len(ramp) - 1)])
        if rivets:
            for rx in range(int(x0) + 3, int(x1) - 2, 6):
                p.px[int(hy) + 1, rx, :3] = ramp[-1]


def hcyl(p: Painter, x0, y0, x1, y1, ramp, *, lit="top", hoops=(), noise=0.8, prof=CYL, bias=0):
    m = mask_rect(p.w, p.h, x0, y0, x1, y1)
    ys = np.arange(p.h, dtype=np.float32)[:, None].repeat(p.w, 1)
    v = (ys + 0.5 - (y0 + y1) / 2.0) / max((y1 - y0) / 2.0, 1.0)
    if lit == "top":
        v = -v
    p.profile(m, v, prof, ramp, noise=noise, bias=bias)
    for hx in hoops:
        band = mask_rect(p.w, p.h, hx, y0, hx + 4, y1)
        p.profile(band, v, prof, ramp, bias=bias - 1, noise=0.0)
        p.flat(mask_rect(p.w, p.h, hx - 1, y0 + 1, hx, y1 - 1), ramp[min(3, len(ramp) - 1)])


def pipe(p: Painter, p0, p1, radius, ramp, *, light=(0.55, -0.83), flange=0, flange_len=4,
         flange_extra=2, noise=0.6, prof=CYL, bias=0):
    mask, across, along = pipe_fields(p.w, p.h, p0, p1, radius)
    ux, uy = p1[0] - p0[0], p1[1] - p0[1]
    ln = math.hypot(ux, uy)
    ux, uy = ux / ln, uy / ln
    ax, ay = -uy, ux
    s = 1.0 if (ax * light[0] + ay * light[1]) > 0 else -1.0
    v = np.clip(s * across / radius, -1, 1)
    p.profile(mask, v, prof, ramp, noise=noise, bias=bias)
    if flange:
        fmask, facross, falong = pipe_fields(p.w, p.h, p0, p1, radius + flange_extra)
        ring = fmask & ((falong % flange) < flange_len) & (falong > flange * 0.5) & (falong < ln - flange * 0.4)
        fv = np.clip(s * facross / (radius + flange_extra), -1, 1)
        p.profile(ring, fv, prof, ramp, bias=bias - 1, noise=0.0)
        edge = ring & ((falong % flange) < 1.0)
        p.flat(edge, ramp[min(4, len(ramp) - 1)])
    return mask


def rivet_row(p: Painter, y, x0, x1, step, color):
    for x in range(int(x0), int(x1), int(step)):
        if 0 <= y < p.h and 0 <= x < p.w:
            p.px[int(y), int(x), :3] = color
            p.px[int(y), int(x), 3] = 255


def lattice(p: Painter, x0, y0, x1, y1, cell, color, *, width=1, posts=True):
    """X-braced lattice between two chords (flat colour, 1px lines)."""
    n = max(1, int(round((x1 - x0) / cell)))
    step = (x1 - x0) / n
    for i in range(n):
        xa, xb = x0 + i * step, x0 + (i + 1) * step
        p.line((xa, y0), (xb, y1), color, width)
        p.line((xa, y1), (xb, y0), color, width)
    if posts:
        for i in range(n + 1):
            xp = x0 + i * step
            p.line((xp, y0), (xp, y1), color, width)


def gauge(p: Painter, cx, cy, r, ramp=STEEL):
    p.part(mask_ellipse(p.w, p.h, cx, cy, r, r), ramp, bevel=1, base=2.0, strength=1.0)
    inner = mask_ellipse(p.w, p.h, cx, cy, max(r - 2, 1), max(r - 2, 1))
    p.flat(inner, (0x0E, 0x0C, 0x16))
    p.line((cx, cy), (cx + r * 0.5, cy - r * 0.55), (0xE4, 0xDC, 0xCC))
    p.flat(mask_ellipse(p.w, p.h, cx, cy, 1, 1), (0xCD, 0x5C, 0x5C))


def ground_fog(p: Painter, y0, y1, color, strength=0.7):
    """Dithered fog toward `color` that thickens downwards, only on opaque pixels."""
    ys = np.arange(p.h, dtype=np.float32)[:, None].repeat(p.w, 1)
    amount = np.clip((ys - y0) / max(y1 - y0, 1.0), 0, 1) * strength
    sel = (amount > bayer_field(p.w, p.h, 8)) & p.opaque()
    p.px[sel, :3] = color


def jagged_poly(rng, pts, jitter=2.0, subdiv=3):
    """Subdivide a polygon's edges and jitter the new vertices (broken, rusted edges)."""
    out = []
    n = len(pts)
    for i in range(n):
        a, b = pts[i], pts[(i + 1) % n]
        out.append(a)
        for k in range(1, subdiv):
            t = k / subdiv
            out.append((a[0] + (b[0] - a[0]) * t + rng.uniform(-jitter, jitter),
                        a[1] + (b[1] - a[1]) * t + rng.uniform(-jitter, jitter)))
    return out


def rust_streaks(p: Painter, region, *, count=14, length=(8, 34), seed=1, tones=(RUST[1], RUST[2], RUST[3])):
    """Vertical rust runs hanging off seams: dithered, fading toward their tail."""
    rng = np.random.default_rng(seed)
    ys, xs = np.nonzero(region)
    if len(xs) == 0:
        return
    for _ in range(count):
        i = int(rng.integers(0, len(xs)))
        x, y0 = int(xs[i]), int(ys[i])
        ln = int(rng.integers(length[0], length[1]))
        tone = tones[int(rng.integers(0, len(tones)))]
        for k in range(ln):
            y = y0 + k
            if y >= p.h or not region[y, x]:
                break
            if rng.random() < 1.0 - 0.8 * (k / ln):
                p.px[y, x, :3] = tone
                if rng.random() < 0.35 and x + 1 < p.w and region[y, x + 1]:
                    p.px[y, x + 1, :3] = tones[0]


def weather(p: Painter, region, *, dark=1.25, light=1.5, amount=1.0):
    """Stains and scuffs: clustered darker / lighter patches on a painted region."""
    f = p.noise_field()
    dk = region & (f < -dark / amount)
    lt = region & (f > light / amount)
    rgb = p.px[:, :, :3].astype(np.float32)
    rgb[dk] *= 0.68
    rgb[lt] = np.minimum(rgb[lt] * 1.22 + 6, 255)
    p.px[:, :, :3] = rgb.astype(np.uint8)


def ladder(p: Painter, x, y0, y1, width=9, ramp=IRON):
    p.flat(mask_rect(p.w, p.h, x, y0, x + 2, y1), ramp[3])
    p.flat(mask_rect(p.w, p.h, x + width - 2, y0, x + width, y1), ramp[2])
    for y in range(int(y0) + 3, int(y1), 6):
        p.flat(mask_rect(p.w, p.h, x + 2, y, x + width - 2, y + 1), ramp[3])


def hazard(p: Painter, x0, y0, x1, y1, tone=RUST[3], dark=INK):
    m = mask_rect(p.w, p.h, x0, y0, x1, y1)
    ys, xs = np.mgrid[0:p.h, 0:p.w]
    stripe = ((xs + ys) // 4) % 2 == 0
    p.flat(m & stripe, tone)
    p.flat(m & ~stripe, dark)
    p.flat(mask_rect(p.w, p.h, x0, y0, x1, y0 + 1), dark)
    p.flat(mask_rect(p.w, p.h, x0, y1 - 1, x1, y1), dark)


def lattice_pylon(p: Painter, x0, x1, y0, y1, ramp=STEEL, light=(0.62, -0.78)):
    """A riveted steel lattice tower: two chords, X braces every `cell` px, cross plates."""
    w = x1 - x0
    for a, b in ((x0, x0 + 5), (x1 - 5, x1)):
        p.part(mask_rect(p.w, p.h, a, y0, b, y1), ramp, light=light, bevel=1, base=1.8, strength=1.0, noise=0.6)
    cell = int(max(w - 8, 20))
    for y in range(int(y0), int(y1) - cell, cell):
        p.line((x0 + 5, y), (x1 - 5, y + cell), ramp[2], 2)
        p.line((x1 - 5, y), (x0 + 5, y + cell), ramp[2], 2)
        p.flat(mask_rect(p.w, p.h, x0 + 5, y, x1 - 5, y + 3), ramp[3])
        rivet_row(p, y + 1, x0 + 7, x1 - 6, 6, ramp[-1])


def _tone(ramp, k):
    return ramp[max(0, min(len(ramp) - 1, k))]


# ---------------------------------------------------------------- hall far ----


def build_hall_far() -> None:
    W, H = 704, 368
    p = Painter(W, H, seed=21)
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    # cool haze: brightest left of centre (where the key light falls), darker at the edges
    centre = np.exp(-(((xs - 300.0) / 250.0) ** 2))
    vert = np.interp(ys, [0, 70, 150, 215, 290, 368], [0.5, 1.2, 2.5, 3.2, 2.0, 0.9])
    field = vert * (0.42 + 0.78 * centre)
    # the roof opening throws a pale pool of sky into the haze (world x ~215 -> frame 250)
    sky = np.exp(-(((xs - 254.0) / 96.0) ** 2 + ((ys - 6.0) / 84.0) ** 2))
    field = field + sky * 4.6
    rgb = ramp_dither(np.clip(field, 0, len(MIST) - 1.01), MIST)
    p.px[:, :, :3] = rgb
    p.px[:, :, 3] = 255

    # furnace haze near the bottom: only the dark end of the warm ramp (never a lit wall)
    glow = np.exp(-(((xs - 335.0) / 220.0) ** 2)) * np.clip((ys - 230.0) / 138.0, 0, 1) ** 1.4
    lvl = glow * 3.0
    warm = ramp_dither(np.clip(lvl, 0, len(EMBERGLOW) - 1.01), EMBERGLOW)
    sel = (lvl > 0.45) & (bayer_field(W, H, 8) < np.clip(lvl * 0.42, 0, 0.8))
    p.px[sel, :3] = warm[sel]
    # (the molten river is its own emissive sprite, pit_river.png, so cold / snuffed
    # variants can let it go dark)

    def silhouette(mask, depth):
        """Paint a mask as haze-coloured silhouette: darker toward the front."""
        base = p.px[:, :, :3].astype(np.float32)
        k = 0.30 + 0.12 * depth
        dark = np.array(NAVY[1], np.float32) * (1 - k) + base * k
        p.px[mask, :3] = np.clip(dark[mask], 0, 255).astype(np.uint8)

    def tower(cx, top, w, depth, bottom=H):
        x0, x1 = cx - w / 2, cx + w / 2
        body = mask_rect(W, H, x0, top, x1, bottom)
        step = max(14, int(w * 0.9))
        hole = np.zeros((H, W), bool)
        for y in range(int(top) + 10, bottom, step * 2):
            hole |= mask_rect(W, H, x0 + 3, y, x1 - 3, y + step - 4)
        body &= ~hole
        cross = np.zeros((H, W), bool)
        for y in range(int(top) + 10, bottom, step * 2):
            cross |= mask_line(W, H, (x0 + 3, y), (x1 - 3, y + step - 4), 1)
            cross |= mask_line(W, H, (x0 + 3, y + step - 4), (x1 - 3, y), 1)
        body |= cross & mask_rect(W, H, x0, top, x1, bottom)
        silhouette(body, depth)
        rim = mask_rect(W, H, x1 - 1, top, x1, bottom) & body
        p.px[rim, :3] = MIST[4]
        silhouette(mask_rect(W, H, x0 - 2, top - 3, x1 + 2, top), depth)

    def stack(cx, top, w, depth):
        silhouette(mask_rect(W, H, cx - w / 2, top, cx + w / 2, H), depth)
        silhouette(mask_rect(W, H, cx - w / 2 - 2, top, cx + w / 2 + 2, top + 4), depth)
        for y in range(int(top) + 20, H, 36):
            silhouette(mask_rect(W, H, cx - w / 2 - 1, y, cx + w / 2 + 1, y + 3), depth + 0.5)

    for cx, top, w, d in [(40, 90, 34, 0.4), (112, 54, 26, 0.5), (186, 126, 30, 0.2), (338, 38, 40, 0.6),
                          (414, 112, 28, 0.2), (478, 66, 32, 0.5), (570, 100, 38, 0.3), (660, 48, 34, 0.6)]:
        tower(cx, top, w, d, bottom=H if cx % 2 == 0 else 330)
    stack(150, 18, 12, 0.7)
    stack(520, 8, 14, 0.8)
    # a crane arm across the hall and its hook cables
    arm = mask_rect(W, H, 230, 74, 520, 80) | mask_poly(W, H, [(520, 74), (560, 94), (556, 98), (520, 80)])
    silhouette(arm, 1.0)
    lat = np.zeros((H, W), bool)
    for x in range(232, 516, 18):
        lat |= mask_line(W, H, (x, 80), (x + 18, 100), 1)
        lat |= mask_line(W, H, (x + 18, 80), (x, 100), 1)
    lat |= mask_rect(W, H, 230, 99, 520, 101)
    silhouette(lat, 0.9)
    for cx in (300, 440):
        silhouette(mask_rect(W, H, cx, 101, cx + 1, 150 + (cx % 17)), 0.8)
    # distant catwalk with posts
    walk_y = 252
    silhouette(mask_rect(W, H, 70, walk_y, 650, walk_y + 3), 0.6)
    for x in range(78, 650, 26):
        silhouette(mask_rect(W, H, x, walk_y - 9, x + 1, walk_y), 0.6)
    silhouette(mask_rect(W, H, 70, walk_y - 9, 650, walk_y - 8), 0.6)
    # vats and smelters standing in the pit: low, dark, with the river glowing behind them
    for cx, w, top in [(180, 60, 318), (250, 38, 326), (420, 70, 316), (500, 44, 324)]:
        silhouette(mask_rect(W, H, cx - w / 2, top, cx + w / 2, 337), 1.1)
        silhouette(mask_ellipse(W, H, cx, top, w / 2, 5), 1.1)
    # lit windows: far, tiny, sparse
    rng = np.random.default_rng(5)
    for _ in range(46):
        x = int(rng.integers(6, W - 6))
        y = int(rng.integers(100, 300))
        if p.px[y, x, 0] < 60:  # only on dark silhouettes
            c = (0xFF, 0xC1, 0x4A) if rng.random() < 0.6 else (0xFF, 0x8C, 0x00)
            p.px[y, x, :3] = c
            if rng.random() < 0.4:
                p.px[y + 1, x, :3] = c
    p.save("hall_far.png")


def build_pit_river() -> None:
    """The molten river along the bottom of the pit: a rippled, dithered band that
    fades out sideways. Emissive in engine (modulated by how hot the furnace burns)."""
    W, H = 704, 40
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    band = np.clip((ys - 4.0) / 30.0, 0, 1)
    ripple = 0.55 * np.sin(xs * 0.11 + ys * 0.9) + 0.35 * np.sin(xs * 0.043 - ys * 0.4)
    side = np.exp(-(((xs - 367.0) / 190.0) ** 4))
    river = (2.8 + 3.0 * band + ripple) * side
    mask = river > 2.3
    rgb = ramp_dither(np.clip(river, 0, len(EMBERGLOW) - 1.01), EMBERGLOW)
    px = np.zeros((H, W, 4), np.uint8)
    px[mask, :3] = rgb[mask]
    px[mask, 3] = 255
    from title_px import save_image
    from PIL import Image
    save_image(Image.fromarray(px, "RGBA"), "pit_river.png")


# ---------------------------------------------------------------- hall mid ----


def build_hall_mid() -> None:
    W, H = 704, 368
    p = Painter(W, H, seed=33)
    p.px[:] = 0
    # two big pylons flank the centre; the knight's column stays clear. The left one is
    # the shaft the big gear turns on (its hub sits at frame x=112).
    for cx, lit in [(112, "right"), (596, "left")]:
        vcyl(p, cx - 15, 0, cx + 15, H, STEEL, lit=lit, hoops=(60, 150, 240, 330), noise=0.9, prof=CYL_SOFT, bias=-1)
        for y in range(18, H - 60, 70):
            p.line((cx - 15 if lit == "right" else cx + 15, y),
                   (cx - 70 if lit == "right" else cx + 70, y + 40), STEEL[2], 2)
    # lower, farther bridge: the furnace lights its underside
    by = 300
    deck = mask_rect(W, H, 70, by, 640, by + 4)
    p.part(deck, STEEL, bevel=1, base=1.9, strength=1.2)
    chord = mask_rect(W, H, 70, by + 20, 640, by + 24)
    p.part(chord, STEEL, bevel=1, base=1.5, strength=1.0)
    lattice(p, 70, by + 4, 640, by + 20, 22, STEEL[1])
    for x in range(78, 640, 22):
        p.flat(mask_rect(W, H, x, by - 8, x + 2, by), STEEL[1])
    p.flat(mask_rect(W, H, 70, by - 9, 640, by - 7), STEEL[2])
    # its piers drop into the pit: braced legs, the pit glow shows between them
    for x in (150, 330, 510):
        p.part(mask_rect(W, H, x - 5, by + 24, x + 5, 360), STEEL, bevel=1, base=1.3, strength=1.0, noise=0.9)
        p.line((x - 5, by + 40), (x - 40, 360), STEEL[1], 2)
        p.line((x + 5, by + 40), (x + 40, 360), STEEL[1], 2)
        p.flat(mask_rect(W, H, x - 7, by + 24, x + 7, by + 28), STEEL[3])
    p.flat(mask_rect(W, H, 70, by + 23, 640, by + 24), EMBERGLOW[3])
    for x in (150, 330, 510):
        p.flat(mask_rect(W, H, x, by - 12, x + 2, by - 9), (0xFF, 0xC1, 0x4A))
    # hanging pipes from the roof, fogged
    for x, ln, r in [(66, 130, 5), (214, 104, 4), (402, 88, 4), (470, 142, 6), (652, 118, 5)]:
        pipe(p, (x, 0), (x, ln), r, STEEL, flange=26, noise=0.8, bias=-1)
        p.flat(mask_rect(W, H, x - r - 1, ln, x + r + 2, ln + 3), STEEL[1])
    # catenary cables across the hall
    for (xa, xb, sag, y0) in [(0, 330, 34, 8), (180, 560, 44, 4), (380, 704, 30, 12), (60, 250, 26, 30)]:
        prev = None
        for x in range(xa, xb + 1, 2):
            t = (x - xa) / (xb - xa)
            pt = (x, y0 + sag * 4 * t * (1 - t))
            if prev is not None:
                p.line(prev, pt, (0x16, 0x14, 0x1E), 1)
            prev = pt
    # soften the whole layer into the haze: dithered fog toward the mist colour
    xs = np.arange(W, dtype=np.float32)[None, :].repeat(H, 0)
    fog = 0.26 + 0.26 * np.exp(-(((xs - 330.0) / 160.0) ** 2))
    sel = (fog > bayer_field(W, H, 8)) & p.opaque()
    p.px[sel, :3] = MIST[3]
    weather(p, p.opaque(), amount=0.8)
    p.save("hall_mid.png")


# -------------------------------------------------------------------- roof ----


def build_roof() -> None:
    W, H = 704, 132
    p = Painter(W, H, seed=45)
    rng = np.random.default_rng(45)
    OPEN0, OPEN1 = 182, 322       # torn opening (frame coords; world = frame - 32)
    plate = mask_rect(W, H, 0, 0, W, 20)
    cut = mask_poly(W, H, [(OPEN0 - 6, 0), (OPEN1 + 14, 0), (OPEN1 + 4, 8), (OPEN1 + 20, 14), (OPEN1 + 6, 22),
                           (OPEN0 - 14, 22), (OPEN0 - 2, 12)])
    plate &= ~cut
    p.part(plate, IRON, bevel=2, base=1.3, strength=1.2, noise=0.8, light=(0.2, 0.98))
    rivet_row(p, 4, 6, W, 12, IRON[3])
    rivet_row(p, 16, 3, W, 12, IRON[3])
    top_chord = mask_rect(W, H, 0, 20, W, 26)
    bot_chord = mask_rect(W, H, 0, 58, W, 64)
    gap = mask_poly(W, H, [(OPEN0 + 2, 18), (OPEN1 + 6, 18), (OPEN1 - 6, 70), (OPEN0 + 18, 70)])
    top_chord &= ~gap
    bot_chord &= ~gap
    p.part(top_chord, STEEL, bevel=1, base=1.6, strength=1.0, light=(0.2, 0.98), noise=0.6)
    p.part(bot_chord, STEEL, bevel=1, base=1.6, strength=1.0, light=(0.2, 0.98), noise=0.6)
    lat = np.zeros((H, W), bool)
    cell = 44
    for x0 in range(0, W, cell):
        if OPEN0 - 20 < x0 < OPEN1 + 10:
            continue
        lat |= mask_line(W, H, (x0, 26), (x0 + cell, 58), 2)
        lat |= mask_line(W, H, (x0 + cell, 26), (x0, 58), 2)
        lat |= mask_rect(W, H, x0, 26, x0 + 3, 58)
    p.part(lat, STEEL, bevel=1, base=1.1, strength=0.8, outline=None, noise=0.6)
    for pts in ([(OPEN0 - 12, 20), (OPEN0 + 22, 20), (OPEN0 + 34, 48), (OPEN0 + 8, 44)],
                [(OPEN1 - 20, 18), (OPEN1 + 12, 20), (OPEN1 + 4, 52), (OPEN1 - 14, 40)]):
        p.part(mask_poly(W, H, jagged_poly(rng, pts, 1.6, 3)), STEEL, bevel=1, base=1.5, strength=1.0)
    for x, y, ln in [(OPEN0 + 30, 40, 24), (OPEN0 + 56, 20, 18), (OPEN1 - 30, 18, 26), (OPEN1 - 8, 46, 20)]:
        p.line((x, y), (x + int(rng.integers(-3, 4)), y + ln), STEEL[2], 1)
    for x, ln, r in [(34, 62, 6), (96, 38, 4), (336, 54, 5), (388, 82, 7), (442, 34, 4), (512, 96, 6),
                     (592, 48, 5), (648, 74, 6)]:
        pipe(p, (x, 60), (x, 60 + ln), r, STEEL, flange=22, noise=0.7, light=(0.3, -0.9), bias=-1)
        p.flat(mask_rect(W, H, x - r - 1, 60 + ln, x + r + 2, 63 + ln), STEEL[1])
    for x in (74, 120, 278, 360, 466, 560, 610):
        ln = 20 + (x * 7) % 46
        p.line((x, 62), (x + 1, 62 + ln), (0x1C, 0x16, 0x1E), 1)
        p.flat(mask_rect(W, H, x - 1, 62 + ln, x + 3, 65 + ln), RUST[2])
    solid = p.opaque()
    below = np.zeros((H, W), bool)
    below[:-1, :] = solid[:-1, :] & ~solid[1:, :]
    p.px[below & (bayer_field(W, H, 4) < 0.6), :3] = RUST[3]
    weather(p, solid, amount=0.9)
    p.save("roof.png")


# ------------------------------------------------------------------ bridge ----


def build_bridge() -> None:
    W, H = 352, 76
    p = Painter(W, H, seed=57)
    DECK = 26     # deck top surface (the knight's feet): bridge origin is (0, 26)
    p.flat(mask_rect(W, H, 0, 10, W, 12), IRON[3])
    p.flat(mask_rect(W, H, 0, 17, W, 18), IRON[2])
    for x in range(10, W, 32):
        p.flat(mask_rect(W, H, x, 11, x + 2, DECK), IRON[2])
        p.flat(mask_rect(W, H, x, 11, x + 1, DECK), IRON[3])
    p.flat(mask_rect(W, H, 0, 9, W, 10), INK)
    deck = mask_rect(W, H, 0, DECK, W, DECK + 4)
    p.part(deck, IRON, bevel=1, base=2.4, strength=1.0, noise=1.1, light=(0.0, -1.0))
    rivet_row(p, DECK + 1, 4, W, 8, IRON[4])
    for x in range(0, W, 3):
        if (x * 37) % 11 < 3:
            p.px[DECK, x, :3] = RUST[3]
    girder = mask_rect(W, H, 0, DECK + 4, W, DECK + 12)
    p.part(girder, STEEL, bevel=1, base=1.6, strength=1.0, noise=0.7, light=(0.0, -1.0))
    for x in range(14, W, 24):
        p.flat(mask_rect(W, H, x, DECK + 6, x + 3, DECK + 10), IRON[0])
    top, bot = DECK + 12, 60
    for x in range(0, W, 32):
        p.part(mask_rect(W, H, x, top, x + 4, bot), STEEL, bevel=1, base=1.6, strength=1.0, noise=0.6)
    cell_mask = np.zeros((H, W), bool)
    for x in range(0, W - 32, 32):
        cell_mask |= mask_line(W, H, (x + 4, top), (x + 32, bot), 2)
        cell_mask |= mask_line(W, H, (x + 32, top), (x + 4, bot), 2)
    p.part(cell_mask, IRON, bevel=1, base=2.0, strength=0.6, outline=None, noise=0.7)
    chord = mask_rect(W, H, 0, bot, W, bot + 6)
    p.part(chord, STEEL, bevel=1, base=1.8, strength=1.0, noise=0.7, light=(0.0, -1.0))
    for x in range(0, W, 32):
        p.part(mask_poly(W, H, [(x - 4, bot), (x + 8, bot), (x + 2, bot - 9)]), IRON, bevel=1, base=1.8)
    p.line((220, bot + 6), (220, bot + 16), IRON[2], 2)
    p.flat(mask_rect(W, H, 217, bot + 16, 224, bot + 19), RUST[3])
    weather(p, p.opaque(), amount=0.9)
    p.save("bridge.png")
    print(f"      deck surface at y={DECK}")


# ------------------------------------------------------------------- masses ----


def _heap(p: Painter, rng, pts, ramp, light, jitter=3.0, noise=0.9, bias=0.0):
    p.part(mask_poly(p.w, p.h, jagged_poly(rng, pts, jitter, 4)), ramp, light=light, bevel=3, strength=1.4,
           noise=noise, tone_bias=bias)


def build_mass_left() -> None:
    """Frame -> world offset (-16, -8). The bridge enters at frame (212, 274)."""
    W, H = 256, 376
    p = Painter(W, H, seed=71)
    rng = np.random.default_rng(71)
    L = (0.62, -0.78)              # light comes from the hall (right, above)
    # steel lattice pylon on the far left edge (full height)
    lattice_pylon(p, 0, 46, 0, H, STEEL, L)
    # rubble base sloping up to the left, down to the bridge abutment
    _heap(p, rng, [(0, 226), (36, 210), (84, 232), (132, 250), (176, 260), (256, 264), (256, H), (0, H)],
          BRICK, L, bias=DIM - 0.6)
    # big horizontal boiler on two saddles
    for sx in (46, 138):
        p.part(mask_poly(W, H, [(sx - 10, 266), (sx + 22, 266), (sx + 30, 300), (sx - 18, 300)]), IRON, light=L,
               bevel=2, base=1.4, strength=1.2, noise=0.8)
    hcyl(p, 20, 206, 182, 266, STEEL, lit="top", hoops=(48, 90, 132), noise=0.9, bias=-1)
    p.part(mask_ellipse(W, H, 20, 236, 9, 30), STEEL, light=L, bevel=3, base=1.8, strength=1.2)
    p.part(mask_ellipse(W, H, 182, 236, 9, 30), STEEL, light=L, bevel=3, base=2.0, strength=1.2)
    gauge(p, 92, 232, 9)
    # the 'cannon' pipe coming down from the gears into the boiler
    pipe(p, (60, 118), (176, 214), 15, STEEL, light=L, flange=34, noise=0.9, bias=-1)
    p.part(mask_ellipse(W, H, 184, 220, 19, 19), STEEL, light=L, bevel=3, base=1.8, strength=1.4)
    p.flat(mask_ellipse(W, H, 186, 222, 10, 10), (0x0A, 0x08, 0x10))
    p.part(mask_ellipse(W, H, 186, 222, 7, 7), IRON, light=L, bevel=2, base=0.6, strength=0.8)
    # machinery blocks stepping toward the bridge
    p.part(mask_rect(W, H, 100, 268, 184, 316), IRON, light=L, bevel=3, strength=1.4, noise=1.0, tone_bias=DIM)
    for y in range(276, 310, 8):
        p.flat(mask_rect(W, H, 108, y, 150, y + 3), (0x0A, 0x08, 0x10))
    rivet_row(p, 271, 104, 182, 8, IRON[4])
    p.part(mask_rect(W, H, 152, 224, 204, 270), RUST, light=L, bevel=3, strength=1.3, noise=1.0, tone_bias=-0.4)
    hazard(p, 154, 258, 202, 268)
    rivet_row(p, 228, 156, 202, 7, RUST[4])
    gauge(p, 130, 296, 7)
    # bridge abutment: heavy plate with ribs
    p.part(mask_rect(W, H, 178, 266, 256, H), IRON, light=L, bevel=3, strength=1.4, noise=1.0, tone_bias=DIM)
    for x in range(188, 250, 20):
        p.part(mask_rect(W, H, x, 274, x + 6, H), STEEL, light=L, bevel=2, base=1.4, strength=1.0)
    rivet_row(p, 270, 182, 254, 7, IRON[4])
    # hanging vertical pipe, iron not rust-orange
    pipe(p, (96, 0), (96, 120), 5, IRON, light=L, flange=28, noise=0.8)
    # steam nozzle on the abutment top (the title vents steam from frame (210, 258))
    p.part(mask_rect(W, H, 205, 256, 215, 267), STEEL, light=L, bevel=1, base=1.6, strength=1.0)
    p.part(mask_rect(W, H, 202, 252, 218, 257), STEEL, light=L, bevel=1, base=2.0, strength=1.0)
    p.flat(mask_rect(W, H, 206, 252, 214, 254), (0x0A, 0x08, 0x10))
    # ladder up the pylon + stairs
    ladder(p, 48, 120, 266, 9)
    for i in range(9):
        p.part(mask_rect(W, H, 6 + i * 5, 352 - i * 9, 98, 360 - i * 9), IRON, light=L, bevel=1, base=1.3,
               strength=0.8)
    for pts in ([(84, H), (110, 322), (148, 312), (182, 328), (210, H)],
                [(0, H), (22, 298), (62, 306), (88, H)]):
        _heap(p, rng, pts, BRICK, L, jitter=2.5, bias=DIM)
    # weathering: rust runs under the hoops and seams, stains everywhere
    solid = p.opaque()
    rust_streaks(p, solid & (np.arange(H)[:, None] > 60) & (np.arange(W)[None, :] > 40), count=36, seed=7)
    weather(p, solid)
    ground_fog(p, 296, H, BRICK[1], 0.55)
    p.save("mass_left.png")


def build_mass_right() -> None:
    """Frame -> world offset (400, -8). The bridge leaves at frame (52, 274); the furnace
    door is the arch cut out at x 52..108, y 212..274."""
    W, H = 256, 376
    p = Painter(W, H, seed=83)
    rng = np.random.default_rng(83)
    L = (-0.62, -0.78)             # light from the hall (left, above)
    # (left edge stays at the housing, x=40, so the bridge deck stays visible up to the door)
    _heap(p, rng, [(256, 204), (214, 200), (160, 220), (108, 242), (66, 262), (50, 284), (40, 296), (40, H), (256, H)],
          BRICK, L, bias=DIM - 0.6, jitter=1.5)
    # furnace housing around the mouth
    p.part(mask_rect(W, H, 40, 190, 176, H), IRON, light=L, bevel=3, strength=1.5, noise=1.0, tone_bias=DIM)
    p.part(mask_poly(W, H, [(40, 190), (176, 190), (176, 176), (150, 160), (66, 160), (40, 176)]), IRON, light=L,
           bevel=3, strength=1.4, noise=0.9, tone_bias=DIM)
    rivet_row(p, 194, 46, 174, 8, IRON[4])
    rivet_row(p, 306, 46, 174, 8, IRON[4])
    for x in range(124, 176, 26):             # panel seams on the housing side
        p.flat(mask_rect(W, H, x, 198, x + 1, 370), IRON[1])
        rivet_row(p, 200, x + 3, x + 4, 1, IRON[4])
    hazard(p, 42, 284, 114, 294)
    # the mouth: an arch cut out of the housing (the sprite shows through)
    arch = mask_rect(W, H, 52, 232, 108, 274) | mask_ellipse(W, H, 80, 232, 28, 20)
    frame = mask_rect(W, H, 46, 226, 114, 280) | mask_ellipse(W, H, 80, 232, 34, 26)
    below = mask_rect(W, H, 0, 274, W, H)
    p.part(frame & ~below, STEEL, light=L, bevel=3, base=1.5, strength=1.3, noise=0.8)
    p.px[arch & ~below, 3] = 0
    # chimney stack, shorter: top at y~40, with a gantry and ladder
    vcyl(p, 150, 40, 206, 190, STEEL, lit="left", hoops=(66, 106, 146), noise=0.9, bias=-1)
    p.part(mask_ellipse(W, H, 178, 42, 30, 8), STEEL, light=L, bevel=3, base=2.2, strength=1.2)
    p.part(mask_rect(W, H, 140, 116, 214, 121), IRON, light=L, bevel=1, base=1.8, strength=1.0)   # gantry
    for x in range(142, 214, 12):
        p.flat(mask_rect(W, H, x, 100, x + 1, 116), IRON[3])
    p.flat(mask_rect(W, H, 140, 100, 214, 101), IRON[3])
    ladder(p, 118, 121, 190, 9)
    pipe(p, (150, 150), (66, 180), 10, STEEL, light=L, flange=30, noise=0.9, bias=-1)
    pipe(p, (206, 64), (256, 64), 9, STEEL, light=L, flange=26, noise=0.9, bias=-1)
    pipe(p, (206, 92), (256, 92), 6, IRON, light=L, flange=22, noise=0.8)
    # valve wheel
    ring = mask_ellipse(W, H, 178, 96, 15, 15) & ~mask_ellipse(W, H, 178, 96, 10, 10)
    p.part(ring, RUST, light=L, bevel=2, base=1.7, strength=1.4)
    for ang in range(0, 180, 45):
        a = math.radians(ang)
        p.line((178 - 12 * math.cos(a), 96 - 12 * math.sin(a)), (178 + 12 * math.cos(a), 96 + 12 * math.sin(a)),
               RUST[2], 2)
    p.flat(mask_ellipse(W, H, 178, 96, 3, 3), RUST[3])
    gauge(p, 186, 222, 9)
    # lower right: round plate where the front gear sits
    p.part(mask_ellipse(W, H, 214, 300, 46, 46), IRON, light=L, bevel=3, base=1.6, strength=1.3, noise=0.9)
    p.part(mask_ellipse(W, H, 214, 300, 30, 30), STEEL, light=L, bevel=3, base=1.2, strength=1.2)
    for pts in ([(256, H), (252, 322), (200, 334), (150, 350), (120, H)],
                [(40, H), (50, 336), (90, 342), (118, H)]):
        _heap(p, rng, pts, BRICK, L, jitter=2.5, bias=DIM)
    solid = p.opaque()
    rust_streaks(p, solid & (np.arange(H)[:, None] > 50), count=30, seed=9)
    weather(p, solid)
    ground_fog(p, 296, H, BRICK[1], 0.55)
    p.save("mass_right.png")
