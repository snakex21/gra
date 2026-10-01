"""Re-export one edited mesh, preserving all other assets.

blender -b art/source/saltward_kit.blend --python-exit-code 1 \
  --python tools/art/export_from_blend.py -- --asset rock_01

Edit the LOD0 mesh in Blender Edit Mode, preserving its object origin, then save.
Generated LOD previews in the source file are refreshed after export.
"""
import argparse
import bpy
import bmesh
import json
import sys
from pathlib import Path
from mathutils import Matrix

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--asset', required=True)
args = parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
manifest_path = ROOT/'assets/art_manifest.json'
manifest = json.loads(manifest_path.read_text())
record = next((a for a in manifest['assets'] if a['id'] == args.asset), None)
assert record, f'Unknown asset {args.asset}'
source = bpy.data.objects.get(args.asset+'_LOD0')
assert source and source.type == 'MESH', 'Expected editable LOD0 mesh in source .blend'
assert source.scale == source.scale.__class__((1,1,1)), 'Apply scale before export'
folder = 'colossus' if record['category'] == 'colossus' else 'environment'
record['lod_triangles'] = []
record['bounds_godot'] = [[v[0], v[2], -v[1]] for v in source.bound_box]
temp = []


def export(ob, path):
    bpy.ops.object.select_all(action='DESELECT')
    ob.hide_viewport = False
    ob.hide_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    ob.data.validate(verbose=False, clean_customdata=False)
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,
        export_materials='NONE',export_yup=True,export_animations=False,export_cameras=False,export_lights=False)
    return sum(len(p.vertices)-2 for p in ob.data.polygons)


for level,ratio in enumerate([1,.48,.18]):
    ob = bpy.data.objects.new('EXPORT_'+args.asset+f'_LOD{level}',source.data.copy())
    bpy.context.scene.collection.objects.link(ob)
    temp.append(ob)
    bpy.context.view_layer.objects.active = ob
    tri = ob.modifiers.new('triangulate','TRIANGULATE')
    bpy.ops.object.modifier_apply(modifier=tri.name)
    if level:
        dec = ob.modifiers.new('decimate','DECIMATE')
        dec.ratio = ratio
        bpy.ops.object.modifier_apply(modifier=dec.name)
    path = ROOT/f'models/{folder}/{args.asset}_lod{level}.glb'
    record['lod_triangles'].append(export(ob,path))
    preview = bpy.data.objects.get(args.asset+f'_LOD{level}')
    if preview and level:
        preview.data = ob.data.copy()
if record['collision'] == 'hull':
    bm = bmesh.new()
    for vertex in source.data.vertices:
        bm.verts.new(vertex.co)
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.001)
    hull = bmesh.ops.convex_hull(bm,input=list(bm.verts),use_existing_faces=False)
    bmesh.ops.delete(bm,geom=list(set(hull['geom_interior']) | set(hull['geom_unused'])),context='VERTS')
    bmesh.ops.triangulate(bm,faces=list(bm.faces))
    mesh = bpy.data.meshes.new(args.asset+'_COL')
    bm.to_mesh(mesh);bm.free()
    col = bpy.data.objects.new('EXPORT_collision',mesh)
    bpy.context.scene.collection.objects.link(col)
    temp.append(col)
    bpy.context.view_layer.objects.active = col
    dec = col.modifiers.new('collision reduction','DECIMATE')
    dec.ratio = min(1,48/max(1,len(mesh.polygons)))
    bpy.ops.object.modifier_apply(modifier=dec.name)
    record['collision_triangles'] = export(col,ROOT/f'models/{folder}/{args.asset}_collision.glb')
    preview = bpy.data.objects.get(args.asset+'_COL')
    if preview:
        preview.data = col.data.copy()
for ob in temp:
    bpy.data.objects.remove(ob,do_unlink=True)
manifest_path.write_text(json.dumps(manifest,indent=2)+'\n')
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath,compress=True)
print('ART_SINGLE_EXPORT_OK',args.asset,record['lod_triangles'])
