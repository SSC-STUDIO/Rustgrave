#!/usr/bin/env python3
"""Bake Rustgrave's original, text-free physical UI carriers with Pillow.

All artwork is drawn on a half-size integer canvas, then enlarged with NEAREST.
There are no external source images, font files, random seeds from the clock, or
AI services. Shape, directional lighting, edge wear and binding are authored
separately; the reading fields deliberately receive very little texture.

    python tools/gen_ui_object_textures.py
    python tools/gen_ui_object_textures.py --check
    python tools/gen_ui_object_textures.py --preview screenshots/peek/ui-upgrade/objects/contact.png

The preview is an ignored review artifact. --check never rewrites the assets:
it regenerates them in memory, compares their PNG bytes, dimensions, RGBA mode,
transparent outer boundary, and the exact 2-by-2 pixel-cell invariant.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import math
import random
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/ui/objects"
SIZES = {
    "board": (1020, 640),
    "ledger": (960, 560),
    "plate": (1120, 640),
    "journal": (880, 580),
    "letter": (640, 420),
    "paper": (460, 480),
}
NEAREST = Image.Resampling.NEAREST


def rgba(color: str, alpha: int = 255) -> tuple[int, int, int, int]:
    value = color.lstrip("#")
    return (*[int(value[i:i + 2], 16) for i in (0, 2, 4)], alpha)


def shift(color: str | tuple, amount: float) -> tuple[int, int, int, int]:
    source = rgba(color) if isinstance(color, str) else color
    return (*[max(0, min(255, round(v + amount))) for v in source[:3]],
            source[3] if len(source) == 4 else 255)


def poly_mask(size: tuple[int, int], points: list[tuple]) -> Image.Image:
    mask = Image.new("L", size)
    ImageDraw.Draw(mask).polygon(points, fill=255)
    return mask


def cut_rect(x: int, y: int, right: int, bottom: int, cut: int = 5) -> list[tuple]:
    return [(x + cut, y), (right - cut, y), (right, y + cut),
            (right, bottom - cut), (right - cut, bottom),
            (x + cut, bottom), (x, bottom - cut), (x, y + cut)]


def fill_poly(im: Image.Image, points: list[tuple], fill, outline=None, width=1):
    draw = ImageDraw.Draw(im)
    draw.polygon(points, fill=fill)
    if outline is not None:
        draw.line(points + points[:1], fill=outline, width=width)


def on_mask(im: Image.Image, layer: Image.Image, mask: Image.Image):
    alpha = ImageChops.multiply(layer.getchannel("A"), mask)
    layer.putalpha(alpha)
    im.alpha_composite(layer)


def shadow(im: Image.Image, mask: Image.Image, offset=(2, 4), radius=3, strength=125):
    """A short, pixelated cast shadow, wholly inside the source canvas."""
    translated = Image.new("L", im.size)
    translated.paste(mask, offset)
    translated = translated.filter(ImageFilter.GaussianBlur(radius))
    translated = translated.point(lambda v: round(v * strength / 255))
    translated.putpixel((0, 0), 0)
    rim = ImageDraw.Draw(translated)
    rim.rectangle((0, 0, im.width - 1, im.height - 1), outline=0)
    color = Image.new("RGBA", im.size, rgba("#08060B", 0))
    color.putalpha(translated)
    im.alpha_composite(color)


def material(im: Image.Image, mask: Image.Image, base: str, seed: int,
             kind="iron", amplitude=2.0):
    """Directional material, with broad tonal masses instead of star-like specks."""
    rng = random.Random(seed)
    w, h = im.size
    coarse = [[rng.uniform(-1, 1) for _ in range(w // 18 + 2)]
              for _ in range(h // 18 + 2)]
    out = Image.new("RGBA", im.size)
    px, mp = out.load(), mask.load()
    origin = rgba(base)
    for y in range(h):
        cy, fy = divmod(y, 18)
        fy /= 18
        for x in range(w):
            if not mp[x, y]:
                continue
            cx, fx = divmod(x, 18)
            fx /= 18
            top = coarse[cy][cx] * (1 - fx) + coarse[cy][cx + 1] * fx
            bot = coarse[cy + 1][cx] * (1 - fx) + coarse[cy + 1][cx + 1] * fx
            field = top * (1 - fy) + bot * fy
            directional = 2.0 - 3.5 * y / max(h, 1) - 1.2 * x / max(w, 1)
            if kind == "iron":
                grain = math.sin(y * 0.72) * 0.65 + math.sin(y * .11) * .45
            elif kind == "leather":
                grain = math.sin(x * .9 + math.sin(y * .7)) * .5
                directional *= 1.4
            else:
                grain = math.sin(y * 2.4 + x * .08) * .28
                directional *= .75
            tone = round(directional + amplitude * field + grain)
            px[x, y] = shift(origin, tone)
    im.alpha_composite(out)


def rivet(im: Image.Image, x: int, y: int, radius=5, brass=False, slot=False):
    d = ImageDraw.Draw(im)
    rim, body, light = ("#382819", "#80603C", "#B99B65") if brass else (
        "#13151B", "#665C54", "#A39B84")
    d.ellipse((x-radius-2, y-radius-1, x+radius+2, y+radius+3), fill=rgba("#0C0D12"))
    d.ellipse((x-radius-1, y-radius-1, x+radius+1, y+radius+1), fill=rgba(rim))
    d.ellipse((x-radius, y-radius, x+radius, y+radius), fill=rgba(body))
    d.arc((x-radius, y-radius, x+radius, y+radius), 190, 305, fill=rgba(light), width=2)
    d.arc((x-radius+1, y-radius+1, x+radius, y+radius), 8, 110,
          fill=rgba("#302A29"), width=2)
    if slot:
        d.line((x-3, y+1, x+3, y-2), fill=rgba("#201B1B"), width=2)
        d.line((x-2, y+2, x+3, y), fill=rgba("#A49070"))
    else:
        d.line((x-2, y-2, x+1, y-3), fill=rgba(light))


def metal_wear(im: Image.Image, mask: Image.Image, seed: int, cold=False):
    """Irregular corrosion islands and hammer facets constrained to the rim."""
    rng = random.Random(seed)
    w, h = im.size
    layer = Image.new("RGBA", im.size)
    d = ImageDraw.Draw(layer)
    rust = ["#493229", "#623D2D", "#79462D", "#985D36"]
    if cold:
        rust = ["#343B40", "#4B4940", "#63503B", "#806042"]
    for i in range(165 if not cold else 82):
        side = rng.randrange(4)
        t = rng.random()
        depth = rng.choice([5, 6, 7, 9, 11, 13])
        x, y = ((round(9+t*(w-18)), depth) if side == 0 else
                (round(9+t*(w-18)), h-depth-7) if side == 1 else
                (depth, round(10+t*(h-25))) if side == 2 else
                (w-depth-3, round(10+t*(h-25))))
        r = rng.randrange(2, 8)
        outline = [(x-r, y), (x-r+2, y-r//2), (x+1, y-r),
                   (x+r, y-1), (x+r-1, y+r//2), (x-1, y+r)]
        d.polygon(outline, fill=rgba(rng.choice(rust), rng.randrange(110, 205)))
        if i % 3 == 0:
            d.line((x-r+1, y-1, x, y-r//2), fill=rgba(rust[-1], 165))
    # Flattened impacts: a dark lower facet and a lit upper cut, never confetti.
    for _ in range(85):
        side = rng.randrange(4)
        x = rng.randrange(16, w-16)
        y = rng.choice([rng.randrange(6, 15), rng.randrange(h-21, h-12)])
        if side > 1:
            x = rng.choice([rng.randrange(6, 15), rng.randrange(w-18, w-8)])
            y = rng.randrange(18, h-22)
        length = rng.randrange(2, 7)
        d.line((x, y+1, x+length, y+2), fill=rgba("#17171B", 190))
        d.line((x, y, x+length-1, y), fill=rgba("#A08B70" if not cold else "#849291", 155))
    on_mask(im, layer, mask)


def board(size: tuple[int, int]) -> Image.Image:
    w, h = size
    im = Image.new("RGBA", size)
    shape = cut_rect(4, 3, w-7, h-10, 8)
    mask = poly_mask(size, shape)
    shadow(im, mask, offset=(2, 4), radius=3, strength=160)
    fill_poly(im, [(x, y+4) for x, y in shape], rgba("#17151A"), rgba("#09080C"))
    material(im, mask, "#524236", 710, amplitude=4.5)
    d = ImageDraw.Draw(im)
    # Thick forged edge: bright upper compression, oxidised downward return.
    d.line(shape[:4], fill=rgba("#756655"), width=2)
    d.line([shape[0], shape[-1], shape[-2]], fill=rgba("#99846A"), width=2)
    d.line(shape[3:7], fill=rgba("#241E20"), width=3)
    inner = cut_rect(12, 11, w-15, h-19, 5)
    inner_mask = poly_mask(size, inner)
    material(im, inner_mask, "#29262A", 711, amplitude=1.6)
    d = ImageDraw.Draw(im)
    d.line(inner+inner[:1], fill=rgba("#15151B"), width=2)
    d.line([(14, h-23), (14, 17), (18, 13), (w-20, 13)], fill=rgba("#625347"))
    d.line([(18, h-21), (w-20, h-21), (w-17, h-24)], fill=rgba("#6B5742"))
    metal_wear(im, mask, 712)
    # Four broad, individually seated iron rivets rather than an ornamental frame.
    for x, y in [(15, 15), (w-18, 15), (15, h-23), (w-18, h-23)]:
        rivet(im, x, y, 5)
    # A few old clamp marks remain only in the lower lip.
    for x in [w//3-7, 2*w//3+5]:
        d.rectangle((x, h-17, x+13, h-12), fill=rgba("#211B1C"))
        d.line((x+1, h-17, x+12, h-17), fill=rgba("#8B6E49"))
    return im


def plate(size: tuple[int, int]) -> Image.Image:
    w, h = size
    im = Image.new("RGBA", size)
    outer = cut_rect(4, 3, w-7, h-10, 4)
    mask = poly_mask(size, outer)
    shadow(im, mask, strength=160)
    fill_poly(im, [(x, y+3) for x, y in outer], rgba("#141A22"))
    material(im, mask, "#4C555A", 181, amplitude=3)
    d = ImageDraw.Draw(im)
    d.line(outer[:3], fill=rgba("#8A9189"), width=2)
    d.line([outer[0], outer[-1], outer[-2]], fill=rgba("#727F7E"), width=2)
    d.line(outer[3:7], fill=rgba("#1A222D"), width=3)
    inner = cut_rect(12, 13, w-15, h-20, 4)
    material(im, poly_mask(size, inner), "#252E36", 182, amplitude=1.4)
    d = ImageDraw.Draw(im)
    d.line(inner+inner[:1], fill=rgba("#121B26"), width=2)
    d.line([(13, h-23), (13, 19), (17, 15), (w-20, 15)], fill=rgba("#74817D"))
    d.line([(17, h-22), (w-20, h-22), (w-17, h-25)], fill=rgba("#59666B"))
    metal_wear(im, mask, 183, cold=True)
    d = ImageDraw.Draw(im)
    # Folded corner brackets carry the bolt; their broad facets read at 540p.
    for sx, sy in [(1, 1), (-1, 1), (1, -1), (-1, -1)]:
        cx = 13 if sx == 1 else w-16
        cy = 15 if sy == 1 else h-23
        bracket = [(cx-8*sx, cy-8*sy), (cx+9*sx, cy-8*sy),
                   (cx+9*sx, cy-3*sy), (cx+3*sx, cy-3*sy),
                   (cx+3*sx, cy+8*sy), (cx-8*sx, cy+8*sy)]
        fill_poly(im, bracket, rgba("#3A444A"), rgba("#101923"))
        d.line(bracket[:3], fill=rgba("#87918B"))
        rivet(im, cx, cy, 4, slot=True)
    # Two punched suspension holes: visibly cut through the cool rolled lip.
    for x in [w//3, 2*w//3]:
        d.rounded_rectangle((x-8, 5, x+8, 12), radius=3, fill=rgba("#101820"))
        d.line((x-6, 5, x+5, 5), fill=rgba("#8A9186"))
        d.line((x-6, 12, x+5, 12), fill=rgba("#72817E"))
        d.rectangle((x-5, 7, x+5, 9), fill=(0, 0, 0, 0))
    # Long rolling marks are confined to the metal lip, never the chapter field.
    for y in [h-17, h-15]:
        d.line((35, y, w-35, y), fill=rgba("#66716F" if y % 2 else "#343F48"))
    return im


def cover(im: Image.Image, mask: Image.Image, seed: int, old=False):
    material(im, mask, "#3D271E" if old else "#4B2B1D", seed, kind="leather", amplitude=4)
    rng = random.Random(seed)
    w, h = im.size
    layer = Image.new("RGBA", im.size)
    d = ImageDraw.Draw(layer)
    # Leather grain is clustered in the visible cover, not spread over the pages.
    for _ in range(900):
        x, y = rng.randrange(4, w-5), rng.randrange(4, h-9)
        if 15 < x < w-16 and 15 < y < h-21:
            continue
        d.line((x, y, x+rng.randrange(1, 4), y-1),
               fill=rgba("#815139" if rng.random() > .5 else "#211812", rng.randrange(65, 135)))
    on_mask(im, layer, mask)
    d = ImageDraw.Draw(im)
    # Paired inset tooling and deliberately uneven, waxed thread stitches.
    d.rounded_rectangle((6, 5, w-9, h-13), radius=5,
                        outline=rgba("#21150F"), width=2)
    d.line((12, 7, w-16, 7), fill=rgba("#916047" if not old else "#70513B"))
    thread = "#A08658" if old else "#C29D65"
    for y in [9, h-17]:
        for x in range(16, w-17, 7):
            d.line((x, y, x+3, y+1), fill=rgba(thread))
            d.point((x+4, y+2), fill=rgba("#1B1510"))
    for x in [9, w-12]:
        for y in range(17, h-22, 7):
            d.line((x, y, x+1, y+3), fill=rgba(thread))
    # Abrasion is broad, worn leather at the corners.
    for x, y, dx, dy in [(7, 6, 1, 1), (w-10, 6, -1, 1),
                          (7, h-15, 1, -1), (w-10, h-15, -1, -1)]:
        d.line((x, y+4*dy, x, y, x+5*dx, y), fill=rgba("#8B6345"), width=2)


def page_shape(w: int, h: int, left=True, offset=0, old=False) -> list[tuple]:
    """Each folio bows down into the binding; outer edges are individually cut."""
    mid = w//2
    if left:
        points = [(14+offset, 13+offset), (25, 12+offset),
                  (mid-35, 14+offset), (mid-12, 17+offset), (mid-3, 21+offset),
                  (mid-3, h-24+offset), (mid-12, h-20+offset),
                  (mid-39, h-19+offset), (17, h-17+offset), (12+offset, h-20+offset)]
    else:
        points = [(mid+3, 21+offset), (mid+12, 17+offset), (mid+35, 14+offset),
                  (w-27, 12+offset), (w-15-offset, 14+offset),
                  (w-13-offset, h-20+offset), (w-19, h-17+offset),
                  (mid+39, h-19+offset), (mid+12, h-20+offset), (mid+3, h-24+offset)]
    if old:
        # Nicks expose older sheets, mostly outside the text's 36px side inset.
        outer = [(15, 48), (13, 51), (15, 54), (14, 111), (12, 114),
                 (14, 117), (13, h-37)] if left else [
                 (w-15, h-37), (w-13, 173), (w-15, 170),
                 (w-14, 79), (w-12, 76), (w-14, 73), (w-15, 43)]
        points += outer
    return points


def folio(im: Image.Image, mask: Image.Image, seed: int, left=True, old=False):
    w, h = im.size
    mid = w//2
    rng = random.Random(seed)
    base = (215, 199, 162) if old else (226, 212, 179)
    tex = Image.new("RGBA", im.size)
    p, mp = tex.load(), mask.load()
    # Light falls over a convex page and drops steeply into the sewn gutter.
    for y in range(h):
        for x in range(w):
            if not mp[x, y]:
                continue
            gutter = abs(x-mid)
            shade = -37*math.exp(-gutter/8) - 8*math.exp(-gutter/28)
            shade += 3.5*math.sin((x/max(w, 1))*math.pi) - 3*y/h
            edge = min(x-12, w-13-x, y-12, h-17-y)
            shade -= max(0, 6-edge) * .55
            fiber = math.sin(y*1.7+x*.13) * .45 + math.sin(x*.19+y*.43) * .35
            val = round(shade+fiber)
            p[x, y] = (*[max(0, min(255, c+val)) for c in base], 255)
    im.alpha_composite(tex)
    # Sparse, low-contrast horizontal fibres follow the paper grain.
    layer = Image.new("RGBA", im.size)
    d = ImageDraw.Draw(layer)
    for _ in range(550):
        x, y = rng.randrange(12, w-12), rng.randrange(13, h-18)
        d.line((x, y, x+rng.randrange(1, 7), y), fill=rgba("#7E6745", 7 if old else 5))
    # Oxidised page edges and foxing are kept in the outer 24 pixels.
    for _ in range(35 if old else 14):
        x = rng.choice([rng.randrange(12, 20), rng.randrange(w-21, w-13)])
        y = rng.randrange(20, h-25)
        r = rng.randrange(1, 4)
        d.ellipse((x-r, y-r, x+r, y+r), fill=rgba("#916F45", rng.randrange(15, 36)))
    on_mask(im, layer, mask)


def book(size: tuple[int, int], old=False) -> Image.Image:
    w, h = size
    im = Image.new("RGBA", size)
    middle = w//2
    cover_points = [(10, 3), (middle-13, 5), (middle, 8), (middle+13, 5),
                    (w-13, 3), (w-5, 10), (w-5, h-16), (w-12, h-9),
                    (middle+15, h-11), (middle, h-14), (middle-15, h-11),
                    (10, h-9), (3, h-16), (3, 10)]
    mask = poly_mask(size, cover_points)
    shadow(im, mask, offset=(2, 4), radius=3, strength=155)
    fill_poly(im, [(x, y+4) for x, y in cover_points], rgba("#170F0E"), rgba("#100C0C"))
    cover(im, mask, 118 if old else 91, old=old)
    d = ImageDraw.Draw(im)
    # Closed cover's joint protrudes above and below the text block.
    d.polygon([(middle-12, 6), (middle, 9), (middle+12, 6),
               (middle+10, h-11), (middle, h-14), (middle-10, h-11)], fill=rgba("#20150F"))
    # Real layered folio edges: six separate contours, lit at their lower return.
    for offset in [4, 3, 2, 1, 0]:
        for left in [True, False]:
            points = page_shape(w, h, left, offset)
            color = "#B3A07A" if offset % 2 else "#CBBA94"
            fill_poly(im, points, rgba(color), rgba("#897551"))
    # Top page is continuous, with bowed edges drawn into the spine.
    for left in [True, False]:
        points = page_shape(w, h, left)
        folio(im, poly_mask(size, points), 211 + int(left) + int(old)*7, left, old)
        d = ImageDraw.Draw(im)
        d.line(points[:5], fill=rgba("#F2E4BB" if not old else "#DFCEA5"))
        d.line(points[5:9], fill=rgba("#9E8962"))
    d = ImageDraw.Draw(im)
    # The narrow concave gutter is a curve, not a flat vertical divider.
    gutter = [(middle-3, 21), (middle-1, 55), (middle-2, h//2),
              (middle-1, h-56), (middle-3, h-24), (middle+3, h-24),
              (middle+1, h-56), (middle+2, h//2), (middle+1, 55), (middle+3, 21)]
    d.polygon(gutter, fill=rgba("#4A3522" if not old else "#38281B"))
    d.line([(middle-4, 22), (middle-3, 65), (middle-4, h//2),
            (middle-3, h-57), (middle-4, h-24)], fill=rgba("#9C855B"))
    d.line([(middle+4, 22), (middle+5, h//2), (middle+4, h-24)],
           fill=rgba("#F0DFB1" if not old else "#D9C599"))
    for y in range(33 if old else 42, h-30, 37 if old else 51):
        d.ellipse((middle-4, y-2, middle-1, y+2), fill=rgba("#2A2117"))
        d.ellipse((middle+1, y+4, middle+4, y+8), fill=rgba("#2A2117"))
        d.line((middle-2, y, middle+2, y+6), fill=rgba("#B19A70" if old else "#BC9F6A"), width=2)
        d.point((middle-1, y), fill=rgba("#E1C994"))
    # Frayed cloth bookmark emerges only at the lower binding edge.
    ribbon = [(middle+8, h-23), (middle+16, h-21), (middle+17, h-4),
              (middle+12, h-8), (middle+8, h-4)]
    fill_poly(im, ribbon, rgba("#713B34" if old else "#756B38"), rgba("#30221C"))
    d.line((middle+10, h-20, middle+11, h-8), fill=rgba("#AB6954" if old else "#B2A367"))
    if old:
        # Bruised page nicks expose the stack without putting marks on the text.
        for y in [49, 112, h-39]:
            d.line((13, y, 16, y+2, 13, y+4), fill=rgba("#8F7855"), width=2)
        for y in [75, 171]:
            d.line((w-15, y, w-12, y+2, w-15, y+5), fill=rgba("#8F7855"), width=2)
        # A leather strap and a worn brass buckle stay in the right cover margin.
        cy = h//2+8
        d.rectangle((w-17, cy-10, w-4, cy+10), fill=rgba("#2A1A13"))
        d.line((w-16, cy-9, w-5, cy-9), fill=rgba("#80573A"))
        d.rectangle((w-14, cy-7, w-7, cy+7), fill=rgba("#6F5732"), outline=rgba("#B49B63"), width=2)
        d.rectangle((w-11, cy-4, w-9, cy+4), fill=rgba("#201911"))
        d.line((w-13, cy, w-6, cy), fill=rgba("#C9AC73"))
        for x, y in [(10, 10), (w-12, 10), (10, h-18), (w-12, h-18)]:
            # Small corner tongues remain on leather, outside the page fields.
            d.rectangle((x-3, y-3, x+3, y+3), fill=rgba("#6F5330"))
            d.line((x-3, y-3, x+2, y-3), fill=rgba("#B39A61"))
    return im


def paper_surface(im: Image.Image, mask: Image.Image, seed: int, folded=False):
    w, h = im.size
    material(im, mask, "#DECDA8" if not folded else "#E3D2AE", seed,
             kind="paper", amplitude=1.8)
    layer = Image.new("RGBA", im.size)
    d = ImageDraw.Draw(layer)
    rng = random.Random(seed)
    # Irregular water/handling stains gather at the outer cut, leaving a quiet centre.
    for _ in range(48):
        side = rng.randrange(4)
        x, y = (rng.randrange(8, w-8), rng.choice([6, h-10])) if side < 2 else (
            rng.choice([6, w-10]), rng.randrange(9, h-12))
        rx, ry = rng.randrange(3, 11), rng.randrange(2, 8)
        d.ellipse((x-rx, y-ry, x+rx, y+ry), fill=rgba("#97754B", rng.randrange(9, 28)))
    for _ in range(800):
        x, y = rng.randrange(5, w-5), rng.randrange(5, h-6)
        d.line((x, y, x+rng.randrange(1, 5), y), fill=rgba("#796340", 5))
    # Longer visible deckle fibres point along the edges rather than across text.
    for _ in range(95):
        x = rng.choice([rng.randrange(5, 12), rng.randrange(w-13, w-6)])
        y = rng.randrange(10, h-12)
        d.line((x, y, x, y+rng.randrange(1, 4)), fill=rgba("#8C724F", 47))
    on_mask(im, layer, mask)


def paper(size: tuple[int, int]) -> Image.Image:
    w, h = size
    im = Image.new("RGBA", size)
    # Hand-cut and worn, with an independent curled corner in the upper right.
    outline = [(7, 5), (47, 4), (81, 6), (119, 4), (w-29, 6),
               (w-7, 25), (w-6, 64), (w-8, 111), (w-5, 159),
               (w-7, h-10), (w-35, h-8), (w-77, h-10),
               (w//2, h-7), (49, h-9), (8, h-7), (6, h-49),
               (8, h-99), (5, 99), (7, 59)]
    mask = poly_mask(size, outline)
    shadow(im, mask, offset=(2, 3), radius=2, strength=125)
    fill_poly(im, [(x, y+1) for x, y in outline], rgba("#806A4B"))
    paper_surface(im, mask, 1139)
    d = ImageDraw.Draw(im)
    d.line(outline+outline[:1], fill=rgba("#B39B74"))
    d.line(outline[:5], fill=rgba("#F1E2BE"))
    # Dog ear has an underside, a cast shadow, and a bright rolled ridge.
    d.polygon([(w-29, 6), (w-29, 29), (w-7, 25)], fill=rgba("#B09B75"))
    d.polygon([(w-28, 6), (w-27, 25), (w-8, 24)], fill=rgba("#F0DFB8"))
    d.line((w-29, 6, w-29, 28, w-8, 25), fill=rgba("#8E7854"))
    d.line((w-27, 7, w-26, 24, w-9, 23), fill=rgba("#F7E9C9"))
    # Pin hole lies above the content margin; pin itself remains an animated prop.
    cx, cy = w//2-13, 10
    d.ellipse((cx-3, cy-2, cx+3, cy+3), fill=rgba("#B59E78"))
    d.ellipse((cx-2, cy-1, cx+2, cy+2), fill=rgba("#514536"))
    d.line((cx-1, cy+3, cx+2, cy+3), fill=rgba("#F2E2BC"))
    # A nearly flattened crease at the lower edge, away from the key list.
    d.line((15, h-15, w//2, h-17, w-19, h-14), fill=rgba("#C8B58E"))
    d.line((15, h-14, w//2, h-16, w-19, h-13), fill=rgba("#EADABA"))
    return im


def letter(size: tuple[int, int]) -> Image.Image:
    w, h = size
    im = Image.new("RGBA", size)
    outline = [(7, 5), (w//3, 4), (w-10, 6), (w-6, 31),
               (w-8, h//2), (w-6, h-26), (w-23, h-7),
               (w//2, h-8), (9, h-6), (6, h-35), (8, 45)]
    mask = poly_mask(size, outline)
    shadow(im, mask, offset=(2, 3), radius=2, strength=130)
    fill_poly(im, [(x, y+1) for x, y in outline], rgba("#8C7552"))
    paper_surface(im, mask, 892, folded=True)
    d = ImageDraw.Draw(im)
    d.line(outline+outline[:1], fill=rgba("#B19A74"))
    d.line(outline[:3], fill=rgba("#F6E8C7"))
    # Fold planes are broad and directional; the central body is kept blank.
    fold = Image.new("RGBA", size)
    fd = ImageDraw.Draw(fold)
    fd.polygon([(8, 7), (w-11, 8), (w//2+6, 48)], fill=rgba("#FCEDCB", 62))
    fd.polygon([(8, 8), (w//2+6, 48), (8, 47)], fill=rgba("#9B805B", 15))
    fd.line((9, 8, w//2+6, 48, w-11, 8), fill=rgba("#8F7754", 37))
    fd.line((10, 10, w//2+6, 50, w-12, 10), fill=rgba("#FFF5D7", 86))
    fd.polygon([(9, h-8), (w//2-5, h-49), (w-24, h-8)], fill=rgba("#C8B48F", 30))
    fd.line((10, h-8, w//2-5, h-49, w-24, h-8), fill=rgba("#8E7654", 35))
    fd.line((10, h-6, w//2-5, h-47, w-24, h-6), fill=rgba("#FFF0CD", 76))
    # Faint cross-fold runs below the warning field, with no printed marks.
    fd.line((10, h//2+14, w//2, h//2+13, w-10, h//2+16), fill=rgba("#9C825F", 19))
    fd.line((10, h//2+15, w//2, h//2+14, w-10, h//2+17), fill=rgba("#FFF0CC", 46))
    on_mask(im, fold, mask)
    d = ImageDraw.Draw(im)
    # A lifted lower right corner reveals the dark underside and curled lip.
    d.polygon([(w-24, h-27), (w-7, h-27), (w-24, h-8)], fill=rgba("#9E8864"))
    d.polygon([(w-22, h-25), (w-7, h-27), (w-24, h-10)], fill=rgba("#F2E2BC"))
    d.line((w-24, h-26, w-24, h-9), fill=rgba("#816B4C"))
    d.line((w-22, h-24, w-22, h-12), fill=rgba("#F8ECCD"))
    return im


def generate() -> dict[str, Image.Image]:
    makers = {"board": board, "ledger": lambda s: book(s), "plate": plate,
              "journal": lambda s: book(s, old=True), "letter": letter, "paper": paper}
    return {name: makers[name]((width//2, height//2)).resize((width, height), NEAREST)
            for name, (width, height) in SIZES.items()}


def png_bytes(im: Image.Image) -> bytes:
    stream = io.BytesIO()
    im.save(stream, format="PNG", optimize=False, compress_level=9)
    return stream.getvalue()


def validate(name: str, im: Image.Image):
    if im.mode != "RGBA" or im.size != SIZES[name]:
        raise ValueError(f"{name}: incorrect mode or dimensions: {im.mode} {im.size}")
    doubled = im.resize((im.width//2, im.height//2), NEAREST).resize(im.size, NEAREST)
    if im.tobytes() != doubled.tobytes():
        raise ValueError(f"{name}: artwork broke the 2px cell grid")
    alpha = im.getchannel("A")
    edges = [alpha.crop((0, 0, im.width, 2)), alpha.crop((0, im.height-2, im.width, im.height)),
             alpha.crop((0, 0, 2, im.height)), alpha.crop((im.width-2, 0, im.width, im.height))]
    if any(edge.getbbox() is not None for edge in edges):
        raise ValueError(f"{name}: silhouette or shadow leaves its canvas")
    if alpha.getextrema() != (0, 255):
        raise ValueError(f"{name}: expected both transparent contour and opaque material")


def preview(images: dict[str, Image.Image], path: Path):
    cell_w, cell_h = 600, 430
    contact = Image.new("RGB", (cell_w*3, cell_h*2), "#161820")
    draw = ImageDraw.Draw(contact)
    for index, (name, im) in enumerate(images.items()):
        x, y = index % 3 * cell_w, index // 3 * cell_h
        draw.rectangle((x+10, y+35, x+cell_w-10, y+cell_h-10), fill="#202129")
        scale = min((cell_w-30)/im.width, (cell_h-50)/im.height)
        shown = im.resize((round(im.width*scale), round(im.height*scale)), NEAREST)
        px = x+(cell_w-shown.width)//2
        py = y+37+(cell_h-48-shown.height)//2
        contact.paste(shown, (px, py), shown)
        draw.text((x+18, y+12), f"{name} / {im.width} x {im.height} / 2px cells", fill="#C6B897")
    path.parent.mkdir(parents=True, exist_ok=True)
    contact.save(path)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="compare regenerated bytes and validate the artwork contract")
    parser.add_argument("--preview", type=Path, help="write an ignored six-object contact sheet")
    args = parser.parse_args()
    images = generate()
    if not args.check:
        OUT.mkdir(parents=True, exist_ok=True)
    for name, im in images.items():
        validate(name, im)
        path = OUT / f"{name}.png"
        content = png_bytes(im)
        if args.check:
            if not path.exists() or path.read_bytes() != content:
                raise SystemExit(f"FAIL {path.relative_to(ROOT)}: missing or no longer reproducible")
            with Image.open(path) as stored:
                validate(name, stored)
        else:
            path.write_bytes(content)
        print(f"{'OK' if args.check else 'WROTE'} {path.relative_to(ROOT)} {im.width}x{im.height} "
              f"sha256={hashlib.sha256(content).hexdigest()}")
    if args.preview:
        path = args.preview if args.preview.is_absolute() else ROOT / args.preview
        preview(images, path)
        print(f"PREVIEW {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
