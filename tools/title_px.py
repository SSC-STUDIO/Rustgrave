"""Shared pixel toolkit for the live-title asset generators (gen_title_assets.py,
gen_title_hall.py): the game's palette ramps, mask helpers, ordered dithering and a
small shaded-"part" painter. 1x pixel art only: no anti-aliasing, and every gradient
in the output is an ordered dither between palette steps.
"""

from __future__ import annotations

import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

from gen_ui_kit import PAL  # noqa: E402

OUT = os.path.join(ROOT, "assets", "title")

# ---------------------------------------------------------------- palette ----


def col(key: str) -> tuple[int, int, int]:
    return PAL[key][:3]


INK = (0x0B, 0x09, 0x10)

# Ramps run dark -> light. Five steps is enough for a bevel without gradients.
IRON = [(0x0E, 0x0B, 0x12), (0x1C, 0x16, 0x1E), (0x2E, 0x26, 0x2E), (0x4A, 0x3E, 0x44), (0x6B, 0x5A, 0x5E)]
RUST = [(0x16, 0x0C, 0x0A), (0x3A, 0x20, 0x12), (0x5A, 0x30, 0x18), (0x8B, 0x45, 0x13), (0xB0, 0x62, 0x34)]
RUST_HOT = [(0x2A, 0x14, 0x0C), (0x5A, 0x2A, 0x14), (0x8B, 0x45, 0x13), (0xC8, 0x6A, 0x1C), (0xFF, 0xA8, 0x40)]
STEEL = [(0x10, 0x11, 0x1C), (0x22, 0x26, 0x36), (0x3A, 0x42, 0x54), (0x5C, 0x68, 0x7A), (0x8E, 0x9C, 0xA8)]
NAVY = [(0x0C, 0x0A, 0x14), (0x14, 0x12, 0x20), (0x1E, 0x1B, 0x2E), (0x2A, 0x26, 0x3C), (0x3A, 0x36, 0x50)]
BRICK = [(0x12, 0x0A, 0x0C), (0x24, 0x12, 0x12), (0x3A, 0x1C, 0x18), (0x58, 0x2C, 0x20), (0x7A, 0x3C, 0x28)]
# cool mist that the key light falls through (Palette.TEAL_DEEP / TEAL / FOG, darkened)
MIST = [(0x08, 0x06, 0x0E), (0x0E, 0x0C, 0x18), (0x16, 0x16, 0x26), (0x22, 0x26, 0x38), (0x30, 0x3A, 0x4C),
        (0x44, 0x54, 0x62), (0x5E, 0x76, 0x80), (0x7F, 0xA8, 0xA0)]
# furnace-lit haze
EMBERGLOW = [(0x1C, 0x0E, 0x0C), (0x32, 0x16, 0x10), (0x52, 0x24, 0x12), (0x7A, 0x36, 0x14),
             (0xA8, 0x4E, 0x14), (0xD8, 0x7A, 0x1C), (0xFF, 0xB0, 0x44)]
EMBER = col("c")
ORANGE = col("b")
BONE = col("e")
ASH = col("d")

BAYER4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], np.float32) / 16.0 + 1 / 32.0
_BAYER8 = None


def _bayer8() -> np.ndarray:
    global _BAYER8
    if _BAYER8 is None:
        m = np.array([[0, 2], [3, 1]], np.float32)
        for _ in range(2):
            m = np.block([[4 * m, 4 * m + 2], [4 * m + 3, 4 * m + 1]])
        _BAYER8 = (m + 0.5) / 64.0
    return _BAYER8


def bayer_field(w: int, h: int, size: int = 8) -> np.ndarray:
    m = _bayer8() if size == 8 else BAYER4
    ys, xs = np.mgrid[0:h, 0:w]
    return m[ys % m.shape[0], xs % m.shape[1]]


