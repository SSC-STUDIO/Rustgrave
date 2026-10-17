"""Generate Rustgrave's pixel UI kit into assets/ui/.

Everything here is authored on a *design grid* (1 design pixel) and written out
at DESIGN_SCALE, so the shipped PNGs are integer-upscaled pixel art that stays
crisp under NEAREST filtering. The kit deliberately owns no gradients or
anti-aliased shapes — only flat indexed colors from the game palette.

Run:  py -3 tools/gen_ui_kit.py
"""

from __future__ import annotations

import os
import random
from typing import Tuple

from PIL import Image, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "assets", "ui")
FONT_JACQUARD = os.path.join(ROOT, "assets", "fonts", "Jacquard24-Regular.ttf")
## CC0 火焰帧表（CodeManu Free Pixel Effects Pack）——余烬粒子与菜单火苗的来源。
FIRE_SHEET = os.path.join(ROOT, "assets", "kenney_clean", "vfx",
                          "9_brightfire_spritesheet.png")
FIRE_COLS, FIRE_ROWS, FIRE_FRAMES = 8, 8, 61

## UI art is authored at 1x and shipped at 2x so borders read chunky next to
## the 24px (= 2x design) text, while the world stays at native 1x.
DESIGN_SCALE = 2

## Palette keys are single chars so pieces can be written as ASCII art.
## Values track scripts/data/palette.gd plus the dark-violet crypt tones that
## the level's clear color already uses.
PAL: dict[str, tuple[int, int, int, int]] = {
    ".": (0, 0, 0, 0),           # transparent
    "0": (0x12, 0x0E, 0x14, 255),  # outline / void
    "1": (0x24, 0x1C, 0x22, 255),  # iron dark  (shadow bevel)
    "2": (0x4A, 0x3E, 0x44, 255),  # iron
    "3": (0x6B, 0x5A, 0x5E, 255),  # iron lit   (highlight bevel)
    "4": (0x14, 0x10, 0x1F, 255),  # panel deep (interior)
    "5": (0x1E, 0x18, 0x30, 255),  # panel mid
    "6": (0x2A, 0x21, 0x40, 255),  # panel edge
    "7": (0x4A, 0x2A, 0x18, 255),  # rust shadow
    "8": (0x8B, 0x45, 0x13, 255),  # rust dark
    "9": (0xA0, 0x52, 0x2D, 255),  # rust mid
    "a": (0xCD, 0x5C, 0x5C, 255),  # rust light
    "b": (0xFF, 0x8C, 0x00, 255),  # toxic glow
    "c": (0xFF, 0xC1, 0x4A, 255),  # ember
    "d": (0xE8, 0xB0, 0x90, 255),  # ember ash
    "e": (0xE4, 0xDC, 0xCC, 255),  # bone
    "g": (0x24, 0x38, 0x2C, 255),  # sludge dark
    "h": (0x3E, 0x6B, 0x4A, 255),  # sludge mid
    "i": (0x61, 0x9E, 0x7A, 255),  # sludge lit
    "j": (0x9E, 0xD0, 0x92, 255),  # sludge highlight
    "v": (0x3A, 0x20, 0x12, 255),  # rust deep (dither partner for "7")
    # semi-transparent variants for in-game overlays that must not block sight
    "K": (0x12, 0x0E, 0x14, 224),
    "L": (0x24, 0x1C, 0x22, 214),
    "M": (0x4A, 0x3E, 0x44, 214),
    "N": (0x14, 0x10, 0x1F, 200),
    "O": (0x8B, 0x45, 0x13, 214),
    "P": (0x1E, 0x18, 0x30, 200),
    "Q": (0x7A, 0x38, 0x14, 110),  # logo halo, inner
    "R": (0x5A, 0x28, 0x12, 56),   # logo halo, outer
    # 底部装饰带的暗度阶梯（同一个墨色，只改不透明度）
    "S": (0x0A, 0x08, 0x0F, 238),
    "T": (0x0A, 0x08, 0x0F, 208),
    "U": (0x0A, 0x08, 0x0F, 160),
    "V": (0x0A, 0x08, 0x0F, 96),
}


