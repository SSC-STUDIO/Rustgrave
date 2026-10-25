"""Build QHD companion art with native drawings or source-assisted relief.

Dedicated title drawings supply native geometry, fittings and casting texture.
Other assets use source-assisted refinement; not every frame was redrawn.
Contours are reconstructed with EPX; native-size geometry then adds chisel cuts,
cast-iron bevels, grain and metal fasteners. No blur, sharpen or random grain.
Original files remain the editable silhouette/palette/animation source of truth.
"""
from pathlib import Path
import hashlib
import json
import re
import numpy as np
from PIL import Image, ImageDraw
import gen_title_hammer

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/qhd'
FAMILIES = ('title', 'env', 'characters', 'player', 'ui', 'fx', 'story')
SOFT = ('glow', 'halo', 'fog', 'mist', 'vignette', 'beam.png', 'steam', 'cloud',
        'rain', 'spark', 'mote', 'smoke', 'dust', 'parallax_sky', 'river_current')
AUTHORED_TITLE = {'title/hammer_body.png', 'title/hammer_head.png', 'title/hammer_arm.png'}


def epx(a):
    """Exact palette-preserving contour reconstruction; no interpolated colors.

    Neighbours are copied only from the same side of the silhouette. Transparent
    texels often carry white RGB, and copying that onto an opaque corner leaves a
    bright rim once the original alpha is restored.
    """
    p = np.pad(a, ((1, 1), (1, 1), (0, 0)), mode='edge')
    solid = a[:, :, 3] > 0
    s = np.pad(solid, 1, mode='edge')
    b, d, f, h = p[:-2, 1:-1], p[1:-1, :-2], p[1:-1, 2:], p[2:, 1:-1]
    sb, sd, sf, sh = s[:-2, 1:-1], s[1:-1, :-2], s[1:-1, 2:], s[2:, 1:-1]
    same = lambda x, y: np.all(x == y, axis=2)
    possible = ~same(b, h) & ~same(d, f)
    out = np.repeat(np.repeat(a, 2, axis=0), 2, axis=1)
    for dy, dx, x, y, sx, sy in ((0, 0, d, b, sd, sb), (0, 1, b, f, sb, sf),
                                 (1, 0, d, h, sd, sh), (1, 1, h, f, sh, sf)):
        mask = possible & same(x, y) & (sx == solid) & (sy == solid)
        out[dy::2, dx::2][mask] = x[mask]
    return out


def material(path):
    name = path.as_posix().lower()
    if any(key in name for key in ('flame', 'forge_mouth', 'fire_skull', 'fx_enemy_death')):
        return 'ember'
    if path.parts[0] in ('characters', 'player'):
        return 'character'
    if any(key in name for key in ('wood', 'crate', 'barrel', 'plank', 'sign', 'coffin')):
        return 'wood'
    if any(key in name for key in ('stone', 'slab', 'brick', 'wall', 'church', 'crypt', 'grave', 'tomb', 'rock', 'paving')):
        return 'stone'
    if path.parts[0] == 'ui':
        return 'interface'
    return 'iron'


