"""Draw title geometry at 16 subpixel sample positions, with new fine joinery.

No original title PNG is used as a drawing input. Existing procedural sources
are evaluated on 4x4 sample phases, preserving their layout and seeded palette.
The output interleaves those geometry samples without antialiasing. The gears
are rasterized directly at density 4. Fine rivets, plate joints and dial ticks
are then authored in physical pixels, clipped to the original opaque surfaces.
"""
from pathlib import Path
import hashlib
import json
import math
import sys
import numpy as np
from PIL import Image, ImageDraw
from density_draw import bevel_materials

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tools'))
import title_px as px
import gen_title_hall as hall
import gen_title_assets as title

OUT = ROOT/'assets/qhd/title'
D = 4
phase = (0, 0)
canvases = {}
original_masks = {name:getattr(px,name) for name in ['mask_rect','mask_poly','mask_line','mask_ellipse']}


def sample(name, w, h, *args, **kw):
    # Use exact high-density geometry, then give the existing painter one
    # sample per logical pixel. This keeps its authored noise and ramp fields.
    if name == 'mask_rect':
        mask = original_masks[name](w*D, h*D, *(v*D for v in args))
    elif name == 'mask_poly':
        mask = original_masks[name](w*D, h*D, [(x*D,y*D) for x,y in args[0]])
    elif name == 'mask_ellipse':
        mask = original_masks[name](w*D, h*D, *(v*D for v in args))
    else:
        p0,p1 = args[:2]
        width = args[2] if len(args)>2 else kw.get('width',1)
        mask = original_masks[name](w*D,h*D,tuple(v*D for v in p0),tuple(v*D for v in p1),width*D)
    return mask[phase[1]::D, phase[0]::D]


def capture(image, name):
    p = np.array(image.convert('RGBA'))
    if name not in canvases:
        canvases[name] = np.zeros((p.shape[0]*D,p.shape[1]*D,4),np.uint8)
    canvases[name][phase[1]::D,phase[0]::D] = p


