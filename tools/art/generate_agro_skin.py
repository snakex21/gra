"""Continuous Agro visual source. Existing Horse.BONES contract, no mechanics.
Authored in a fixed recorded native neutral pose (Godot Y-up), with explicit inverse binds.
Run: blender --background --python tools/art/generate_agro_skin.py -- --regenerate
"""
import bpy, bmesh, math, json, sys
from pathlib import Path
from mathutils import Vector, Matrix, kdtree
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
if (ROOT/'art/source/agro_skin_v4.blend').exists() and '--regenerate' not in sys.argv:
 raise SystemExit('Editable source exists; pass -- --regenerate explicitly to replace generated output.')
bpy.ops.wm.read_factory_settings(use_empty=True)
def v(p):return Vector((p[0],-p[2],p[1]))
mat=bpy.data.materials.new('Agro neutral anatomical clay');mat.diffuse_color=(.30,.29,.265,1);mat.use_nodes=True
p=mat.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(.30,.29,.265,1);p.inputs['Roughness'].default_value=.80
parts=[]
def mesh(name,pts,faces):
 d=bpy.data.meshes.new(name);d.from_pydata([v(x) for x in pts],[],faces);d.update()
 bm=bmesh.new();bm.from_mesh(d);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(d);bm.free()
 o=bpy.data.objects.new(name,d);bpy.context.collection.objects.link(o);parts.append(o)
 for f in d.polygons:f.use_smooth=True
 return o

def loft_z(name,rows,n=32):
 pts=[]
 for z,w,top,bottom in rows:
  for j in range(n):
   a=j*math.tau/n;c,s=math.cos(a),math.sin(a)
   mid=(top+bottom)/2;ry=(top-bottom)/2
   # Broad ribcage sides and a narrower dorsal ridge; continuous asymmetric section.
   width=w*(1-.13*max(0,s)**2)
   pts.append((width*c,mid+ry*s,z))
 faces=[(r*n+j,r*n+(j+1)%n,(r+1)*n+(j+1)%n,(r+1)*n+j) for r in range(len(rows)-1) for j in range(n)]
 faces.extend([tuple(reversed(range(n))),tuple((len(rows)-1)*n+j for j in range(n))])
 return mesh(name,pts,faces)

def loft_y(name,rows,n=24):
 pts=[]
 for y,w,d,cx,cz in rows:
  for j in range(n):
   a=j*math.tau/n;pts.append((cx+w*math.cos(a),y,cz+d*math.sin(a)))
 faces=[(r*n+j,r*n+(j+1)%n,(r+1)*n+(j+1)%n,(r+1)*n+j) for r in range(len(rows)-1) for j in range(n)]
 faces.extend([tuple(reversed(range(n))),tuple((len(rows)-1)*n+j for j in range(n))])
 return mesh(name,pts,faces)

body=loft_z('Continuous ribcage withers and croup',[
 (-1.13,.045,1.43,1.19),(-1.02,.20,1.59,1.02),(-.85,.295,1.73,.925),(-.60,.325,1.78,.895),
 (-.30,.355,1.66,.86),(0,.35,1.64,.91),(.30,.32,1.65,1.04),(.62,.39,1.73,.95),
 (.86,.35,1.66,.99),(1.03,.23,1.56,1.14),(1.12,.035,1.37,1.29)])
def neutral_neck():
 rows=[(1.24,-.73,.11,.13,.15),(1.45,-.80,.235,.28,.38),
       (1.68,-1.04,.190,.22,.29),(1.93,-1.29,.132,.14,.19),
       (2.12,-1.47,.102,.105,.14),(2.23,-1.51,.075,.09,.10)]
 n=28;pts=[]
 for y,z,width,throat,crest in rows:
  for j in range(n):
   a=j*math.tau/n;sn=math.sin(a);radius=crest if sn>0 else throat
   pts.append((width*math.cos(a),y+sn*radius*.69,z+sn*radius*.72))
 faces=[(r*n+j,r*n+(j+1)%n,(r+1)*n+(j+1)%n,(r+1)*n+j) for r in range(len(rows)-1) for j in range(n)]
 faces.extend([tuple(reversed(range(n))),tuple((len(rows)-1)*n+j for j in range(n))])
 obj=mesh('Anatomical neutral neck crest throat and shoulder flow',pts,faces);obj['preposed']=True
