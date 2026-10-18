"""Render labelled contact sheets / crops (dev helper, read-only on the project).

Two modes:

1. Sprite-sheet crops (original behaviour):
     python tools/contact_sheet.py <png> <out.png> x,y,w,h [x,y,w,h ...]

2. Beat sheets, for the campaign-v2 visual audit (5 key beats per chapter):
     python tools/contact_sheet.py --sheet <out.png> --cols 5 \
         --title "level02b 运渣水渠" \
         label=/abs/path/a.png "水闸广场=/abs/path/b.png" ...

   Each panel is labelled in the top-left corner and scaled down to fit
   --panel-width (default 512; nearest-neighbour so pixel art stays crisp).
   `--crop x,y,w,h` crops every input frame to that rectangle first (counts in
   source pixels, i.e. before down-scaling) - handy for zooming into one prop.
   Inputs may live outside the project (e.g. a Godot `user://` output dir), so
   the audit can run without writing into the repo.
"""
import sys

from PIL import Image, ImageDraw

PAD = 12
LABEL_H = 22
SCALE = 3


def _sheet_mode(argv):
    out_path = argv[0]
    cols = 5
    title = ""
    panel_w = 512
    crop = None
    panels = []
    i = 1
    while i < len(argv):
        arg = argv[i]
        if arg == "--cols" and i + 1 < len(argv):
            cols = max(1, int(argv[i + 1]))
            i += 2
        elif arg == "--title" and i + 1 < len(argv):
            title = argv[i + 1]
            i += 2
        elif arg == "--panel-width" and i + 1 < len(argv):
            panel_w = max(64, int(argv[i + 1]))
            i += 2
        elif arg == "--crop" and i + 1 < len(argv):
            crop = tuple(int(v) for v in argv[i + 1].split(","))
            i += 2
        else:
            if "=" not in arg:
                raise SystemExit("panel must be label=path, got %r" % arg)
            label, path = arg.split("=", 1)
            panels.append((label, path))
            i += 1
    if not panels:
        raise SystemExit("no panels given")

    rendered = []
    for label, path in panels:
        img = Image.open(path).convert("RGBA")
        if crop is not None:
            img = img.crop(crop)
        if img.width > panel_w:
            h = max(1, round(img.height * panel_w / img.width))
            img = img.resize((panel_w, h), Image.NEAREST)
        rendered.append((label, img))

    cell_w = max(img.width for _, img in rendered)
    row_h = max(img.height for _, img in rendered) + LABEL_H
    rows = (len(rendered) + cols - 1) // cols
    header = 30 if title else 0
    total_w = PAD + cols * (cell_w + PAD)
    total_h = header + PAD + rows * (row_h + PAD)
    sheet = Image.new("RGBA", (total_w, total_h), (28, 26, 32, 255))
    draw = ImageDraw.Draw(sheet)
    if title:
        draw.text((PAD, 8), title, fill=(240, 226, 196, 255))
    for index, (label, img) in enumerate(rendered):
        cx = PAD + (index % cols) * (cell_w + PAD)
        cy = header + PAD + (index // cols) * (row_h + PAD)
        draw.text((cx, cy), label, fill=(196, 160, 120, 255))
        sheet.alpha_composite(img, (cx, cy + LABEL_H))
    sheet.save(out_path)
    print(out_path, sheet.size)


def _crop_mode(argv):
    src = Image.open(argv[0]).convert("RGBA")
    out_path = argv[1]
    boxes = [tuple(int(v) for v in arg.split(",")) for arg in argv[2:]]
    cells = []
    for box in boxes:
        x, y, w, h = box
        crop = src.crop((x, y, x + w, y + h)).resize((w * SCALE, h * SCALE), Image.NEAREST)
        cells.append((box, crop))
    row_h = max(c.height for _, c in cells) + 28
    total_w = sum(c.width for _, c in cells) + PAD * (len(cells) + 1)
    sheet = Image.new("RGBA", (total_w, row_h + PAD), (40, 40, 48, 255))
    draw = ImageDraw.Draw(sheet)
    cx = PAD
    for box, crop in cells:
        sheet.alpha_composite(crop, (cx, 20))
        draw.text((cx, 4), "%d,%d %dx%d" % box, fill=(255, 255, 255, 255))
        cx += crop.width + PAD
    sheet.save(out_path)
    print(out_path, sheet.size)


def main(argv):
    if argv and argv[0] == "--sheet":
        if len(argv) < 2:
            raise SystemExit("--sheet needs an output path")
        _sheet_mode(argv[1:])
    else:
        _crop_mode(argv)


if __name__ == "__main__":
    main(sys.argv[1:])
