"""Original, reproducible pixel drawings for Rustgrave's two bookend Bosses.

No source pictures are opened. Every cluster, material and articulated pose below
is authored here; Pillow only rasterizes integer coordinates without antialiasing.
Run with the bundled Python (Pillow), optionally --only executioner/nightmare.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets' / 'characters'

# The first Boss is cold wrought iron, faded funeral cloth and hot seams.
IRON = {
    'ink': '#15151e', 'deep': '#252732', 'shade': '#3b414b',
    'steel': '#697578', 'edge': '#a5b3ac', 'white': '#d2d6be',
    'rust': '#7c4134', 'copper': '#b7734b', 'gold': '#dcaa62',
    'cloth': '#392735', 'fold': '#593542', 'red': '#923f38',
    'ember': '#e46f39', 'hot': '#ffe0a0',
}
# The last Boss is a riderless ceramic reliquary horse, not the first Boss's metal.
BONE = {
    'ink': '#191926', 'deep': '#33303c', 'shade': '#65595d',
    'bone': '#aa9b90', 'edge': '#dccdb1', 'white': '#f0e2c4',
    'oxide': '#743c38', 'rust': '#a65b43', 'copper': '#ce9159',
    'cloth': '#513342', 'fold': '#80404e', 'ember': '#ed7841',
    'hot': '#ffd99b', 'ash': '#858086',
}


class Pixels:
    def __init__(self, image: Image.Image, palette: dict[str, str]):
        self.image = image
        self.d = ImageDraw.Draw(image)
        self.p = palette

    def poly(self, points, color, outline='ink'):
        pts = [(round(x), round(y)) for x, y in points]
        self.d.polygon(pts, fill=self.p.get(color, color))
        if outline:
            self.d.line(pts + [pts[0]], fill=self.p.get(outline, outline), width=1)

    def rect(self, box, color):
        self.d.rectangle(tuple(round(v) for v in box), fill=self.p.get(color, color))

    def line(self, points, color, width=1):
        self.d.line([(round(x), round(y)) for x, y in points],
                    fill=self.p.get(color, color), width=width)

    def rivet(self, x, y, light='edge'):
        self.rect((x-1, y-1, x+1, y+1), 'ink')
        self.rect((x, y, x, y), light)


def cleaver(p: Pixels, hand, tip, heat: bool):
    """Long split-edge execution cleaver, attached to the pose's real hand."""
    hx, hy = hand; tx, ty = tip
    vx, vy = tx-hx, ty-hy
    norm = max(1, math.hypot(vx, vy)); nx, ny = -vy/norm, vx/norm
    end = (hx+vx*1.17, hy+vy*1.17)
    p.line([end, (hx-vx*.34, hy-vy*.34)], 'ink', 5)
    p.line([end, (hx-vx*.34, hy-vy*.34)], 'rust', 3)
    p.line([(hx+nx,hy+ny),(tx+nx,ty+ny)], 'copper')
    def q(a, b): return (hx+vx*a+nx*b, hy+vy*a+ny*b)
    p.poly([q(.58,-3),q(1.25,-4),q(1.31,2),q(1.16,12),
            q(.89,14),q(.87,10),q(.61,9),q(.53,3)], 'shade')
    p.poly([q(.64,1),q(1.19,0),q(1.09,9),q(.88,11),q(.84,7),q(.61,6)], 'steel')
    p.line([q(1.26,3),q(1.14,11),q(.89,13)], 'white', 2)
    p.line([q(.66,3),q(.87,4),q(.92,8)], 'ember' if heat else 'rust')
    for a in [.71,.91,1.09]:
        x,y=q(a,-1);p.rivet(round(x),round(y),'copper')


