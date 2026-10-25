"""Original connected fire, coal bed and forge grate; no external image inputs.

The low fallback and QHD strip use the same continuous drawing at densities 1/4.
Eight looping phases; every tongue grows from the fixed root/coal bed.
"""
from pathlib import Path
import json
import math
import hashlib
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[2]
COUNT=8


def tongue(draw, density, root, height, width, clock, seed, color):
    left,right=[],[]
    for i in range(33):
        t=i/32
        # Advected bend moves upwards; no flame mass detaches from the fuel.
        bend=(math.sin(clock*2+seed-t*5)*1.1+math.sin(clock+seed+t*8)*.45)*t
        x=root[0]+bend
        y=root[1]-height*t
        r=width*(1-t)**.68*(1+.14*math.sin(t*10-clock*2+seed))
        left.append(((x-r)*density,y*density))
        right.append(((x+r)*density,y*density))
    draw.polygon(left+right[::-1],fill=color)


def flame(density,frame):
    image=Image.new('RGBA',(16*density,24*density))
    draw=ImageDraw.Draw(image)
    clock=frame/COUNT*math.tau
    for color,scale in [('#b53c17',1),('#ee651b',.87),('#ffad35',.66),('#ffe49a',.36)]:
        for x,h,w,seed in [(8,20,4.2,0),(4.5,13,2.5,1.7),(11.2,15,2.7,3.4)]:
            height=(h+1.6*math.sin(clock+seed))*scale
            tongue(draw,density,(x,24.0),height,w*scale,clock,seed,color)
    return image


def forge(density,frame):
    w,h=60,66
    image=Image.new('RGBA',(w*density,h*density),'#3b1815')
    draw=ImageDraw.Draw(image)
    def box(rect,color):
        draw.rectangle(tuple(round(v*density) for v in rect),fill=color)
    # Distinct refractory courses and fine mortar, lit from the coal bed.
    for row in range(7):
        for x in range(-8 if row%2 else 0,w,14):
            y=row*9
            box((x+.4,y+.4,x+13.5,y+8.4),'#60301e' if row<4 else '#ae4c20')
            box((x+.8,y+.6,x+13,y+1),'#8a4426')
    clock=frame/COUNT*math.tau
    for color,scale in [('#ac3416',1),('#ed5a17',.91),('#ff9a29',.71),('#ffdda0',.42)]:
        for x,height,width,seed in [(7,27,7,1.5),(18,43,8,0),(31,36,9,3.8),(45,46,8,2),(55,28,6,4.4)]:
            tongue(draw,density,(x,61.5),(height+3*math.sin(clock+seed))*scale,
                   width*scale,clock,seed,color)
    # Glowing irregular coals with dark crusts; root remains below the bars.
    for x in range(0,w,4):
        y=60+(x*7%3)
        box((x,y,x+3.5,65),'#f28124')
        box((x+.5,y+.3,x+2.8,y+1.2),'#ffe3a1')
        box((x,y+2,x+2,y+3),'#6a291c')
    # Grate: narrow inward glow edge and cool iron face, fully in front of fire.
    for x in range(5,w,12):
        box((x,0,x+1.7,65),'#16131b')
        box((x,0,x+.35,65),'#8f5030')
        box((x+.5,0,x+.8,65),'#42343b')
    box((0,64.5,59.9,65.9),'#221922')
    return image


def main():
    records={}
    for relative,size,draw in [('fx/shrine_flame.png',(16,24),flame),('title/forge_fire.png',(60,66),forge)]:
        for density in (1,4):
            out=ROOT/'assets'/('qhd' if density==4 else '')/relative
            out.parent.mkdir(parents=True,exist_ok=True)
            sheet=Image.new('RGBA',(size[0]*COUNT*density,size[1]*density))
            for frame in range(COUNT):
                sheet.paste(draw(density,frame),(frame*size[0]*density,0))
            sheet.save(out,optimize=True)
            if density==4:
                records['res://assets/'+relative]={'texture':'res://assets/qhd/'+relative,
                    'logical_size':[size[0]*COUNT,size[1]],'physical_size':list(sheet.size),
                    'frames':COUNT,'method':'original advected connected tongues, coal bed and iron grate',
                    'sha256':hashlib.sha256(out.read_bytes()).hexdigest()}
    (ROOT/'assets/qhd/fire.json').write_text(json.dumps(records,indent=2)+'\n')
    print('Drew 8 connected shrine flames and 8 animated forge hearth frames at 1x/4x')


if __name__=='__main__':
    main()