class Grid:
    """A mutable design-grid bitmap addressed as grid[x, y] = palette char."""

    def __init__(self, w: int, h: int, fill: str = "."):
        self.w = w
        self.h = h
        self.cells = [[fill] * w for _ in range(h)]

    def __setitem__(self, xy, ch: str) -> None:
        x, y = xy
        if 0 <= x < self.w and 0 <= y < self.h:
            self.cells[y][x] = ch

    def __getitem__(self, xy) -> str:
        x, y = xy
        return self.cells[y][x]

    def stamp(self, x0: int, y0: int, art: list[str]) -> None:
        """Blit ASCII art, treating ' ' as "leave whatever is underneath"."""
        for dy, row in enumerate(art):
            for dx, ch in enumerate(row):
                if ch != " ":
                    self[x0 + dx, y0 + dy] = ch

    def to_image(self, scale: int = DESIGN_SCALE) -> Image.Image:
        img = Image.new("RGBA", (self.w, self.h))
        img.putdata([PAL[ch] for row in self.cells for ch in row])
        return img.resize((self.w * scale, self.h * scale), Image.NEAREST)

    def save(self, name: str, scale: int = DESIGN_SCALE) -> None:
        path = os.path.join(OUT, name)
        self.to_image(scale).save(path)
        w, h = self.w * scale, self.h * scale
        print(f"  {name:<26} {w}x{h}")


def frame(w: int, h: int, rings: list[tuple[str, str]], interior: str,
          chamfer: int = 0, dither: str = "") -> Grid:
    """Build a beveled picture frame.

    `rings` runs outside-in as (lit, shadow) color pairs; the lit color is used
    on the top/left flanks and the shadow color on bottom/right, which is what
    sells depth in pixel art. `chamfer` cuts the corners diagonally for the
    gothic octagonal silhouette. `dither` checkers the interior with a second
    tone so a stretched panel never reads as one flat rectangle — the theme
    tiles the middle slice to keep the checker at 1:1.
    """
    g = Grid(w, h)
    for y in range(h):
        for x in range(w):
            left, top = x, y
            right, bottom = w - 1 - x, h - 1 - y
            cx, cy = min(left, right), min(top, bottom)
            depth = min(cx, cy, cx + cy - chamfer)
            if depth < 0:
                continue
            if depth >= len(rings):
                g[x, y] = dither if dither != "" and (x + y) % 2 else interior
                continue
            lit, shadow = rings[depth]
            nearest = min(left, top, right, bottom)
            g[x, y] = lit if nearest in (left, top) else shadow
    return g


