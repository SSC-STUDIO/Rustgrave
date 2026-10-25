"""Draw all 459 independent original boss frames at four physical samples/unit.

Run with Pillow + numpy. This calls the editable drawing sources through a
high-density pen; existing PNGs are only read to verify logical canvas sizes.
"""
from pathlib import Path
import hashlib
import importlib.util
import json
import sys
from PIL import Image
from density_draw import install, bevel_materials, Images

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/qhd/characters'


def source(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    install(mod)
    return mod


def frames():
    ex = source('qhd_ex', 'tools/art/gen_original_executioner_nightmare.py')
    for _, (folder, draw, actions) in ex.SPECS.items():
        for action, count in actions.items():
            for i in range(count):
                yield folder, action, i, draw(action, i, count).image
    bells = source('qhd_bells', 'tools/gen_original_bell_bosses.py')
    specs = {
        'hollow_bell': {'idle':4, 'pendulum':6, 'bell_drop':6, 'chain_pull':6, 'toll_wave':6, 'stagger':4, 'hammer':4},
        'bell_founder': {'idle':4, 'hammer_slam':6, 'bell_shard':6, 'mold_cast':6, 'molten_pool':6, 'stagger':4},
        'emberwind_herald': {'idle':6, 'dive':6, 'wind_push':6, 'feather_blades':6, 'updraft':6, 'downed':4},
    }
    for boss, actions in specs.items():
        for hot in (False, True):
            for action, count in actions.items():
                for i in range(count):
                    if boss == 'hollow_bell':
                        canvas = bells.hollow_hammer(i, hot) if action == 'hammer' else bells.hollow_bell(action, i, hot)
                        if action in ('idle', 'stagger') and i % 2:
                            shifted = Images.new('RGBA', canvas.size)
                            shifted.alpha_composite(canvas, (1 if i == 1 else -1, 0))
                            canvas = shifted
                    else:
                        canvas = getattr(bells, boss)(action, i, hot)
                    yield 'original_'+boss, ('hot_' if hot else '')+action, i, canvas.image
                    if boss == 'bell_founder':
                        yield 'original_'+boss, ('hot_' if hot else '')+'tool_'+action, i, bells.bell_founder(action, i, hot, hammer=True).image
    choir = source('qhd_choir', 'tools/gen_original_choir_warden.py')
    for folder, actions, draw in [(choir.W_NAME, choir.W_ACTIONS, choir.warden),
                                  (choir.C_NAME, choir.C_ACTIONS, choir.choir)]:
        for action, count in actions.items():
            for i in range(count):
                yield folder, action, i, draw(action, i).image
    for cantor in range(3):
        for action, count in choir.S_ACTIONS.items():
            for i in range(count):
                yield f'{choir.C_NAME}/cantor_{cantor}', action, i, choir.cantor(cantor, action, i).image


def main():
    records = {}
    for folder, action, i, image in frames():
        rel = Path(folder) / action / f'{action}_{i}.png'
        old = ROOT / 'assets/characters' / rel
        if not old.exists():
            raise ValueError(f'Unexpected source frame {old}')
        with Image.open(old) as logical:
            assert image.size == tuple(v*4 for v in logical.size), rel
            logical_size = logical.size
        image = bevel_materials(image)
        dest = OUT / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        image.save(dest, optimize=True)
        records['res://assets/characters/'+rel.as_posix()] = {
            'texture': 'res://assets/qhd/characters/'+rel.as_posix(), 'logical_size': logical_size,
            'physical_size': image.size, 'sha256': hashlib.sha256(dest.read_bytes()).hexdigest(),
            'method': 'rerasterized original drawing + physical-pixel material edge bevels'}
    assert len(records) == 459, len(records)
    (OUT.parent/'bosses.json').write_text(json.dumps(records, indent=2)+'\n', encoding='utf-8')
    print(f'Drew {len(records)} QHD boss frames from independent editable sources')


if __name__ == '__main__':
    main()
