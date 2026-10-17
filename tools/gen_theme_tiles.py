"""Cut per-chapter terrain skins and set pieces from packs already in the repo.

Every chapter used to walk on the same purple church slab. This tool gives the
themes their own ground without new art:

  brick_*    Gothic Horror brick + plank ledges        -> 锈城街巷 (town)
  castle_*   Gothic Castle olive brick with gold trim  -> 钟楼 (bell tower)
  iron_*     church slabs gradient-mapped to rust iron -> 齿轮工坊 (workshop)
  basalt_*   church slabs gradient-mapped to hot slag  -> 熔渣深渊 / 炉心 (forge)
  rampart_*  church slabs gradient-mapped to wall grey -> 锈城城墙 (ramparts)

Slab sheets keep SolidPlatform's 48x48 contract (16px lip row, body rows);
float pieces are 16px left / mid / right like float_*.png.

Set pieces from Gothic Horror (furnace, skull arch, rock pile, bones, brick
house facade, toppled tower) are written next to them.

Backdrop plates are gradient-mapped copies of existing parallax layers, so
chapters that share a pack still read as different places (assets/env/backdrop/):
  forge_*     industrial skyline as a furnace glow    -> 熔渣深渊
  core_hall   castle interior burned crimson          -> 炉心深处
  wall_town   Gothic Horror town seen from the wall   -> 锈城城墙
  wall_clouds Gothic Horror clouds in night teal      -> 锈城城墙

Usage: python tools/gen_theme_tiles.py
"""
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENV = os.path.join(ROOT, "assets", "env")
EXT = os.path.join(ROOT, "assets", "external", "gothicvania_patreon")
HORROR = os.path.join(EXT, "Gothic-Horror-Files", "PNG", "layers", "tiles.png")
CASTLE = os.path.join(EXT, "Gothic-Castle-Files", "PNG", "layers", "gothic-castle-tileset.png")
T = 16


def load(path):
    return Image.open(path).convert("RGBA")


def tile(sheet, x, y, w=T, h=T):
    return sheet.crop((x, y, x + w, y + h))


def shade(img, k):
    px = img.load()
    out = img.copy()
    po = out.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            po[x, y] = (int(r * k), int(g * k), int(b * k), a)
    return out


def save(img, name):
    path = os.path.join(ENV, name)
    img.save(path)
    print("wrote", os.path.relpath(path, ROOT), img.size)


def slab(rows):
    """rows: list of 3 lists of 3 16px tiles -> 48x48 sheet."""
    out = Image.new("RGBA", (48, 48), (0, 0, 0, 0))
    for r, row in enumerate(rows):
        for c, t in enumerate(row):
            out.alpha_composite(t, (c * T, r * T))
    return out


def gradient_map(img, stops):
    """Luminance -> palette ramp. stops: [(0..1, (r,g,b)), ...] ascending."""
    out = img.copy()
    px = img.load()
    po = out.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            for i in range(len(stops) - 1):
                t0, c0 = stops[i]
                t1, c1 = stops[i + 1]
                if lum <= t1 or i == len(stops) - 2:
                    k = 0.0 if t1 == t0 else max(0.0, min(1.0, (lum - t0) / (t1 - t0)))
                    po[x, y] = tuple(int(c0[j] + (c1[j] - c0[j]) * k) for j in range(3)) + (a,)
                    break
    return out


# The church slabs sit around luminance 0.1-0.6; ramps are stretched to that.
RAMPS = {
    "iron": [(0.0, (14, 11, 10)), (0.16, (46, 33, 27)), (0.3, (92, 62, 44)),
             (0.45, (142, 98, 64)), (0.7, (196, 148, 98))],
    "basalt": [(0.0, (8, 5, 5)), (0.16, (26, 14, 13)), (0.3, (46, 24, 20)),
               (0.45, (88, 38, 24)), (0.7, (206, 98, 40))],
    "rampart": [(0.0, (12, 14, 18)), (0.16, (40, 44, 52)), (0.3, (74, 80, 90)),
                (0.45, (116, 122, 130)), (0.7, (176, 180, 184))],
}


def opaque(img, floor):
    """Flatten transparency onto `floor` so a fill tile never shows holes."""
    base = Image.new("RGBA", img.size, tuple(floor) + (255,))
    base.alpha_composite(img)
    return base