def lerp3(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def ramp_pick(ramp, idx: np.ndarray) -> np.ndarray:
    arr = np.array(ramp, np.uint8)
    return arr[np.clip(idx, 0, len(ramp) - 1)]


def ramp_dither(field: np.ndarray, ramp, size: int = 8) -> np.ndarray:
    """Scalar field (0..len(ramp)-1) -> RGB through the ramp, ordered-dithering
    between neighbouring steps so smooth fields become banded pixel art."""
    h, w = field.shape
    f = np.clip(field, 0, len(ramp) - 1 - 1e-4)
    idx = np.floor(f + bayer_field(w, h, size) - 0.5 + 0.5 * 0).astype(np.int32)
    base = np.floor(f).astype(np.int32)
    frac = f - base
    pick_hi = frac > bayer_field(w, h, size)
    idx = base + pick_hi.astype(np.int32)
    return ramp_pick(ramp, idx)


# ------------------------------------------------------------------ masks ----


def mask_poly(w: int, h: int, pts) -> np.ndarray:
    im = Image.new("L", (w, h), 0)
    ImageDraw.Draw(im).polygon([(float(x), float(y)) for x, y in pts], fill=255)
    return np.array(im) > 0


def mask_rect(w: int, h: int, x0: float, y0: float, x1: float, y1: float) -> np.ndarray:
    m = np.zeros((h, w), bool)
    xi0, yi0 = int(max(0, math.floor(x0))), int(max(0, math.floor(y0)))
    xi1, yi1 = int(min(w, math.ceil(x1))), int(min(h, math.ceil(y1)))
    if xi1 > xi0 and yi1 > yi0:
        m[yi0:yi1, xi0:xi1] = True
    return m


def mask_ellipse(w: int, h: int, cx: float, cy: float, rx: float, ry: float) -> np.ndarray:
    ys, xs = np.mgrid[0:h, 0:w]
    return ((xs + 0.5 - cx) / max(rx, 0.5)) ** 2 + ((ys + 0.5 - cy) / max(ry, 0.5)) ** 2 <= 1.0


def mask_line(w: int, h: int, p0, p1, width: float = 1) -> np.ndarray:
    im = Image.new("L", (w, h), 0)
    ImageDraw.Draw(im).line([(float(p0[0]), float(p0[1])), (float(p1[0]), float(p1[1]))],
                            fill=255, width=max(1, int(round(width))))
    return np.array(im) > 0


def pipe_fields(w: int, h: int, p0, p1, radius: float):
    """Pipe between two points -> (mask, across, along). `across` is the signed
    distance to the axis (px), `along` the position along it from p0."""
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    px, py = xs + 0.5, ys + 0.5
    ax, ay = p1[0] - p0[0], p1[1] - p0[1]
    length = math.hypot(ax, ay)
    ux, uy = ax / length, ay / length
    dx, dy = px - p0[0], py - p0[1]
    along = dx * ux + dy * uy
    across = -dx * uy + dy * ux
    mask = (np.abs(across) <= radius) & (along >= 0) & (along <= length)
    return mask, across, along


def blur3(a: np.ndarray) -> np.ndarray:
    p = np.pad(a, 1, mode="edge")
    out = np.zeros_like(a, np.float32)
    for dy in range(3):
        for dx in range(3):
            out += p[dy:dy + a.shape[0], dx:dx + a.shape[1]]
    return out / 9.0


def inside_distance(mask: np.ndarray, maxd: int) -> np.ndarray:
    """1 on the outermost pixels of the mask, 2 one step in, ... (capped)."""
    d = np.zeros(mask.shape, np.int16)
    cur = mask.copy()
    for i in range(1, maxd + 1):
        d[cur] = i
        pad = np.pad(cur, 1, constant_values=True)  # image borders never erode
        cur = cur & pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:]
        if not cur.any():
            break
    return d


# ---------------------------------------------------------------- painter ----