def outline(g: Grid, ch: str = "0") -> None:
    """Wrap the opaque silhouette in a 1px edge so a piece reads on any backdrop."""
    edges = [
        (x, y)
        for y in range(g.h) for x in range(g.w)
        if g[x, y] == "." and any(
            0 <= x + dx < g.w and 0 <= y + dy < g.h and g[x + dx, y + dy] not in (".", ch)
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
    ]
    for x, y in edges:
        g[x, y] = ch


# --- CC0 fire frames, distilled to the design grid ------------------------

## 火焰密度 -> 色板，按亮度单调排列，让锈红外焰过渡到余烬亮芯。
FIRE_RAMP = ["7", "8", "9", "a", "b", "c"]


def _fire_frame(sheet: Image.Image, index: int) -> Image.Image | None:
    """Crop one animation frame down to its inked bounding box."""
    fw, fh = sheet.width // FIRE_COLS, sheet.height // FIRE_ROWS
    col, row = index % FIRE_COLS, index // FIRE_COLS
    cell = sheet.crop((col * fw, row * fh, col * fw + fw, row * fh + fh))
    bbox = cell.split()[3].getbbox()
    return cell.crop(bbox) if bbox is not None else None


def _distill(src: Image.Image, w: int, h: int, alpha_cut: int) -> Grid:
    """Area-average a fire frame onto a w*h design grid and snap it to the palette.

    Sampling the 100px source down at runtime made the motes disappear — every
    NEAREST tap landed in the transparent margin. Averaging here keeps the
    pack's silhouette and hands Godot art that is already ember-sized.

    The ramp is driven by *coverage*, not luminance: the source is an additive
    glow whose wisps are bright but thin, so luminance mapping painted the
    wisps as brightly as the core and the flame came out flat.
    """
    small = src.resize((w, h), Image.BOX)
    px = small.load()
    g = Grid(w, h)
    for y in range(h):
        for x in range(w):
            a = px[x, y][3]
            if a < alpha_cut:
                continue
            density = (a - alpha_cut) / float(255 - alpha_cut)
            level = int(density ** 0.7 * len(FIRE_RAMP))
            g[x, y] = FIRE_RAMP[min(len(FIRE_RAMP) - 1, level)]
    return g


def _fire_strip(name: str, cell: Tuple[int, int], count: int, first: int, step: int,
                alpha_cut: int, scale: int, do_outline: bool) -> None:
    """Write a single-row animation strip distilled from the CC0 fire sheet."""
    sheet = Image.open(FIRE_SHEET).convert("RGBA")
    cw, ch = cell
    g = Grid(cw * count, ch)
    for i in range(count):
        src = _fire_frame(sheet, (first + i * step) % FIRE_FRAMES)
        if src is None:
            continue
        piece = _distill(src, cw, ch, alpha_cut)
        if do_outline:
            outline(piece)
        for y in range(ch):
            for x in range(cw):
                if piece[x, y] != ".":
                    g[i * cw + x, y] = piece[x, y]
    g.save(name, scale=scale)


def ember_motes() -> None:
    """Ember motes: 6x6 design px shipped 1:1, so they can only ever draw crisp.

    Used both for the title's drifting embers and for the brazier that burns
    beside the selected menu row.
    """
    _fire_strip("ember_motes.png", (6, 6), 8, 4, 6, 150, scale=1, do_outline=False)


# --- 9-slice panels -------------------------------------------------------

RIVET = [
    ".8.",
    "8c8",
    ".7.",
]


def panel_stone() -> None:
    """Workhorse panel: iron bevel, rust hairline, deep violet interior."""
    g = frame(12, 12, [
        ("0", "0"),
        ("3", "1"),
        ("2", "1"),
        ("8", "7"),
        ("6", "6"),
    ], "4", chamfer=1, dither="5")
    g.save("panel_stone.png")


def panel_ornate() -> None:
    """Menu / dialog panel: thicker rust band plus ember rivets in the corners."""
    g = frame(20, 20, [
        ("0", "0"),
        ("3", "1"),
        ("2", "1"),
        ("1", "1"),
        ("8", "7"),
        ("9", "8"),
        ("7", "7"),
        ("6", "6"),
        ("5", "5"),
    ], "4", chamfer=2, dither="5")
    for cx, cy in ((4, 4), (13, 4), (4, 13), (13, 13)):
        g.stamp(cx, cy, RIVET)
    g.save("panel_ornate.png")


def panel_hud() -> None:
    """Translucent HUD plate — legible over the level without blocking sight."""
    g = frame(10, 10, [
        ("K", "K"),
        ("M", "L"),
        ("O", "O"),
        ("P", "P"),
    ], "N", chamfer=1, dither="P")
    g.save("panel_hud.png")


def buttons() -> None:
    """Menu-row plates. Four rings deep, with a dithered interior.

    The interior is a two-tone checker rather than a flat fill, and the theme
    tiles the middle slice so the speckle repeats at 1:1 instead of smearing
    into a solid rectangle across a 420px row.
    """
    size = 10
    variants = {
        "btn_normal.png": ([("0", "0"), ("3", "1"), ("7", "7"), ("6", "6")], "5", "4"),
        "btn_hover.png": ([("0", "0"), ("c", "8"), ("9", "9"), ("8", "7")], "7", "v"),
        "btn_pressed.png": ([("0", "0"), ("1", "2"), ("7", "7"), ("6", "6")], "v", "7"),
        "btn_disabled.png": ([("0", "0"), ("1", "1"), ("5", "5"), ("4", "4")], "4", "4"),
    }
    for name, (rings, interior, alt) in variants.items():
        g = frame(size, size, rings, interior, chamfer=1)
        for y in range(len(rings), size - len(rings)):
            for x in range(len(rings), size - len(rings)):
                if (x + y) % 2 == 1:
                    g[x, y] = alt
        g.save(name)


def bars() -> None:
    """Inset gutter + fills for the meters.

    The gutter's stretchable middle carries one tick, so a stylebox set to tile
    turns into a segmented meter — a stretched rectangle would read as a plain
    box no matter how nicely its rim is beveled.
    """
    track = Grid(8, 8)
    for y in range(8):
        for x in range(8):
            edge = min(x, y, 7 - x, 7 - y)
            if edge == 0:
                track[x, y] = "0"
            elif edge == 1:
                # 内凹：上/左压暗、下/右提亮，读起来是一道沉进面板的槽
                track[x, y] = "1" if (x == 1 or y == 1) else "2"
            else:
                track[x, y] = "4"
    for y in range(2, 6):
        track[2, y] = "7"
    track.save("bar_track.png")

    def fill(top: str, body: str, bottom: str, edge: str) -> Grid:
        """顶沿高光、底沿压暗、右端亮一格当作前进边缘。"""
        g = Grid(8, 8)
        for y in range(8):
            row = top if y <= 1 else (bottom if y >= 6 else body)
            for x in range(8):
                g[x, y] = edge if x >= 6 and 1 < y < 6 else row
        return g

    fill("j", "h", "g", "i").save("bar_fill_toxin.png")
    fill("c", "9", "7", "b").save("bar_fill_ember.png")


def heart_slot() -> None:
    """Translucent iron socket behind each heart, with rust studs at the corners."""
    g = frame(13, 11, [("K", "K"), ("M", "L")], "N", chamfer=1)
    for x, y in ((2, 1), (10, 1), (2, 9), (10, 9)):
        g[x, y] = "O"
    g.save("heart_slot.png")


# --- fixed-size ornaments -------------------------------------------------

def banner() -> None:
    """Announcement ribbon: pointed caps, dark body, 9-sliced across x only.

    Height is fixed by the art (21 design px holds 24px text plus the caps'
    taper); callers pin the panel to it so the caps never stretch off-grid.
    """
    cap_w, h, mid_w = 11, 21, 2
    mid_y = h // 2
    g = Grid(cap_w * 2 + mid_w, h)

    def column(x: int, top: int) -> None:
        bottom = h - 1 - top
        g[x, top] = "0"
        g[x, bottom] = "0"
        if bottom - top >= 2:
            g[x, top + 1] = "8"
            g[x, bottom - 1] = "8"
        for y in range(top + 2, bottom - 1):
            g[x, y] = "5"

    tops = [round(mid_y - mid_y * x / (cap_w - 1)) for x in range(cap_w)]
    for x, top in enumerate(tops):
        if top == mid_y:  # the tip is a single ember point
            g[x, mid_y] = "9"
            g[g.w - 1 - x, mid_y] = "9"
            continue
        column(x, top)
        column(g.w - 1 - x, top)
    for x in range(cap_w, cap_w + mid_w):
        column(x, 0)
    # clasp studs just inside both caps
    g[5, mid_y] = "c"
    g[g.w - 6, mid_y] = "c"
    g.save("banner.png")


def divider() -> None:
    """Title-screen rule: tapering rust line with a toxic diamond at center."""
    w, h = 96, 7
    g = Grid(w, h)
    mid = h // 2
    for x in range(w):
        t = abs(x - (w - 1) / 2.0) / ((w - 1) / 2.0)  # 0 center .. 1 ends
        g[x, mid] = "9" if t < 0.25 else ("8" if t < 0.62 else "7")
        # 中段垫一道更暗的线，横线在暗底上有厚度又不会抢眼
        if t < 0.45:
            g[x, mid + 1] = "7"
    diamond = [
        "...c...",
        "..c9c..",
        ".c989c.",
        "c98b89c",
        ".c989c.",
        "..c9c..",
        "...c...",
    ]
    g.stamp(w // 2 - 3, 0, diamond)
    g.save("divider.png")


def cursor_spike() -> None:
    """Menu selection marker: chunky rust arrowhead with an ember tip."""
    w, h = 9, 14
    g = Grid(w, h)
    cy = (h - 1) / 2.0
    for y in range(h):
        reach = int(round((h * 0.5 - abs(y - cy)) * 1.15))
        for x in range(reach):
            t = x / max(1, reach - 1)
            g[x, y] = "8" if t < 0.34 else ("9" if t < 0.72 else "c")
    outline(g)
    g.save("cursor_spike.png")


def corner_bracket() -> None:
    """Screen-corner filigree: double rule with a rosette elbow and serif tips.

    Two parallel rules separated by one empty design pixel — at 2x that is a
    2px/2px/2px band, which is the smallest double rule that still reads as
    deliberate ironwork rather than a stray line.
    """
    n = 20
    outer, inner = 17, 11
    g = Grid(n, n)

    def ramp(i: int, span: int) -> str:
        t = i / (span - 1)
        return "9" if t < 0.34 else ("8" if t < 0.70 else "7")

    for i in range(outer):
        g[i, 0] = ramp(i, outer)
        g[0, i] = ramp(i, outer)
    for i in range(inner):
        g[i, 2] = ramp(i, inner)
        g[2, i] = ramp(i, inner)
    # 两条线的末端各收一个短衬脚，臂尖不至于断得突然
    for y in range(3):
        g[outer - 1, y] = "8"
        g[y, outer - 1] = "8"
    for y in range(2, 5):
        g[inner - 1, y] = "7"
        g[y, inner - 1] = "7"
    # 肘部铆钉压住两条线的起点
    g.stamp(0, 0, ["c9c", "9b9", "c9c"])
    g.save("corner_bracket.png")


def band_edge() -> None:
    """Bottom credit band: rust hairline with riveted ends over a dark strip."""
    w, h = 14, 15
    g = Grid(w, h)
    for x in range(w):
        g[x, 0] = "0"
        g[x, 1] = "9" if 2 <= x <= w - 3 else "8"
        g[x, 2] = "7"
    # 越往下越沉，最后压成不透明，接住屏幕底边
    for y, ch in enumerate("VUTTSSSSSSSS"):
        for x in range(w):
            g[x, 3 + y] = ch
    for cx in (2, w - 3):
        g.stamp(cx - 1, 1, [".8.", "8c8", ".7."])
    g.save("band_edge.png")


def vignette() -> None:
    """Low-HP blood vignette: ordered-dithered radial ramp, NEAREST-upscaled.

    Written at quarter resolution so it reads as deliberate pixel dithering
    instead of a smooth photographic gradient.
    """
    w, h = 320, 180
    bayer = [
        [0, 8, 2, 10],
        [12, 4, 14, 6],
        [3, 11, 1, 9],
        [15, 7, 13, 5],
    ]
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    cx, cy = (w - 1) / 2.0, (h - 1) / 2.0
    for y in range(h):
        for x in range(w):
            # normalized elliptical distance, 0 at center, 1 at the edges
            d = max(abs(x - cx) / cx, abs(y - cy) / cy)
            k = max(0.0, (d - 0.55) / 0.45) ** 1.6
            level = k * 16.0
            on = level > bayer[y % 4][x % 4]
            if on:
                px[x, y] = (0x8C, 0x14, 0x14, 255)
    path = os.path.join(OUT, "vignette_blood.png")
    img.save(path)
    print(f"  {'vignette_blood.png':<26} {w}x{h}")


# --- title word mark ------------------------------------------------------

TITLE_TEXT = "RUSTGRAVE"
TITLE_CAP = 40  # design px, so the shipped logo is 80 px tall at 2x


def _threshold_glyphs(text: str, cap: int) -> list[list[bool]]:
    """Rasterize a blackletter word to a hard 1-bit design-grid bitmap.

    Jacquard is an outline font whose diamond lattice never lands exactly on a
    pixel grid, so we pick the point size whose inked height matches `cap` and
    then hard-threshold — that is what makes the shipped logo pixel-crisp.
    """
    best = None
    for size in range(cap, cap * 3):
        font = ImageFont.truetype(FONT_JACQUARD, size)
        mask = font.getmask(text, mode="L")
        bbox = Image.frombytes("L", mask.size, bytes(mask)).getbbox()
        if bbox is None:
            continue
        height = bbox[3] - bbox[1]
        if best is None or abs(height - cap) < abs(best[0] - cap):
            best = (height, size)
        if height > cap * 1.4:
            break
    _, size = best
    font = ImageFont.truetype(FONT_JACQUARD, size)
    mask = font.getmask(text, mode="L")
    img = Image.frombytes("L", mask.size, bytes(mask))
    img = img.crop(img.getbbox())
    return [[img.getpixel((x, y)) >= 110 for x in range(img.width)]
            for y in range(img.height)]


def title_logo() -> None:
    bits = _threshold_glyphs(TITLE_TEXT, TITLE_CAP)
    bh, bw = len(bits), len(bits[0])
    pad = 6
    g = Grid(bw + pad * 2, bh + pad * 2 + 3)
    ox, oy = pad, pad

    def solid(x: int, y: int) -> bool:
        return 0 <= y < bh and 0 <= x < bw and bits[y][x]

    rng = random.Random(0x8B4513)
    # 0) forge glow: two translucent rings bleeding out of the silhouette
    for radius, ch in ((4, "R"), (2, "Q")):
        for y in range(-radius, bh + radius):
            for x in range(-radius, bw + radius):
                if solid(x, y):
                    continue
                near = any(solid(x + dx, y + dy)
                           for dy in range(-radius, radius + 1)
                           for dx in range(-radius, radius + 1)
                           if dx * dx + dy * dy <= radius * radius)
                if near:
                    g[ox + x, oy + y] = ch
    # 1) body: vertical ember->rust ramp, plus rust pitting near the bottom
    for y in range(bh):
        t = y / max(1, bh - 1)
        if t < 0.16:
            body = "d"
        elif t < 0.42:
            body = "c"
        elif t < 0.70:
            body = "9"
        else:
            body = "8"
        for x in range(bw):
            if not solid(x, y):
                continue
            ch = body
            if t > 0.55 and rng.random() < 0.13:
                ch = "7"  # corrosion speckle eats into the lower half
            g[ox + x, oy + y] = ch
    # 2) top highlight on the first inked pixel of every column
    for x in range(bw):
        for y in range(bh):
            if solid(x, y):
                g[ox + x, oy + y] = "e"
                break
    # 3) hard outline all around so the mark reads against any keyart
    for y in range(-1, bh + 1):
        for x in range(-1, bw + 1):
            if solid(x, y):
                continue
            touching = any(solid(x + dx, y + dy)
                           for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1),
                                          (1, 1), (-1, 1), (1, -1), (-1, -1)))
            if touching:
                g[ox + x, oy + y] = "0"
    # 4) rust drips: a few short runs hanging off the baseline
    for x in range(bw):
        deepest = max((y for y in range(bh) if solid(x, y)), default=None)
        if deepest is None or deepest < bh - 3:
            continue
        if rng.random() < 0.12:
            for k in range(1, rng.randint(2, 4)):
                g[ox + x, oy + deepest + k] = "7" if k > 1 else "8"
                g[ox + x, oy + deepest + k + 1] = "0"
    g.save("title_logo.png")