neutral_neck()
# Integrated cheek/jaw, thinner bridge, widening nostril/muzzle zone.
head_core=loft_z('Single equine skull jaw bridge and muzzle',[
 (-.85,.055,2.57,2.33),(-.94,.142,2.58,2.12),(-1.10,.168,2.56,2.06),(-1.23,.146,2.44,2.055),
 (-1.38,.118,2.31,1.99),(-1.51,.109,2.16,1.89),(-1.62,.111,2.015,1.815),
 (-1.70,.115,1.99,1.775),(-1.77,.100,1.965,1.785),(-1.81,.080,1.94,1.805)],32)
for vert in head_core.data.vertices:
 vert.co.z=2.39+(vert.co.z-2.39)*.78
 vert.co.y=.95+(vert.co.y-.95)*.78
for s in [-1,1]:
 loft_y('Tapered leaf ear',[(2.45,.055,.060,s*.105,-.98),(2.53,.045,.043,s*.124,-.96),(2.65,.022,.022,s*.133,-.935),(2.70,.003,.005,s*.127,-.925)],16)
 # Fore shoulder expands into thorax; hind thigh into croup. One continuous shell.
 for rear,z in [(False,-.78),(True,.78)]:
  x=s*.24
  loft_y(('Hind' if rear else 'Fore')+' limb continuous muscle to cannon',[
   (1.46,.12 if rear else .140,.18 if rear else .190,x*.8 if rear else x,z+.015 if rear else z+.035),
   (1.18,.140 if rear else .110,.200 if rear else .150,x,z+.025),
   (1.00,.137 if rear else .088,.177 if rear else .120,x,z+.015),
   (.81,.086 if rear else .070,.115 if rear else .088,x,z+.012),
   (.65,.066,.083,x,z),(.55,.065,.079,x,z),(.44,.052,.067,x,z+.007),
   (.28,.043,.052,x,z+.013),(.10,.045,.052,x,z),(-.015,.063,.075,x,z),(-.060,.064,.083,x,z)
  ],20)
# Sculpt/weld in the actual neutral standing pose. Bind to the recorded fixed
# native neutral transforms directly; NEVER invert blended skinning matrices.
# The target Horse skeleton and its animation/IK remain completely unchanged.
def smooth(a,b,x):
 t=max(0,min(1,(x-a)/(b-a)));return t*t*(3-2*t)
reference=json.loads((ROOT/'assets/agro_skin_neutral_reference.json').read_text())
deforms={}
for name,rows in reference['deforms'].items():
 M=Matrix.Identity(4)
 for col in range(4):
  for row in range(3):M[row][col]=rows[col][row]
 deforms[name]=M

def source_weights(name,pos):
 x,y,z=pos
 if 'skull' in name or 'ear' in name:return {'head':1.0}
 if 'ribcage' in name:return {'body':1.0}
 if 'neck' in name:
  nw=smooth(1.33,1.81,y);hw=smooth(2.24,2.46,y)
  return {'body':1-nw,'neck':nw*(1-hw),'head':nw*hw}
 side=('f' if z<0 else 'r')+('l' if x<0 else 'r')
 limb=1-smooth(1.00,1.41,y);low=1-smooth(.44,.69,y);hoof=1-smooth(-.035,.045,y)
 return {'body':1-limb,side+'_up':limb*(1-low),side+'_low':limb*low*(1-hoof),side+'_hoof':limb*low*hoof}