class Painter:
    """RGBA canvas that paints shaded 'parts' in painter's order."""

    def __init__(self, w: int, h: int, seed: int = 1) -> None:
        self.w, self.h = w, h
        self.px = np.zeros((h, w, 4), np.uint8)
        self.rng = np.random.default_rng(seed)

    def opaque(self) -> np.ndarray:
        return self.px[:, :, 3] > 0

    def fill_rgb(self, rgb) -> None:
        self.px[:, :, :3] = rgb
        self.px[:, :, 3] = 255

    def noise_field(self) -> np.ndarray:
        """Unit-variance noise made of clustered patches (70%) plus a little grain
        (30%): weathering that reads as stains, not salt-and-pepper."""
        blob = self.rng.random((self.h, self.w)).astype(np.float32)
        blob = blur3(blur3(blur3(blob)))
        blob = (blob - blob.mean()) / (blob.std() + 1e-6)
        grain = (self.rng.random((self.h, self.w)).astype(np.float32) - 0.5) * 3.46
        return blob * 0.85 + grain * 0.5

    def part(self, mask, ramp, *, light=(-0.55, -0.83), bevel=2, base=None, strength=1.6,
             outline=INK, noise=0.0, tone_grad=None, tone_bias=0.0) -> None:
        """Paint `mask` with a bevel-shaded ramp. `light` points *toward* the light."""
        if not mask.any():
            return
        n = len(ramp)
        d = inside_distance(mask, bevel + 1)
        height = np.clip((d - 1) / max(bevel, 1), 0.0, 1.0).astype(np.float32)
        height = blur3(height)
        gy, gx = np.gradient(height)
        facing = -(gx * light[0] + gy * light[1])
        peak = float(np.abs(facing[mask]).max())
        facing = facing / max(peak, 1e-6)
        if base is None:
            base = (n - 1) * 0.5
        t = np.full(mask.shape, base + tone_bias, np.float32)
        t += facing * strength * (1.0 - height * 0.35)
        if noise > 0:
            t += self.noise_field() * noise * 0.55
        if tone_grad is not None:
            ys = np.arange(self.h, dtype=np.float32)[:, None]
            t = t + tone_grad(ys)
        idx = np.clip(np.rint(t), 0, n - 1).astype(np.int32)
        rgb = ramp_pick(ramp, idx)
        self.px[mask, :3] = rgb[mask]
        self.px[mask, 3] = 255
        if outline is not None:
            edge = mask & (d <= 1)
            self.px[edge, :3] = outline
            self.px[edge, 3] = 255

    def profile(self, mask, v, prof, ramp, *, outline=INK, noise=0.0, bias=0) -> None:
        """Paint a cylinder-like part: `v` is -1..1 across the part, `prof` a list of
        ramp indices sampled left->right over that range."""
        if not mask.any():
            return
        k = len(prof)
        bins = np.clip(((v + 1.0) * 0.5 * k).astype(np.int32), 0, k - 1)
        idx = np.array(prof, np.int32)[bins] + bias
        if noise > 0:
            idx = idx + np.rint(self.noise_field() * noise * 0.55).astype(np.int32)
        rgb = ramp_pick(ramp, np.clip(idx, 0, len(ramp) - 1))
        self.px[mask, :3] = rgb[mask]
        self.px[mask, 3] = 255
        if outline is not None:
            d = inside_distance(mask, 2)      # 1 = outermost ring only (needs maxd >= 2)
            edge = mask & (d <= 1)
            self.px[edge, :3] = outline

    def flat(self, mask, color, alpha: int = 255) -> None:
        self.px[mask, :3] = color
        self.px[mask, 3] = alpha

    def line(self, p0, p1, color, width: int = 1) -> None:
        self.flat(mask_line(self.w, self.h, p0, p1, width), color)

    def dither_flat(self, mask, color, density, size: int = 8) -> None:
        field = bayer_field(self.w, self.h, size)
        dens = density if isinstance(density, np.ndarray) else np.full((self.h, self.w), density, np.float32)
        sel = mask & (dens > field)
        self.px[sel, :3] = color
        self.px[sel, 3] = 255

    def image(self) -> Image.Image:
        return Image.fromarray(self.px, "RGBA")

    def save(self, name: str) -> None:
        save_image(self.image(), name)


def save_image(img: Image.Image, name: str) -> None:
    os.makedirs(OUT, exist_ok=True)
    img.save(os.path.join(OUT, name))
    print(f"  {name:<22} {img.width}x{img.height}")


def outline_pass(p: Painter, color=INK) -> None:
    """1px rim around the whole silhouette, drawn on the outermost opaque pixels."""
    solid = p.opaque()
    pad = np.pad(solid, 1)
    edge = solid & ~(pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])
    p.px[edge, :3] = color
