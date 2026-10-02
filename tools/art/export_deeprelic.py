"""Export hand-edited Deeprelic LOD meshes without regenerating the entire kit.
Usage: blender -b art/source/deeprelic.blend --python-exit-code 1 \
 --python tools/art/export_deeprelic.py -- --asset processional_arch
Edit each LOD in Edit Mode; collision recipes remain separately authored in JSON.
"""
import argparse, json, sys
from pathlib import Path
import bpy
ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--asset',required=True)
a=p.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
mp=ROOT/'assets/deeprelic_manifest.json';manifest=json.loads(mp.read_text())
record=next((r for r in manifest['assets'] if r['id']==a.asset),None)
assert record, f'Unknown Deeprelic model: {a.asset}'
counts=[]
for level in range(3):
    source=bpy.data.objects.get(f'{a.asset}_LOD{level}')
    assert source and source.type=='MESH',f'Missing editable LOD{level}'
    assert all(abs(s-1)<1e-6 for s in source.scale),'Apply mesh scale first'
    temp=bpy.data.objects.new('EXPORT_'+source.name,source.data.copy())
    bpy.context.scene.collection.objects.link(temp)
    bpy.ops.object.select_all(action='DESELECT');temp.select_set(True)
    bpy.context.view_layer.objects.active=temp
    triangulate=temp.modifiers.new('export triangulation','TRIANGULATE')
    bpy.ops.object.modifier_apply(modifier=triangulate.name)
    temp.data.validate(verbose=False,clean_customdata=False)
    bpy.ops.export_scene.gltf(filepath=str(ROOT/f'models/deeprelic/{a.asset}_lod{level}.glb'),export_format='GLB',use_selection=True,export_materials='NONE',export_yup=True,export_animations=False,export_cameras=False,export_lights=False)
    counts.append(sum(len(f.vertices)-2 for f in temp.data.polygons))
    if level==0:record['bounds_godot']=[[v[0],v[2],-v[1]] for v in temp.bound_box]
    bpy.data.objects.remove(temp,do_unlink=True)
assert 0<counts[2]<=counts[1]<=counts[0], 'Review edited LOD triangle ordering'
record['lod_triangles']=counts
mp.write_text(json.dumps(manifest,indent=2)+'\n')
print('DEEPRELIC_EDITED_EXPORT_OK',a.asset,counts)
