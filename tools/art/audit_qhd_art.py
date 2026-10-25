"""Verify physical QHD pixels, original geometry and source reproducibility."""
from pathlib import Path
import argparse
import hashlib
import json
from PIL import Image, ImageDraw
from gen_qhd_bosses import frames
from density_draw import bevel_materials

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'screenshots/acceptance/qhd/art'


def audit(reproduce=False):
    records = json.loads((ROOT/'assets/qhd/bosses.json').read_text())
    assert len(records) == 459
    owners, total_bytes = {}, 0
    for path, record in records.items():
        file = ROOT/record['texture'].removeprefix('res://')
        assert hashlib.sha256(file.read_bytes()).hexdigest() == record['sha256'], file
        image = Image.open(file).convert('RGBA')
        logical = Image.open(ROOT/path.removeprefix('res://')).convert('RGBA')
        assert image.size == tuple(v*4 for v in logical.size)
        assert set(image.getchannel('A').tobytes()) <= {0, 255}, file
        assert image.getbbox(), file
        assert image.tobytes() != logical.resize(image.size, Image.Resampling.NEAREST).tobytes(), file
        digest = hashlib.sha256(image.tobytes()).hexdigest()
        boss = path.split('/')[4]
        assert digest not in owners or owners[digest] == boss, (file, owners.get(digest))
        owners[digest] = boss
        total_bytes += image.width*image.height*4
    checked = 0
    if reproduce:
        for folder, action, i, image in frames():
            delivered = Image.open(ROOT/'assets/qhd/characters'/folder/action/f'{action}_{i}.png')
            assert delivered.tobytes() == bevel_materials(image).tobytes(), (folder, action, i)
            checked += 1
        assert checked == len(records)
    OUT.mkdir(parents=True, exist_ok=True)
    bosses = ['executioner', 'hollow_bell', 'capstan_warden', 'silent_choir', 'bell_founder', 'emberwind_herald', 'nightmare']
    board = Image.new('RGB', (1800, 1100), '#141a22')
    pen = ImageDraw.Draw(board)
    for n, boss in enumerate(bosses):
        folder = ROOT/'assets/characters'/('original_'+boss)/'idle/idle_0.png'
        before = Image.open(folder).convert('RGBA')
        after = Image.open(ROOT/'assets/qhd/characters'/folder.relative_to(ROOT/'assets/characters')).convert('RGBA')
        # Inspect native physical pixels; crop transparent space for board only.
        bbox = before.getbbox()
        before = before.crop(bbox)
        after = after.crop(tuple(v*4 for v in bbox))
        scale = min(240/after.width, 410/after.height, 1)
        size = (max(1, round(after.width*scale)), max(1, round(after.height*scale)))
        x, y = (n % 4)*450+12, (n//4)*540+10
        pen.text((x,y), boss, fill='#e7c799')
        board.paste(before.resize(size, Image.Resampling.NEAREST), (x,y+30), before.resize(size, Image.Resampling.NEAREST))
        board.paste(after.resize(size, Image.Resampling.NEAREST), (x+220,y+30), after.resize(size, Image.Resampling.NEAREST))
        pen.text((x,y+470), 'original                    QHD drawing', fill='#a7b9c6')
    board.save(OUT/'boss-comparison.png')
    report = {'boss_frames':len(records), 'reproduced':checked, 'cross_boss_duplicate_frames':0,
              'all_have_new_detail':True, 'rgba_mib_all_frames':round(total_bytes/1048576,2),
              'animation_cache_mib_limit':96}
    (OUT/'boss-audit.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reproduce', action='store_true')
    audit(parser.parse_args().reproduce)
