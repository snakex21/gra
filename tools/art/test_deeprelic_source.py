from pathlib import Path
import bpy,json,bmesh,math
from mathutils import Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[2]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'art/source/deeprelic.blend'))
m=json.loads((ROOT/'assets/deeprelic_manifest.json').read_text());checks=0;ceiling_rays=0
for a in m['assets']:
 for lod in range(3):
  o=bpy.data.objects[a['id']+f'_LOD{lod}'];assert o.type=='MESH';assert o['source_seed']==70231
  assert len(o.data.polygons)==a['lod_triangles'][lod];assert len(o.data.uv_layers)==1
  assert all(math.isfinite(c) for v in o.data.vertices for c in v.co);checks+=5
  tree=BVHTree.FromPolygons([v.co for v in o.data.vertices],[p.vertices for p in o.data.polygons],all_triangles=True)
  def ray(start,end):
   s=Vector((start[0],-start[2],start[1]));e=Vector((end[0],-end[2],end[1]));d=e-s
   return tree.ray_cast(s,d.normalized(),d.length)
  for p in a['passage_probes']:
   result=ray(p['from'],p['to']);assert (result[0] is not None)==(p['expect']=='hit'),(a['id'],lod,p,result);checks+=1
assert any(im.packed_file is not None for im in bpy.data.images)
report={'checks':checks,'upward_ceiling_rays':ceiling_rays,'assets':len(m['assets']),'lod_meshes':len(m['assets'])*3,'result':'passed','coverage':'Editable meshes, UVs, finite coordinates, LOD counts, shared packed atlas, gates and broken bridge clear across all visual LODs'}
(ROOT/'art/reports/v7/source_geometry.json').write_text(json.dumps(report,indent=2)+'\n')
print('DEEPRELIC_SOURCE_OK',report)
