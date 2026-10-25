"""Rerasterize the editable boss drawings at physical-pixel density.

Coordinates exposed to each drawing stay in world units. Shapes and strokes
are rasterized on the larger canvas BEFORE rasterization, not resized PNGs.
No antialiasing: fine contours and material bevels remain opaque pixel art.
"""
from PIL import Image, ImageDraw
import numpy as np


class Canvas:
    def __init__(self, image, density=4):
        self.image, self.density = image, density

    @property
    def size(self):
        return tuple(v // self.density for v in self.image.size)

    @property
    def width(self):
        return self.size[0]

    @property
    def height(self):
        return self.size[1]

    def getbbox(self):
        box = self.image.getbbox()
        if not box:
            return None
        s = self.density
        return (box[0] // s, box[1] // s, (box[2]+s-1)//s, (box[3]+s-1)//s)

    def crop(self, box):
        return Canvas(self.image.crop(tuple(round(v*self.density) for v in box)), self.density)

    def resize(self, size, resample=Image.Resampling.NEAREST):
        return Canvas(self.image.resize(tuple(round(v*self.density) for v in size), resample), self.density)

    def alpha_composite(self, other, dest=(0, 0)):
        self.image.alpha_composite(other.image, tuple(round(v*self.density) for v in dest))

    def load(self):
        return LogicalPixels(self)


class LogicalPixels:
    """Source-authored pixel accents on top of rerasterized geometry."""
    def __init__(self, canvas):
        self.canvas = canvas

    def __getitem__(self, pos):
        x, y = pos
        s = self.canvas.density
        return self.canvas.image.getpixel((x*s+s//2, y*s+s//2))

    def __setitem__(self, pos, color):
        x, y = pos
        s = self.canvas.density
        ImageDraw.Draw(self.canvas.image).rectangle((x*s,y*s,x*s+s-1,y*s+s-1),fill=color)


class Images:
    Resampling = Image.Resampling

    @staticmethod
    def new(mode, size, color=0):
        return Canvas(Image.new(mode, tuple(v*4 for v in size), color))


class Pen:
    def __init__(self, canvas):
        self.d = ImageDraw.Draw(canvas.image)
        self.s = canvas.density

    def coordinates(self, xy):
        if isinstance(xy[0], (tuple, list)):
            return [(round(x*self.s), round(y*self.s)) for x, y in xy]
        return tuple(round(v*self.s) for v in xy)

    def line(self, xy, fill=None, width=1, joint=None):
        self.d.line(self.coordinates(xy), fill, max(1, round(width*self.s)), joint=joint)

    def polygon(self, xy, fill=None, outline=None, width=1):
        self.d.polygon(self.coordinates(xy), fill, outline, max(1, round(width*self.s)))

    def rectangle(self, xy, fill=None, outline=None, width=1):
        self.d.rectangle(self.coordinates(xy), fill, outline, max(1, round(width*self.s)))

    def ellipse(self, xy, fill=None, outline=None, width=1):
        self.d.ellipse(self.coordinates(xy), fill, outline, max(1, round(width*self.s)))

    def rounded_rectangle(self, xy, radius=0, fill=None, outline=None, width=1):
        self.d.rounded_rectangle(self.coordinates(xy), round(radius*self.s), fill, outline,
                                 max(1, round(width*self.s)))

    def arc(self, xy, start, end, fill=None, width=1):
        self.d.arc(self.coordinates(xy), start, end, fill, max(1, round(width*self.s)))

    def point(self, xy, fill=None):
        x, y = self.coordinates(xy)
        self.d.rectangle((x, y, x+self.s-1, y+self.s-1), fill)


class Pens:
    Draw = Pen


def install(module):
    module.Image = Images
    module.ImageDraw = Pens


def bevel_materials(image):
    """One physical-pixel edge light inside each painted material facet.

    The extra detail follows the drawn facet, including articulated limbs; it
    never leaks into transparent pixels or adds screen-space random grain.
    """
    p = np.array(image)
    rgb = p[:, :, :3].astype(np.int16)
    opaque = p[:, :, 3] == 255
    up = np.concatenate((rgb[:1], rgb[:-1]), axis=0)
    down = np.concatenate((rgb[1:], rgb[-1:]), axis=0)
    top = opaque & (np.max(np.abs(rgb-up), axis=2) > 22)
    bottom = opaque & (np.max(np.abs(rgb-down), axis=2) > 22) & ~top
    # Preserve emissive flame cores and deep silhouette ink.
    material = (rgb.max(axis=2) > 45) & (rgb.max(axis=2) < 225)
    rgb[top & material] += 12
    rgb[bottom & material] -= 10
    p[:, :, :3] = rgb.clip(0, 255).astype(np.uint8)
    return Image.fromarray(p)
