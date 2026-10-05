"""Deterministic, isolated Valus/Gaius/Pelagia surface finish.

Reads immutable shared atlas as source; never edits it or any GLB. PNG tile rows
are bottom-up relative to authored UV tile numbers. Tile 10 is deliberately
untouched: Pelagia control teeth and Valus ornament share it. numpy + Pillow.
"""
from pathlib import Path
import argparse, hashlib, io, json
import numpy as np
from PIL import Image, ImageFilter
ROOT = Path(__file__).resolve().parents[2]
SEED = 2601004
TILES = {0:'valus layered stone',2:'gaius cut stone',5:'pelagia waterworn stone',6:'valus coarse wool',7:'gaius weathered wool',8:'pelagia dark fur',11:'gaius aged bronze',13:'pelagia oxidized fittings'}

def tile_slice(tile, n=512):
    return slice((3-tile//4)*n,(4-tile//4)*n),slice((tile%4)*n,(tile%4+1)*n)

def blur(a,radius):
    # Float precision avoids quantization bands in low-frequency mineral deposits.
    fy=np.fft.fftfreq(a.shape[0])[:,None];fx=np.fft.fftfreq(a.shape[1])[None,:]
    kernel=np.exp(-2*np.pi*np.pi*radius*radius*(fx*fx+fy*fy))
    return np.fft.ifft2(np.fft.fft2(a)*kernel).real

def fields(tile,n=512):
    y,x=np.mgrid[:n,:n];rng=np.random.default_rng(SEED+tile)
    broad=blur(rng.normal(0,1,(n,n)),18);broad=(broad-broad.mean())/(broad.std()+1e-8)
    grain=blur(rng.normal(0,1,(n,n)),.65);grain=grain/(grain.std()+1e-8)
    pits=np.zeros((n,n));wear=np.zeros((n,n))
    for _ in range(95 if tile in (0,2,5) else 45):
        cx,cy=rng.uniform(0,n,2);r=rng.uniform(1,4.5)
        pits+=np.exp(-((x-cx)**2+(y-cy)**2)/(r*r))
    if tile==0:
        strata=np.sin(y*.078+1.8*np.sin(x*.013)+broad*.24)
        grooves=np.exp(-((strata+.72)/.17)**2)
        f=4.6*broad+3.1*grain-14*grooves-12*pits
        wear=np.clip(strata,0,1)
        rough=.91+.035*broad+.035*pits
    elif tile==2:
        # Crossing mineral beds and incised seams, not a flat hue substitution.
        phase=x*.058+y*.018+np.sin(y*.017)*1.8
        seams=np.exp(-((np.sin(phase)+.90)/.095)**2)
        f=5*broad+2.5*grain-16*seams-13*pits+4*np.maximum(np.sin(phase+.28),0)
        rough=.84+.045*broad+.07*seams
    elif tile==5:
        flow=np.sin(x*.048+np.sin(y*.013)*2.7)
        deposits=np.clip(broad+.15,0,1.8)
        f=5.5*broad+2.2*grain+5*flow-12*pits
        wear=deposits
        rough=.74+.085*deposits+.035*pits
    elif tile in (6,7,8):
        wave=x*(.33 if tile==6 else .40)+1.7*np.sin(y*.024)+.65*np.sin(y*.084)
        fibers=np.sin(wave)+.38*np.sin(wave*2.8+y*.007)
        clumps=np.sin(x*.081+1.5*np.sin(y*.019))
        # Irregular broken strand highlights avoid a machined corduroy effect.
        broken=.55+.45*np.sin(y*.039+x*.006)**2
        f=(6.7 if tile==6 else 5.5)*fibers*broken+4.5*clumps+3*broad+1.2*grain
        rough=.94+.018*broad
    else:
        patina=np.clip((broad+.28)/1.25,0,1)
        hairline=np.maximum(np.sin(x*.43+y*.15+np.sin(y*.09))-0.965,0)*22
        f=4*broad+2*grain-12*patina-9*pits+9*hairline
        wear=patina
        rough=.61+.28*patina+.055*pits
    f-=f.mean() # keep authored average hue/luminance: finish, not recoloring
    return f,np.clip(rough,.48,.98),wear,pits

def generate(root=ROOT):
    source=root/'textures/colossi_v3';albedo=np.array(Image.open(source/'atlas_2k.png').convert('RGB'));normal=np.array(Image.open(source/'atlas_normal.png').convert('RGB'))
    assert albedo.shape==normal.shape==(2048,2048,3)
    out=albedo.copy();norm=normal.copy();orm=np.empty_like(out);orm[:]=[255,217,0]
    records=[]
    for tile,label in TILES.items():
        sl=tile_slice(tile);f,rough,wear,pits=fields(tile);rgb=albedo[sl].astype(float)+f[:,:,None]
        if tile==5:rgb+=wear[:,:,None]*np.array([2,1,-2])
        if tile in (11,13):rgb+=wear[:,:,None]*np.array([-3,2,1])
        out[sl]=np.clip(np.rint(rgb),0,255).astype('uint8')
        # Tangent-space +Y: PNG scanline axis is opposite authored UV V.
        dy,dx=np.gradient(blur(f, .65)/255)
        n=normal[sl].astype(float)/255*2-1;n[:,:,0]-=dx*3.2;n[:,:,1]+=dy*3.2
        n/=np.linalg.norm(n,axis=-1,keepdims=True);norm[sl]=np.clip(np.rint((n*.5+.5)*255),0,255).astype('uint8')
        orm[sl[0],sl[1],1]=np.rint(rough*255).astype('uint8')
        if tile in (11,13):orm[sl[0],sl[1],2]=np.rint((.32 if tile==11 else .22)*(1-wear*.85)*255).astype('uint8')
        records.append({'tile':tile,'surface':label,'mean_abs_delta':float(np.abs(out[sl].astype(float)-albedo[sl]).mean()),'roughness_min':float(rough.min()),'roughness_max':float(rough.max())})
    return {'atlas_2k.png':out,'atlas_normal.png':norm,'atlas_orm.png':orm},records

def encoded(a):
    b=io.BytesIO();Image.fromarray(a).save(b,format='PNG',optimize=True);return b.getvalue()

def main():
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');p.add_argument('--report');args=p.parse_args()
    arrays,records=generate();dst=ROOT/'textures/colossi_material_finish';dst.mkdir(exist_ok=True)
    hashes={}
    for name,array in arrays.items():
        raw=encoded(array);path=dst/name
        if args.check:assert path.read_bytes()==raw,'Not reproducible: '+name
        else:path.write_bytes(raw)
        hashes[name]=hashlib.sha256(raw).hexdigest()
    report={'seed':SEED,'profiles':['valus','gaius','pelagia'],'tiles':records,'untouched_control_tooth_tile':10,'files':hashes,'check':args.check}
    if args.report:Path(args.report).write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
if __name__=='__main__':main()
