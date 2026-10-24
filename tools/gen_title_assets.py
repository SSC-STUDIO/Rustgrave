#!/usr/bin/env python3
"""Pixel assets for the live title scene (scripts/ui/title_world.gd).

The title used to be one static key-art PNG. It is now a real-time lit scene in a
640x360 SubViewport, and this tool bakes the pieces that read better as
hand-controlled pixel art than as engine shapes (assets/title/*.png):

  gear_big / gear_mid / gear_small   rotation strips: exactly one *spoke period* of
                                     frames, so the loop is seamless and the gears
                                     turn with no sprite rotation (a rotated pixel
                                     sprite breaks its pixels)
  hall_far      the hazy far end of the forge hall + the pale pool under the roof gap
  hall_mid      mid-distance pylons, hanging pipes, a second (lower) bridge
  roof          ceiling trusses with the torn opening the light shaft falls through
  mass_left /   dark foreground machinery, warm-lit on the edge that faces the hall
  mass_right
  bridge        the long iron bridge the knight stands on (deck surface at y=26)
  forge_mouth   the furnace door at the bridge end (tinted / dimmed per variant)
  lantern       two frames: cold cage / lit cage
  steam         six dithered puff frames
  beam          the dithered light shaft (additive in engine)
  vignette      dithered corner darkening

Everything is authored at 1x, NEAREST, no anti-aliasing, on the game's own 16-colour
rust ramp (tools/gen_ui_kit.PAL) plus two cool "mist" tones from scripts/data/palette.gd.
Shading is computed (bevel + light direction + noise) and then quantised to a few
palette steps, so nothing is a smooth gradient; every ramp is an ordered dither.

Run:  python tools/gen_title_assets.py             (everything)
      python tools/gen_title_assets.py gears hall  (subset, by builder-name prefix)
"""

from __future__ import annotations

import math
import sys

import numpy as np
from PIL import Image

from title_px import (BAYER4, BONE, ASH, EMBERGLOW, INK, IRON, MIST, RUST, STEEL, Painter, bayer_field, blur3,
                      inside_distance, mask_ellipse, mask_line, mask_poly, mask_rect, ramp_dither, ramp_pick,
                      save_image)
import gen_title_hall as hall

# ------------------------------------------------------------------ gears ----


