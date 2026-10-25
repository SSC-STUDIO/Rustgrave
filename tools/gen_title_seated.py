"""Author the title-only seated pose from each existing skin's idle armour pixels.

The head and torso stay at 1x; the lower silhouette is redrawn as bent knees,
short hanging shins and boots on a low iron stool. No scaled standing sprite or
death pose is used. The 48px canvas bottom is the bridge foot baseline.
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
FOLDERS = ("player_fantasy_knight", "player_cemetery_hero", "player_gothic_hero")


def build(folder: str) -> None:
    source = Image.open(ROOT / "assets/characters" / folder / "idle/idle_0.png").convert("RGBA")
    bounds = source.getbbox()
    assert bounds is not None
    x0, y0, x1, y1 = bounds
    torso_h = round((y1 - y0) * 0.64)
    torso = source.crop((x0, y0, x1, y0 + torso_h))
    pose = Image.new("RGBA", (48, 48))
    draw = ImageDraw.Draw(pose)
    # A low stool and a distinct seat under the hip make the resting posture legible.
    draw.rectangle((15, 40, 29, 42), fill="#4a3e44")
    draw.rectangle((16, 43, 18, 47), fill="#241c22")
    draw.rectangle((27, 43, 29, 47), fill="#241c22")
    palette = sorted({rgb for rgb in source.getdata() if rgb[3] > 200},
                     key=lambda c: c[0] * .21 + c[1] * .72 + c[2] * .07)
    dark = palette[len(palette) // 5]
    mid = palette[len(palette) // 2]
    light = palette[len(palette) * 4 // 5]
    # Rear thigh, front bent knee and vertical greave, all authored on whole pixels.
    draw.polygon(((21, 35), (29, 36), (34, 39), (33, 42), (22, 40)), fill=dark)
    draw.polygon(((22, 34), (29, 35), (37, 37), (38, 42), (33, 42), (32, 39), (22, 38)), fill=mid)
    draw.line(((24, 35), (31, 36), (36, 38)), fill=light, width=1)
    draw.rectangle((34, 41, 38, 46), fill=dark)
    draw.rectangle((35, 41, 37, 44), fill=mid)
    draw.rectangle((34, 46, 41, 47), fill=dark)
    draw.line((35, 46, 40, 46), fill=light)
    draw.rectangle((28, 41, 31, 46), fill=dark)
    draw.rectangle((28, 46, 35, 47), fill=dark)
    # Keep the source head/torso pixels; arms now rest at the seated hip line.
    pose.alpha_composite(torso, (22 - torso.width // 2, 37 - torso.height))
    target = ROOT / "assets/title" / f"seated_{folder}.png"
    pose.save(target)
    print(f"{target.name}: source armour={bounds}, seated bbox={pose.getbbox()}")


if __name__ == "__main__":
    for name in FOLDERS:
        build(name)
