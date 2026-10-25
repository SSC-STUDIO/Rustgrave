"""Register original-referenced action sheets; retain original palette and mask.

The generated drawing supplies material detail, while the existing animation
remains authoritative for silhouette, frame order, canvas, facing and foot point.
No network access or service credentials are part of this importer.
"""
from pathlib import Path
import argparse
import hashlib
import json
import statistics

import numpy as np
from PIL import Image

from redraw_asset_pipeline import ROOT, OUTPUT, lock_style

SOURCES = ROOT / 'art_sources/redrawn_characters'


def extract_part(image, slot):
    part = image.crop(slot).convert('RGB')
    colors = np.asarray(part)
    matte = (colors[..., 0] > 160) & (colors[..., 2] > 160) & (colors[..., 1] < 120)
    # The service may enlarge poses enough that a neighbouring foot crosses a
    # cell boundary. Keep the complete main component and interior effects;
    # never let a clipped neighbour determine an action's scale.
    parents, runs, previous = [], [], []
    def root(label):
        while parents[label] != label:
            parents[label] = parents[parents[label]]
            label = parents[label]
        return label
    for y, row in enumerate(~matte):
        edges = np.diff(np.pad(row.astype(np.int8), (1, 1)))
        current = []
        for x0, x1 in zip(np.flatnonzero(edges == 1), np.flatnonzero(edges == -1)):
            links = [root(label) for a, b, label in previous if b >= x0 and a <= x1]
            if links:
                label = min(links)
                for other in links:
                    parents[other] = label
            else:
                label = len(parents)
                parents.append(label)
            current.append((int(x0), int(x1), label))
            runs.append((y, int(x0), int(x1), label))
        previous = current
    components = {}
    for y, a, b, label in runs:
        group = components.setdefault(root(label), [part.width, part.height, 0, 0, 0])
        group[0] = min(group[0], a); group[1] = min(group[1], y)
        group[2] = max(group[2], b); group[3] = max(group[3], y + 1)
        group[4] += b - a
    if not components:
        raise ValueError('Empty animation slot')
    main = max(components.values(), key=lambda c: c[4])
    selected = [main] + [c for c in components.values() if c is not main and c[4] >= main[4] * .08
        and c[0] > 0 and c[1] > 0 and c[2] < part.width and c[3] < part.height]
    bounds = (min(c[0] for c in selected), min(c[1] for c in selected), max(c[2] for c in selected), max(c[3] for c in selected))
    return part.crop(bounds)


def compile_action(work, name):
    layout_path = work / (name + '-layout.json')
    drawing_path = work / (name + '-generated.png')
    if not layout_path.exists():
        layout_path = work / name / 'layout.json'
        drawing_path = work / name / 'drawing.png'
    layout = json.loads(layout_path.read_text())
    raw = Image.open(drawing_path).convert('RGB')
    source_image = raw.copy()
    if list(raw.size) != layout['size']:
        aspect = (raw.width / raw.height) / (layout['size'][0] / layout['size'][1])
        if abs(aspect - 1) > .05:
            raise ValueError('Action sheet canvas changed shape: ' + name)
        raw = raw.resize(layout['size'], Image.Resampling.LANCZOS)
    parts = [extract_part(raw, row['slot']) for row in layout['frames']]
    scale = statistics.median((row['bbox'][3] - row['bbox'][1]) * 4 / part.height
        for row, part in zip(layout['frames'], parts))
    # One scale across an entire action; no frame-to-frame changes in body size.
    for row, part in zip(layout['frames'], parts):
        w, h = row['size']
        b = row['bbox']
        center = (b[0] + b[2]) * 2
        scale = min(scale, center * 2 / part.width, (w * 4 - center) * 2 / part.width,
                    b[3] * 4 / part.height)
    source_dir = SOURCES / name
    source_dir.mkdir(parents=True, exist_ok=True)
    source_image.save(source_dir / 'drawing.png')
    (source_dir / 'layout.json').write_text(json.dumps(layout, indent=2) + '\n')
    prompt = work / (name + '-prompt.txt')
    if prompt.exists():
        (source_dir / 'prompt.txt').write_text(prompt.read_text(encoding='utf8'), encoding='utf8')
    records = {}
    for row, part in zip(layout['frames'], parts):
        source = ROOT / row['source']
        if row.get('source_sha256') and hashlib.sha256(source.read_bytes()).hexdigest() != row['source_sha256']:
            raise ValueError('Original changed after reference preparation: ' + row['source'])
        original = Image.open(source).convert('RGBA')
        b = row['bbox']
        painting = Image.new('RGB', (original.width * 4, original.height * 4), (255, 0, 255))
        resized = part.resize((max(1, round(part.width * scale)), max(1, round(part.height * scale))), Image.Resampling.LANCZOS)
        x = round((b[0] + b[2]) * 2 - resized.width * .5)
        y = b[3] * 4 - resized.height
        if x < 0 or y < 0 or x + resized.width > painting.width or y + resized.height > painting.height:
            raise ValueError('Registered frame would clip: ' + row['source'])
        painting.paste(resized, (x, y))
        detail = lock_style(original, painting, 4, tile_edges=False, role=row['source'])
        target = OUTPUT / Path(row['source']).relative_to('assets')
        target.parent.mkdir(parents=True, exist_ok=True)
        detail.save(target, compress_level=6)
        records['res://' + row['source']] = {
            'texture': 'res://' + target.relative_to(ROOT).as_posix(),
            'logical_size': list(original.size), 'physical_size': list(detail.size), 'density': 4,
            'original_bbox': list(original.getbbox()), 'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
            'method': 'original-referenced action redraw; shared action scale; original alpha and palette locked',
            'shared_action_scale': scale, 'redraw_source': (source_dir / 'drawing.png').relative_to(ROOT).as_posix(),
            'sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
        }
    print(name, len(records), 'frames', flush=True)
    return records