# --- HUD v2: open cluster instead of a boxed status sheet ----------------

def hud_backing() -> None:
    """Ink ribbon behind the HUD cluster: a rust spine with rivets on the left,
    a dark body, and a dithered fade on the right so the cluster melts into
    the level instead of sitting in a framed box. 9-sliced (left 6 / right 8)."""
    w, h = 20, 16
    g = Grid(w, h)
    for y in range(h):
        for x in range(w):
            if x == 0:
                g[x, y] = "0"
            elif x == 1:
                g[x, y] = "8"
            elif x == 2:
                g[x, y] = "7"
            elif x < w - 8:
                g[x, y] = "T"
            else:
                # 8px dither ramp T -> U -> V -> clear
                k = x - (w - 8)
                tones = ["T", "U", "U", "V", "V", ".", ".", "."]
                ch = tones[k]
                if ch != "." and (x + y) % 2 and k >= 2:
                    ch = tones[min(7, k + 1)]
                g[x, y] = ch
    for y in (2, h - 3):
        g[1, y] = "c"
    g[1, 0] = "0"
    g[1, h - 1] = "0"
    g.save("hud_backing.png")


def socket_gems() -> None:
    """Sword socket: an iron ring (empty) and a faceted gem drawn in greys so
    the HUD can tint it per core (kiln / tether / ember)."""
    ring = Grid(13, 13)
    art = [
        "....00000....",
        "...0322210...",
        "..032...210..",
        ".032.....210.",
        "032.......210",
        "02.........10",
        "02.........10",
        "02.........10",
        "021.......110",
        ".021.....110.",
        "..0211.1110..",
        "...0211110...",
        "....00000....",
    ]
    ring.stamp(0, 0, art)
    for x, y in ((6, 0), (0, 6), (12, 6), (6, 12)):
        ring[x, y] = "8"
    ring.save("socket_ring.png")
    gem = Grid(13, 13)
    gem.stamp(0, 0, [
        ".............",
        ".............",
        "......e......",
        ".....eed.....",
        "....eeedd....",
        "...eeed3dd...",
        "..eeed333dd..",
        "...dd3332d...",
        "....d3322....",
        ".....322.....",
        "......2......",
        ".............",
        ".............",
    ])
    gem.save("socket_gem.png")


def hud_kit() -> None:
    hud_backing()
    socket_gems()


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    print("generating assets/ui/ ...")
    panel_stone()
    panel_ornate()
    panel_hud()
    buttons()
    bars()
    heart_slot()
    banner()
    divider()
    cursor_spike()
    corner_bracket()
    band_edge()
    vignette()
    ember_motes()
    title_logo()
    hud_kit()


if __name__ == "__main__":
    import sys
    if sys.argv[1:] == ["hud"]:
        os.makedirs(OUT, exist_ok=True)
        hud_kit()
    else:
        main()