def executioner(action: str, frame: int, count: int) -> Image.Image:
    im = Image.new('RGBA', (100,100)); p = Pixels(im,IRON)
    phase = frame / max(1,count-1)
    breath = [0,0,-1,-1,0,1][frame % 6] if action in ('idle','idle2') else 0
    lean = round(math.sin(phase*math.pi)*3) if action == 'attack' else 0
    cx, y = 56-lean, breath
    hot = action in ('skill','summon')
    if action == 'attack':
        poses=[((51,45),(49,12)),((50,42),(59,8)),((46,43),(38,8)),
               ((39,49),(14,36)),((39,55),(10,61)),((42,57),(17,70)),
               ((45,52),(24,49)),((46,49),(26,28))]
        hand,tip=poses[frame % len(poses)]
    elif hot:
        hand=(43,48-round(math.sin(phase*math.pi)*8)); tip=(26,22-round(math.sin(phase*math.pi)*6))
    else: hand,tip=(43,49+y),(24,25+y)
    # Torn ceremonial mantle, complete rear silhouette before the armour.
    wave = round(math.sin(frame*1.1)*2)
    p.poly([(cx+8,34+y),(cx+18,39+y),(cx+23,64),(cx+26+wave,78),
            (cx+17,74),(cx+13,81),(cx+7,75),(cx-1,77),(cx-6,42+y)],'cloth')
    p.poly([(cx+10,40+y),(cx+15,47+y),(cx+19+wave,73),(cx+12,69)],'fold')
    p.line([(cx+17,48+y),(cx+20,65),(cx+23+wave,74)],'red')
    # Recessed greaves, broad staggered feet: source baseline remains y=83.
    for lx, knee in [(cx-9,70),(cx+5,72)]:
        p.poly([(lx-3,61),(lx+5,61),(lx+6,knee),(lx+3,80),(lx-5,80),(lx-4,knee)],'deep')
        p.poly([(lx-3,68),(lx+3,69),(lx+2,78),(lx-3,78)],'steel')
        p.line([(lx-3,69),(lx-3,77)],'edge')
        p.poly([(lx-5,78),(lx+4,78),(lx+6,82),(lx-7,82),(lx-8,81)],'shade')
        p.line([(lx-7,82),(lx+5,82)],'copper')
    # Ribbed cuirass with a split seam; deliberate asymmetric shoulder plates.
    p.poly([(cx-12,38+y),(cx+8,35+y),(cx+14,43+y),(cx+11,62),
            (cx+4,69),(cx-9,66),(cx-15,50+y)],'shade')
    p.poly([(cx-9,41+y),(cx+1,38+y),(cx+4,59),(cx-7,62),(cx-11,52+y)],'steel')
    p.poly([(cx+3,39+y),(cx+10,42+y),(cx+8,60),(cx+3,63)],'deep')
    for ry in [45,50,55]:
        p.line([(cx-10,ry+y),(cx-1,ry-2+y),(cx+8,ry+y)],'deep',2)
        p.line([(cx-9,ry-1+y),(cx-2,ry-3+y)],'edge')
    p.line([(cx+1,41+y),(cx-2,48+y),(cx+2,53+y),(cx,61)],'ember' if hot else 'rust')
    p.poly([(cx-16,37+y),(cx-9,34+y),(cx-2,37+y),(cx-3,45+y),(cx-14,48+y),(cx-19,43+y)],'steel')
    p.line([(cx-16,37+y),(cx-9,35+y),(cx-3,38+y)],'edge')
    p.poly([(cx+6,35+y),(cx+13,34+y),(cx+19,40+y),(cx+16,47+y),(cx+7,45+y)],'shade')
    for rx,ry in [(cx-12,39+y),(cx+13,39+y),(cx-8,61),(cx+7,63)]: p.rivet(rx,ry,'copper')
    p.rect((cx-10,61,cx+11,65),'rust');p.rect((cx-2,61,cx+2,65),'gold')
    for xx in range(cx-8,cx+11,5):p.rect((xx,66,xx+3,72),'shade')
    # Original closed funerary hood: stepped arch, eye slit, copper cheek grille.
    p.poly([(cx-9,34+y),(cx-10,28+y),(cx-5,22+y),(cx+3,20+y),
            (cx+11,25+y),(cx+12,36+y),(cx+6,41+y),(cx-3,39+y)],'deep')
    p.poly([(cx-8,29+y),(cx-3,24+y),(cx+3,23+y),(cx+7,27+y),(cx+7,35+y),(cx+1,38+y),(cx-6,35+y)],'shade')
    p.line([(cx-7,28+y),(cx-2,24+y),(cx+2,23+y)],'edge')
    p.rect((cx-8,30+y,cx+3,32+y),'ink')
    p.line([(cx-7,31+y),(cx-2,31+y)],'hot' if hot else 'gold')
    for xx in [cx-4,cx-1,cx+2]:p.line([(xx,35+y),(xx+1,37+y)],'copper')
    # Small slab buckler with an iron seal, never a gear-shield silhouette.
    sx = cx-11 if action != 'idle2' else cx-19
    p.poly([(sx-9,45+y),(sx+6,41+y),(sx+9,45+y),(sx+7,65+y),
            (sx-2,70+y),(sx-11,63+y)],'deep')
    p.poly([(sx-7,46+y),(sx+4,44+y),(sx+6,47+y),(sx+4,63+y),(sx-2,67+y),(sx-8,61+y)],'shade')
    p.line([(sx-7,47+y),(sx-7,60+y),(sx-2,65+y)],'edge')
    p.poly([(sx-3,48+y),(sx+1,50+y),(sx+2,60+y),(sx-3,62+y),(sx-6,57+y)],'rust')
    p.line([(sx-2,50+y),(sx-2,60+y)],'ember' if hot else 'copper',2)
    for rx,ry in [(sx-7,47+y),(sx+4,46+y),(sx-2,65+y)]:p.rivet(rx,ry)
    cleaver(p,hand,tip,hot)
    p.poly([(cx-13,44+y),(hand[0]+3,hand[1]-3),(hand[0]+5,hand[1]+2),
            (hand[0]-1,hand[1]+5),(cx-17,51+y)],'steel')
    p.rect((hand[0]-2,hand[1]-2,hand[0]+2,hand[1]+2),'copper')
    if hot:
        for j in range(5):
            ex=44+(j*11+frame*3)%32;ey=53-(frame*7+j*9)%39
            p.rect((ex,ey,ex+1,ey+2),'hot' if j%2 else 'ember')
    if action == 'death':
        # Collapse the original drawing into a grounded, split-armour corpse.
        bbox=im.getbbox();crop=im.crop(bbox)
        h=max(17,round(crop.height*(1-.66*phase)))
        crop=crop.resize((crop.width,h),Image.Resampling.NEAREST)
        im=Image.new('RGBA',(100,100));im.alpha_composite(crop,(bbox[0],83-h))
        d=ImageDraw.Draw(im)
        for j in range(round(phase*5)):
            x=20+j*13;d.rectangle((x,82-j%2,x+3,83-j%2),fill=IRON['rust'])
    return im