def transfer_material_details(character, action, reference_action='idle'):
    """Carry the same character's drawn material detail onto another original pose.

    This does not invent a replacement animation or claim another service edit.
    Original pixels select matching colored material patches from its completed
    redraw; transparency and pose stay exactly on the original action frames.
    """
    samples = {}
    references = []
    for path in sorted((ROOT / 'assets/characters' / character / reference_action).glob('*.png')):
        detailed_path = OUTPUT / path.relative_to(ROOT / 'assets')
        if not detailed_path.exists():
            continue
        before = np.asarray(Image.open(path).convert('RGBA'))
        after = np.asarray(Image.open(detailed_path).convert('RGBA'))
        references.append(detailed_path.relative_to(ROOT).as_posix())
        for y, x in zip(*np.nonzero(before[..., 3] > 240)):
            rgb = tuple(int(c) for c in before[y, x, :3])
            patch = after[y*4:y*4+4, x*4:x*4+4, :3].astype(np.float32)
            luma = patch @ np.array([.25, .6, .15])
            gain = np.clip((luma + 12) / (luma.mean() + 12), .7, 1.35)
            if rgb not in samples or gain.std() > samples[rgb].std():
                samples[rgb] = gain
    if not samples:
        raise ValueError('No completed reference action to transfer')
    palette = np.asarray(list(samples), dtype=np.float32)
    gains = list(samples.values())
    cache = {}
    records = {}
    for path in sorted((ROOT / 'assets/characters' / character / action).glob('*.png')):
        original = Image.open(path).convert('RGBA')
        old = np.asarray(original)
        out = np.asarray(original.resize((original.width*4, original.height*4), Image.Resampling.NEAREST)).copy()
        for y, x in zip(*np.nonzero(old[..., 3])):
            color = tuple(int(c) for c in old[y, x, :3])
            if color not in cache:
                closest = int(np.argmin(np.sum((palette - np.array(color)) ** 2, axis=1)))
                cache[color] = gains[closest]
            out[y*4:y*4+4, x*4:x*4+4, :3] = np.clip(np.array(color) * cache[color][..., None], 0, 255).astype(np.uint8)
        out[out[..., 3] == 0] = 0
        target = OUTPUT / path.relative_to(ROOT / 'assets')
        target.parent.mkdir(parents=True, exist_ok=True)
        Image.fromarray(out).save(target, compress_level=6)
        source = path.relative_to(ROOT).as_posix()
        records['res://' + source] = {
            'texture': 'res://' + target.relative_to(ROOT).as_posix(),
            'logical_size': list(original.size), 'physical_size': [original.width*4, original.height*4], 'density': 4,
            'source_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'method': 'same-character drawn material transfer onto the original pose; original palette and alpha retained',
            'detail_references': references, 'sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
        }
    return records


def main(work, names):
    catalog_path = OUTPUT / 'catalog.json'
    catalog = json.loads(catalog_path.read_text())
    for name in names:
        catalog['assets'].update(compile_action(work, name))
    catalog_path.write_text(json.dumps(catalog, indent=2) + '\n')
    mapping = {p: v['texture'] for p, v in catalog['assets'].items()}
    (ROOT / 'scripts/visuals/redrawn_texture_catalog.gd').write_text(
        'extends RefCounted\n## Original-based redraws; logical size always comes from the source.\nconst REPLACEMENTS := '
        + json.dumps(mapping, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('names', nargs='+')
    parser.add_argument('--work', type=Path, default=ROOT / 'screenshots/acceptance/native-scenery-redraw/ai')
    args = parser.parse_args()
    main(args.work, args.names)
