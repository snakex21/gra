"""Original deterministic texture-only finish for existing Traveler and Agro GLBs.

No Blender regeneration: accessor/vertex/index/skin/node/animation bytes remain
unchanged. Run after exporting edited art, or --baseline COMMIT for reproducible
release regeneration. Only existing PNG bufferViews are replaced; no added GPU
textures, material slots, shader features or runtime work. Python: numpy, Pillow.
"""
from pathlib import Path
import argparse, io, json, struct, subprocess, hashlib
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]
SEED=2601004

def unpack(raw):
    assert raw[:4]==b'glTF'
    n,kind=struct.unpack_from('<II',raw,12); assert kind==0x4e4f534a
    doc=json.loads(raw[20:20+n]); bn,bk=struct.unpack_from('<II',raw,20+n);assert bk==0x004e4942
    assert 28+n+bn==len(raw), 'Unexpected extra GLB chunks'
    assert len(doc.get('buffers',[]))==1 and 'uri' not in doc['buffers'][0], 'Only embedded single-buffer GLBs supported'
    return doc,raw[28+n:28+n+bn]
def png(a):
    s=io.BytesIO();Image.fromarray(np.clip(np.rint(a),0,255).astype('uint8')).save(s,format='PNG',optimize=True);return s.getvalue()
def pixels(raw):return np.array(Image.open(io.BytesIO(raw))).astype(float)
def tex(doc,data,index):
    v=doc['bufferViews'][doc['images'][index]['bufferView']];return data[v.get('byteOffset',0):v.get('byteOffset',0)+v['byteLength']]
def normals(field,scale):
    # PNG rows run downward; glTF tangent-space V runs upward (OpenGL +Y).
    dy,dx=np.gradient(field);a=np.stack((-dx*scale,+dy*scale,np.ones_like(field)),axis=-1);a/=np.linalg.norm(a,axis=-1,keepdims=True);return (a*.5+.5)*255

def cloth(n,seed):
    y,x=np.mgrid[:n,:n];rng=np.random.default_rng(seed)
    warp=np.sin(x*np.pi/2)*np.sin(y*np.pi/2)
    slub=np.sin(x*.15+np.sin(y*.033)*.55)
    dye=np.sin(x*.026+y*.018)*np.cos(y*.037)
    return 1.8*warp+1.5*slub+2.6*dye+rng.normal(0,.5,(n,n))