def nightmare(action: str, frame: int, count: int) -> Image.Image:
    im=Image.new('RGBA',(128,96));p=Pixels(im,BONE)
    gallop=action=='gallop'; t=frame*math.tau/count
    bob=round(math.sin(t*2)*(2 if gallop else 1))
    # Back legs in shadow; four independently bent limbs distinguish the gait.
    legs=[(82,65,1),(48,67,-1),(91,65,-1),(39,66,1)]
    for i,(x,y,sgn) in enumerate(legs):
        stride=round(math.sin(t+(i%2)*math.pi)*12) if gallop else (i%2)*3
        knee=(x+stride//2,y+13+bob)
        hoof=(x-stride+sgn*3,94-(max(0,round(math.cos(t+i)*10)) if gallop else 0))
        p.line([(x,y+bob),knee,hoof],'ink',7)
        p.line([(x,y+bob),knee,hoof],'shade' if i<2 else 'bone',4)
        p.line([(x-1,y+bob), (knee[0]-1,knee[1]),(hoof[0]-1,hoof[1]-3)],'edge' if i>=2 else 'ash')
        p.poly([(knee[0]-3,knee[1]-3),(knee[0]+3,knee[1]-2),
                (knee[0]+4,knee[1]+2),(knee[0]-2,knee[1]+4)],'copper' if i>=2 else 'oxide')
        p.poly([(hoof[0]-5,hoof[1]-3),(hoof[0]+3,hoof[1]-4),
                (hoof[0]+6,hoof[1]),(hoof[0]-6,hoof[1])],'deep')
        p.line([(hoof[0]-5,hoof[1]),(hoof[0]+5,hoof[1])],'copper')
    # A curved ceramic rib-cage encloses the visible kiln heart.
    p.poly([(35,48+bob),(46,43+bob),(66,43+bob),(86,48+bob),
            (98,57+bob),(94,70+bob),(82,75+bob),(53,75+bob),(36,65+bob)],'deep')
    p.poly([(39,50+bob),(50,46+bob),(68,46+bob),(86,51+bob),
            (93,59+bob),(88,69+bob),(59,71+bob),(42,63+bob)],'oxide')
    p.poly([(54,51+bob),(72,49+bob),(85,57+bob),(80,67+bob),
            (64,69+bob),(55,63+bob)],'ember')
    p.poly([(62,53+bob),(73,53+bob),(79,58+bob),(75,64+bob),
            (65,65+bob),(60,59+bob)],'hot')
    for i in range(6):
        x=43+i*8;y=47+round(abs(i-2)*1.4)+bob
        p.poly([(x,y),(x+5,y+1),(x+7,y+11),(x+4,y+19),(x,y+17),(x+2,y+9)],'bone')
        p.line([(x+1,y+2),(x+3,y+9),(x+1,y+15)],'white')
        p.line([(x+5,y+4),(x+6,y+11),(x+3,y+18)],'shade')
    p.line([(38,49+bob),(49,44+bob),(68,44+bob),(87,50+bob),(96,57+bob)],'edge',3)
    for i in range(8):
        x=42+i*7;y=44+round(abs(i-3)*1.3)+bob
        p.rect((x,y-2,x+3,y+2),'deep');p.rect((x,y-2,x+2,y),'edge')
    # Recurved neck; anatomical skull, split kiln jaw, long forehead seam.
    p.poly([(39,62+bob),(31,50+bob),(29,37+bob),(21,29+bob),
            (27,24+bob),(39,31+bob),(50,44+bob),(53,57+bob)],'shade')
    p.poly([(36,55+bob),(32,43+bob),(30,31+bob),(36,34+bob),
            (45,46+bob),(46,56+bob)],'bone')
    p.line([(31,33+bob),(34,44+bob),(38,51+bob)],'edge',2)
    p.poly([(15,30+bob),(21,22+bob),(33,23+bob),(35,33+bob),
            (29,42+bob),(19,44+bob),(10,39+bob),(9,35+bob)],'bone')
    p.poly([(12,31+bob),(20,25+bob),(28,25+bob),(25,30+bob),(14,36+bob)],'edge')
    p.poly([(23,30+bob),(29,30+bob),(28,36+bob),(22,36+bob),(20,34+bob)],'ink')
    p.line([(22,33+bob),(27,32+bob)],'hot',2)
    p.poly([(10,37+bob),(19,38+bob),(26,37+bob),(23,42+bob),(17,44+bob),(10,41+bob)],'deep')
    p.line([(11,39+bob),(21,40+bob)],'ember')
    p.rect((10,33+bob,12,34+bob),'deep')
    p.poly([(26,25+bob),(27,16+bob),(31,12+bob),(31,27+bob)],'shade')
    p.line([(28,21+bob),(30,15+bob)],'edge')
    p.poly([(19,25+bob),(17,18+bob),(20,19+bob),(24,24+bob)],'deep')
    # Hanging funeral name-tabs form the mane; nothing is borrowed from a rider.
    for i in range(7):
        x=34+i*2;y=28+i*4+bob; flutter=round(math.sin(t+i)*2)
        p.poly([(x,y),(x+5,y+1),(x+10+flutter,y+10),(x+5,y+8)],'cloth')
        p.line([(x+2,y+2),(x+7+flutter,y+8)],'copper')
        p.rect((x+5+flutter,y+6,x+6+flutter,y+8),'edge')
    # Segmented spinal tail, with a forked ember tassel.
    tail=[(96,57+bob),(103,60+bob),(108,69+bob),(109+round(math.sin(t)*3),81)]
    p.line(tail,'ink',6);p.line(tail,'oxide',4);p.line(tail,'copper')
    for i,(x,y) in enumerate(tail[1:]):p.rivet(x,y,'edge')
    ex,ey=tail[-1]
    p.poly([(ex-3,ey-1),(ex+4,ey),(ex+9,ey+8),(ex+3,ey+5),
            (ex+3,ey+12),(ex-2,ey+7),(ex-6,ey+10)],'fold')
    p.line([(ex,ey),(ex+2,ey+7)],'ember',2)
    for i in range(3):
        x=54+(i*17+frame*3)%42;y=42-(frame*3+i*7)%16
        p.rect((x,y,x+1,y+2),'ember')
    return im


SPECS = {
    'executioner': ('original_executioner', executioner,
                    {'idle':6,'idle2':4,'summon':6,'attack':8,'skill':6,'death':8}),
    'nightmare': ('original_nightmare', nightmare, {'idle':8,'gallop':8}),
}


def generate(only=None):
    for name,(directory,draw,actions) in SPECS.items():
        if only and only!=name: continue
        records=[]; previews=[]
        for action,n in actions.items():
            target=OUT/directory/action;target.mkdir(parents=True,exist_ok=True)
            for i in range(n):
                image=draw(action,i,n);path=target/f'{action}_{i}.png';image.save(path)
                records.append({'action':action,'frame':i,'size':image.size,
                                'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
                previews.append((action,i,image))
        (OUT/directory/'authorship.json').write_text(json.dumps({
            'artist':'Original Rustgrave project drawing authored in the accompanying source',
            'generator':str(Path(__file__).relative_to(ROOT)).replace('\\','/'),
            'inputs':[], 'method':'integer pixel clusters; no sampled reference assets; transparent RGBA',
            'palette':IRON if name=='executioner' else BONE,'frames':records},indent=2),encoding='utf-8')
        width=1600;cellw=320;cellh=220;rows=math.ceil(len(previews)/5)
        sheet=Image.new('RGB',(width,rows*cellh),'#25242d');sd=ImageDraw.Draw(sheet)
        for j,(action,i,im) in enumerate(previews):
            x=(j%5)*cellw;y=(j//5)*cellh
            scaled=im.resize((im.width*2,im.height*2),Image.Resampling.NEAREST)
            sheet.paste(scaled,(x+(cellw-scaled.width)//2,y+20),scaled)
            sd.text((x+6,y+5),f'{action} {i}',fill='#d2c8b6')
        dest=ROOT/'screenshots/acceptance/overhaul-v3/original-bosses/source-previews'
        dest.mkdir(parents=True,exist_ok=True);sheet.save(dest/f'{name}.png')
        print(directory,len(records),'original frames')


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--only',choices=SPECS)
    generate(parser.parse_args().only)
