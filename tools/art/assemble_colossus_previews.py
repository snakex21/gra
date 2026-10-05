"""Compose labeled evidence boards from untouched matched CPU render PNGs."""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

FONT='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
BOLD='/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
def font(size,bold=False): return ImageFont.truetype(BOLD if bold else FONT,size)
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def build(output,filename,rows,cell_width):
    gap,pad=12,24
    cols=len(rows[0])
    cell_height=round(cell_width*.9)
    header,label,rowgap,footer=118,36,44,48
    width=pad*2+cols*cell_width+(cols-1)*gap
    height=header+len(rows)*(label+cell_height+rowgap)+footer
    board=Image.new('RGB',(width,height),(24,30,34));d=ImageDraw.Draw(board)
    d.text((pad,21),'COLOSSUS MATERIAL FINISH',font=font(27,True),fill=(237,238,230))
    d.text((pad,61),'Actual Godot-loaded sculptures | Matched camera, light and transforms | Blender Cycles CPU',font=font(17),fill=(174,184,190))
    sources=[]
    for row_idx,row in enumerate(rows):
        top=header+row_idx*(label+cell_height+rowgap)
        for col,(subject,lod,view,variant,title) in enumerate(row):
            left=pad+col*(cell_width+gap)
            p=output/'renders'/f'{subject}_lod{lod}_{view}_{variant}.png'
            picture=Image.open(p).convert('RGB')
            assert picture.width/picture.height > 1.1
            picture=picture.resize((cell_width,cell_height),Image.Resampling.LANCZOS)
            d.text((left,top),title,font=font(16,True),fill=(239,199,117) if variant=='after' else (212,218,221))
            board.paste(picture,(left,top+label))
            sources.append({'path':str(p.relative_to(output)),'sha256':sha(p)})
    d.text((pad,height-45),'Geometry / UVs / weak points retained. Frozen material review; not a Godot GPU screenshot or performance test.',font=font(15),fill=(174,184,190))
    png=output/(filename+'.png');jpg=output/(filename+'.jpg')
    board.save(png)
    board.save(jpg,quality=78,optimize=True,progressive=True,subsampling=0)
    (output/(filename+'.json')).write_text(json.dumps({'sources':sources,'png_sha256':sha(png),'jpg_sha256':sha(jpg),'composer_sha256':sha(Path(__file__))},indent=2))
    return jpg


def pair(subject,lod,view,title):
    return [(subject,lod,view,v,f'{title} | '+v.title()) for v in ('before','after')]


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('output',type=Path);args=parser.parse_args()
    out=args.output.resolve()
    review=build(out,'review_board',[
        pair(subject,0,'overview',subject.capitalize())+pair(subject,0,'surface','Surface detail')
        for subject in ('valus','gaius','pelagia')],440)
    lod=build(out,'lod_board',[
        sum((pair(subject,level,'overview',f'{subject.capitalize()} LOD{level}') for level in range(3)),[])
        for subject in ('valus','gaius','pelagia')],280)
    pose=build(out,'weakpoint_board',[
        pair(subject,0,'weakpoint',subject.capitalize()+' / weak-point context')
        for subject in ('valus','gaius','pelagia')],670)
    previews=[review,lod,pose]
    assert sum(p.stat().st_size for p in previews)<1_800_000,'Package JPEG board budget exceeded'
    delivery={'previews':[{'path':str(p.relative_to(out)),'sha256':sha(p),'bytes':p.stat().st_size} for p in previews],
              'standalone_pngs':['review_board.png','lod_board.png','weakpoint_board.png'],'package_preview_bytes':sum(p.stat().st_size for p in previews)}
    (out/'delivery_previews.json').write_text(json.dumps(delivery,indent=2))
    print('COLOSSUS_BOARDS_OK',delivery['package_preview_bytes'],'package JPEG bytes')

if __name__=='__main__':main()