samples=[]
for obj in parts:
 bpy.context.view_layer.objects.active=obj
 sub=obj.modifiers.new('Fair anatomical profile curves','SUBSURF');sub.levels=2;bpy.ops.object.modifier_apply(modifier=sub.name)
 for vert in obj.data.vertices:
  pos=Vector((vert.co.x,vert.co.z,-vert.co.y))
  if 'skull' in obj.name:
   yy=2.39+(pos.y-2.39)/.78;zz=-.95+(pos.z+.95)/.78
   socket=.024*math.exp(-((yy-2.435)/.044)**2-((zz+1.07)/.056)**2)
   nostril=.028*math.exp(-((yy-1.91)/.041)**2-((zz+1.72)/.055)**2)
   jaw_plane=.010*math.exp(-((yy-2.22)/.12)**2-((zz+1.06)/.12)**2)
   pos.x-=math.copysign((socket+nostril+jaw_plane)*smooth(.06,.12,abs(pos.x)),pos.x)
  sample_position=deforms['neck'].inverted()@pos if obj.get('preposed') else pos
  w=source_weights(obj.name,sample_position)
  target=pos if obj.get('preposed') else sum(((deforms[k]@pos)*a for k,a in w.items()),Vector((0,0,0)))
  vert.co=v(target);samples.append((target,w))
# Actual union in neutral posture, rather than disconnected overlap at runtime.
bpy.ops.object.select_all(action='DESELECT')
for o in parts:o.select_set(True)
bpy.context.view_layer.objects.active=body;bpy.ops.object.join();core=bpy.context.object;core.name='Agro continuous skin greybox'
rem=core.modifiers.new('Weld anatomical neutral junctions','REMESH');rem.mode='VOXEL';rem.voxel_size=.016;rem.use_smooth_shade=True;bpy.ops.object.modifier_apply(modifier=rem.name)
sm=core.modifiers.new('Relax welded junctions','SMOOTH');sm.factor=.45;sm.iterations=4;bpy.ops.object.modifier_apply(modifier=sm.name)
# Low-amplitude integrated scapular and gluteal planes, never attached spheres.
for vert in core.data.vertices:
 x,y,z=vert.co.x,vert.co.z,-vert.co.y
 side=smooth(.18,.32,abs(x))
 ridge_z=-.50-.55*(1.65-y)
 shoulder=.033*math.exp(-((z-ridge_z)/.10)**2-((y-1.35)/.29)**2)
 haunch=.025*math.exp(-((z-.75)/.25)**2-((y-1.28)/.25)**2)
 vert.co.x+=math.copysign(side*(shoulder+haunch),x)
core.data.calc_loop_triangles();dec=core.modifiers.new('Anatomical core budget','DECIMATE');dec.ratio=min(1,6480/len(core.data.loop_triangles));bpy.ops.object.modifier_apply(modifier=dec.name)
bm=bmesh.new();bm.from_mesh(core.data)
boundary=[e for e in bm.edges if e.is_boundary]
if boundary:bmesh.ops.holes_fill(bm,edges=boundary,sides=6)
bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(core.data);bm.free()
tri=core.modifiers.new('Explicit triangles','TRIANGULATE');bpy.ops.object.modifier_apply(modifier=tri.name)
# Triangulation can dissolve microscopic junction caps; close and verify them.
bm=bmesh.new();bm.from_mesh(core.data)
boundary=[e for e in bm.edges if e.is_boundary]
if boundary:bmesh.ops.holes_fill(bm,edges=boundary,sides=6)
bmesh.ops.triangulate(bm,faces=list(bm.faces));bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
# Voxel/decimation can leave microscopic two-sided detached triangle islands.
# Discard only tiny detached remnants; a disconnected anatomical part is an error.
remaining=set(bm.verts);components=[]
while remaining:
 seed=remaining.pop();group={seed};todo=[seed]
 while todo:
  vert=todo.pop()
  for edge in vert.link_edges:
   other=edge.other_vert(vert)
   if other in remaining:remaining.remove(other);group.add(other);todo.append(other)
 components.append(group)
components.sort(key=len,reverse=True)
for group in components[1:]:
 assert len(group)<=6, 'Disconnected anatomical component'
 bmesh.ops.delete(bm,geom=list(group),context='VERTS')
