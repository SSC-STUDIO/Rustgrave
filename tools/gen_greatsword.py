"""Generate the Ember-Knight's rusted greatsword sprites.

Why this exists (docs/art-spec.md「主角剪影要点」): the knight's frame animation
(Fantasy Knight) carries only a small sword, so the character reads as a normal
plated soldier instead of "扛着过重的锯齿巨剑". The written identity calls for a
blade 1.3–1.6× body height (body ≈ 37px → blade ≈ 50–58px). This tool bakes that
blade as 1x pixel art in the game's own 16-color ramp, so the silhouette is the
weapon:

  greatsword_back.png     背扛斜挎（探索/跑/跳/冲刺时可见）
  greatsword_planted.png  开场：剑尖杵进地里，骑士趴在一旁

Both are drawn on an integer pixel grid with a single scanline pass (no
anti-aliasing, no resampling): an asymmetric blade — straight saw-toothed
leading edge, slightly bellied back edge, fuller groove, crossguard, wrapped
grip, ember pommel — outlined in Void so it separates from the magenta night.

Run:  py -3 tools/gen_greatsword.py
"""

from __future__ import annotations

import math
import os

from PIL import Image

from gen_ui_kit import PAL

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "assets", "player")

## 色板键见 gen_ui_kit.PAL；只允许本项目色板内的颜色。
OUTLINE = "0"
BLADE_LIGHT = "a"     # rust light — 受光的上刃
BLADE_MID = "9"       # rust mid — 剑面
BLADE_DARK = "8"      # rust dark — 背光面
BLADE_SHADOW = "7"    # rust shadow — 最暗的下缘 / 凹槽
GUARD_LIT = "3"
GUARD = "2"
GRIP = "7"
POMMEL = "c"
POMMEL_HOT = "d"
RUST_SPECK = "6"


class Canvas:
    """Indexed pixel canvas: every write must be a palette key."""

    def __init__(self, width: int, height: int) -> None:
        self.w = width
        self.h = height
        self.cells = [[None] * width for _ in range(height)]

    def put(self, x: int, y: int, key: str) -> None:
        if 0 <= x < self.w and 0 <= y < self.h:
            self.cells[y][x] = key

    def get(self, x: int, y: int) -> str | None:
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.cells[y][x]
        return None

    def filled(self, x: int, y: int) -> bool:
        return self.get(x, y) is not None

    def outline(self, key: str = OUTLINE) -> None:
        """1px rim on every transparent pixel touching the silhouette."""
        edge: list[tuple[int, int]] = []
        for y in range(self.h):
            for x in range(self.w):
                if self.cells[y][x] is not None:
                    continue
                for nx, ny in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    if self.filled(x + nx, y + ny):
                        edge.append((x, y))
                        break
        for x, y in edge:
            self.cells[y][x] = key

    def to_image(self) -> Image.Image:
        img = Image.new("RGBA", (self.w, self.h), (0, 0, 0, 0))
        px = img.load()
        for y in range(self.h):
            for x in range(self.w):
                key = self.cells[y][x]
                if key is not None:
                    px[x, y] = PAL[key]
        return img


def _width_at(u: float, length: float) -> tuple[float, float]:
    """(back-edge half width, leading-edge half width) at distance u from hilt.

    The back edge stays almost straight and only narrows over the last quarter;
    the leading edge bellies out just past the guard, then tapers to the point.
    """
    t = min(max(u / length, 0.0), 1.0)
    if t < 0.09:
        back = 2.6 + 10.0 * t
        lead = 2.4 + 9.0 * t
    elif t < 0.62:
        k = (t - 0.09) / 0.53
        # 刀身要"直"：背刃几乎不鼓，前刃只微微外扩 —— 太鼓会读成叶片/木桨。
        back = 3.6 + 0.18 * math.sin(k * math.pi)
        lead = 3.5 + 0.55 * math.sin(k * math.pi)
    elif t < 0.88:
        k = (t - 0.62) / 0.26
        back = 3.75 * (1.0 - 0.58 * k)
        lead = 4.05 * (1.0 - 0.64 * k)
    else:
        k = (t - 0.88) / 0.12
        back = 1.55 * (1.0 - k) + 0.6
        lead = 1.65 * (1.0 - k) + 0.5
    return back, lead


def _teeth_bump(u: float, length: float) -> float:
    """Saw teeth on the leading edge: base attached to the blade, apex outward."""
    start = length * 0.13
    period = max(6.0, length * 0.125)
    if u < start or u > length * 0.87:
        return 0.0
    phase = (u - start) % period
    if phase > period * 0.55:
        return 0.0
    return 1.7 * math.sin(math.pi * phase / (period * 0.55))


def _chip_cut(u: float, length: float) -> float:
    """One battle chip taken out of the back edge (damage storytelling)."""
    centre = length * 0.46
    half = 2.6
    if abs(u - centre) > half:
        return 0.0
    return 1.7 * (1.0 - abs(u - centre) / half)


