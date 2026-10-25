"""Build a review board and integrity index for the seven original boss drawings.

This checks pixel delivery, not artistic originality; editable drawing sources
and visual review provide that evidence. The board enlarges each portrait to
fit its card and is deliberately not a world-scale comparison.
"""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "assets/characters"
OUT = ROOT / "screenshots/acceptance/overhaul-v3/original-bosses"
SPECS = [
    ("executioner", "刽子手", "闭面葬甲 · 碑盾裂斧", 38),
    ("hollow_bell", "空钟", "悬挂裂钟 · 独立钟舌", 72),
    ("capstan_warden", "绞盘守渠人", "潜水重甲 · 水平双绞筒", 40),
    ("silent_choir", "无声唱诗班", "烛冠管风琴 · 三种唱诗面具", 60),
    ("bell_founder", "铸钟人", "四层铸模甲 · 背炉分节锤", 128),
    ("emberwind_herald", "炉风先驱", "分节钢翼 · 五片镜眼尾羽", 68),
    ("nightmare", "梦魇", "窑骨骸马 · 炉心名牌鬃", 53),
]


def reproduce():
    staging = OUT / "reproduction"
    staging.mkdir(parents=True, exist_ok=True)
    (staging / ".gdignore").touch()
    targets = staging / "assets/characters"

    def load_source(name, relative):
        spec = importlib.util.spec_from_file_location(name, ROOT / relative)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    ex = load_source("original_executioner_nightmare", "tools/art/gen_original_executioner_nightmare.py")
    ex.OUT = targets
    ex.generate()
    bells = load_source("original_bell_bosses", "tools/gen_original_bell_bosses.py")
    bells.BASE = targets
    bells.generate_hollow_bell()
    bells.generate_bell_founder()
    bells.generate_emberwind_herald()
    choir = load_source("original_choir_warden", "tools/gen_original_choir_warden.py")
    choir.ASSETS = targets
    choir.EVIDENCE = staging / "choir-warden"
    choir.generate(False)
    count = 0
    for generated in targets.rglob("*.png"):
        delivered = ASSETS / generated.relative_to(targets)
        with Image.open(generated) as a, Image.open(delivered) as b:
            assert a.size == b.size and a.tobytes() == b.tobytes(), delivered
        count += 1
    assert count == 459, count
    return count


def main(verify_sources=False):
    OUT.mkdir(parents=True, exist_ok=True)
    reproduced = reproduce() if verify_sources else None
    font_path = "C:/Windows/Fonts/msyh.ttc"
    title_font = ImageFont.truetype(font_path, 30)
    font = ImageFont.truetype(font_path, 23)
    small = ImageFont.truetype(font_path, 18)
    board = Image.new("RGB", (1600, 1030), "#101d25")
    d = ImageDraw.Draw(board)
    d.text((32, 16), "锈墓 / 七位独立设计的原创 Boss", font=title_font, fill="#eadab4")
    d.text((32, 62), "项目源稿逐像素绘制；各卡片独立放大，非游戏内尺寸比例。", font=small, fill="#9cb0ae")
    all_hashes, records = {}, []
    for i, (name, label, design, expected) in enumerate(SPECS):
        folder = ASSETS / ("original_" + name)
        files = sorted(folder.rglob("*.png"))
        assert len(files) == expected, (name, len(files), expected)
        hashes = {}
        for path in files:
            with Image.open(path) as im:
                assert im.mode == "RGBA", path
                assert set(im.getchannel("A").tobytes()) <= {0, 255}, path
                digest = hashlib.sha256(im.tobytes()).hexdigest()
                if digest in all_hashes:
                    assert all_hashes[digest] == name, (path, "cross-boss duplicated pixels")
                all_hashes[digest] = name
                hashes[path.relative_to(ROOT).as_posix()] = digest
        portrait = Image.open(folder / "idle/idle_0.png").convert("RGBA")
        if name == "hollow_bell":
            clapper = Image.open(folder / "hammer/hammer_0.png").convert("RGBA")
            portrait.alpha_composite(clapper, (60, 240))
        elif name == "bell_founder":
            tool = Image.open(folder / "tool_idle/tool_idle_0.png").convert("RGBA")
            portrait.alpha_composite(tool)
        if name == "silent_choir":
            combined = Image.new("RGBA", (228, 152))
            combined.alpha_composite(portrait, (66, 0))
            for n, offset in enumerate([(0, 82), (44, 87), (176, 84)]):
                cantor = Image.open(folder / f"cantor_{n}/idle/idle_0.png").convert("RGBA")
                combined.alpha_composite(cantor, offset)
            portrait = combined
        portrait = portrait.crop(portrait.getbbox())
        scale = max(1, min(3, 376 // portrait.width, 325 // portrait.height))
        portrait = portrait.resize((portrait.width * scale, portrait.height * scale), Image.Resampling.NEAREST)
        x, y = (i % 4) * 400, 110 + (i // 4) * 455
        d.rounded_rectangle((x + 12, y, x + 388, y + 438), radius=10, fill="#20313a", outline="#4d6668")
        d.text((x + 28, y + 14), label, font=font, fill="#e4c88d")
        board.paste(portrait, (x + (400 - portrait.width) // 2, y + 72 + (325 - portrait.height)), portrait)
        d.text((x + 24, y + 403), design, font=small, fill="#a6c1bf")
        records.append({"boss":name,"frame_count":expected,"hashes":hashes})
    d.text((1228, 610), "459 张透明像素帧", font=font, fill="#e4c88d")
    for j, text in enumerate(["独立轮廓 / 独立装备", "实际战斗步骤驱动姿势", "源稿、色板与哈希随仓库交付"]):
        d.text((1228, 665 + j * 42), text, font=small, fill="#a6c1bf")
    board.save(OUT / "seven-original-bosses.png")
    report = {"purpose":"pixel delivery index; not proof of artistic originality or input acceptance",
              "total_frames":sum(s[3] for s in SPECS),"binary_alpha":True,
              "cross_boss_duplicate_pixel_frames":0,"source_reproduced_frames":reproduced,"bosses":records}
    (OUT / "original-assets-review.json").write_text(json.dumps(report,indent=2,ensure_ascii=False)+"\n",encoding="utf-8")
    print(json.dumps({"frames":report["total_frames"],"board":str(OUT / "seven-original-bosses.png")}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reproduce",action="store_true",help="redraw every frame into staging and compare exact pixels")
    main(parser.parse_args().reproduce)