def gear_sheet(name: str, radius: float, teeth: int, spokes: int, frames: int, ramp,
               *, hub: float = 0.27, rim: float = 0.15, tooth: float = 0.11,
               spoke: float = 0.12, direction: int = 1, seed: int = 3,
               light=(-0.55, -0.83), cols: int = 8) -> None:
    """A `cols`-wide grid of `frames` rotation frames covering exactly one spoke
    period (a grid, not one long strip: keeps every texture well under 4096px)."""
    ss = 4
    size = int(2 * radius + 8)
    size += size % 2
    hs = size * ss
    c = hs / 2.0
    ys, xs = np.mgrid[0:hs, 0:hs].astype(np.float32)
    dx, dy = xs + 0.5 - c, ys + 0.5 - c
    rr = np.hypot(dx, dy) / ss                        # radius in final px
    phi = np.arctan2(dy, dx)
    r_tip = radius
    th = max(2.5, radius * tooth)
    r_root = r_tip - th
    r_rim_in = r_root - max(3.0, radius * rim)
    r_hub = radius * hub
    spoke_half = max(1.6, radius * spoke * 0.5)
    tooth_p = 2 * math.pi / teeth
    spoke_p = 2 * math.pi / spokes
    assert teeth % spokes == 0, "teeth must be a multiple of spokes for a seamless loop"
    rng = np.random.default_rng(seed)
    n_ang, n_r = 96, int(radius * 1.3) + 2
    speck = rng.random((n_ang, n_r)).astype(np.float32)

    rows = (frames + cols - 1) // cols
    sheet = Image.new("RGBA", (size * cols, size * rows), (0, 0, 0, 0))
    base_idx = (len(ramp) - 1) * 0.5
    cs = size / 2.0
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    rpx = np.hypot(xx + 0.5 - cs, yy + 0.5 - cs)
    for f in range(frames):
        theta = direction * f * spoke_p / frames
        a = phi - theta
        u = np.mod(a, tooth_p) / tooth_p
        edge = np.where(u < 0.14, r_root + th * (u / 0.14),
                        np.where(u < 0.46, r_tip,
                                 np.where(u < 0.60, r_tip - th * ((u - 0.46) / 0.14), r_root)))
        disc = rr <= edge
        sector = np.mod(a + spoke_p / 2, spoke_p) - spoke_p / 2
        across = rr * np.sin(sector)
        along = rr * np.cos(sector)
        taper = 1.0 + 0.45 * np.clip(1.0 - (rr - r_hub) / max(r_rim_in - r_hub, 1.0), 0, 1)
        spoke_mask = (np.abs(across) <= spoke_half * taper) & (along > 0)
        solid = disc & ((rr >= r_rim_in) | (rr <= r_hub) | spoke_mask)

        bevel_w = 3.0 * ss
        d = inside_distance(solid, int(bevel_w) + 1)
        height = np.clip((d - 1) / bevel_w, 0.0, 1.0).astype(np.float32)
        height = blur3(blur3(height))
        gy, gx = np.gradient(height)
        facing = -(gx * light[0] + gy * light[1])
        peak = float(np.abs(facing[solid]).max())
        facing = facing / max(peak, 1e-6)
        # rust mottling is glued to the gear (polar coords), not to the screen
        ai = (np.mod(a, spoke_p) / spoke_p * n_ang).astype(np.int32) % n_ang
        ri = np.clip(rr.astype(np.int32), 0, n_r - 1)
        s = speck[ai, ri]
        mot = np.where(s < 0.09, -1.1, np.where(s > 0.93, 0.8, 0.0))
        tone = base_idx + facing * 1.6 * (1.0 - height * 0.3) + mot
        tone += np.where((rr >= r_rim_in) & (rr <= r_root), 0.4, 0.0)       # raised rim
        tone += np.where(rr <= r_hub, 0.3, 0.0)
        # a dark groove just inside the rim ring and around the hub: reads as a cast plate
        groove = (np.abs(rr - (r_rim_in + 1.4)) < 0.75) | (np.abs(rr - (r_hub + 0.6)) < 0.7)
        tone -= np.where(groove, 1.1, 0.0)

        blocks = solid.reshape(size, ss, size, ss)
        cover = blocks.mean(axis=(1, 3))
        tsum = (tone * solid).reshape(size, ss, size, ss).sum(axis=(1, 3))
        csum = np.maximum(blocks.sum(axis=(1, 3)), 1)
        tone_f = tsum / csum
        final_solid = cover >= 0.5
        idx = np.clip(np.rint(tone_f), 0, len(ramp) - 1).astype(np.int32)
        rgb = ramp_pick(ramp, idx)
        img = np.zeros((size, size, 4), np.uint8)
        img[final_solid, :3] = rgb[final_solid]
        img[final_solid, 3] = 255
        pad = np.pad(final_solid, 1)
        rim_px = final_solid & ~(pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])
        img[rim_px, :3] = INK
        # hub: dark axle, ring, bolts on the spoke angles
        axle_r = max(2.2, r_hub * 0.32)
        img[(rpx <= axle_r), :3] = ramp[0]
        ring = (rpx > axle_r) & (rpx <= axle_r + 1.0)
        img[ring & final_solid, :3] = INK
        bolt_r = r_hub * 0.68
        for k in range(spokes * 2):
            ang = theta + k * spoke_p / 2.0
            bx, by = cs + bolt_r * math.cos(ang), cs + bolt_r * math.sin(ang)
            bolt = ((xx + 0.5 - bx) ** 2 + (yy + 0.5 - by) ** 2) <= 1.1 ** 2
            img[bolt & final_solid, :3] = ramp[-1] if k % 2 == 0 else ramp[1]
        sheet.paste(Image.fromarray(img, "RGBA"), ((f % cols) * size, (f // cols) * size))
    save_image(sheet, name)
    print(f"      frames={frames} grid={cols}x{rows} frame={size}px period={360 / spokes:.1f} deg "
          f"step={360 / spokes / frames:.2f} deg")


def build_gears() -> None:
    print("gears")
    gear_sheet("gear_big.png", 66, 24, 8, 32, RUST, hub=0.28, rim=0.14, tooth=0.10, spoke=0.15, direction=1,
               seed=11, cols=8)
    gear_sheet("gear_mid.png", 42, 16, 8, 32, IRON, hub=0.30, rim=0.17, tooth=0.12, spoke=0.16, direction=-1,
               seed=12, light=(-0.5, -0.86), cols=8)
    gear_sheet("gear_small.png", 26, 12, 6, 24, RUST, hub=0.34, rim=0.2, tooth=0.14, spoke=0.2, direction=1,
               seed=13, cols=6)


# ----------------------------------------------------------------- scenery ----


def build_hall() -> None:
    print("hall")
    hall.build_hall_far()
    hall.build_pit_river()
    hall.build_hall_mid()
    hall.build_roof()


def build_masses() -> None:
    print("masses")
    hall.build_mass_left()
    hall.build_mass_right()


def build_bridge() -> None:
    print("bridge")
    hall.build_bridge()


# ------------------------------------------------------------ small sprites ----


def build_forge_mouth() -> None:
    """Interior of the furnace door (the mass has an arch cut out in front of it)."""
    print("forge_mouth")
    W, H = 60, 66
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    rng = np.random.default_rng(91)
    lumps = blur3(blur3(rng.random((H, W)).astype(np.float32))) * 2.0 - 1.0
    vert = np.interp(ys, [0, 18, 40, 60, 66], [0.4, 1.2, 3.0, 4.6, 5.8])
    field = vert + lumps * 1.6 + np.exp(-(((xs - 30.0) / 26.0) ** 2)) * 0.8
    rgb = ramp_dither(np.clip(field, 0, len(EMBERGLOW) - 1.01), EMBERGLOW)
    px = np.zeros((H, W, 4), np.uint8)
    px[:, :, :3] = rgb
    px[:, :, 3] = 255
    # flame tongues: lighter jagged shapes rising off the coals
    p = Painter(W, H, seed=92)
    p.px = px
    for cx, hgt, wd in [(10, 26, 7), (22, 36, 9), (34, 30, 8), (46, 38, 9), (54, 22, 6)]:
        tip = H - 8 - hgt
        pts = [(cx - wd, H - 6), (cx - wd * 0.5, H - 6 - hgt * 0.45), (cx - wd * 0.2, tip + hgt * 0.25),
               (cx, tip), (cx + wd * 0.2, tip + hgt * 0.3), (cx + wd * 0.55, H - 6 - hgt * 0.5), (cx + wd, H - 6)]
        p.flat(mask_poly(W, H, pts), EMBERGLOW[5])
        inner = [(cx - wd * 0.5, H - 6), (cx, tip + hgt * 0.45), (cx + wd * 0.5, H - 6)]
        p.flat(mask_poly(W, H, inner), EMBERGLOW[6])
    # coal bed
    p.flat(mask_rect(W, H, 0, H - 7, W, H), EMBERGLOW[4])
    for x in range(0, W, 3):
        if (x * 17) % 7 < 3:
            p.px[H - 7 + (x % 3), x, :3] = EMBERGLOW[6]
    # hearth bars in front
    for x in range(5, W, 12):
        p.flat(mask_rect(W, H, x, 0, x + 2, H), (0x0A, 0x08, 0x10))
        p.flat(mask_rect(W, H, x, 0, x + 1, H), IRON[2])
    p.save("forge_mouth.png")


LANTERN = [
    "....0000....",
    "...033330...",
    "...03..30...",
    "....0000....",
    "...022220...",
    "..03333330..",
    "..02222220..",
    "..02GGGG20..",
    "..02GHHG20..",
    "..02GHHG20..",
    "..02GHHG20..",
    "..02GGGG20..",
    "..02222220..",
    "...023320...",
    "....0220....",
    "....0110....",
    ".....00.....",
]


def build_lantern() -> None:
    """Two frames, 12x17 each: [cold cage | lit cage]."""
    print("lantern")
    cold = {"G": (0x16, 0x14, 0x22), "H": (0x22, 0x1E, 0x32), "0": INK, "1": IRON[1], "2": IRON[2], "3": IRON[3]}
    lit = {"G": (0xE8, 0x7C, 0x14), "H": (0xFF, 0xE0, 0x9A), "0": INK, "1": IRON[1], "2": IRON[2], "3": IRON[3]}
    h, w = len(LANTERN), len(LANTERN[0])
    sheet = Image.new("RGBA", (w * 2, h), (0, 0, 0, 0))
    for fi, table in enumerate((cold, lit)):
        px = np.zeros((h, w, 4), np.uint8)
        for y, row in enumerate(LANTERN):
            for x, ch in enumerate(row):
                if ch == ".":
                    continue
                px[y, x, :3] = table[ch]
                px[y, x, 3] = 255
        sheet.paste(Image.fromarray(px, "RGBA"), (fi * w, 0))
    save_image(sheet, "lantern.png")


def build_steam() -> None:
    print("steam")
    n, size = 6, 28
    rng = np.random.default_rng(101)
    base_noise = blur3(blur3(rng.random((size, size)).astype(np.float32)))
    base_noise = (base_noise - base_noise.mean()) * 4.0
    sheet = Image.new("RGBA", (size * n, size), (0, 0, 0, 0))
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float32)
    for k in range(n):
        cx, cy = size / 2.0, size - 8.0 - k * 1.6
        r = 3.0 + k * 2.3
        dist = np.hypot(xs + 0.5 - cx, (ys + 0.5 - cy) * 1.1) / r
        dens = np.clip(1.0 - dist, 0, 1) ** 0.65 * (1.0 - 0.10 * k) + base_noise * 0.10
        keep = dens > (BAYER4[ys.astype(int) % 4, xs.astype(int) % 4] * 0.9 + 0.08)
        px = np.zeros((size, size, 4), np.uint8)
        tone = np.clip((dens - 0.15) * 1.6, 0, 1)
        col_hi = np.array(BONE, np.float32)
        col_lo = np.array((0x8A, 0x7E, 0x82), np.float32)
        rgb = (col_lo[None, None, :] * (1 - tone[:, :, None]) + col_hi[None, None, :] * tone[:, :, None])
        px[keep, :3] = rgb[keep].astype(np.uint8)
        px[keep, 3] = 255
        sheet.paste(Image.fromarray(px, "RGBA"), (k * size, 0))
    save_image(sheet, "steam.png")


def build_beam() -> None:
    """The light shaft: slanted band, dithered into four alpha tiers. White; tinted in engine."""
    print("beam")
    W, H = 252, 330
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    xl = 8.0 + 0.25 * ys          # keep in sync with TitleSparks._spawn_dust
    xr = 140.0 + 0.28 * ys
    inside = np.minimum(xs - xl, xr - xs)
    edge = np.clip(inside / 22.0, 0, 1)
    fade = np.interp(ys, [0, 60, 200, H], [0.55, 1.0, 0.7, 0.18])
    t = (xs - xl) / np.maximum(xr - xl, 1.0)
    rays = 0.78 + 0.22 * np.sin(t * math.tau * 3.0 + ys * 0.01) * np.sin(t * math.tau * 1.3 + 1.0)
    dens = edge * fade * rays
    q = np.floor(np.clip(dens, 0, 1) * 3.0 + (bayer_field(W, H, 8) - 0.5) * 0.9 + 0.35).astype(np.int32)
    q = np.clip(q, 0, 3)
    alpha = np.array([0, 70, 135, 210], np.uint8)[q]
    px = np.zeros((H, W, 4), np.uint8)
    px[:, :, :3] = 255
    px[:, :, 3] = alpha
    save_image(Image.fromarray(px, "RGBA"), "beam.png")


def build_vignette() -> None:
    print("vignette")
    W, H = 640, 360
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    dx = (xs - W / 2) / (W / 2)
    dy = (ys - H / 2) / (H / 2)
    d = np.sqrt(dx * dx * 0.82 + dy * dy * 1.1)
    dens = np.clip((d - 0.62) / 0.62, 0, 1) ** 1.35
    q = np.floor(dens * 5.0 + (bayer_field(W, H, 8) - 0.5) + 0.5).astype(np.int32)
    q = np.clip(q, 0, 5)
    alpha = np.array([0, 40, 80, 120, 160, 205], np.uint8)[q]
    px = np.zeros((H, W, 4), np.uint8)
    px[:, :, :3] = (6, 4, 10)
    px[:, :, 3] = alpha
    save_image(Image.fromarray(px, "RGBA"), "vignette.png")


def build_glow() -> None:
    """Soft round glow (white, alpha falloff): additive halos and light cookies."""
    print("glow")
    S = 128
    ys, xs = np.mgrid[0:S, 0:S].astype(np.float32)
    d = np.hypot(xs + 0.5 - S / 2, ys + 0.5 - S / 2) / (S / 2)
    a = np.clip(1.0 - d, 0, 1) ** 2.2
    px = np.zeros((S, S, 4), np.uint8)
    px[:, :, :3] = 255
    px[:, :, 3] = np.rint(a * 255).astype(np.uint8)
    save_image(Image.fromarray(px, "RGBA"), "glow.png")


# ------------------------------------------------------------------- main ---

BUILDERS = {
    "gears": build_gears,
    "hall": build_hall,
    "masses": build_masses,
    "bridge": build_bridge,
    "forge_mouth": build_forge_mouth,
    "lantern": build_lantern,
    "steam": build_steam,
    "beam": build_beam,
    "vignette": build_vignette,
    "glow": build_glow,
}


def main(argv: list[str]) -> None:
    wanted = argv[1:] or list(BUILDERS)
    for key in wanted:
        match = [name for name in BUILDERS if name.startswith(key)]
        if not match:
            print(f"unknown asset group: {key} (have: {', '.join(BUILDERS)})")
            continue
        for name in match:
            BUILDERS[name]()


if __name__ == "__main__":
    main(sys.argv)