def draw_greatsword(canvas: Canvas, hilt: tuple[float, float],
                    tip: tuple[float, float], length: float) -> None:
    """Single scanline pass: silhouette, 4-step rust ramp, fuller and edge detail."""
    hx, hy = hilt
    dx, dy = tip[0] - hx, tip[1] - hy
    norm = math.hypot(dx, dy)
    ux, uy = dx / norm, dy / norm              # along the blade, hilt -> tip
    px, py = -uy, ux                           # across it
    reach = max(length, norm)
    min_x = int(math.floor(min(hx, hx + ux * reach) - 12))
    max_x = int(math.ceil(max(hx, hx + ux * reach) + 12))
    min_y = int(math.floor(min(hy, hy + uy * reach) - 12))
    max_y = int(math.ceil(max(hy, hy + uy * reach) + 12))

    for y in range(min_y, max_y + 1):
        for x in range(min_x, max_x + 1):
            ddx, ddy = x - hx, y - hy
            u = ddx * ux + ddy * uy
            v = ddx * px + ddy * py
            if u < 0.0 or u > length:
                continue
            back, lead = _width_at(u, length)
            back_eff = max(0.0, back - _chip_cut(u, length))
            lead_eff = lead + _teeth_bump(u, length)
            if v < -back_eff - 0.2 or v > lead_eff + 0.2:
                continue
            total = back_eff + lead_eff
            q = (v + back_eff) / max(total, 0.001)
            if v < 0.0:
                # 背光侧：上刃高光只给最外 1px，其余走中间锈色。
                if -v > back_eff - 1.05:
                    key = BLADE_LIGHT
                elif -v > back_eff - 2.2:
                    key = BLADE_MID
                else:
                    key = BLADE_DARK
            else:
                if v > lead_eff - 0.9:
                    key = BLADE_MID if q < 0.94 else BLADE_LIGHT
                elif v > lead_eff - 2.4:
                    key = BLADE_DARK
                else:
                    key = BLADE_MID
            # 剑脊凹槽：离中线略偏的一列暗线，长刀在低分辨率下才有"厚度"。
            groove = lead_eff * 0.42
            if 6.0 < u < length * 0.82 and abs(v - groove) < 0.55:
                key = BLADE_SHADOW
            canvas.put(x, y, key)

    # 锈斑：让平面不塑料；位置固定（确定性）。
    spans = ((0.24, -1.4), (0.37, 0.8), (0.56, -0.6), (0.71, 1.4), (0.83, -0.4))
    for t, off in spans:
        u = length * t
        x = int(round(hx + ux * u + px * off))
        y = int(round(hy + uy * u + py * off))
        canvas.put(x, y, RUST_SPECK)

    _draw_guard(canvas, hx, hy, ux, uy, px, py)


def _draw_guard(canvas: Canvas, hx: float, hy: float, ux: float, uy: float,
                px: float, py: float) -> None:
    """Crossguard, wrapped grip and ember pommel, all in blade-local space."""
    half_span = 8.0
    thickness = 3.0
    # 护手横杆：沿垂直轴伸出，靠近剑身的两侧各有一段上翘的钩。
    for i in range(-int(half_span), int(half_span) + 1):
        for k in range(-2, 2):
            a = hx + px * i - ux * (k * 0.55 + 1.4)
            b = hy + py * i - uy * (k * 0.55 + 1.4)
            key = GUARD_LIT if k == -2 else GUARD
            canvas.put(int(round(a)), int(round(b)), key)
    for side in (-1.0, 1.0):
        for k in range(3):
            a = hx + px * (half_span * side) - ux * (0.2 + k * 0.9)
            b = hy + py * (half_span * side) - uy * (0.2 + k * 0.9)
            canvas.put(int(round(a)), int(round(b)), GUARD)
    # 握柄：剑柄向剑尖反方向伸出 7px，隔 2px 一道亮纹。
    grip_len = 7.0
    for i in range(int(grip_len) + 1):
        for k in (-1, 0, 1):
            a = hx - ux * (i + 1.2) + px * (k * 0.75)
            b = hy - uy * (i + 1.2) + py * (k * 0.75)
            key = GUARD_LIT if (k == -1 and i % 3 == 1) else GRIP
            canvas.put(int(round(a)), int(round(b)), key)
    # 柄尾余烬石：3x3，中心亮、外圈热。
    pommel_u = grip_len + 2.4
    for oy in range(-1, 2):
        for ox in range(-1, 2):
            a = hx - ux * pommel_u + px * ox + ux * 0.0
            b = hy - uy * pommel_u + py * oy
            key = POMMEL_HOT if (ox == 0 and oy == 0) else POMMEL
            canvas.put(int(round(a)), int(round(b)), key)


def build_back() -> Canvas:
    """背扛：剑柄在左下、剑尖朝右上，刀身约 52px（≈1.45 倍身长）。"""
    canvas = Canvas(62, 52)
    draw_greatsword(canvas, hilt=(13.0, 41.0), tip=(56.0, 8.0), length=52.0)
    canvas.outline()
    return canvas


def build_planted() -> Canvas:
    """竖插：剑尖朝下插在土里，护手在上；总高约 66px。"""
    canvas = Canvas(34, 70)
    draw_greatsword(canvas, hilt=(17.0, 15.0), tip=(17.0, 64.0), length=49.0)
    canvas.outline()
    return canvas


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    print("generating greatsword ...")
    for name, canvas in (("greatsword_back.png", build_back()),
                         ("greatsword_planted.png", build_planted())):
        path = os.path.join(OUT, name)
        canvas.to_image().save(path)
        print(f"  {name:<26} {canvas.w}x{canvas.h}")


if __name__ == "__main__":
    main()
