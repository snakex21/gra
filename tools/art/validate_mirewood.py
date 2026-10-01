#!/usr/bin/env python3
"""Offline checks of the actual Mirewood GLBs, source, recipes and scope boundary."""
import hashlib,json,math,struct,subprocess
from pathlib import Path
from validate_exports import read_glb
ROOT=Path(__file__).resolve().parents[2]
BASE='f48162425002ec23562a271c11b4abd8b6c593cf'
m=json.loads((ROOT/'assets/mirewood_manifest.json').read_text())
def accessor(g, binary, n):
    a=g['accessors'][n];v=g['bufferViews'][a['bufferView']]
    fmt={5121:'B',5123:'H',5125:'I',5126:'f'}[a['componentType']]
    count={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
    width=struct.calcsize('<'+fmt*count);stride=v.get('byteStride',width)
    offset=v.get('byteOffset',0)+a.get('byteOffset',0)
    return [struct.unpack_from('<'+fmt*count,binary,offset+i*stride) for i in range(a['count'])]
ids=set();rows=[];checks=0
for a in m['assets']:
    aid=a['id'];assert aid not in ids;ids.add(aid)
    tri=[]
    for level in range(3):
        path=ROOT/f'models/mirewood/{aid}_lod{level}.glb'
        tri.append(read_glb(path,a['bounds_godot'] if level==0 else None))
        raw=path.read_bytes();size=struct.unpack_from('<I',raw,12)[0];g=json.loads(raw[20:20+size])
        attrs=g['meshes'][0]['primitives'][0]['attributes']
        assert 'TEXCOORD_0' in attrs and 'NORMAL' in attrs,(aid,'UV/normals missing')
        assert not g.get('skins') and not g.get('animations'),aid
        binary_size=struct.unpack_from('<I',raw,20+size)[0]
        binary=raw[28+size:28+size+binary_size]
        uv=accessor(g,binary,attrs['TEXCOORD_0'])
        assert all(all(math.isfinite(x) and -.001<=x<=1.001 for x in p) for p in uv),(aid,'bad UV')
        normals=accessor(g,binary,attrs['NORMAL'])
        assert all(all(math.isfinite(x) for x in p) and sum(x*x for x in p)>.9 for p in normals),(aid,'bad normals')
        positions=accessor(g,binary,attrs['POSITION'])
        indexes=[v[0] for v in accessor(g,binary,g['meshes'][0]['primitives'][0]['indices'])]
        for t in range(0,len(indexes),3):
            p0,p1,p2=[positions[indexes[t+k]] for k in range(3)]
            u=[p1[k]-p0[k] for k in range(3)];v=[p2[k]-p0[k] for k in range(3)]
            cross=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]]
            assert sum(c*c for c in cross)>1e-16,(aid,level,'zero-area triangle',t//3)
        checks+=7
    assert tri==a['lod_triangles'] and 0<tri[2]<=tri[1]<tri[0],(aid,tri)
    assert tri[0]<20000,(aid,'excess budget')
    shapes=a.get('collision_shapes',[])
    assert bool(shapes)==(a['collision']=='compound'),(aid,'collision policy mismatch')
    for s in shapes:
        assert s['type'] in ['box','convex'],s
        if s['type']=='box':
            assert len(s['size'])==3 and min(s['size'])>0
            assert len(s['position'])==3
            assert all(math.isfinite(v) for v in s['size']+s['position']+s.get('rotation',[0,0,0]))
        else:
            assert 4<=len(s['points'])<=32
            assert all(len(p)==3 and all(math.isfinite(v) for v in p) for p in s['points'])
        checks+=1
    assert len(shapes)<=64,(aid,'too many collision proxies')
    prefab=ROOT/f'environment/mirewood/{aid}.tscn'
    assert prefab.exists() and 'mirewood_asset.gd' in prefab.read_text()
    rows.append({'id':aid,'triangles':tri,'proxy_shapes':len(shapes),'glb_bytes':sum((ROOT/f'models/mirewood/{aid}_lod{l}.glb').stat().st_size for l in range(3))})
    checks+=5
assert len(ids)==31,len(ids)
source=ROOT/'art/source/mirewood.blend';assert source.exists() and source.stat().st_size>100000
for path in ['src','scenes','tests','project.godot','assets/colossus_visual_contract.json']:
    assert not subprocess.check_output(['git','diff',BASE,'--',path],cwd=ROOT),path
checks+=7
texture_sizes = {'atlas_1k.png':1024,'peat_albedo.png':1024,'peat_normal.png':1024,'moss_albedo.png':1024,'moss_normal.png':1024}
texture_bytes = 0
for filename, size in texture_sizes.items():
    path = ROOT/'textures/mirewood'/filename
    raw = path.read_bytes()
    assert raw[:8] == b'\x89PNG\r\n\x1a\n'
    assert struct.unpack('>II',raw[16:24]) == (size,size),(filename,'wrong map dimensions')
    texture_bytes += len(raw)
    checks += 2
report={'checks':checks,'asset_count':len(rows),'lod_glbs':len(rows)*3,'assets':rows,'unique_triangles_by_lod':[sum(r['triangles'][i] for r in rows) for i in range(3)],'collision_shape_count':sum(r['proxy_shapes'] for r in rows),'runtime_glb_bytes':sum(r['glb_bytes'] for r in rows),'source_blend_bytes':source.stat().st_size,'new_textures':5,'source_texture_bytes':texture_bytes,'texture_dimensions':texture_sizes,'shared_original_atlas':'textures/mirewood/atlas_1k.png','shared_atlas_estimate_rgba8_full_mips_bytes':5592405,'all_five_maps_estimate_rgba8_full_mips_bytes':27962025,'scope_base':BASE,'scope_fence':'src, scenes, tests, project.godot and original colossus contract unchanged','notes':['Exactly one surface per GLB, new shared atlas override, no embedded images; five shared texture maps.','Collision recipes remain separate from visual LODs and retain openings.','Triangle totals are unique library geometry, not the rendered-frame workload.','Atlas memory is an uncompressed theoretical estimate; actual renderer counters are reported separately.']}
folder=ROOT/'art/reports/v5';folder.mkdir(parents=True,exist_ok=True)
(folder/'export_budgets.json').write_text(json.dumps(report,indent=2)+'\n')
paths=[p for d in ['models/mirewood','environment/mirewood'] for p in (ROOT/d).rglob('*') if p.is_file() and not p.name.endswith('.import')]+[source,ROOT/'assets/mirewood_manifest.json']
(folder/'checksums.json').write_text(json.dumps({'algorithm':'SHA-256','files':[{'path':str(p.relative_to(ROOT)),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'bytes':p.stat().st_size} for p in sorted(paths)]},indent=2)+'\n')
print('MIREWOOD_EXPORTS_OK',json.dumps({k:v for k,v in report.items() if k not in ['assets','notes']}))
