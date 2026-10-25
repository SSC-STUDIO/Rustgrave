"""Audit detailed scene/material delivery; generate a native-pixel review board."""
from pathlib import Path
import hashlib
import json
from collections import Counter
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'screenshots/acceptance/qhd/art'


def main():
    material=json.loads((ROOT/'assets/qhd/materials.json').read_text())
    records={}
    for name in ('materials','title','fire'):
        data=json.loads((ROOT/f'assets/qhd/{name}.json').read_text())
        records.update(data.get('assets',data))
    changed=0
    unchanged=[]
    for path,record in records.items():
        file=ROOT/record['texture'].removeprefix('res://')
        assert hashlib.sha256(file.read_bytes()).hexdigest()==record['sha256'],file
        before=Image.open(ROOT/path.removeprefix('res://')).convert('RGBA')
        after=Image.open(file).convert('RGBA')
        assert before.size==tuple(record['logical_size']),path
        assert after.size==tuple(v*4 for v in before.size),path
        if before.resize(after.size,Image.Resampling.NEAREST).tobytes()!=after.tobytes():
            changed+=1
        else:
            unchanged.append(path)
        if path.startswith('res://assets/env/') and before.getbbox():
            assert (after.getbbox()[3]+3)//4==before.getbbox()[3],(path,'ground anchor')
    OUT.mkdir(parents=True,exist_ok=True)
    board=Image.new('RGB',(1700,1030),'#171c25')
    d=ImageDraw.Draw(board)
    items=['env/props/iron/pipe_valve.png','env/props/basalt/broken_machine.png',
           'env/ember_nest.png','player/greatsword_back.png','env/iron_slab_a.png',
           'title/bridge.png','title/mass_right.png','ui/title_logo.png']
    for n,relative in enumerate(items):
        source=ROOT/'assets'/relative
        if not source.exists():
            continue
        after=Image.open(ROOT/'assets/qhd'/relative).convert('RGBA')
        before=Image.open(source).convert('RGBA')
        x,y=(n%4)*425+12,(n//4)*510+12
        scale=min(190/after.width,420/after.height)
        size=(max(1,round(after.width*scale)),max(1,round(after.height*scale)))
        old=before.resize(size,Image.Resampling.NEAREST)
        new=after.resize(size,Image.Resampling.NEAREST)
        board.paste(old,(x,y+36),old)
        board.paste(new,(x+208,y+36),new)
        d.text((x,y),relative,fill='#e0b984')
        d.text((x,y+474),'1x fallback               QHD detail',fill='#b7c6d0')
    board.save(OUT/'scenery-comparison.png')
    report={'detailed_scene_assets':len(records),'differ_from_nearest_enlargement':changed,
            'unchanged_detail_inputs':unchanged,'raster_materials':len(material['assets']),
            'preserved_atmospheric_or_legacy_inputs':len(material['preserved']),
            'families':dict(Counter(p.split('/')[3] for p in records)),
            'sha256_dimensions_and_environment_ground_anchor_checks':'passed'}
    (OUT/'scenery-audit.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report))


if __name__=='__main__':
    main()
