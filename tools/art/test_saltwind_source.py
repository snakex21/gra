"""Check original editable source, UV metric ratios and structural openings."""
from pathlib import Path
import bpy,json,math
from mathutils import Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[2]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'art/source/saltwind.blend'))
m=json.loads((ROOT/'assets/saltwind_manifest.json').read_text());checks=0
for a in m['assets']:
 for lod in range(3):
  o=bpy.data.objects[a['id']+f'_LOD{lod}'];assert o.type=='MESH';assert o['source_seed']==47063
  assert len(o.data.polygons)==a['lod_triangles'][lod];assert len(o.data.uv_layers)==1;checks+=4
# UV metric scale is isotropic on axis-aligned architecture faces.
for name in ['wind_gate_13m','wind_sieve_tower','ribbed_salt_pillar','sunken_retaining_wall']:
 o=bpy.data.objects[name+'_LOD1'];uv=o.data.uv_layers[0]
 for p in o.data.polygons:
  if max(abs(x) for x in p.normal)<.999:continue
  world=[o.data.vertices[o.data.loops[li].vertex_index].co for li in p.loop_indices]
  tex=[uv.data[li].uv for li in p.loop_indices];scales=[]
  for i in range(3):
   edge=(world[(i+1)%3]-world[i]).length
   if edge>.001:scales.append((tex[(i+1)%3]-tex[i]).length/edge)
  assert max(scales)/min(scales)<1.002,(name,scales);checks+=1
for a in m['assets']:
 if not a['passage_probes']:continue
 for lod in range(3):
  o=bpy.data.objects[a['id']+f'_LOD{lod}'];tree=BVHTree.FromPolygons([v.co for v in o.data.vertices],[p.vertices for p in o.data.polygons],all_triangles=True)
  for probe in a['passage_probes']:
   if probe['expect']!='clear':continue
   x,y,z=probe['from'];start=Vector((x,-z,y));x,y,z=probe['to'];end=Vector((x,-z,y));delta=end-start
   hit=tree.ray_cast(start,delta.normalized(),delta.length)
   assert hit[0] is None,(a['id'],lod,'visual passage closed');checks+=1
assert len(bpy.data.images)>0
for name in ['atlas_1k']:
 image=bpy.data.images[name];assert image.packed_file is not None;checks+=1
print('SALTWIND_SOURCE_OK',checks,'checks; editable LODs, isotropic UVs, visual passages, packed model atlas')
