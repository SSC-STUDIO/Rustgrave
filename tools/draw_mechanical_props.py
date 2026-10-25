"""Original 1x pixel drawings for the chapter machinery set.

Replaces flat luminance-mapped placeholders. Sizes and bottom-centre anchors are
retained; geometry is drawn here, without tracing or resampling an input image.
gen_theme_tiles.py calls render too, so rebuilding a theme preserves the artwork.
"""
from pathlib import Path
import json
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
KEYS = ('beam','beam_bolts','beam_narrow','metal_panel','pipe_valve',
        'broken_machine','girder_l','girder_r','fence','warning_plate','chain')


def render(key, size, ramp, family, density=1):
    if density == 4:
        from art.density_draw import Images, Pens
        im = Images.new('RGBA', size)
        d = Pens.Draw(im)
    else:
        im = Image.new('RGBA', size)
        d = ImageDraw.Draw(im)
    p = [tuple(rgb)+(255,) for _,rgb in ramp]
    w,h = size
    def rect(box,c): d.rectangle(box,fill=p[c])
    def line(points,c,width=1): d.line(points,fill=p[c],width=width)
    def bolt(x,y):
        rect((x-1,y-1,x+1,y+1),0)
        d.point((x,y-1),fill=p[4]);d.point((x,y),fill=p[3])
    def rail(y):
        rect((0,y,w-1,y+3),0);line((1,y+1,w-2,y+1),3)
        line((1,y+2,w-2,y+2),1)
        for x in (3,w-4): bolt(x,y+1)
    def diagonal(reverse=False):
        x0,x1=(3,w-4) if not reverse else (w-4,3)
        line((x0,4,x1,h-5),0,7);line((x0,4,x1,h-5),2,5)
        line((x0-1,4,x1-1,h-5),4);line((x0+2,5,x1+2,h-4),1)
        for x,y in [(x0,4),(x1,h-5)]: bolt(x,y)
    if key in ('beam','beam_bolts','beam_narrow'):
        diagonal();diagonal(True);rail(0);rail(h-4)
        if key=='beam_bolts':
            rect((w//2-4,h//2-3,w//2+4,h//2+3),0)
            rect((w//2-3,h//2-2,w//2+3,h//2+2),2)
            bolt(w//2-2,h//2);bolt(w//2+2,h//2)
    elif key in ('girder_l','girder_r'):
        diagonal(key=='girder_r')
        for y,x in [(0,w-9 if key=='girder_r' else 0),
                    (h-7,0 if key=='girder_r' else w-9)]:
            rect((x,y,x+8,y+6),0);rect((x+1,y+1,x+7,y+4),2)
            line((x+1,y+1,x+7,y+1),4);bolt(x+4,y+3)
    elif key in ('metal_panel','warning_plate'):
        rect((0,0,w-1,h-1),0);rect((1,1,w-2,h-2),1)
        rect((2,2,w-3,h-3),2);line((2,2,w-3,2),4)
        line((2,3,2,h-3),3);line((3,h-3,w-3,h-3),0)
        for x in (4,w-5):
            for y in (4,h-5): bolt(x,y)
        if key=='metal_panel':
            line((4,h//2,w-5,h//2),0);line((4,h//2+1,w-5,h//2+1),3)
            for y in (9,12,22,25):
                line((9,y,w-9,y),0);line((9,y+1,w-9,y+1),1)
            # A buckled corner and two long scoring marks.
            line((w-9,h-5,w-5,h-9),4);line((6,17,10,20),1)
        else:
            for x in range(5,w-5):
                for y in (h-9,h-8,h-7):
                    d.point((x,y),fill=p[0 if (x+y)//4%2 else 3])
            d.polygon([(w//2,7),(7,h-13),(w-8,h-13)],fill=p[0])
            d.line([(w//2,10),(11,h-15),(w-12,h-15),(w//2,10)],fill=p[4])
            line((w//2,13,w//2,17),4);d.point((w//2,19),fill=p[4])
    elif key=='pipe_valve':
        # Elbow, cast flange, wheel and spindle have distinct silhouettes.
        line((0,h-8,12,h-8,12,11,w-1,11),0,9)
        line((0,h-8,12,h-8,12,11,w-1,11),2,7)
        line((1,h-10,10,h-10,10,9,w-1,9),4)
        rect((4,h-13,7,h-3),0);line((5,h-12,5,h-4),3)
        rect((w-9,6,w-5,16),0);line((w-8,7,w-8,15),3)
        d.ellipse((14,2,30,18),fill=p[0]);d.ellipse((16,4,28,16),fill=p[3])
        d.ellipse((18,6,26,14),fill=p[0]);line((22,5,22,15),2)
        line((17,10,27,10),2);bolt(22,10)
        line((16,5,19,3),4);line((27,14,29,11),1)
        rect((8,h-7,14,h-2),1)
        rect((0,h-3,17,h-1),0);line((1,h-3,16,h-3),3)
    elif key=='broken_machine':
        rect((1,h-6,w-2,h-1),0);line((2,h-5,w-3,h-5),3)
        d.polygon([(3,h-7),(3,12),(8,7),(20,7),(24,12),(24,h-7)],fill=p[0])
        rect((5,13,21,h-7),2);line((6,14,6,h-9),4)
        # Missing cover exposes an axle, wheel teeth and dark hollow.
        d.ellipse((7,13,21,27),fill=p[1]);d.ellipse((10,16,18,24),fill=p[0])
        for x,y in [(7,20),(14,13),(21,20),(14,27)]: rect((x-1,y-1,x+1,y+1),3)
        bolt(14,20);line((20,10,28,6,32,11),2,3)
        line((23,23,29,25,27,30,33,31),1,2)
        line((25,24,30,26,28,29),3)
        d.polygon([(2,11),(8,3),(15,5),(9,12)],fill=p[2])
        line((3,10,8,4,13,5),4)
    elif key=='fence':
        for x in (3,12,22,w-4):
            rect((x-1,2,x+1,h-1),0);line((x,3,x,h-2),3)
            d.polygon([(x-2,4),(x,0),(x+2,4)],fill=p[3])
        for y in (6,h-7):
            rect((0,y,w-1,y+2),0);line((0,y,w-1,y),3)
        for x in (4,13,23,w-5): d.point((x,7),fill=p[4])
    elif key=='chain':
        for y in range(-1,h,8):
            d.ellipse((1,y,7,y+10),fill=p[0]);d.ellipse((2,y+1,6,y+9),fill=p[3])
            d.ellipse((3,y+3,5,y+7),fill=(0,0,0,0))
            line((2,y+2,2,y+6),4);line((6,y+5,6,y+8),1)
            line((4,y+8,4,y+12),2,2)
    else:
        raise ValueError(key)
    # Sparse, attached corrosion clusters follow surfaces; avoid random confetti.
    pixels=im.load()
    for y in range(2,h-2):
        for x in range(2,w-2):
            if pixels[x,y][3] and pixels[x,y] in (p[2],p[3]) and (x*17+y*31)%113<3:
                pixels[x,y]=p[1]
                if pixels[x+1,y][3]: pixels[x+1,y]=p[1]
    if family=='moss':
        for x in range(3,w-3,7):
            for y in range(h-3):
                if pixels[x,y][3]:
                    for dy in range(3):
                        if pixels[x,y+dy][3]: pixels[x,y+dy]=p[3]
                    break
    return im.image if density == 4 else im


def main():
    from gen_theme_tiles import HISTORY_RAMPS, GROUND_REMAINS_RAMP
    count=0
    for family in (*HISTORY_RAMPS,'ground'):
        ramp=GROUND_REMAINS_RAMP if family=='ground' else HISTORY_RAMPS[family]
        for key in KEYS:
            path=ROOT/'assets/env/props'/family/(key+'.png')
            if not path.exists(): continue
            with Image.open(path) as old: size=old.size
            render(key,size,ramp,family).save(path)
            count+=1
    print(json.dumps({'original_mechanical_drawings':count}))

if __name__=='__main__': main()
