#!/usr/bin/env python3
"""Offline, dependency-free GLB/PNG/provenance validation and static budget report."""
import hashlib
import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read_glb(path, expected_bounds=None):
    raw = path.read_bytes()
    magic, version, size = struct.unpack_from('<III', raw)
    assert magic == 0x46546C67 and version == 2 and size == len(raw), path
    length, kind = struct.unpack_from('<II', raw, 12)
    assert kind == 0x4E4F534A, path
    gltf = json.loads(raw[20:20+length])
    blen, btype = struct.unpack_from('<II', raw, 20+length)
    assert btype == 0x004E4942, path
    binary = raw[28+length:28+length+blen]
    assert not gltf.get('images') and not gltf.get('textures'), 'No per-model texture duplication'
    assert len(gltf['meshes']) == 1, path
    assert len(gltf['meshes'][0]['primitives']) == 1, path
    primitive = gltf['meshes'][0]['primitives'][0]
    acc = gltf['accessors'][primitive['attributes']['POSITION']]
    if expected_bounds is not None:
        for axis in range(3):
            assert abs(min(v[axis] for v in expected_bounds)-acc['min'][axis]) < .001, (path,'minimum bound',axis)
            assert abs(max(v[axis] for v in expected_bounds)-acc['max'][axis]) < .001, (path,'maximum bound',axis)
    view = gltf['bufferViews'][acc['bufferView']]
    offset = view.get('byteOffset', 0)+acc.get('byteOffset', 0)
    stride = view.get('byteStride', 12)
    for i in range(acc['count']):
        xyz = struct.unpack_from('<3f', binary, offset+i*stride)
        assert all(math.isfinite(v) for v in xyz), path
    index = gltf['accessors'][primitive['indices']]
    assert index['count'] % 3 == 0, path
    return index['count']//3


def main():
    manifest = json.loads((ROOT/'assets/art_manifest.json').read_text())
    records = []
    for asset in manifest['assets']:
        base = ROOT/asset['runtime']
        triangles = [read_glb(base.with_name(base.name.replace('_lod0',f'_lod{i}')), asset['bounds_godot'] if i == 0 else None) for i in range(3)]
        assert 0 < triangles[2] <= triangles[1] <= triangles[0], asset['id']
        assert triangles == asset['lod_triangles'], (asset['id'], triangles, asset['lod_triangles'])
        col = base.with_name(base.name.replace('_lod0','_collision'))
        col_triangles = read_glb(col) if col.exists() else None
        if col_triangles is not None:
            assert col_triangles <= 60, (asset['id'],col_triangles)
        records.append({'id':asset['id'],'triangles':triangles,'collision_triangles':col_triangles})
    textures = []
    for file in sorted((ROOT/'textures/environment').glob('*.png')):
        raw = file.read_bytes()
        assert raw[:8] == b'\x89PNG\r\n\x1a\n'
        w,h = struct.unpack_from('>II',raw,16)
        assert w <= 1024 and h <= 1024
        assert w & (w-1) == 0 and h & (h-1) == 0
        textures.append({'file':str(file.relative_to(ROOT)),'size':[w,h],'bytes':len(raw)})
    contract = json.loads((ROOT/'assets/colossus_visual_contract.json').read_text())
    observed = hashlib.sha256((ROOT/contract['source']).read_bytes()).hexdigest()
    assert observed == contract['source_sha256'], 'Gameplay segment contract changed: inspect and update the art adapter, not gameplay'
    assert len(contract['rest_joints']) == 17
    roots = ['models','textures','art/source','environment','materials','tools/art','art/scripts','art/tests']
    files = []
    for root in roots:
        for file in sorted((ROOT/root).rglob('*')):
            if not file.is_file() or file.name.endswith(('.import','.blend1','.pyc')) or 'output' in file.parts or '__pycache__' in file.parts:
                continue
            files.append({'path':str(file.relative_to(ROOT)),'sha256':hashlib.sha256(file.read_bytes()).hexdigest(),'bytes':file.stat().st_size})
    report = {'asset_count':len(records),'assets':records,'textures':textures,'unique_base_triangles':sum(a['triangles'][0] for a in records),'texture_rgba8_mip_estimate_bytes':int(sum(t['size'][0]*t['size'][1]*4*4/3 for t in textures)),'runtime_glb_bytes':sum(f['bytes'] for f in files if f['path'].endswith('.glb')),'notes':['Texture estimate assumes all files simultaneously resident as uncompressed RGBA8 plus mipmaps; renderer counters are recorded separately.','Collision counts exclude built-in box/cylinder/heightfield proxies and the untouched gameplay segment shapes.','All GLBs use one surface and reference the shared Godot atlas material at runtime.']}
    (ROOT/'art/reports').mkdir(parents=True,exist_ok=True)
    (ROOT/'art/reports/asset_budgets.json').write_text(json.dumps(report,indent=2)+'\n')
    (ROOT/'assets/art_checksums.json').write_text(json.dumps({'algorithm':'SHA-256','files':files},indent=2)+'\n')
    print(f'EXPORTS_OK: {len(records)} assets / {len(records)*3} LOD GLBs / {len(textures)} textures; original 17-segment contract unchanged')


if __name__ == '__main__':
    main()
