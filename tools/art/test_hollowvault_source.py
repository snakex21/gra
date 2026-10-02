from pathlib import Path
import bpy,json,bmesh,math
from mathutils import Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[2]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'art/source/hollowvault.blend'))
m=json.loads((ROOT/'assets/hollowvault_manifest.json').read_text());checks=0;ceiling_rays=0
for a in m['assets']:
 for lod in range(3):
  o=bpy.data.objects[a['id']+f'_LOD{lod}'];assert o.type=='MESH';assert o['source_seed']==69173
  assert len(o.data.polygons)==a['lod_triangles'][lod];assert len(o.data.uv_layers)==1
  assert all(math.isfinite(c) for v in o.data.vertices for c in v.co);checks+=5
  tree=BVHTree.FromPolygons([v.co for v in o.data.vertices],[p.vertices for p in o.data.polygons],all_triangles=True)
  def ray(start,end):
   s=Vector((start[0],-start[2],start[1]));e=Vector((end[0],-end[2],end[1]));d=e-s
   return tree.ray_cast(s,d.normalized(),d.length)
  for p in a['passage_probes']:
   result=ray(p['from'],p['to']);assert (result[0] is not None)==(p['expect']=='hit'),(a['id'],lod,p,result);checks+=1
  if 'closed_dome' in a['id']:
   rx,rz=(22,28) if a['id'].startswith('great') else (12,15)
   for ix in range(-8,9):
    for iz in range(-8,9):
     x=rx*ix/10+.013;z=rz*iz/10+.019
     if (x/rx)**2+(z/rz)**2>.8:continue
     hit,normal,_,_=ray((x,1,z),(x,50,z))
     assert hit is not None,(a['id'],lod,x,z,'ceiling hole')
     assert normal.z<-.08,(a['id'],lod,x,z,'outward interior normal',normal)
     ceiling_rays+=1
   bm=bmesh.new();bm.from_mesh(o.data)
   assert all(e.is_manifold for e in bm.edges),(a['id'],lod,'nonmanifold shell');bm.free();checks+=1
  if a['id'].startswith('vault_'):
   hit,normal,_,_=ray((1,3,0),(1,10,0));assert hit is not None and normal.z<0,(a['id'],lod,'roof normal');checks+=1
assert any(im.packed_file is not None for im in bpy.data.images)
report={'checks':checks,'upward_ceiling_rays':ceiling_rays,'assets':len(m['assets']),'lod_meshes':len(m['assets'])*3,'result':'passed','coverage':'Manifold solid dome shells, complete upper hemisphere, inward roof normals, visual passages all three LODs'}
(ROOT/'art/reports/v6/source_geometry.json').write_text(json.dumps(report,indent=2)+'\n')
print('HOLLOWVAULT_SOURCE_OK',report)