def traveler(doc,data):
    # Follow the atlas material texture references: the separate hair material
    # deliberately uses another ORM image with the same name and is untouched.
    mat=next(m for m in doc['materials'] if m['name']=='Travelers_v3_Woven_PBR_Atlas')
    p=mat['pbrMetallicRoughness']; ids=[doc['textures'][v]['source'] for v in [p['baseColorTexture']['index'],mat['normalTexture']['index'],p['metallicRoughnessTexture']['index']]]
    alb,norm,orm=[pixels(tex(doc,data,i)) for i in ids]
    assert all(a.shape[:2]==(1024,1024) for a in (alb,norm,orm)), 'Traveler atlas size changed; audit before finishing'
    n=alb.shape[0]//4;y,x=np.mgrid[:n,:n]
    # Godot/glTF UV origin and PNG row origin differ, so tile zero is bottom left.
    selected={0:([174,164,138],.94,'cloth'),1:([71,94,98],.92,'cloth'),2:([44,63,64],.96,'cloth'),6:([57,37,25],.77,'leather'),7:([104,72,44],.76,'leather'),9:([191,178,140],.93,'cloth'),15:([117,109,88],.94,'cloth')}
    for tile,(color,rough,kind) in selected.items():
        ys=slice((3-tile//4)*n,(4-tile//4)*n);xs=slice(tile%4*n,(tile%4+1)*n)
        if kind=='cloth':
            f=cloth(n,SEED+tile)
            # Low-contrast woven border follows the authored per-piece atlas UVs.
            border=np.exp(-((x-n*.09)/2.2)**2)+np.exp(-((x-n*.91)/2.2)**2)
            if tile in (1,2,15):f+=border*(4.0+1.5*np.sin(y*np.pi/4))
        else:
            rng=np.random.default_rng(SEED+tile)
            f=2.7*np.sin(x*.028)*np.cos(y*.047)+rng.normal(0,1.5,(n,n))
            f+=2*np.sin(x*.39+np.sin(y*.093))*np.sin(y*.27)
            f+=3*np.exp(-((x-n*.08)/9)**2)
        alb[ys,xs,:3]=np.array(color)+f[:,:,None]
        norm[ys,xs,:3]=normals(f/255,2.4)
        orm[ys,xs,1]=np.clip(rough*255+f*.65,0,255)
    return {i:png(a) for i,a in zip(ids,(alb,norm,orm))}

def agro(doc,data):
    result={};n=256;y,x=np.mgrid[:n,:n]
    specs={'agro_dark_bay':([82,58,41],'fur'),'agro_black_points':([39,39,37],'fur'),'agro_worn_leather':([100,70,43],'leather'),'agro_woven_blanket':([120,86,64],'cloth')}
    for name,(color,kind) in specs.items():
        if kind=='fur':
            f=2.9*np.sin(x*.47+np.sin(y*.034)*1.4)+1.2*np.sin(x*1.42+y*.019)+2.1*np.sin(y*.034+x*.018)
        elif kind=='leather':
            f=2.8*np.sin(x*.043)*np.cos(y*.036)+np.random.default_rng(SEED).normal(0,1,(n,n))
            f+=4*np.exp(-((x-23)/8)**2)+2*np.sin(x*.41+np.sin(y*.13))
        else:
            f=cloth(n,SEED+99)
            # Restrained saddle-cloth woven bands, no alteration of the mesh UVs.
            edge=np.minimum(y,n-1-y)
            f+=np.where((edge>19)&(edge<29),10,0)+np.where((edge>33)&(edge<36),-8,0)
            f+=np.where((edge>40)&(edge<54),3*np.cos(x*np.pi/8)*np.cos(y*np.pi/8),0)
        for i,im in enumerate(doc.get('images',[])):
            if im['name']==name+'_albedo':
                a=pixels(tex(doc,data,i));assert a.shape[:2]==(256,256), 'Agro atlas size changed';a[:,:,:3]=np.array(color)+f[:,:,None];result[i]=png(a)
            elif im['name']==name+'_normal':
                a=pixels(tex(doc,data,i));assert a.shape[:2]==(256,256), 'Agro atlas size changed';a[:,:,:3]=normals(f/255,1.8 if kind=='fur' else 2.1);result[i]=png(a)
    return result

def replace_images(doc,data,replacements):
    changed={doc['images'][i]['bufferView']:raw for i,raw in replacements.items()}
    out=bytearray()
    for i,v in enumerate(doc['bufferViews']):
        raw=changed.get(i,data[v.get('byteOffset',0):v.get('byteOffset',0)+v['byteLength']])
        out.extend(b'\0'*(-len(out)%4));v['byteOffset']=len(out);v['byteLength']=len(raw);out.extend(raw)
    doc['buffers'][0]['byteLength']=len(out);out.extend(b'\0'*(-len(out)%4))
    j=json.dumps(doc,separators=(',',':'),ensure_ascii=False).encode();j+=b' '*(-len(j)%4)
    return struct.pack('<4sII',b'glTF',2,28+len(j)+len(out))+struct.pack('<II',len(j),0x4e4f534a)+j+struct.pack('<II',len(out),0x004e4942)+out

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--traveler-only',action='store_true');ap.add_argument('--baseline');ap.add_argument('--check',action='store_true');ap.add_argument('--report');args=ap.parse_args();records=[]
    paths=sorted((ROOT/'models/characters/travelers_v3').glob('traveler_lod*.glb'))+sorted((ROOT/'models/agro_v3').glob('*_lod*.glb'))
    if args.traveler_only: paths=[p for p in paths if '/travelers_v3/' in p.as_posix()]
    for path in paths:
        rel=path.relative_to(ROOT).as_posix();source=subprocess.check_output(['git','show',args.baseline+':'+rel],cwd=ROOT) if args.baseline else path.read_bytes()
        doc,data=unpack(source);changes=traveler(doc,data) if '/travelers_v3/' in rel else agro(doc,data)
        if not changes:continue
        # Keep Godot's existing extracted sources coherent, including a manually
        # imported PNG lacking generator_parameters (which Godot won't overwrite).
        # Leave sidecar settings/UIDs untouched; next editor import refreshes cache.
        for index,raw in changes.items():
            extracted=path.with_name(path.stem+'_'+doc['images'][index]['name']+'.png')
            if extracted.exists():
                if args.check:assert extracted.read_bytes()==raw, str(extracted)+' extracted PNG is stale'
                else:extracted.write_bytes(raw)
        output=replace_images(doc,data,changes)
        if args.check: assert path.read_bytes()==output,rel+' differs from deterministic finish'
        else:path.write_bytes(output)
        records.append({'path':rel,'images':len(changes),'before_bytes':len(source),'after_bytes':len(output),'sha256':hashlib.sha256(output).hexdigest()})
    # Existing source .blend and original external textures remain editable bases.
    # This post-export finish is deliberately separate from geometry generation.
    for filename in ['travelers_v3_manifest.json','agro_dormin_v3_manifest.json']:
        if args.traveler_only and not filename.startswith('travelers'): continue
        path=ROOT/'assets'/filename; manifest=json.loads(path.read_text())
        manifest['material_finish']={'generator':'tools/art/refine_character_materials.py','seed':SEED,'scope':'Traveler and Agro only; post-export embedded PNG finish; original editable Blender sources unchanged','reapply':'python tools/art/refine_character_materials.py'}
        if filename.startswith('travelers'):
            for asset in manifest['assets']:
                if asset['id']=='traveler':
                    for lod in asset['lods']:lod['bytes']=(ROOT/lod['runtime']).stat().st_size
        else:manifest['totals']['agro']['glb_bytes']=sum(p.stat().st_size for p in (ROOT/'models/agro_v3').glob('*.glb'))
        serialized=json.dumps(manifest,indent=2)+'\n'
        if args.check:assert path.read_text()==serialized,filename+' metadata is stale'
        else:path.write_text(serialized)
    report={'seed':SEED,'files':records,'texture_dimensions_unchanged':True,'base':args.baseline,'check':args.check}
    if args.report:Path(args.report).write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'files':len(records),'bytes':sum(r['after_bytes'] for r in records),'check':args.check}))
if __name__=='__main__':main()
