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

def frame(index):
    phase=index/COUNT*math.tau
    image=Image.new('RGBA',(W,H))
    draw=ImageDraw.Draw(image)
    # Each tongue is rooted at the same coal bed. Scanline widths taper upward;
    # two harmonics lift/peel the tips without a sheet-wide translation or zoom.
    tongues=[(15,28,6.2,0.0),(10,20,4.0,2.0),(21,22,4.2,4.1)]
    for level,color in enumerate(PAL):
        for center,height,width,offset in tongues:
            height=round(height+2.0*math.sin(phase+offset)+1.0*math.sin(2*phase-offset))
            height=max(6,height-level*3)
            width=max(0.7,width-level*0.85)
            for rise in range(height+1):
                q=rise/height
                sway=(math.sin(phase-q*3.6+offset)*2.6+math.sin(2*phase-q*5.1)*1.0)*q*q
                curl=2.8*math.sin(phase+offset)*q**3
                c=center+sway+curl
                radius=width*(1-q)**0.72
                if rise==height: radius=0.35
                left,right=round(c-radius),round(c+radius)
                draw.line((left,BASE-rise,right,BASE-rise),fill=color)
    # Small dark notches carve the upper silhouette only, never cut the root.
    # Body already forms one connected component; sparks are authored separately.
    return image

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

if __name__=='__main__': main()