# Reject spurious tiny fins at tangent voxel intersections (e.g. ear base).
fins=[f for f in bm.faces if sum(e.is_boundary for e in f.edges)>=2 and any(len(e.link_faces)>2 for e in f.edges) and f.calc_area()<.0002]
if fins:bmesh.ops.delete(bm,geom=fins,context='FACES_ONLY')
wire=[e for e in bm.edges if not e.link_faces]
if wire:bmesh.ops.delete(bm,geom=wire,context='EDGES')
assert all(e.is_manifold for e in bm.edges), 'Core must stay closed after reduction'
bm.to_mesh(core.data);bm.free()
core.data.materials.clear();core.data.materials.append(mat)
for f in core.data.polygons:f.use_smooth=True
# Dense component-aware nearest-surface transfer, then topology-local smoothing.
kd=kdtree.KDTree(len(samples))
for i,(point,w) in enumerate(samples):kd.insert(point,i)
kd.balance();weights=[]
for vert in core.data.vertices:
 point=Vector((vert.co.x,vert.co.z,-vert.co.y));acc={}
 for _,index,distance in kd.find_n(point,4):
  for name,value in samples[index][1].items():acc[name]=acc.get(name,0)+value/max(distance,.002)**2
 total=sum(acc.values());weights.append({k:a/total for k,a in acc.items() if a>0})
adj=[set() for _ in core.data.vertices]
for edge in core.data.edges:
 a,b=edge.vertices;adj[a].add(b);adj[b].add(a)
for iteration in range(4):
 updated=[]
 for i,w in enumerate(weights):
  acc={k:value*.55 for k,value in w.items()}
  for j in adj[i]:
   for k,value in weights[j].items():acc[k]=acc.get(k,0)+value*.45/max(1,len(adj[i]))
  x=core.data.vertices[i].co.x
  acc={k:a for k,a in acc.items() if a>1e-5 and (not '_' in k or k[1]==('l' if x<0 else 'r'))}
  acc=dict(sorted(acc.items(),key=lambda kv:-kv[1])[:4]);total=sum(acc.values())
  updated.append({k:a/total for k,a in acc.items()})
 weights=updated
# The saddle-bearing thoracic back is deliberately rigid to the body bone.
for i,vert in enumerate(core.data.vertices):
 x,y,z=vert.co.x,vert.co.z,-vert.co.y
 if abs(x)<.28 and y>1.48 and -.43<z<.38:weights[i]={'body':1.0}
# Rest-bone data is precisely the public Horse contract, never a hand-set runtime pose.
rest={'body':(0,1.27,0),'neck':(0,1.49,-.95),'head':(0,2.39,-.95)}
parents={'body':None,'neck':'body','head':'neck'}
for side,x,z in [('fl',-.24,-.78),('fr',.24,-.78),('rl',-.24,.78),('rr',.24,.78)]:
 for suffix,y in [('up',1.17),('low',.55),('hoof',-.03)]:rest[side+'_'+suffix]=(x,y,z)
 parents[side+'_up']='body';parents[side+'_low']=side+'_up';parents[side+'_hoof']=side+'_low'
# Blender bone matrix columns must convert Godot identity basis; use +Z bones
# (Godot +Y) and roll 0, then glTF binds carry Blender's bone basis conversion.
arm=bpy.data.armatures.new('Existing Horse canonical rest');rig=bpy.data.objects.new('HorseRigContract',arm);bpy.context.collection.objects.link(rig)
bpy.context.view_layer.objects.active=rig;bpy.ops.object.mode_set(mode='EDIT')
for name,loc in rest.items():
 b=arm.edit_bones.new(name);b.head=(0,0,0);b.tail=(0,.1,0)
 G=Matrix.Identity(4)
 for col in range(4):
  for row in range(3):G[row][col]=reference['global_pose'][name][col][row]
 C=Matrix(((1,0,0,0),(0,0,-1,0),(0,1,0,0),(0,0,0,1)))
 b.matrix=C@G;b.length=.1
 if parents[name]:b.parent=arm.edit_bones[parents[name]]
bpy.ops.object.mode_set(mode='OBJECT')
for name in rest:core.vertex_groups.new(name=name)
for vert,w in zip(core.data.vertices,weights):
 for name,value in w.items():core.vertex_groups[name].add([vert.index],value,'REPLACE')
