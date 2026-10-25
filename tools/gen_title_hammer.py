#!/usr/bin/env python3
"""Original title trip-hammer drawings, rasterized at QHD presentation density.

The prop is placed at 2x world scale: eight texels per local unit match the hall's
four texels per world unit. Geometry, fittings and material fields are authored
here; no old PNG is enlarged. Body origin remains (18,44), with a wider 44x56
canvas that includes the entire right bearing. Low-density fallback art is
sampled from the same drawing. Requires Pillow and numpy.
"""
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
INK, SEAM, EDGE = "#0e0c15", "#19151e", "#796b70"
DENSITY = 8


class MetalDrawing:
    """Palette-stepped casting grain, clipped corrosion and explicit fittings."""

    def __init__(self, size, origin=(0, 0), density=DENSITY, seed=37):
        self.size, self.origin, self.s = size, origin, density
        self.image = Image.new("RGBA", (size[0]*density, size[1]*density))
        self.d = ImageDraw.Draw(self.image)
        yy, xx = np.indices((self.image.height, self.image.width))
        self.x, self.y = xx/density-origin[0], yy/density-origin[1]
        rng = np.random.default_rng(seed)
        # Interpolation only synthesizes the noise field, never source art.
        def field(cell):
            grid = rng.random((max(2, self.image.height//cell+2),
                               max(2, self.image.width//cell+2))).astype("float32")
            return np.asarray(Image.fromarray(grid).resize(self.image.size, Image.Resampling.BILINEAR))
        self.coarse, self.grain = field(density*3), field(3)
        self.pit = rng.random(xx.shape)

    def at(self, p):
        return tuple(round((v+o)*self.s) for v, o in zip(p, self.origin))

    def polygon(self, points, color):
        self.d.polygon([self.at(p) for p in points], fill=color)

    def line(self, points, color, width=.125):
        self.d.line([self.at(p) for p in points], fill=color, width=max(1, round(width*self.s)))

    def rect(self, box, color):
        x0, y0 = self.at(box[:2])
        x1, y1 = self.at(box[2:])
        self.d.rectangle((x0,y0,x1-1,y1-1), fill=color)

    def ellipse(self, box, color):
        self.d.ellipse((*self.at(box[:2]), *self.at(box[2:])), fill=color)

    def face(self, points, base, *, slope=0.0, rust=0.0):
        mask = Image.new("1", self.image.size)
        ImageDraw.Draw(mask).polygon([self.at(p) for p in points], fill=1)
        active = np.asarray(mask)
        grain = (self.coarse-.5)*18+(self.grain-.5)*11
        grain += np.sin(self.y*5+self.x*.4)*.6
        grain += slope*(self.x-np.mean(self.x[active]))
        grain = np.round(grain/2.5)*2.5
        color = np.array(base, dtype=float)[None,None,:]+grain[:,:,None]
        if rust:
            # Broken oxide islands and lipped casting pits are deliberately
            # coarser than film grain, so the iron reads under the hall lights.
            rugged = self.coarse + (self.grain-.5)*.4
            oxide = np.clip((rugged-(.64-rust*.17))*5, 0, .75)
            oxide = np.round(oxide*5)/5
            color = color*(1-oxide[:,:,None])+np.array((79,47,32))*oxide[:,:,None]
            cavities = (self.grain>.63)&(self.coarse>.4)
            color[cavities] *= .64
            lips = np.roll(cavities, -1, axis=0)&~cavities
            color[lips] += 8
            color[(self.pit>.975)&(oxide>.15)] *= .52
            laminations = (np.sin(self.y*12+self.x*.6)>0.65)&(self.grain>.56)
            color[laminations] *= .83
        a = np.array(self.image)
        a[active,:3] = np.clip(color[active],0,255).astype("uint8")
        a[active,3] = 255
        self.image = Image.fromarray(a)
        self.d = ImageDraw.Draw(self.image)

    def plate(self, box, base=(55,49,59), bevel=.375, rust=.6):
        x0,y0,x1,y1 = box
        b = bevel
        self.polygon([(x0+b,y0),(x1-b,y0),(x1,y0+b),(x1,y1-b),
                      (x1-b,y1),(x0+b,y1),(x0,y1-b),(x0,y0+b)], INK)
        self.face([(x0+b,y0+b),(x1-b,y0+b),(x1-b,y1-b),(x0+b,y1-b)],base,rust=rust)
        self.line([(x0+b,y1-b),(x0+b,y0+b),(x1-b,y0+b)],"#6a5b62")
        self.line([(x1-b,y0+2*b),(x1-b,y1-b),(x0+2*b,y1-b)],"#211c25",.25)

    def bolt(self, x, y, radius=.5):
        r = radius
        self.ellipse((x-r-.18,y-r+.12,x+r+.18,y+r+.35),INK)
        self.polygon([(x-r,y-r*.45),(x,y-r),(x+r,y-r*.45),
                      (x+r,y+r*.45),(x,y+r),(x-r,y+r*.45)],"#63575e")
        self.line([(x-r*.55,y-r*.4),(x,y-r*.65),(x+r*.45,y-r*.35)],"#a08a7b")
        self.line([(x-r*.45,y+.1),(x+r*.45,y+.1)],"#252029")

    def rust_patch(self, x, y, width, height):
        a = np.array(self.image)
        field = ((self.x-x)/width)**2+((self.y-y)/height)**2
        mask = (field<.65+self.coarse*.6)&(a[:,:,3]>0)
        mix = np.clip((1.2-field)*(.22+self.grain*.32),0,.58)
        oxide = np.stack((68+self.grain*30,36+self.grain*15,26+self.grain*11),axis=2)
        a[mask,:3] = (a[:,:,:3]*(1-mix[:,:,None])+oxide*mix[:,:,None])[mask].astype("uint8")
        self.image = Image.fromarray(a)
        self.d = ImageDraw.Draw(self.image)

    def save(self, name):
        source,detail = ROOT/"assets/title"/name, ROOT/"assets/qhd/title"/name
        detail.parent.mkdir(parents=True,exist_ok=True)
        self.image.save(detail,optimize=True)
        self.image.resize(self.size,Image.Resampling.NEAREST).save(source,optimize=True)
        print(f"{name}: logical={self.size}, native={self.image.size}")


def body():
    p = MetalDrawing((44,56),(18,44))
    p.plate((-18,-3,24,0),(45,38,46),bevel=.5)
    p.line([(-17,-2.5),(23,-2.5)],"#817075",.25)
    p.line([(-17,-.5),(23,-.5)],SEAM,.375)
    # Rear I-beam with flanges, recessed web, clamps and punched inspection slots.
    p.plate((14,-42,21,-2),(47,40,48),bevel=.5,rust=.95)
    p.face([(14.5,-41),(16,-41),(16,-3),(14.5,-3)],(75,65,69),slope=-2,rust=.8)
    p.face([(19,-41),(20.5,-41),(20.5,-3),(19,-3)],(32,27,36),rust=.7)
    p.rect((16,-36,19,-4),"#29222c")
    p.line([(16.25,-35.5),(16.25,-4)],"#51414a",.25)
    for y in (-32.5,-20.5,-8.5):
        p.plate((14,y,21,y+1.8),(72,58,61),bevel=.25)
        p.bolt(15,y+.8,.35)
        p.bolt(19.7,y+.8,.35)
    for y in (-29.5,-26,-17.5,-14,-5):
        p.plate((16.75,y,18.25,y+1.3),(24,21,30),bevel=.125,rust=0)
    p.rust_patch(16,-29,1.1,5)
    p.rust_patch(18.7,-17,.7,4)
    # Braced foot: raised lip, lightening holes and end fasteners.
    p.polygon([(14,-16),(16,-15),(11,-2.5),(8.5,-2.5)],INK)
    p.face([(14.5,-15.5),(15.5,-15),(10.5,-3),(9,-3)],(57,44,49),rust=1)
    p.line([(14.6,-15),(9.8,-3.5)],"#89705f",.25)
    for i in range(3):
        x,y = 13.8-i*1.3,-13+i*3.5
        p.ellipse((x-.3,y-.5,x+.3,y+.5),SEAM)
    p.bolt(14.7,-15,.5)
    p.bolt(10,-3.7,.5)
    # Flanged journal housing; pivot is (17,-38), not the image's corner.
    p.plate((12.5,-43.5,22.5,-34.25),(58,48,55),bevel=1)
    p.ellipse((13.3,-41.9,21,-34.4),INK)
    p.ellipse((13.65,-41.55,20.65,-34.75),"#766255")
    p.ellipse((14.2,-41,20.1,-35.3),"#40343b")
    p.ellipse((14.9,-40.3,19.4,-35.9),"#16131d")
    p.ellipse((15.5,-39.7,18.8,-36.5),"#73605a")
    p.line([(14.4,-38.7),(14.7,-39.6),(15.7,-40.4)],"#ac8e73",.25)
    for x in (13.6,21.1):
        for y in (-42.4,-35.5):
            p.bolt(x,y,.5)
    p.line([(17.6,-42.5),(17.6,-41.5)],SEAM,.25)
    p.bolt(17.6,-42.3,.3)
    # Forged anvil: sculpted waist, gussets, stamped web, replaceable steel face.
    p.plate((-11,-5.5,11,-3),(54,42,48),bevel=.5)
    p.face([(-7,-10.5),(6,-10.5),(4,-6),(8.5,-5),(-8.5,-5),(-4.5,-6)],
           (58,46,51),slope=-1,rust=1)
    p.face([(3.5,-10.5),(6,-10.5),(4,-6),(8.5,-5),(5,-5)],(30,25,34),rust=.5)
    p.face([(-7,-10.5),(-5.5,-10.5),(-3,-6),(-7.5,-5)],(82,64,62),rust=.7)
    p.plate((-3.2,-9.4,2.6,-6),(37,30,39),bevel=.375)
    p.line([(-1.8,-8.8),(.7,-8.8),(-.5,-7.4),(.7,-6.8)],"#7c6051",.25)
    p.line([(-5,-9.5),(-5.5,-8.4),(-4.8,-7.4)],"#ad7a54")
    p.plate((-11.25,-13.5,11,-10),(65,53,59),bevel=.5,rust=.4)
    p.face([(-11,-13.4),(10,-13.4),(8.5,-12),(-10,-12)],(108,92,91),slope=-1,rust=.2)
    p.face([(-11,-13.3),(-16,-12),(-16.5,-11.3),(-11,-11.3)],(73,60,66),rust=.4)
    p.line([(-15,-11.8),(-11,-12.6),(-3,-12.6)],"#95817e")
    p.line([(-10.5,-11.5),(9.7,-11.5)],"#28212b",.25)
    p.line([(-9,-10.5),(8.5,-10.5)],"#806967")
    for x,y,length in [(-8,-12.8,2),(-4.2,-13.1,1.5),(.4,-12.7,2),(5,-12.8,1.5),(8,-12.9,.8)]:
        p.line([(x,y),(x+length,y-.15)],"#423740")
    for x in (-9.4,9):
        p.bolt(x,-4.25,.5)
    p.rust_patch(-7.7,-5,2,.6)
    p.rust_patch(6,-10.8,2,.7)
    for x in (-15.5,22):
        p.bolt(x,-1.7,.5)
    p.save("hammer_body.png")


def head():
    p = MetalDrawing((18,14),seed=73)
    p.polygon([(1.5,0),(15.5,0),(18,2),(17.5,12),(15,14),(2,14),(0,12),(0,1.5)],INK)
    p.face([(1,2.3),(14.5,2.3),(14.5,10.4),(1,10.8)],(63,52,61),slope=-.5,rust=.8)
    p.face([(1,1.5),(2.5,.5),(15.2,.5),(16.7,2.2),(14.5,3),(2,3)],(101,85,90),slope=-.7,rust=.6)
    p.face([(14.5,3),(17.2,2.1),(16.8,11.5),(14.5,12.5)],(34,28,39),slope=-1,rust=.7)
    p.line([(2,.7),(14.6,.7),(16.2,1.7)],"#b69c8f")
    p.line([(15.2,3),(16.7,2.6),(16.3,10.8)],"#594751",.25)
    for x in (2,12.1):
        p.plate((x,2.6,x+1.7,10.5),(76,60,64),bevel=.25,rust=.9)
        for y in (4,8.8):
            p.bolt(x+.85,y,.45)
        p.rust_patch(x+.3,7.2,.5,1.8)
    p.plate((5.1,4.2,10.8,8.7),(43,35,46),bevel=.4,rust=.8)
    p.polygon([(7.7,4.9),(9.3,6.4),(7.7,8),(6.2,6.4)],"#271f2b")
    p.line([(7.7,5.35),(8.75,6.4),(7.7,7.4)],"#8a6d5d",.25)
    p.line([(7.7,5.35),(6.7,6.4),(7.7,7.4)],"#58434a")
    p.face([(1.2,10.6),(14.3,10.3),(16.6,11.5),(14.7,13.3),(2,13.3),(.8,12.2)],
           (93,76,76),slope=-1,rust=.4)
    p.line([(1.3,10.7),(14.1,10.5)],"#201a25",.25)
    p.line([(1.6,11.2),(14,11),(15.7,11.7)],"#b49987")
    p.line([(2,12.8),(14.5,12.8),(16.2,11.7)],"#806b6c",.25)
    for x,y,length in [(3.7,5.6,1.1),(9.4,3.4,1.8),(5,9.5,1.7),(10.8,9.3,1),
                       (4,11.7,2.1),(8.4,11.9,1.4),(11.7,12.2,.9)]:
        p.line([(x,y),(x+length,y-.25)],"#3d303a")
        p.line([(x,y+.125),(x+length*.65,y)],"#88706b")
    p.save("hammer_head.png")


def arm():
    # End pins are (1.5,3.5) and (20.5,3.5), nineteen local units apart.
    p = MetalDrawing((22,7),seed=101)
    p.polygon([(1,1),(20,1),(21.75,2.4),(21.75,4.6),(20,6),(1,6),(0,5),(0,2)],INK)
    p.face([(1,1.5),(20,1.5),(21,2.5),(20,5.5),(1,5.5),(.5,4.5),(.5,2.5)],
           (66,54,61),rust=.9)
    p.line([(1,1.6),(19.8,1.6),(20.7,2.3)],"#998276",.25)
    p.line([(1,5.1),(19.7,5.1)],"#29202d",.375)
    p.plate((4.2,2.4,17.9,4.6),(29,24,34),bevel=.4,rust=0)
    p.line([(5,4.3),(17.2,4.3)],"#64515a")
    for x in (6,10.5,15.2):
        p.line([(x,2.4),(x+.5,4.6)],"#705750",.5)
        p.line([(x+.4,2.5),(x+.9,4.4)],"#231b28",.25)
    for x in (1.5,20.5):
        p.ellipse((x-1.3,2.2,x+1.3,4.8),"#201a27")
        p.ellipse((x-1,2.5,x+1,4.5),"#87705b")
        p.bolt(x,3.5,.65)
    p.rust_patch(17.7,4.5,1.4,.5)
    p.save("hammer_arm.png")


def main():
    body()
    head()
    arm()


if __name__ == "__main__":
    main()