def ramp_color(ramp, t):
    for i in range(len(ramp) - 1):
        t0, c0 = ramp[i]
        t1, c1 = ramp[i + 1]
        if t <= t1 or i == len(ramp) - 2:
            k = 0.0 if t1 == t0 else max(0.0, min(1.0, (t - t0) / (t1 - t0)))
            return tuple(int(c0[j] + (c1[j] - c0[j]) * k) for j in range(3))
    return ramp[-1][1]


def masonry_tile(ramp, seed, face=(0.2, 0.3), mortar=0.04):
    """16x16 seamless masonry: two 8px courses of 8px stones, the lower course offset by 4,
    1px mortar joints, a lit top-left edge and a shaded bottom-right edge per stone, a few
    speckles and one hairline crack. Colours come from the family ramp so every chapter's
    foundation matches its own floor instead of dissolving into a flat black fill."""
    import random
    rng = random.Random(seed)
    img = Image.new("RGBA", (T, T), ramp_color(ramp, mortar) + (255,))
    px = img.load()
    for course in range(2):
        y0 = course * 8
        shift = 0 if course == 0 else 4
        for k in range(2):
            x0 = (k * 8 + shift) % T
            base = rng.uniform(*face)
            for dy in range(7):
                for dx in range(7):
                    x = (x0 + dx) % T
                    y = y0 + dy
                    t = base
                    if dy == 0 or dx == 0:
                        t += 0.07
                    elif dy == 6 or dx == 6:
                        t -= 0.05
                    px[x, y] = ramp_color(ramp, max(0.0, t)) + (255,)
            for _ in range(2):
                x = (x0 + rng.randint(1, 5)) % T
                y = y0 + rng.randint(1, 5)
                px[x, y] = ramp_color(ramp, base + rng.choice((-0.06, 0.05))) + (255,)
    cx = rng.randint(2, 12)
    cy = rng.randint(1, 5) * 2
    for i in range(3):
        px[(cx + i) % T, min(T - 1, cy + i)] = ramp_color(ramp, mortar + 0.02) + (255,)
    return img


def masonry_fill(prefix, ramp, level):
    """Foundation tiles under a floor. The old fill was the flat dark-blue deep tile run
    through the ramp, i.e. a black void. `level` scales the whole tile; the platform then
    darkens it a little more per row, so the floor reads as masonry sinking into the
    dark rather than a slab hanging over nothing."""
    save(shade(masonry_tile(ramp, sum(ord(c) * (i + 1) for i, c in enumerate(prefix)) & 0xffff), level), "%s_fill.png" % prefix)
    save(shade(masonry_tile(ramp, (sum(ord(c) * (i + 7) for i, c in enumerate(prefix)) * 31) & 0xffff, face=(0.16, 0.26)), level * 0.9),
         "%s_fill_b.png" % prefix)


# Foundation brightness per family (before the per-row darkening in SolidPlatform).
FILL_LEVEL = {"iron": 0.85, "basalt": 1.0, "rampart": 0.9}


def recolor_family(prefix, ramp, fill_level=0.62):
    for s in ("a", "b", "c"):
        save(gradient_map(load(os.path.join(ENV, "slab_%s.png" % s)), ramp), "%s_slab_%s.png" % (prefix, s))
    masonry_fill(prefix, ramp, fill_level)
    save(gradient_map(load(os.path.join(ENV, "float_small.png")), ramp), "%s_float_small.png" % prefix)
    save(gradient_map(load(os.path.join(ENV, "float_left.png")), ramp), "%s_float_left.png" % prefix)
    save(gradient_map(load(os.path.join(ENV, "float_right.png")), ramp), "%s_float_right.png" % prefix)
    for s in ("a", "b", "c", "d"):
        save(gradient_map(load(os.path.join(ENV, "float_mid_%s.png" % s)), ramp), "%s_float_mid_%s.png" % (prefix, s))