def relief(source, kind, density):
    """Material cuts are placed in physical texels, within the original silhouette.

    Color regions supply the part masks: raised top/left edge, recessed lower
    edge, then material-specific incisions. These are new sub-world-pixel marks.
    Darkness and detail contrast stay bounded so characters remain readable.
    """
    original = np.array(source.convert('RGBA'))
    a = epx(epx(original)) if density == 4 else epx(original)
    rgb = a[:, :, :3].astype(np.int16)
    alpha = a[:, :, 3]
    solid = alpha > 200
    lum = (rgb[:, :, 0] * .25 + rgb[:, :, 1] * .60 + rgb[:, :, 2] * .15)
    active = solid & (lum > 21) & (lum < 222)
    # Material plate edges, not every magnified source pixel.
    above = np.roll(lum, 1, axis=0)
    left = np.roll(lum, 1, axis=1)
    below = np.roll(lum, -1, axis=0)
    top_edge = active & ((lum - above > 10) | (lum - left > 14))
    bottom_edge = active & (lum - below > 12)
    delta = np.zeros(solid.shape, np.int16)
    delta[top_edge] = 9 if kind == 'character' else 12
    delta[bottom_edge & ~top_edge] = -10
    y, x = np.indices(solid.shape)
    # No independent random marks: these deterministic strokes follow the
    # surface's construction. Character frames receive only local contour relief
    # to avoid texture swimming as their pose moves across the frame canvas.
    interior = active.copy()
    for axis in (0, 1):
        interior &= np.roll(active, density, axis) & np.roll(active, -density, axis)
    if kind == 'wood':
        grain = ((x + (y // (11 * density)) % 3) % (5 * density) == 2) & (y % (17 * density) > 3)
        delta[interior & grain] = -10
        delta[interior & np.roll(grain, 1, axis=1)] = 5
    elif kind == 'stone':
        course = y % (8 * density)
        joint = (course == 0) | (((x + (y // (8 * density) % 2) * 8 * density) % (16 * density) == 0) & (course < 7 * density))
        delta[interior & joint] = -11
        delta[interior & np.roll(joint, 1, axis=0) & ~joint] = 7
        # Short diagonal chisel notches rather than stippled noise.
        cut = ((x + y) % (19 * density) == 0) & (x % (19 * density) < 4)
        delta[interior & cut] = -7
    elif kind == 'iron':
        # Fine machining lines and small recessed screw heads on broad plates.
        groove = (y % (12 * density) == 0) & (x % (28 * density) > 5 * density)
        delta[interior & groove] = -8
        cx, cy = (x % (20 * density)) - 4 * density, (y % (20 * density)) - 4 * density
        nut = ((np.abs(cx) + np.abs(cy)) <= 3) & ((np.abs(cx) + np.abs(cy)) >= 2)
        delta[interior & nut] = 16
        delta[interior & (np.abs(cx) <= 1) & (cy == 0)] = -16
    elif kind == 'ember':
        # Preserve coherent animation tongues; only refine their existing ridges.
        delta[top_edge] = 7
        delta[bottom_edge] = -5
    elif kind == 'interface':
        delta[top_edge] = 10
        delta[bottom_edge] = -8
    # Keep each source's hue; a restrained tonal extension supplies the bevels.
    a[:, :, :3] = np.clip(rgb + delta[:, :, None], 0, 255).astype(np.uint8)
    # Preserve the full canvas and exact bottom-centre anchor/alpha footprint.
    a[:, :, 3] = np.repeat(np.repeat(original[:, :, 3], density, axis=0), density, axis=1)
    a[a[:, :, 3] == 0] = 0
    return Image.fromarray(a), int(np.count_nonzero(delta))


def title_detail(im, relative, density):
    """Original small-scale fittings drawn for the title's existing machinery.

    Explicit fixture coordinates are world units, converted before rasterization.
    These are not copied image details: seams, inspection hatches and gauge marks.
    """
    specs = {
        'title/mass_left.png': [(48, 142, 31, 42), (145, 203, 27, 36), (89, 292, 38, 30)],
        'title/hall_mid.png': [(80, 180, 26, 40), (569, 180, 26, 40)],
    }
    if relative.as_posix() not in specs:
        return im
    overlay = Image.new('RGBA', im.size)
    d = ImageDraw.Draw(overlay)
    s = density
    for x, y, w, h in specs[relative.as_posix()]:
        box = (x*s, y*s, (x+w)*s, (y+h)*s)
        d.rounded_rectangle(box, radius=2*s, fill=(24, 20, 27), outline=(73, 61, 64), width=1)
        d.line((x*s+2, y*s+2, (x+w)*s-2, y*s+2), fill=(107, 85, 78), width=1)
        for px in (x+2, x+w-2):
            for py in (y+2, y+h-2):
                d.ellipse((px*s-2, py*s-2, px*s+2, py*s+2), fill=(105, 91, 86), outline=(12, 10, 18))
                d.line((px*s-1, py*s, px*s+1, py*s), fill=(24, 20, 27))
        for slot in range(5):
            yy = (y+7+slot*3)*s
            d.line(((x+6)*s, yy, (x+w-6)*s, yy), fill=(12, 11, 18), width=2)
            d.line(((x+6)*s, yy+2, (x+w-6)*s, yy+2), fill=(75, 57, 53), width=1)
    a, b = np.array(im), np.array(overlay)
    mask = (a[:, :, 3] > 200) & (b[:, :, 3] > 0)
    a[mask, :3] = b[mask, :3]
    return Image.fromarray(a)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    # These enlarged title props need 8x local density and purpose-drawn parts.
    # Rebuild them from their drawing source; generic relief must not overwrite
    # the journal, pin fittings or the native casting texture.
    gen_title_hammer.main()
    records = []
    for family in FAMILIES:
        for path in sorted((ROOT / 'assets' / family).rglob('*.png')):
            relative = path.relative_to(ROOT / 'assets')
            name = relative.as_posix().lower()
            if any(key in name for key in SOFT):
                continue
            # Legacy alternate plates are unused duplicates; keep the active art.
            if '_legacy' in name or '_2x' in name:
                continue
            source = Image.open(path).convert('RGBA')
            # A 1280-wide painted storyboard already has half-QHD density.
            density = 2 if max(source.size) >= 1280 else 4
            kind = material(relative)
            authored = relative.as_posix() in AUTHORED_TITLE
            if authored:
                density = gen_title_hammer.DENSITY
                image = Image.open(OUT / relative).convert('RGBA')
                marks = int(np.count_nonzero(np.array(image)[:, :, 3]))
            else:
                image, marks = relief(source, kind, density)
                image = title_detail(image, relative, density)
            target = OUT / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            image.save(target, optimize=True)
            records.append({'source': 'res://assets/' + relative.as_posix(),
                'companion': 'res://assets/qhd/' + relative.as_posix(),
                'logical_size': list(source.size), 'density': density,
                'physical_size': list(image.size), 'material': kind, 'relief_texels': marks,
                'method': 'original geometry and material fields' if authored else 'source-assisted material relief',
                'source_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                'sha256': hashlib.sha256(target.read_bytes()).hexdigest()})
    report = {'version': 1, 'target': [2560, 1440], 'count': len(records),
        'method': 'Original native title machinery; other assets use EPX contour reconstruction, material relief and title fittings',
        'records': records}
    (OUT / 'manifest.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf8')
    print(json.dumps({'textures': len(records), 'disk_mb': round(sum((ROOT / r['companion'].replace('res://','')).stat().st_size for r in records) / 1048576, 2)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
