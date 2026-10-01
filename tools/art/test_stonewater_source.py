"""Blender source regression: continuous structural roofs and isotropic planar UVs.
Run: blender -b --python-exit-code 1 --python tools/art/test_stonewater_source.py
"""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
import bpy,math
from mathutils import Vector
from mathutils.bvhtree import BVHTree
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'art/source/stonewater.blend'))
checks=0
# Rays at/adjacent to every masonry boundary verify continuous shell coverage.
for name,r,spring,count,axis,offset in [('aqueduct_span_12m',6,6,24,'z',0),('cistern_vault_8m',3,3,20,'x',1.2),('monumental_portal',3,4,20,'z',0),('causeway_8m',.8,.65,10,'z',0)]:
 o=bpy.data.objects[name+'_LOD0'];tree=BVHTree.FromPolygons([v.co for v in o.data.vertices],[p.vertices for p in o.data.polygons],all_triangles=True)
 origin=Vector((offset,0,spring))
 for j in range(1,count):
  for delta in [-1e-4,0,1e-4]:
   a=j*math.pi/count+delta
   direction=Vector((math.cos(a),0,math.sin(a))) if axis=='z' else Vector((0,-math.cos(a),math.sin(a)))
   hit=tree.ray_cast(origin,direction,r+1.3)
   assert hit[0] is not None,(name,j,delta,'roof leak')
   checks+=1
print('STONEWATER_SOLID_SHELL_PASS',checks,'rays through structural mortar boundaries')
# UV edges of an axis-aligned pier face preserve metric ratios after projection.
o=bpy.data.objects['ribbed_pier_10m_LOD1'];uv=o.data.uv_layers[0];checked=0
for p in o.data.polygons:
 n=p.normal
 if max(abs(n.x),abs(n.y),abs(n.z))<.999:continue
 world=[];texture=[]
 for li in p.loop_indices:
  world.append(o.data.vertices[o.data.loops[li].vertex_index].co)
  texture.append(uv.data[li].uv)
 scales=[]
 for i in range(3):
  edge=(world[(i+1)%3]-world[i]).length;uv_edge=(texture[(i+1)%3]-texture[i]).length
  if edge>.001:scales.append(uv_edge/edge)
 assert max(scales)/min(scales)<1.001,scales
 checked+=1
print('STONEWATER_UV_ASPECT_PASS',checked,'axis-aligned pier triangles')