def brick_family(h):
    tops = [tile(h, 32, 64), tile(h, 176, 64), tile(h, 192, 64), tile(h, 48, 64), tile(h, 64, 64)]
    bricks = [tile(h, 32, 80), tile(h, 64, 80)]
    dark = [shade(b, 0.72) for b in bricks]
    flip = [b.transpose(Image.FLIP_LEFT_RIGHT) for b in bricks]
    # Moss tops are rare: one per sheet, in a different column each time.
    save(slab([[tops[0], tops[1], tops[2]], [bricks[0], bricks[1], flip[0]], [dark[1], dark[0], dark[1]]]), "brick_slab_a.png")
    save(slab([[tops[1], tops[3], tops[0]], [flip[1], bricks[0], bricks[1]], [dark[0], dark[1], dark[0]]]), "brick_slab_b.png")
    save(slab([[tops[2], tops[0], tops[4]], [bricks[1], flip[1], bricks[0]], [dark[1], dark[0], dark[0]]]), "brick_slab_c.png")
    save(shade(bricks[0], 0.62), "brick_fill.png")
    save(shade(bricks[1].transpose(Image.FLIP_LEFT_RIGHT), 0.5), "brick_fill_b.png")
    small = Image.new("RGBA", (32, T), (0, 0, 0, 0))
    small.alpha_composite(tile(h, 48, 16), (0, 0))
    small.alpha_composite(tile(h, 64, 16), (T, 0))
    save(small, "brick_float_small.png")
    # Plank ledge: 80px long piece -> caps + three mids.
    save(tile(h, 32, 16), "brick_float_left.png")
    save(tile(h, 96, 16), "brick_float_right.png")
    for i, s in enumerate(("a", "b", "c")):
        save(tile(h, 48 + i * T, 16), "brick_float_mid_%s.png" % s)