mod=core.modifiers.new('Existing Horse skeleton deformation','ARMATURE');mod.object=rig;core.parent=rig
# Core coat, dark lower legs and muzzle remain separate regions of one closed skin.
for name in ['Agro core black points','Agro detail muzzle','Agro core cream star']:
 m=bpy.data.materials.new(name);m.diffuse_color=(.3,.29,.265,1);m.use_nodes=True
 core.data.materials.append(m)
G=Matrix.Identity(4)
for col in range(4):
 for row in range(3):G[row][col]=reference['global_pose']['head'][col][row]
for face in core.data.polygons:
 center=sum((core.data.vertices[i].co for i in face.vertices),Vector((0,0,0)))/len(face.vertices)
 point=Vector((center.x,center.z,-center.y));head_local=G.inverted()@point
 canonical_head=Vector((head_local.x,2.39+head_local.y/.78,-.95+head_local.z/.78))
 if point.y<.53 or canonical_head.y>2.50 and abs(canonical_head.x)>.065:face.material_index=1
 elif canonical_head.z< -1.56 and canonical_head.y<2.22 and point.z< -1.6:face.material_index=2
 elif (canonical_head.x/.035)**2+((canonical_head.y-2.505)/.065)**2+((canonical_head.z+1.08)/.10)**2<1.0:face.material_index=3
sys.path.insert(0,str(Path(__file__).parent))
from agro_skin_details import build as build_details
details=build_details(core,rig,reference,deforms,ROOT)
bm=bmesh.new();bm.from_mesh(core.data);bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.to_mesh(core.data);bm.free()
# UVs are authoring-only greybox; final texture pass follows anatomy approval.
bpy.context.view_layer.objects.active=core;rig.select_set(False);core.select_set(True)
# Explicit planar fur/tack UVs do not need edit-mode topology changes.
uv=core.data.uv_layers.new(name='Agro surface UV')
for face in core.data.polygons:
 normal=face.normal
 for loop_index in face.loop_indices:
  point=core.data.vertices[core.data.loops[loop_index].vertex_index].co
  x,y,z=point.x,point.z,-point.y
  name=core.data.materials[face.material_index].name
  scale=12.0 if name in ['Agro neutral anatomical clay','Agro core black points','Agro detail cloth'] else 6.0
  if abs(normal.x)>=max(abs(normal.y),abs(normal.z)):coord=(z*scale,y*scale)
  elif abs(normal.z)>abs(normal.y):coord=(z*scale,x*scale)
  else:coord=(x*scale,y*scale)
  uv.data[loop_index].uv=coord
(ROOT/'models/agro_skin').mkdir(exist_ok=True,parents=True)
assert not core.data.validate(verbose=False,clean_customdata=False), 'Exporter must not repair authored geometry'
# Three explicitly budgeted handoff LODs, all on the same named fixed binds.
variants=[];counts=[];bounds=[]
for lod,ratio in enumerate([1.0,.458,.175]):
 obj=core
 if lod:
  obj=core.copy();obj.data=core.data.copy();bpy.context.collection.objects.link(obj)
  bpy.context.view_layer.objects.active=obj
  dec=obj.modifiers.new('Visual LOD reduction','DECIMATE');dec.ratio=ratio
  while list(obj.modifiers).index(dec)>0:bpy.ops.object.modifier_move_up(modifier=dec.name)
  bpy.ops.object.modifier_apply(modifier=dec.name)
  # Reduction may collapse tiny detail triangles; validate the reduced mesh once.
  obj.data.validate(verbose=False,clean_customdata=False)
 obj.name=f'Agro continuous visual LOD{lod}'
 assert not obj.data.validate(verbose=False,clean_customdata=False), 'LOD must export without repair'
 obj.data.calc_loop_triangles();counts.append(len(obj.data.loop_triangles))
 coords=[(v.co.x,v.co.z,-v.co.y) for v in obj.data.vertices]
 bounds.append({'min':[min(p[k] for p in coords) for k in range(3)],'max':[max(p[k] for p in coords) for k in range(3)]})
 bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);rig.select_set(True)
 bpy.ops.export_scene.gltf(filepath=str(ROOT/f'models/agro_skin/agro_lod{lod}.glb'),export_format='GLB',use_selection=True,export_yup=True,export_animations=False,export_skins=True,export_materials='EXPORT',export_tangents=True)
 obj.hide_set(lod>0);obj.hide_render=lod>0;variants.append(obj)
