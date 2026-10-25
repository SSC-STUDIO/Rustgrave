"""Decode every project bitmap and build review sheets by asset family.

Animation folders are represented by their first, middle and final frames. This
is a delivery/visual-review aid, not a score that decides artistic quality.
"""
from pathlib import Path
from collections import defaultdict, Counter
import argparse, hashlib, json, math, re
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
EXTS = {'.png','.jpg','.jpeg','.webp','.bmp'}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',default='screenshots/acceptance/material-polish-20261025/inventory')
    parser.add_argument('--baseline',help='Earlier inventory.json to compare sizes and file hashes against')
    args = parser.parse_args()
    out = ROOT/args.out
    out.mkdir(parents=True,exist_ok=True)
    font = ImageFont.truetype('C:/Windows/Fonts/consola.ttf',12)
    records, errors, families = [], [], defaultdict(list)
    for path in sorted((ROOT/'assets').rglob('*')):
        if path.suffix.lower() not in EXTS: continue
        relative = path.relative_to(ROOT).as_posix()
        try:
            with Image.open(path) as source:
                source.load()
                im = source.convert('RGBA')
                alpha = im.getchannel('A')
                colors = im.getcolors(4097)
                record = {'file':relative,'size':list(im.size),'bytes':path.stat().st_size,
                          'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
                          'alpha_bbox':alpha.getbbox(),'alpha_extrema':alpha.getextrema(),
                          'colors_up_to_4096':len(colors) if colors else '>4096'}
                records.append(record)
                # Frame sequence files share a family, individual props/atlases do not.
                stem = re.sub(r'[_-]?\d+$','',path.stem)
                key = str(path.parent.relative_to(ROOT/'assets'))+'/'+stem
                families[key].append(path)
        except Exception as error:
            errors.append({'file':relative,'error':str(error)})
    groups = defaultdict(list)
    for key,paths in families.items():
        indexes = sorted(set([0,len(paths)//2,len(paths)-1])) if len(paths)>3 else range(len(paths))
        top = paths[0].relative_to(ROOT/'assets').parts[0]
        for index in indexes: groups[top].append(paths[index])
    sheets=[]
    for group,paths in sorted(groups.items()):
        for page in range(math.ceil(len(paths)/48)):
            chunk=paths[page*48:(page+1)*48]
            sheet=Image.new('RGB',(1536,math.ceil(len(chunk)/8)*158+28),'#171d26')
            draw=ImageDraw.Draw(sheet)
            draw.text((8,6),f'{group}: family samples {page*48+1}..{page*48+len(chunk)}',font=font,fill='#f0c989')
            for i,path in enumerate(chunk):
                x,y=i%8*192,i//8*158+28
                draw.rectangle((x+3,y+2,x+188,y+124),fill='#303744')
                with Image.open(path) as source:
                    im=source.convert('RGBA')
                    # Show complete atlases; never infer native resolution from thumbnail size.
                    scale=min(180/im.width,118/im.height,4)
                    size=(max(1,round(im.width*scale)),max(1,round(im.height*scale)))
                    im=im.resize(size,Image.Resampling.NEAREST)
                    sheet.paste(im,(x+96-size[0]//2,y+62-size[1]//2),im)
                    label=path.relative_to(ROOT/'assets').as_posix()
                    draw.text((x+4,y+126),label[-28:],font=font,fill='#e7e2d3')
                    draw.text((x+4,y+140),f'{source.width}x{source.height}',font=font,fill='#91adb6')
            name=f'{group}-{page+1:02d}.png'
            sheet.save(out/name)
            sheets.append({'file':name,'samples':[p.relative_to(ROOT).as_posix() for p in chunk]})
    report={'bitmaps':len(records),'families':len(families),'decode_errors':errors,
            'counts':dict(Counter(r['file'].split('/')[1] for r in records)),
            'review_sheets':sheets,'records':records,
            'scope':'All bitmap files under assets decoded; visual sheets sample animation families. No automatic artistic-quality claim.'}
    if args.baseline:
        baseline=json.loads((ROOT/args.baseline).read_text(encoding='utf-8'))
        old={r['file']:r for r in baseline['records']}
        current={r['file']:r for r in records}
        report['delta']={
            'added':sorted(current.keys()-old.keys()),
            'removed':sorted(old.keys()-current.keys()),
            'changed':[r['file'] for r in records if r['file'] in old and r['sha256']!=old[r['file']]['sha256']],
            'size_changes':[{'file':r['file'],'before':old[r['file']]['size'],'after':r['size']}
                            for r in records if r['file'] in old and r['size']!=old[r['file']]['size']]}
    (out/'inventory.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:report[k] for k in ['bitmaps','families','decode_errors','counts']}))
    print('Review sheets:',len(sheets))

if __name__=='__main__': main()