def castle_family(c):
    tops = [tile(c, 32, 32), tile(c, 48, 32), tile(c, 80, 32)]
    body = [tile(c, 32, 48), tile(c, 48, 48), tile(c, 80, 48)]
    dark = [shade(b, 0.7) for b in body]
    save(slab([[tops[0], tops[1], tops[0]], [body[0], body[1], body[0]], [dark[1], dark[0], dark[1]]]), "castle_slab_a.png")
    save(slab([[tops[1], tops[0], tops[1]], [body[1], body[0], body[1]], [dark[0], dark[1], dark[0]]]), "castle_slab_b.png")
    save(slab([[tops[0], tops[1], tops[1]], [body[1], body[1], body[0]], [dark[0], dark[0], dark[1]]]), "castle_slab_c.png")
    save(shade(body[0], 0.8), "castle_fill.png")
    save(shade(body[2].transpose(Image.FLIP_LEFT_RIGHT), 0.66), "castle_fill_b.png")
    small = Image.new("RGBA", (32, T), (0, 0, 0, 0))
    small.alpha_composite(tops[0], (0, 0))
    small.alpha_composite(tops[1], (T, 0))
    save(small, "castle_float_small.png")
    # Floating ledge: gold-trim top row with a dark outer edge so the ends close.
    for name, src, side in (("left", tops[0], 0), ("right", tops[1], 1)):
        t = src.copy()
        px = t.load()
        for y in range(T):
            for k in range(2):
                x = k if side == 0 else T - 1 - k
                r, g, b, a = px[x, y]
                px[x, y] = (r // 3, g // 3, b // 3, a)
        save(t, "castle_float_%s.png" % name)
    save(tops[0], "castle_float_mid_a.png")
    save(tops[1], "castle_float_mid_b.png")


TOWER_RAMP = [(0.0, (10, 14, 18)), (0.18, (34, 42, 50)), (0.32, (66, 78, 88)),
              (0.46, (104, 116, 124)), (0.7, (150, 160, 166))]
# Church balustrade / door arch are violet. Wall tops want cold grey, streets warm stone.
WARM_RAMP = [(0.0, (14, 11, 10)), (0.2, (52, 42, 36)), (0.38, (96, 82, 68)),
             (0.55, (148, 130, 106)), (0.8, (196, 178, 150))]
COLD_RAMP = RAMPS["rampart"]


def set_pieces(h):
    pieces = {
        "gh_furnace.png": (272, 64, 32, 96),
        "gh_skull_arch.png": (224, 112, 32, 48),
        "gh_rock_pile.png": (128, 96, 32, 48),
        "gh_bones.png": (80, 112, 32, 16),
        "gh_brick_house.png": (416, 0, 384, 176),
        "gh_ruin_tower.png": (784, 16, 256, 160),
    }
    for name, (x, y, w, hh) in pieces.items():
        img = tile(h, x, y, w, hh)
        bbox = img.getbbox()
        if bbox:
            img = img.crop(bbox)
        if name == "gh_ruin_tower.png":
            img = gradient_map(img, TOWER_RAMP)
        save(img, name)
    for src, dst, ramp in (("balustrade", "balustrade_wall", COLD_RAMP), ("balustrade", "balustrade_town", WARM_RAMP),
                           ("door_arch", "door_arch_wall", COLD_RAMP), ("door_arch", "door_arch_town", WARM_RAMP)):
        save(gradient_map(load(os.path.join(ENV, src + ".png")), ramp), dst + ".png")


def gradient_map_norm(img, stops, ceiling=0.7):
    """Gradient map after stretching the sprite's own luminance (2nd..98th percentile)
    to 0..ceiling, so dark sprites (rubble, crosses) land on the same ramp range as slabs."""
    px = img.load()
    lums = []
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if a:
                lums.append(0.299 * r + 0.587 * g + 0.114 * b)
    if not lums:
        return img.copy()
    lums.sort()
    lo = lums[int(len(lums) * 0.02)] / 255.0
    hi = lums[min(len(lums) - 1, int(len(lums) * 0.98))] / 255.0
    span = max(hi - lo, 0.05)
    out = img.copy()
    po = out.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if not a:
                continue
            lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            t = max(0.0, min(1.0, (lum - lo) / span)) * ceiling
            for i in range(len(stops) - 1):
                t0, c0 = stops[i]
                t1, c1 = stops[i + 1]
                if t <= t1 or i == len(stops) - 2:
                    k = 0.0 if t1 == t0 else max(0.0, min(1.0, (t - t0) / (t1 - t0)))
                    po[x, y] = tuple(int(c0[j] + (c1[j] - c0[j]) * k) for j in range(3)) + (a,)
                    break
    return out


# Material family -> ramp used for recolored props (assets/env/props/<family>/<key>.png).
# Same families as SolidPlatform skins; graveyard ("ground") keeps the stock props.
PROP_RAMPS = {
    "iron": RAMPS["iron"],
    "basalt": RAMPS["basalt"],
    "rampart": RAMPS["rampart"],
    "brick": WARM_RAMP,
    "castle": [(0.0, (8, 10, 6)), (0.2, (34, 38, 24)), (0.38, (70, 76, 46)),
               (0.55, (120, 122, 70)), (0.7, (178, 170, 100))],
    "stone": [(0.0, (10, 9, 16)), (0.2, (36, 34, 50)), (0.38, (72, 70, 92)),
              (0.55, (112, 110, 132)), (0.7, (170, 168, 186))],
    "moss": [(0.0, (6, 12, 12)), (0.2, (22, 40, 38)), (0.38, (48, 78, 66)),
             (0.55, (90, 122, 92)), (0.7, (150, 170, 120))],
}
# Stock sprites that pick up a family recolor. Wall-set pieces are excluded.
RECOLOR_PROPS = {
    "slab": "slab_a.png", "plate": "plate_stone.png",
    "rubble_dry": "rubble_a.png", "rubble_dry_b": "rubble_b.png", "rubble_dry_c": "rubble_c.png",
    "balustrade": "balustrade.png", "door_arch": "door_arch.png",
    "statue": "statue_keeper.png", "grave_cross": "grave_cross.png",
    "rock_pile": "gh_rock_pile.png",
}
# A grave cross or a keeper statue has no business in a forge; those families skip them.
SKIP_PROPS = {
    "iron": {"statue", "grave_cross"},
    "basalt": {"statue", "grave_cross"},
    "rampart": {"grave_cross"},
    "castle": {"grave_cross"},
}


def prop_variants():
    for family, ramp in PROP_RAMPS.items():
        out_dir = os.path.join(ENV, "props", family)
        os.makedirs(out_dir, exist_ok=True)
        for key, src in RECOLOR_PROPS.items():
            if key in SKIP_PROPS.get(family, ()):
                continue
            img = gradient_map_norm(load(os.path.join(ENV, src)), ramp)
            img.save(os.path.join(out_dir, key + ".png"))
        print("wrote props/%s" % family)


# Cathedral / nave paving: the stock church slab is a saturated lavender that glows next to
# the graveyard soil and the dark nave walls. Same slab and ledge drawings, slate ramp.
def nave_family():
    ramp = PROP_RAMPS["stone"]
    for s in ("a", "b", "c"):
        save(gradient_map(load(os.path.join(ENV, "slab_%s.png" % s)), ramp), "nave_slab_%s.png" % s)
    for name in ("left", "right"):
        save(gradient_map(load(os.path.join(ENV, "float_%s.png" % name)), ramp), "nave_float_%s.png" % name)
    for s in ("a", "b", "c", "d"):
        save(gradient_map(load(os.path.join(ENV, "float_mid_%s.png" % s)), ramp), "nave_float_mid_%s.png" % s)
    save(gradient_map(load(os.path.join(ENV, "float_small.png")), ramp), "nave_float_small.png")
    masonry_fill("nave", ramp, 0.62)


IND = os.path.join(ROOT, "assets", "external", "oga_parallax", "pack", "parallax-industrial-pack", "layers")
BACKDROPS = {
    "forge_sky.png": (os.path.join(IND, "skill-desc_0003_bg.png"),
                      [(0.13, (22, 6, 6)), (0.3, (92, 26, 14)), (0.42, (196, 82, 32))]),
    "forge_far.png": (os.path.join(IND, "skill-desc_0002_far-buildings.png"),
                      [(0.0, (58, 16, 12)), (1.0, (58, 16, 12))]),
    "forge_mid.png": (os.path.join(IND, "skill-desc_0001_buildings.png"),
                      [(0.0, (26, 8, 7)), (1.0, (26, 8, 7))]),
    "forge_near.png": (os.path.join(IND, "skill-desc_0000_foreground.png"),
                       [(0.13, (8, 3, 3)), (0.38, (36, 12, 9))]),
    "core_hall.png": (os.path.join(EXT, "Old-dark-Castle-tileset-Files", "PNG", "old-dark-castle-interior-background.png"),
                      [(0.1, (14, 4, 6)), (0.2, (52, 12, 14)), (0.32, (128, 36, 26))]),
    "wall_town.png": (os.path.join(EXT, "Gothic-Horror-Files", "PNG", "layers", "town.png"),
                      [(0.17, (14, 30, 34)), (0.34, (46, 78, 80)), (0.44, (206, 190, 112))]),
    "wall_clouds.png": (os.path.join(EXT, "Gothic-Horror-Files", "PNG", "layers", "clouds.png"),
                        [(0.3, (22, 42, 48)), (0.42, (52, 82, 88)), (0.52, (96, 126, 126))]),
}


# Church wall plates ship on an opaque flat wall colour. Planted in a chapter
# they read as blue boxes. Flood the flat colour out from the plate border so
# only the carved window / altar / gargoyle remains (interior darks survive).
PLATES = ["bg_wall_window", "bg_column_skulls", "bg_altar", "bg_gargoyle", "bg_wall_torch", "column_big"]
WALL_KEYS = {(39, 38, 56), (45, 39, 75)}


def key_plate(img):
    out = img.copy()
    px = out.load()
    w, h = out.size
    seen = set()
    stack = [(x, y) for x in range(w) for y in (0, h - 1)] + [(x, y) for y in range(h) for x in (0, w - 1)]
    while stack:
        x, y = stack.pop()
        if (x, y) in seen or not (0 <= x < w and 0 <= y < h):
            continue
        seen.add((x, y))
        r, g, b, a = px[x, y]
        if a != 0 and (r, g, b) not in WALL_KEYS:
            continue
        px[x, y] = (0, 0, 0, 0)
        stack.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
    return out


def plates():
    for name in PLATES:
        save(key_plate(load(os.path.join(ENV, name + ".png"))), name + "_cut.png")


def tower_wall(c):
    """192x192 bell-tower shaft wall. Castle brick sunk dark, a timber floor band,
    pilasters, two staggered arrow slits (moonlight inside), one bricked-up slit and
    a broken-brick patch. Tiles on both axes, so it can climb the whole tower without
    drawing a floor line in the air, and the pattern only repeats every 192px."""
    n = 192
    body = [shade(tile(c, x, 48), 0.66) for x in (32, 48, 80)]
    out = Image.new("RGBA", (n, n), (0, 0, 0, 255))
    for r in range(n // T):
        for col in range(n // T):
            t = body[(r * 7 + col * 5 + r * col * 3) % 3]
            if (r * 3 + col) % 2:
                t = t.transpose(Image.FLIP_LEFT_RIGHT)
            out.alpha_composite(t, (col * T, r * T))
    px = out.load()

    def blend(x, y, rgb, k):
        r, g, b, a = px[x % n, y % n]
        px[x % n, y % n] = (int(r + (rgb[0] - r) * k), int(g + (rgb[1] - g) * k), int(b + (rgb[2] - b) * k), 255)

    # mortar bands every 48px: a darker course so the wall reads as laid stone
    for y in range(0, n, 48):
        for x in range(n):
            blend(x, y + 47, (6, 7, 5), 0.55)
    # pilasters: lighter, edged, with a capital and a base so they read as structure
    for cx in (0, 94):
        for y in range(n):
            for dx in range(10):
                x = cx + dx
                edge = dx in (0, 9)
                blend(x, y, (10, 10, 8) if edge else (58, 56, 40), 0.7 if edge else 0.55)
        for dy in (0, 1, 2):
            for dx in range(-2, 12):
                blend(cx + dx, 46 + dy, (84, 78, 52), 0.8)
                blend(cx + dx, 94 + dy, (84, 78, 52), 0.8)
    # timber floor band: a beam across the whole tile with nails
    for y in range(88, 97):
        shade_k = 0.55 if y in (88, 96) else 1.0
        for x in range(n):
            base = (86, 58, 34) if y not in (88, 96) else (44, 28, 16)
            blend(x, y, base, 0.9 * shade_k if shade_k < 1 else 0.85)
    for x in range(10, n, 24):
        blend(x, 92, (196, 170, 110), 0.9)

    def slit(sx, sy, w=8, h=30, lit=True):
        for y in range(sy - 3, sy + h + 3):
            for x in range(sx - 3, sx + w + 3):
                px[x % n, y % n] = (48, 44, 26, 255)
        for y in range(sy, sy + h):
            for x in range(sx, sx + w):
                if y - sy < 4 and abs((x - sx) - (w - 1) / 2.0) > (y - sy) + 0.5:
                    continue
                if lit:
                    glow = 1.0 - (y - sy) / float(h)
                    px[x % n, y % n] = (int(40 + 40 * glow), int(44 + 46 * glow), int(70 + 70 * glow), 255)
                else:
                    px[x % n, y % n] = (30, 29, 22, 255)
        for x in range(sx - 4, sx + w + 4):
            px[x % n, (sy + h + 3) % n] = (70, 64, 38, 255)

    slit(36, 14)                   # high slit above the floor band
    slit(140, 100)                 # staggered slit on the next floor
    slit(44, 130, lit=False)       # bricked-up: same frame, no light
    # broken-brick patch: lighter mortar showing through
    for y in range(150, 168):
        for x in range(120, 160):
            if (x * 7 + y * 13) % 5 < 2:
                blend(x, y, (92, 88, 60), 0.55)
    return out


def backdrops():
    out_dir = os.path.join(ENV, "backdrop")
    os.makedirs(out_dir, exist_ok=True)
    for name, (src, ramp) in BACKDROPS.items():
        img = gradient_map(load(src), ramp)
        path = os.path.join(out_dir, name)
        img.save(path)
        print("wrote", os.path.relpath(path, ROOT), img.size)
    img = tower_wall(load(CASTLE))
    path = os.path.join(out_dir, "tower_wall.png")
    img.save(path)
    print("wrote", os.path.relpath(path, ROOT), img.size)


def main():
    h = load(HORROR)
    c = load(CASTLE)
    brick_family(h)
    castle_family(c)
    for prefix, ramp in RAMPS.items():
        recolor_family(prefix, ramp, FILL_LEVEL.get(prefix, 0.7))
    nave_family()
    set_pieces(h)
    prop_variants()
    plates()
    backdrops()


if __name__ == "__main__":
    main()
