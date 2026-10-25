"""Prepare whole-action edit references; never contacts a generation service."""
from pathlib import Path
import argparse
import json
import math
import hashlib

from redraw_asset_pipeline import PROMPT

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DESCRIPTIONS = {
    'player_fantasy_knight': 'compact armored knight, olive aged steel plates, chain mail, leather belts and boots, pale cloth and the same weapon',
    'player_cemetery_hero': 'the same cemetery warrior, identical costume, face, hair, weapon and muted palette',
    'player_gothic_hero': 'the same gothic adventurer, identical costume, face, hair, weapon and muted palette',
    'gear_shield_executioner': 'the same imposing hooded undead executioner, identical heavy armor and axe, pale exposed bone and rusted iron',
    'boss_nightmare': 'the same monstrous nightmare horse, identical armored anatomy, palette and spectral details',
    'scrapper_hell_hound': 'the same low slung hell hound, identical elongated anatomy, fur, claws and palette',
    'spitter_hell_beast': 'the same spitting hell beast, identical grotesque anatomy, mouth, teeth, skin and palette',
    'ghost': 'the same spectral ghost, identical cloth silhouette, hood, face and translucent color family',
    'skeleton': 'the same rising skeleton warrior, identical bone structure, skull, equipment and palette',
    'fire_skull': 'the same flying fire skull, identical skull structure and coherent flame anatomy and colors',
    'flying_demon': 'the same flying demon, identical wing shapes, body proportions and palette',
    'flying_demon_px': 'the same flying demon, identical wing shapes, body proportions and palette',
}


def layout_size(n, width, height):
    for density in [6, 5, 4, 3, 2]:
        cell = (math.ceil((width * density + 32) / 16) * 16, math.ceil((height * density + 32) / 16) * 16)
        choices = []
        for cols in range(1, n + 1):
            rows = math.ceil(n / cols)
            size = (max(1024, cell[0] * cols), max(768, cell[1] * rows))
            if max(size) <= 3840 and max(size) / min(size) <= 3 and 655360 <= math.prod(size) <= 8294400:
                choices.append((abs(math.log(size[0] / size[1] / 1.5)), cols, rows, size))
        if choices:
            _, cols, rows, size = min(choices)
            return density, cell, cols, rows, size
    raise ValueError('Animation does not fit a single generation canvas')


def main(characters, work):
    work.mkdir(parents=True, exist_ok=True)
    config_path = work / 'prompts.json'
    config = json.loads(config_path.read_text()) if config_path.exists() else {}
    added = []
    for char in characters:
        for folder in sorted((ROOT / 'assets/characters' / char).iterdir()):
            if not folder.is_dir():
                continue
            files = sorted(folder.glob('*.png'), key=lambda p: int(p.stem.rsplit('_', 1)[1]))
            if not files:
                continue
            name = char + '__' + folder.name
            if name in config:
                continue
            images = [Image.open(p).convert('RGBA') for p in files]
            density, cell, cols, rows, size = layout_size(len(files), max(i.width for i in images), max(i.height for i in images))
            sheet = Image.new('RGB', size, (255, 0, 255))
            records = []
            for i, (p, im) in enumerate(zip(files, images)):
                scaled = im.resize((im.width * density, im.height * density), Image.Resampling.NEAREST)
                x = i % cols * cell[0] + (cell[0] - scaled.width) // 2
                y = i // cols * cell[1] + (cell[1] - scaled.height) // 2
                sheet.paste(scaled, (x, y), scaled)
                records.append({'source': p.relative_to(ROOT).as_posix(), 'slot': [i % cols * cell[0], i // cols * cell[1], (i % cols + 1) * cell[0], (i // cols + 1) * cell[1]],
                    'frame_origin': [x, y], 'size': list(im.size), 'bbox': im.getbbox(), 'source_sha256': hashlib.sha256(p.read_bytes()).hexdigest()})
            sheet.save(work / (name + '-reference.png'))
            (work / (name + '-layout.json')).write_text(json.dumps({'density': density, 'size': list(size), 'cell': cell, 'frames': records}, indent=2))
            prompt = f'''{PROMPT} This is the complete original {folder.name} animation, exactly {len(files)} frames in {cols} columns and {rows} rows. Preserve every original pose, slot, facing direction, silhouette, foot point and phase. Keep {DESCRIPTIONS[char]} and the original palette. Refine only existing materials with smaller crisp pixel clusters, fine chips, chain links, cloth folds and worn edges. Do not redesign the character or turn it into realistic concept art. Empty cells and all existing gaps must remain flat magenta. Keep the exact drawing bounds and canvas {size[0]}x{size[1]}.'''
            (work / (name + '-prompt.txt')).write_text(prompt, encoding='utf8')
            config[name] = {'size': f'{size[0]}x{size[1]}', 'prompt_file': name + '-prompt.txt', 'images': [name + '-reference.png']}
            added.append(name)
    config_path.write_text(json.dumps(config, indent=2))
    (work / 'new-character-tasks.json').write_text(json.dumps(added, indent=2))
    print(len(added), 'whole-action references prepared')


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('characters', nargs='+', choices=DESCRIPTIONS)
    p.add_argument('--work', type=Path, default=ROOT / 'screenshots/acceptance/native-scenery-redraw/ai')
    args = p.parse_args()
    main(args.characters, args.work)
