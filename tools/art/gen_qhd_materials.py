"""Refine existing raster art with physical-pixel facets and material engraving.

This is a derived-image treatment, not a claim to redraw imported characters.
The original design and palette masses are preserved. New edge cuts, inset
surface lines and bevel highlights are painted at density 4. Random screen grain,
blur, sharpening and interpolated upscaling are deliberately absent.
"""
from pathlib import Path
import hashlib
import json
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import sys

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/qhd'
D=4
sys.path.insert(0,str(ROOT/'tools'))
from draw_mechanical_props import render as draw_mechanical, KEYS
from gen_theme_tiles import HISTORY_RAMPS, GROUND_REMAINS_RAMP
from density_draw import bevel_materials


def classify(path):
    name=path.stem.lower()
    if any(x in name for x in ('tree','bush','leaf','grass','moss_edge')):
        return 'foliage'
    if any(x in name for x in ('cloud','fog','glow','beam','vignette','haze','steam','sky')):
        return 'atmosphere'
    if 'characters' in path.parts or path.parts[0]=='player' or name.startswith('seated'):
        return 'actor'
    if path.parts[0]=='ui':
        return 'ui'
    if any(x in name for x in ('pipe','metal','beam','girder','machine','chain','gear','forge','iron','warning','furnace','sword')):
        return 'metal'
    return 'stone'


def refine(source,kind):
    p=np.array(source.convert('RGBA'))
    # Preserve the existing palette masses, then author detail within them.
    image=source.convert('RGBA').resize((source.width*D,source.height*D),Image.Resampling.NEAREST)
    if kind=='atmosphere':
        # Light masks and atmospheric plates intentionally remain low-frequency.
        return None
    arr=np.array(image)
    rgb=arr[:,:,:3].astype(np.int16)
    opaque=arr[:,:,3]==255
    up=np.concatenate((rgb[:1],rgb[:-1]),axis=0)
    down=np.concatenate((rgb[1:],rgb[-1:]),axis=0)
    left=np.concatenate((rgb[:,:1],rgb[:,:-1]),axis=1)
    right=np.concatenate((rgb[:,1:],rgb[:,-1:]),axis=1)
    # Single physical-pixel facet edges, not a stroke around each source pixel.
    material=opaque & (rgb.max(axis=2)>35) & (rgb.max(axis=2)<226)
    top=material & (np.max(np.abs(rgb-up),axis=2)>18)
    bottom=material & (np.max(np.abs(rgb-down),axis=2)>18) & ~top
    side=material & (np.max(np.abs(rgb-left),axis=2)>24) & ~top & ~bottom
    rgb[top]+=np.array([13,12,10])
    rgb[bottom]-=np.array([10,10,9])
    rgb[side]+=np.array([6,7,8])
    arr[:,:,:3]=rgb.clip(0,255).astype(np.uint8)
    # Chamfer convex silhouette corners by one physical pixel. Full logical
    # pixel centres, feet and material bounds stay covered by their old design.
    a=p[:,:,3]>0
    padded=np.pad(a,1)
    for sy,sx,dy,dx in [(0,0,-1,-1),(0,3,-1,1),(3,0,1,-1),(3,3,1,1)]:
        convex=a & ~padded[1+dy:1+dy+a.shape[0],1:1+a.shape[1]] & ~padded[1:1+a.shape[0],1+dx:1+dx+a.shape[1]]
        arr[sy::D,sx::D,3][convex]=0
    image=Image.fromarray(arr)
    if kind in ('actor','ui','foliage'):
        return image
    # Sparse material engraving, anchored inside broad palette runs. It cannot
    # cross a silhouette, grout line or existing painted material boundary.
    layer=Image.new('RGBA',image.size)
    d=ImageDraw.Draw(layer)
    for y in range(2,p.shape[0]-2,4):
        x=1
        while x<p.shape[1]-2:
            color=p[y,x]
            end=x+1
            while end<p.shape[1]-1 and np.array_equal(p[y,end],color):
                end+=1
            lum=int(color[:3].max())
            if end-x>=4 and color[3]==255 and 40<lum<210:
                shade=tuple(max(0,int(v)-12) for v in color[:3])+(255,)
                glint=tuple(min(255,int(v)+14) for v in color[:3])+(255,)
                if kind=='metal':
                    # A short inset witness mark with an illuminated lower lip.
                    x0=(x+1)*D
                    x1=min((end-1)*D,x0+13)
                    yy=y*D+2
                    d.line((x0,yy,x1,yy),fill=shade,width=1)
                    d.line((x0+1,yy+1,x1-1,yy+1),fill=glint,width=1)
                else:
                    # Two subpixel planes of a stone chip, following the facet.
                    xx=(x+1)*D
                    yy=y*D+1
                    d.polygon([(xx,yy),(xx+5,yy+1),(xx+3,yy+3),(xx,yy+2)],fill=shade)
                    d.line((xx,yy,xx+4,yy),fill=glint,width=1)
            x=end
    detail=np.array(layer)
    detail[:,:,3]=np.where(arr[:,:,3]==255,detail[:,:,3],0)
    image.alpha_composite(Image.fromarray(detail))
    return image


