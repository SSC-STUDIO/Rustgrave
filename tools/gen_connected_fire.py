"""Draw an original, rooted 16-frame pixel flame; no source images or resampling.

The flame is opaque colour on binary alpha, rendered with normal unshaded blend.
Additive light and sparse sparks are separate at runtime, preserving orange edges.
"""
from pathlib import Path
import math, json, hashlib
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[1]
W,H,COUNT=32,40,16
BASE=36
PAL=['#a73520','#d95220','#ed7928','#ffad38','#ffd967','#fff1b4']

def _noise(x, frame_index, salt):
    n=(x*57+frame_index*131+salt*17)&255
    n=(n*1103515245+12345)&0x7FFFFFFF
    return (n%1000)/1000.0


def frame(index):
    """One coal bed, uneven licks. Tips split and die; the root stays joined."""
    phase=index/COUNT*math.tau
    # Lean is lopsided: a slow roll plus a quicker hitch, not one smooth sine.
    lean=2.8*math.sin(phase)+1.2*math.sin(phase*2.0+0.7)
    third=0.35+0.65*max(0.0, math.sin(phase-0.6))
    # (center, height, half-width). Heights stay in a flame range; the shape changes, not the size.
    licks=[
        (15.0+lean*0.55, 23+4*math.sin(phase+0.2), 4.6),
        (11.2+1.6*math.sin(phase*1.6+2.1), 13+5*math.sin(phase*0.7+1.4), 2.3),
        (20.4-lean*0.35, 10+9*third, 1.8),
    ]
    heights=[0]*W
    for center,height,half in licks:
        height=max(4.0, height)
        for x in range(W):
            dist=abs(x+0.5-center)/half
            if dist>=1.0:
                continue
            # Flat foot, pinched tip, then a stair notch so the edge is not a curve.
            shape=(1.0-dist)**0.4
            jag=_noise(x, index, 2)*(1.6 if dist>0.35 else 0.2)
            column=int(round(height*shape-jag))
            if column>heights[x]:
                heights[x]=column
    for x in range(11, 22):
        heights[x]=max(heights[x], 5+(1 if _noise(x, index, 9)>0.55 else 0))
    # One notch in the tallest lick, so a tip splits without chopping the whole flame.
    notch=None
    notch_n=-1.0
    for x in range(1, W-1):
        if heights[x]<16:
            continue
        n=_noise(x, index, 5)
        if n>notch_n:
            notch_n=n
            notch=x
    if notch is not None:
        heights[notch]=max(10, heights[notch]-2-int(_noise(notch, index, 6)*3))
    image=Image.new('RGBA', (W, H))
    pixels=image.load()
    for x in range(W):
        column=heights[x]
        if column<=0:
            continue
        for rise in range(column):
            y=BASE-rise
            if y<0 or y>=H:
                continue
            xx=x
            q=rise/float(column)
            left=heights[x-1] if x else 0
            right=heights[x+1] if x<W-1 else 0
            edge=rise>=column-1 or rise>left or rise>right
            if q<0.16:
                color_index=1 if edge else 2
            elif q<0.40:
                color_index=2 if edge else 3
            elif q<0.66:
                color_index=3 if edge else 4
            elif q<0.86:
                color_index=4 if edge else 5
            else:
                color_index=3 if edge else 5
            if _noise(x, index, rise+11)>0.84 and q>0.28:
                color_index=max(0, color_index-1)
            color=PAL[color_index]
            pixels[xx, y]=(int(color[1:3], 16), int(color[3:5], 16), int(color[5:7], 16), 255)
    return image

def build_forge():
    """A deep hearth with rolling fire behind stationary iron bars (60x66/frame)."""
    strip=Image.new('RGBA',(60*COUNT,66))
    for i in range(COUNT):
        im=Image.new('RGBA',(60,66),'#25100e')
        d=ImageDraw.Draw(im)
        # Charred firebrick: dark at the throat, red reflected light near the bed.
        for y in range(66):
            for x in range(60):
                h=(x*37+y*19+x*y*3)%71
                c=['#25100e','#351610','#4a1e13'][min(2,y//24)]
                if h<7: c='#4a1e13'
                if y%9==0 or (x+(y//9%2)*7)%15==0: c='#1c0d0c'
                d.point((x,y),fill=c)
        for x,offset,scale in [(9,2,1.30),(29,7,1.55),(49,12,1.20)]:
            tongue=frame((i+offset)%COUNT)
            size=(round(W*scale),round(H*scale))
            tongue=tongue.resize(size,Image.Resampling.NEAREST)
            im.alpha_composite(tongue,(x-round(16*scale),62-round(BASE*scale)))
        d=ImageDraw.Draw(im)
        # Individual clinker pieces; no broad pale stripe at the foot of the fire.
        for y in range(60,66):
            for x in range(60):
                h=(x*11+y*17)%23
                d.point((x,y),fill=['#38150f','#69281a','#b84720','#ed7928'][min(3,h//6)])
        for x in range(5,60,12):
            d.line((x,0,x,65),fill='#160e10',width=2)
            d.line((x-1,8,x-1,64),fill='#65402c')
            d.line((x-1,48,x-1,63),fill='#9b5730')
        strip.paste(im,(i*60,0))
    strip.save(ROOT/'assets/title/forge_mouth.png')

def main():
    output=ROOT/'assets/fx/connected_flame.png'
    output.parent.mkdir(parents=True,exist_ok=True)
    strip=Image.new('RGBA',(W*COUNT,H))
    hashes=[]
    for i in range(COUNT):
        im=frame(i);strip.paste(im,(i*W,0));hashes.append(hashlib.sha256(im.tobytes()).hexdigest())
    strip.save(output)
    (output.with_suffix('.json')).write_text(json.dumps({'source':'tools/gen_connected_fire.py',
        'authorship':'Original project pixel drawing; no image inputs','cell':[W,H],
        'frames':COUNT,'fps':12,'root':[16,BASE],'palette':PAL,'pixel_sha256':hashes},indent=2)+'\n',encoding='utf-8')
    print('Authored',output,strip.size)
    build_forge()

if __name__=='__main__': main()
