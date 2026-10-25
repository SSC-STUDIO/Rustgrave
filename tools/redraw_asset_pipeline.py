"""Original-based detail redraw preparation and import, without service credentials.

Source composition, palette, alpha and logical canvas are authoritative. New
detail is drawn by the image service from the supplied original reference;
import removes matte hallucinations and corrects broad color/lighting drift.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'assets/redrawn'
SOURCES = ROOT / 'art_sources/redrawn'

PROMPT = '''Use case: precise-object-edit. ORIGINAL-BASED DETAIL REDRAW of existing Rustgrave game art. Image 1 is the authoritative original artwork, enlarged only as a guide. Keep the EXACT composition, positions, silhouettes, proportions, construction, palette families and light direction. Preserve the existing Gothic stylized pixel-art family with finer small pixel clusters and readable crisp details at high resolution. Add material details INSIDE existing forms: chiseled chips, cracks and fine masonry joints on stone; thin rivet seams and rust on iron; wood grain and small worn fittings; finer foliage/branch details; delicate cloud curls where already present. Do NOT invent a new asset, different background, new objects, buildings, characters, moon, clouds or scenery. No realistic photography, realistic concept art, smooth vector shapes, stylistic replacement, blur, extra objects, labels, interface, frame or watermark. Preserve the exact original drawing bounds and all empty areas. The background outside original alpha is the flat magenta reference matte, which must stay empty. Keep edges and horizontal/vertical repeating structure fixed. This must immediately read as the SAME original artwork with added finer detail. Preserve any bottom/right padding as blank magenta. Return one faithful detail redraw of the reference.'''


def role_prompt(path):
    name = str(path).lower()
    if 'sky' in name or 'cloud' in name:
        return 'This is ONLY the original SKY/CLOUD layer. Keep exactly its original clouds and original moon count. Absolutely NO land, rocks, trees, buildings, architecture, graves, towers or figures anywhere. Only refine existing cloud shapes and the existing moon surface.'
    if 'mountain' in name:
        return 'This is ONLY the original ROCKY RIDGE layer. Refine its exact existing peaks with smaller rock strata and chips. Absolutely NO new moon, clouds, buildings, graves, trees, houses or towers.'
    return 'Refine only the exact existing objects and materials visible in the reference. Keep object count, colors and construction unchanged.'


def prepare(paths, work):
    work.mkdir(parents=True, exist_ok=True)
    config_path = work / 'prompts.json'
    config = json.loads(config_path.read_text()) if config_path.exists() else {}
    names = []
    for path in paths:
        path = Path(path)
        relative = path.relative_to(ROOT) if path.is_absolute() else path
        source_path = ROOT / relative
        image = Image.open(source_path).convert('RGBA')
        name = 'detail_' + hashlib.sha256(relative.as_posix().encode()).hexdigest()[:16]
        names.append(name)
        if name in config:
            continue
        chosen = None
        for d in range(12, 0, -1):
            w, h = image.width * d, image.height * d
            size = [math.ceil(max(w, h / 3) / 16) * 16, math.ceil(max(h, w / 3) / 16) * 16]
            if math.prod(size) < 655360:
                # Space around a small prop is an explicit blank region.
                size = [max(1024, size[0]), max(768, size[1])]
            if max(size) <= 3840 and math.prod(size) <= 8294400:
                chosen = d, w, h, size
                break
        if chosen is None:
            raise ValueError('Source exceeds image editing canvas: ' + str(relative))
        d, w, h, size = chosen
        sheet = Image.new('RGB', size, (255, 0, 255))
        enlarged = image.resize((w, h), Image.Resampling.NEAREST)
        sheet.paste(enlarged, (0, 0), enlarged)
        sheet.save(work / (name + '-reference.png'))
        (work / (name + '-prompt.txt')).write_text(PROMPT + '\n' + role_prompt(relative) + '\nSource role: ' + relative.as_posix(), encoding='utf8')
        layout = {'source': relative.as_posix(), 'source_sha256': hashlib.sha256(source_path.read_bytes()).hexdigest(),
            'density': d, 'size': size, 'image_bounds': [0, 0, w, h], 'logical_size': list(image.size)}
        (work / (name + '-layout.json')).write_text(json.dumps(layout, indent=2))
        config[name] = {'size': f'{size[0]}x{size[1]}', 'prompt_file': name + '-prompt.txt', 'images': [name + '-reference.png']}
    config_path.write_text(json.dumps(config, indent=2))
    (work / 'prepared-detail-tasks.json').write_text(json.dumps(names, indent=2))
    print(len(names), 'original-based detail references prepared')


def prepare_grouped(group_file, work):
    groups = json.loads(Path(group_file).read_text())
    prepare([row['source'] for row in groups['individual']], work)
    config = json.loads((work / 'prompts.json').read_text())
    names = json.loads((work / 'prepared-detail-tasks.json').read_text())
    for row, name in zip(groups['individual'], names):
        layout_path = work / (name + '-layout.json')
        layout = json.loads(layout_path.read_text())
        layout['variants'] = row['variants']
        layout_path.write_text(json.dumps(layout, indent=2))
    for start in range(0, len(groups['atlas']), 8):
        batch = groups['atlas'][start:start + 8]
        signature = '|'.join(row['source'] for row in batch)
        name = 'detail_atlas_' + hashlib.sha256(signature.encode()).hexdigest()[:16]
        names.append(name)
        if name in config:
            continue
        cols, cell = 4, 768
        rows = math.ceil(len(batch) / cols)
        size = [cols * cell, max(1024, rows * cell)]
        sheet = Image.new('RGB', size, (255, 0, 255))
        records = []
        for i, row in enumerate(batch):
            path = ROOT / row['source']
            im = Image.open(path).convert('RGBA')
            d = max(1, min(48, 704 // max(im.size)))
            w, h = im.width * d, im.height * d
            x = i % cols * cell + (cell - w) // 2
            y = i // cols * cell + (cell - h) // 2
            enlarged = im.resize((w, h), Image.Resampling.NEAREST)
            sheet.paste(enlarged, (x, y), enlarged)
            records.append({'source': row['source'], 'variants': row['variants'], 'source_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                'density': d, 'image_bounds': [x, y, x + w, y + h], 'logical_size': list(im.size)})
        sheet.save(work / (name + '-reference.png'))
        prompt = PROMPT + f'\nThis is a production sprite atlas of exactly {len(batch)} ORIGINAL scenery/terrain assets in {cols} columns and {rows} rows, read left to right then top to bottom. Redraw EVERY cell in place. Keep each cell content at EXACTLY the same position, size, color and silhouette. Do not fill empty cells, rescale, move or rearrange anything. Each image is an independent asset: no scenery or object behind it. Preserve the magenta gaps and all existing tile edge relationships. The materials in the original cells are the only materials to refine.'
        (work / (name + '-prompt.txt')).write_text(prompt)
        (work / (name + '-layout.json')).write_text(json.dumps({'size': size, 'frames': records}, indent=2))
        config[name] = {'size': f'{size[0]}x{size[1]}', 'prompt_file': name + '-prompt.txt', 'images': [name + '-reference.png']}
    (work / 'prompts.json').write_text(json.dumps(config, indent=2))
    (work / 'prepared-detail-tasks.json').write_text(json.dumps(names, indent=2))
    print(len(names), 'original-based jobs cover', sum(len(row['variants']) for rows in groups.values() for row in rows), 'source variants')


def lock_style(original, painting, density, tile_edges=True, role=''):
    """Keep source alpha and broad color design; retain the newly drawn detail.

    A service sometimes adds a moon or scenery in a transparent gap despite
    instructions. The original mask makes that impossible in the shipped art.
    Correcting low frequency color drift keeps new detail in the same art family.
    """
    expected = (original.width * density, original.height * density)
    if painting.size != expected:
        raise ValueError('Generated image does not match prepared drawing bounds')
    base = original.convert('RGBA').resize(expected, Image.Resampling.NEAREST)
    rgb = painting.convert('RGB')
    radius = max(2, density * 1.5)
    mask = np.asarray(base.getchannel('A'), np.float32) / 255
    def masked_low(image, blur_radius):
        blurred_mask = np.asarray(base.getchannel('A').filter(ImageFilter.GaussianBlur(blur_radius)), np.float32) / 255
        rgb_array = np.asarray(image.convert('RGB'), np.float32)
        premul = Image.fromarray(np.uint8(rgb_array * mask[..., None]))
        smoothed = np.asarray(premul.filter(ImageFilter.GaussianBlur(blur_radius)), np.float32)
        return smoothed / np.maximum(blurred_mask[..., None], .001)

    # Transparent pixels in the old files often contain WHITE or PURPLE RGB.
    # Alpha-aware filtering prevents those hidden colors becoming opaque rims.
    reference_low = masked_low(base, max(1, density * .3))
    painted = np.asarray(rgb, np.float32)
    painted_low = masked_low(rgb, radius)
    # Original large shapes and colors dominate. The new fine engraving and
    # smaller pixel clusters remain from the actual redraw, not procedural noise.
    detail = np.clip(painted - painted_low, -52, 52)
    detail_luma = detail[..., 0] * .25 + detail[..., 1] * .60 + detail[..., 2] * .15
    gain = np.clip(1 + detail_luma / 55, .35, 1.8)
    if 'sky' in role.lower():
        # A sky redraw may only develop the existing moon/cloud structures.
        # Flat empty sky cannot acquire a spurious building silhouette.
        old = np.asarray(original.convert('RGB'), np.float32)
        edge = np.asarray(original.convert('RGB').filter(ImageFilter.FIND_EDGES), np.float32).max(axis=2)
        permission = np.clip((old[..., 0] - 140) / 65, 0, 1)
        permission = np.maximum(permission, np.clip((edge - 35) / 55, 0, 1) * (old[..., 0] > 110))
        permission = np.asarray(Image.fromarray(np.uint8(permission * 255)).resize(expected, Image.Resampling.BILINEAR), np.float32) / 255
        gain = 1 + (gain - 1) * permission
    result = reference_low * gain[..., None]
    if tile_edges:
        y, x = np.indices(expected[::-1])
        edge_distance = np.minimum(np.minimum(x, expected[0] - 1 - x), np.minimum(y, expected[1] - 1 - y))
        weight = np.clip(edge_distance / max(1, density), 0, 1)[..., None]
        result = np.asarray(base)[..., :3] * (1 - weight) + result * weight
    out = np.asarray(base).copy()
    out[..., :3] = np.clip(np.rint(result / 2) * 2, 0, 255).astype(np.uint8)
    out[out[..., 3] == 0] = 0
    return Image.fromarray(out)


def compile_drawings(work, names):
    output_catalog = OUTPUT / 'catalog.json'
    report = json.loads(output_catalog.read_text()) if output_catalog.exists() else {'assets': {}}
    for name in names:
        layout = json.loads((work / (name + '-layout.json')).read_text())
        raw_path = work / (name + '-generated.png')
        if not raw_path.exists():
            raw_path = work / (name + '.png')
        raw = Image.open(raw_path).convert('RGB')
        native_scale = min(raw.width / layout['size'][0], raw.height / layout['size'][1])
        aspect_change = (raw.width / raw.height) / (layout['size'][0] / layout['size'][1])
        # Single originals can be registered to their canonical canvas even when
        # the service normalizes a narrow request. Atlases need fixed cell geometry.
        if abs(aspect_change - 1) > (.01 if 'frames' in layout else .30):
            raise ValueError('Service changed canvas aspect: ' + name)
        saved_source = SOURCES / (name + '.png')
        saved_source.parent.mkdir(parents=True, exist_ok=True)
        raw.save(saved_source)
        # Some services return 2048 square for a larger square request. Remap
        # coordinates proportionally, but derive output density from real texels.
        if list(raw.size) != layout['size']:
            raw = raw.resize(layout['size'], Image.Resampling.LANCZOS)
        (SOURCES / (name + '-layout.json')).write_text(json.dumps(layout, indent=2))
        (SOURCES / (name + '-prompt.txt')).write_text((work / (name + '-prompt.txt')).read_text(encoding='utf8'), encoding='utf8')
        for item in layout.get('frames', [layout]):
            source_path = ROOT / item['source']
            if item.get('source_sha256') and hashlib.sha256(source_path.read_bytes()).hexdigest() != item['source_sha256']:
                raise ValueError('Original changed after redraw preparation: ' + str(source_path))
            painting = raw.crop(item['image_bounds'])
            for variant in item.get('variants', [item['source']]):
                original = Image.open(ROOT / variant).convert('RGBA')
                d = max(1, min(12, int(painting.width * native_scale / original.width), int(painting.height * native_scale / original.height)))
                detail = painting.resize((original.width * d, original.height * d), Image.Resampling.LANCZOS)
                result = lock_style(original, detail, d, role=variant)
                rel = Path(variant).relative_to('assets')
                target = OUTPUT / rel
                target.parent.mkdir(parents=True, exist_ok=True)
                result.save(target, optimize=True)
                report['assets']['res://' + variant] = {'texture': 'res://' + target.relative_to(ROOT).as_posix(),
                    'logical_size': list(original.size), 'physical_size': list(result.size), 'density': d,
                    'method': 'original image edit; original alpha/composition/palette locked; new AI-drawn fine detail',
                    'detail_reference_original': item['source'], 'redraw_source': saved_source.relative_to(ROOT).as_posix(),
                    'returned_canvas': list(Image.open(saved_source).size), 'reference_canvas': layout['size'],
                    'sha256': hashlib.sha256(target.read_bytes()).hexdigest()}
                print(variant, result.size, flush=True)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    output_catalog.write_text(json.dumps(report, indent=2) + '\n')
    mapping = {p: v['texture'] for p, v in report['assets'].items()}
    (ROOT / 'scripts/visuals/redrawn_texture_catalog.gd').write_text('extends RefCounted\n## Generated from original-based redraws. Logical size always comes from the source.\nconst REPLACEMENTS := ' + json.dumps(mapping, indent=2) + '\n')


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('mode', choices=['prepare', 'prepare-grouped', 'compile'])
    p.add_argument('items', nargs='+')
    p.add_argument('--work', type=Path, default=ROOT / 'screenshots/acceptance/native-scenery-redraw/ai')
    a = p.parse_args()
    if a.mode == 'prepare-grouped':
        prepare_grouped(a.items[0], a.work)
    elif a.mode == 'prepare':
        prepare(a.items, a.work)
    else:
        compile_drawings(a.work, a.items)