legacy=json.loads((ROOT/'assets/agro_dormin_v3_manifest.json').read_text())
hoofs=[sum(item['triangle_counts'][lod] for item in legacy['items'] if item['actor']=='agro' and item['bone'].endswith('hoof')) for lod in range(3)]
totals=[counts[i]+hoofs[i] for i in range(3)]
assert all(a<=b for a,b in zip(totals,[9482,4347,1676])), ('Total LOD budget',totals)
# Pack the established palette for an editable source preview; runtime shares the
# originals through AgroArt, so the GLBs themselves add no duplicate texture set.
palette={
 'Agro neutral anatomical clay':('agro_dark_bay',.78,.5),
 'Agro core black points':('agro_black_points',.72,.5),
 'Agro detail points':('agro_black_points',.86,.22),
 'Agro detail muzzle':('agro_soft_muzzle',.70,.5),
 'Agro detail leather':('agro_worn_leather',.72,.5),
 'Agro detail cloth':('agro_woven_blanket',.94,.5),
}
for material_name,(legacy_name,roughness,specular) in palette.items():
 material=bpy.data.materials[material_name];shader=material.node_tree.nodes.get('Principled BSDF')
 shader.inputs['Roughness'].default_value=roughness;shader.inputs['Specular IOR Level'].default_value=specular
 prefix='head_lod0_' if legacy_name=='agro_soft_muzzle' else 'body_lod0_'
 for channel in ['albedo','normal']:
  path=ROOT/'models/agro_v3'/f'{prefix}{legacy_name}_{channel}.png'
  if not path.exists():raise RuntimeError('Missing established palette source: '+str(path))
  image=bpy.data.images.load(str(path),check_existing=True)
  if channel=='normal':image.colorspace_settings.name='Non-Color'
  image.pack();image.filepath='//../../models/agro_v3/'+path.name
  texture=material.node_tree.nodes.new('ShaderNodeTexImage');texture.image=image
  if channel=='albedo':material.node_tree.links.new(texture.outputs['Color'],shader.inputs['Base Color'])
  else:
   normal=material.node_tree.nodes.new('ShaderNodeNormalMap');material.node_tree.links.new(texture.outputs['Color'],normal.inputs['Color']);material.node_tree.links.new(normal.outputs['Normal'],shader.inputs['Normal'])
scene=bpy.context.scene;scene['scope']='Agro continuous skin on original bones and fixed binds; standing carriage revised separately in Horse._pose; dynamic reins provided by AgroReins'
scene['bind_contract']='Fixed native neutral pose. Imported runtime palette is reused read-only; no new texture files.'
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/source/agro_skin_v4.blend'),compress=True)
report={'version':4,'render_only':True,'source':'res://art/source/agro_skin_v4.blend','generator':'tools/art/generate_agro_skin.py','details':details,'triangles':counts[0],'skin_triangle_counts':counts,'unchanged_hoof_triangle_counts':hoofs,'total_triangle_counts':totals,'runtime_reins_triangle_count':32,'complete_runtime_triangle_counts':[n+32 for n in totals],'baseline_total_triangle_counts':[9482,4347,1676],'lod_ratios':[1,.458,.175],'bounds':bounds,'rest':rest,'parents':parents,'max_influences':max(map(len,weights)),'weight_contract':'Fixed recorded native neutral bind pose; separately revised runtime idle carriage does not alter bind matrices','neutral_reference':'assets/agro_skin_neutral_reference.json','runtime_materials':'Shared existing Agro body/head material resources. Only mane/tail gets a shallow matte clone; texture refs unchanged.','new_texture_files':0,'limitations':['No live GPU or FPS validation','Prescribed production gait snapshots are not live controller movement','Existing two-bone leg pose and linear-skinning volume limitations remain','Opaque low-poly hair; no secondary mane/tail physics']}
(ROOT/'assets/agro_skin_manifest.json').write_text(json.dumps(report,indent=2)+'\n')
print('AGRO_SKIN_V4_OK',json.dumps(report))