def logo(source):
    # Rasterize the existing outline font at physical density, retaining the
    # exact shipped logical rectangle and its intended blackletter wordmark.
    import sys
    sys.path.insert(0,str(ROOT/'tools'))
    import gen_ui_kit as ui
    bits=np.array(ui._threshold_glyphs(ui.TITLE_TEXT,ui.TITLE_CAP*8),np.uint8)*255
    glyph=Image.fromarray(bits)
    w,h=source.size
    target=(max(1,(w-24)*D),max(1,(h-30)*D))
    # Outline font is sampled again at its target size; only the final layout
    # fit may adjust a few pixels when font metrics differ between versions.
    glyph=glyph.resize(target,Image.Resampling.NEAREST)
    mask=Image.new('L',(w*D,h*D))
    mask.paste(glyph,(12*D,12*D))
    a=np.array(mask)>0
    yy=np.arange(h*D)[:,None]/(h*D)
    colors=np.array([[244,226,190],[255,193,74],[173,91,42],[94,44,28]],np.uint8)
    levels=np.broadcast_to(np.clip((yy*4).astype(int),0,3),a.shape)
    arr=np.zeros((h*D,w*D,4),np.uint8)
    arr[:,:,:3]=colors[levels]
    arr[:,:,3]=np.where(a,255,0)
    rim=np.array(mask.filter(ImageFilter.MaxFilter(3)))>0
    arr[rim & ~a]=[13,10,16,255]
    top=a & ~np.concatenate((a[:1],a[:-1]),axis=0)
    arr[top,:3]=[255,238,202]
    return Image.fromarray(arr)


def main():
    records={}
    preserved=[]
    files=[]
    for folder in ('env','characters','ui','player','title'):
        files+=list((ROOT/'assets'/folder).rglob('*.png'))
    for file in sorted(files):
        rel=file.relative_to(ROOT/'assets')
        # Independent boss sources and title geometry have dedicated drawers.
        if any(part.startswith('original_') for part in rel.parts):
            continue
        if rel.parts[0]=='title' and not file.stem.startswith('seated') and file.stem!='lantern':
            continue
        # Obsolete boss sprites are retained only for backwards compatibility.
        if rel.parts[0]=='characters' and rel.parts[1] in ('boss_nightmare','boss_hollow_bell','bell_founder','emberwind_herald'):
            preserved.append({'path':rel.as_posix(),'reason':'legacy fallback; original boss replaces this artwork'})
            continue
        source=Image.open(file).convert('RGBA')
        kind=classify(rel)
        mechanical=(len(rel.parts)==4 and rel.parts[:2]==('env','props') and file.stem in KEYS
                    and rel.parts[2] in (*HISTORY_RAMPS,'ground'))
        if mechanical:
            family=rel.parts[2]
            ramp=GROUND_REMAINS_RAMP if family=='ground' else HISTORY_RAMPS[family]
            image=bevel_materials(draw_mechanical(file.stem,source.size,ramp,family,density=4))
        else:
            image=logo(source) if rel.as_posix()=='ui/title_logo.png' else refine(source,kind)
        if image is None:
            preserved.append({'path':rel.as_posix(),'reason':'low-frequency atmosphere/light mask retained intentionally'})
            continue
        target=OUT/rel
        target.parent.mkdir(parents=True,exist_ok=True)
        image.save(target,optimize=True)
        records['res://assets/'+rel.as_posix()]={'texture':'res://assets/qhd/'+rel.as_posix(),
            'logical_size':source.size,'physical_size':image.size,'material':kind,
            'method':'original mechanical geometry at density 4' if mechanical else 'outline font rasterization' if file.stem=='title_logo' else 'derived physical-pixel facets and material engraving',
            'sha256':hashlib.sha256(target.read_bytes()).hexdigest()}
    (OUT/'materials.json').write_text(json.dumps({'assets':records,'preserved':preserved},indent=2)+'\n')
    print(f'Refined {len(records)} raster assets; retained {len(preserved)} atmospheric/legacy inputs')


if __name__=='__main__':
    main()