def fine_joinery(image, name):
    image = bevel_materials(image)
    layer = Image.new('RGBA',image.size)
    d = ImageDraw.Draw(layer)
    def line(points, fill='#706269', width=1):
        d.line([(round(x*D),round(y*D)) for x,y in points],fill=fill,width=width)
    def rivet(x,y,r=.65):
        x,y,r=x*D,y*D,r*D
        d.ellipse((x-r,y-r,x+r,y+r),fill='#14121a',outline='#6d5c58',width=1)
        d.line((x-r/2,y-r/2,x+r/2,y+r/2),fill='#a08169',width=1)
        d.point((x-1,y-1),fill='#b5997b')
    def dial(x,y,r):
        d.ellipse(((x-r)*D,(y-r)*D,(x+r)*D,(y+r)*D),fill='#171821',outline='#6b6c70',width=2)
        for k in range(11):
            a=math.radians(140+k*26)
            line([(x+math.cos(a)*r*.78,y+math.sin(a)*r*.78),
                  (x+math.cos(a)*r*.58,y+math.sin(a)*r*.58)],'#aaa190',1)
        line([(x,y),(x+r*.40,y-r*.50)],'#d29a55',2)
        rivet(x,y,.4)
    if name == 'bridge.png':
        for x in range(4,350,8):
            rivet(x,27.8,.5)
        for x in range(0,352,32):
            for y in (39,58):
                rivet(x+2,y,.6)
            line([(x+5,30.5),(x+29,30.5)],'#8a7370')
            line([(x+6,64),(x+28,64)],'#544650')
        for x in range(10,340,16):
            line([(x,26.5),(x+3,26.5)],'#b09679')
    if name == 'mass_left.png':
        dial(92,232,7)
        dial(130,296,5.5)
        for x in range(26,178,12):
            rivet(x,209,.7)
            rivet(x,263,.7)
        for x in (49,91,133):
            line([(x,213),(x,257)],'#4a4653')
            for y in (216,228,244,255):
                rivet(x+2,y,.5)
        for x in range(182,254,10):
            rivet(x,270,.6)
        for y in range(276,360,14):
            for x in (190,210,230):
                rivet(x,y,.55)
    if name == 'mass_right.png':
        dial(186,222,7)
        for x in range(46,174,8):
            for y in (194,306):
                rivet(x,y,.6)
        for y in (66,106,146):
            for x in range(154,204,7):
                rivet(x,y+1,.5)
        for k in range(11):
            a=math.pi+k*math.pi/10
            rivet(80+31*math.cos(a),232+23*math.sin(a),.6)
        for x in (125,151,174):
            line([(x,202),(x,286)],'#322b36')
            line([(x+.5,203),(x+.5,284)],'#6d5152')
            for y in range(210,280,16):
                rivet(x+2,y,.5)
    if name in ('roof.png','hall_mid.png'):
        # These lie on the old trusses; transparent holes stay transparent.
        for x in range(12,image.width//D,28):
            for y in ((19,35,48) if name=='roof.png' else (98,180,270)):
                rivet(x,y,.45)
    # Never fill transparent cutouts or extend a silhouette with extra detail.
    a=np.array(layer)
    source=np.array(image)
    a[:,:,3]=np.where(source[:,:,3]==255,a[:,:,3],0)
    image.alpha_composite(Image.fromarray(a))
    return image


def main():
    global phase
    OUT.mkdir(parents=True,exist_ok=True)
    for name in original_masks:
        def wrapped(w,h,*args,_name=name,**kw):
            return sample(_name,w,h,*args,**kw)
        for mod in (px,hall,title):
            setattr(mod,name,wrapped)
    px.save_image = capture
    hall.save_image = capture
    title.save_image = capture
    builders=[hall.build_hall_far,hall.build_hall_mid,hall.build_roof,
              hall.build_bridge,hall.build_mass_left,hall.build_mass_right]
    for sy in range(D):
        for sx in range(D):
            phase=(sx,sy)
            for build in builders:
                build()
        print(f'Geometry sample row {sy+1}/4',flush=True)
    records={}
    def deliver(image,name,method):
        image.save(OUT/name,optimize=True)
        # Existing PNGs are read only to enforce the logical contract.
        logical=Image.open(ROOT/'assets/title'/name).size
        assert image.size==tuple(v*D for v in logical),(name,image.size,logical)
        records['res://assets/title/'+name]={'texture':'res://assets/qhd/title/'+name,
            'logical_size':logical,'physical_size':image.size,'method':method,
            'sha256':hashlib.sha256((OUT/name).read_bytes()).hexdigest()}
    for name,arr in canvases.items():
        deliver(fine_joinery(Image.fromarray(arr),name),name,'sampled original geometry + physical-pixel joinery')
    # Direct-density gear rasterization, no phase sampling or old PNG input.
    title.save_image=lambda image,name:deliver(image,name,'original polar gear drawing rasterized at density 4')
    for name,radius,teeth,spokes,count,ramp,kw in [
        ('gear_big.png',66,24,8,32,title.RUST,dict(hub=.28,rim=.14,tooth=.10,spoke=.15,seed=11)),
        ('gear_mid.png',42,16,8,32,title.IRON,dict(hub=.30,rim=.17,tooth=.12,spoke=.16,direction=-1,seed=12,light=(-.5,-.86))),
        ('gear_small.png',26,12,6,24,title.RUST,dict(hub=.34,rim=.2,tooth=.14,spoke=.2,seed=13,cols=6))]:
        title.gear_sheet(name,radius,teeth,spokes,count,ramp,density=D,**kw)
    (OUT.parent/'title.json').write_text(json.dumps(records,indent=2)+'\n')
    print(f'Drew {len(records)} title layers at QHD density',flush=True)


if __name__=='__main__':
    main()
