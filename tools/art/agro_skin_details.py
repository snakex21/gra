"""Original low-budget neutral-pose mane, tail, facial inserts and riding tack.
All attachments are weighted to existing named bones; no simulation or new rig.
"""
import bpy,bmesh,math,random
from mathutils import Vector

def build(core,rig,reference,deforms,root):
 mats={}
 for name,color,rough,metal in [('points',(.026,.026,.025),.72,0),('eye',(.009,.007,.005),.12,0),('leather',(.17,.09,.041),.72,0),('cloth',(.24,.155,.095),.94,0),('brass',(.30,.23,.12),.42,.8)]:
  m=bpy.data.materials.new('Agro detail '+name);m.diffuse_color=(*color,1);m.use_nodes=True;p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=rough;p.inputs['Metallic'].default_value=metal;mats[name]=m
 objects=[]
 def cv(p):return (p[0],-p[2],p[1])
 def mesh(name,pts,faces,mat,weights):
  d=bpy.data.meshes.new(name);d.from_pydata([cv(p) for p in pts],[],faces);d.update();bm=bmesh.new();bm.from_mesh(d);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(d);bm.free()
  o=bpy.data.objects.new(name,d);bpy.context.collection.objects.link(o);d.materials.append(mats[mat])
  for f in d.polygons:f.use_smooth=True
  for bone in reference['global_pose']:o.vertex_groups.new(name=bone)
  ws=[weights]*len(pts) if isinstance(weights,dict) else weights
  for i,w in enumerate(ws):
   for bone,value in w.items():o.vertex_groups[bone].add([i],value,'REPLACE')
  objects.append(o);return o
 def smooth(a,b,x):
  t=max(0,min(1,(x-a)/(b-a)));return t*t*(3-2*t)
 def neck_weights(p):
  # Approximate local height in canonical neck coordinates solely for weights.
  q=deforms['neck'].inverted()@Vector(p);nw=smooth(1.33,1.81,q.y);hw=smooth(2.24,2.46,q.y)
  return {'body':1-nw,'neck':nw*(1-hw),'head':nw*hw}
 def lock(name,coords,widths,width_axis,mat,weight):
  axis=Vector(width_axis).normalized();points=[];ws=[]
  for i,(p,w) in enumerate(zip(coords,widths)):
   p=Vector(p);direction=Vector(coords[min(i+1,len(coords)-1)])-Vector(coords[max(0,i-1)])
   side=direction.cross(axis).normalized()
   for xx,yy in [(-.5,0),(-.2,.033),(.2,.033),(.5,0),(.2,-.028),(-.2,-.028)]:
    point=p+axis*w*xx+side*w*yy;points.append(point);ws.append(weight(point) if callable(weight) else weight)
  n=6;faces=[(r*n+j,r*n+(j+1)%n,(r+1)*n+(j+1)%n,(r+1)*n+j) for r in range(len(coords)-1) for j in range(n)]
  faces.extend([tuple(reversed(range(n))),tuple((len(coords)-1)*n+j for j in range(n))]);return mesh(name,points,faces,mat,ws)
 rng=random.Random(7391)
 # A connected curved curtain reads as a mane rather than armour-like leaves.
 count=30;across=5;pts=[];ws=[]
 for back in [False,True]:
  for i in range(count):
   t=i/(count-1);y=1.75+.54*t;z=-.57-.86*t
   length=.17+.085*math.sin(math.pi*t)**.6+.025*math.sin(i*2.2)
   width=.235-.13*t
   for j in range(across):
    f=j/(across-1);x=(width*math.sin(f*math.pi*.62)+.009)*(1 if not back else .975)
    x+=.0028*math.sin(i*math.pi/2)*(math.sin(math.pi*f)**.5)
    point=(x,y-length*f,z+.022*f+(.004 if back else 0));pts.append(point);ws.append(neck_weights(point))
 faces=[];layer=count*across
 for side in range(2):
  off=side*layer
  for i in range(count-1):
   for j in range(across-1):
    quad=(off+i*across+j,off+i*across+j+1,off+(i+1)*across+j+1,off+(i+1)*across+j)
    faces.append(quad if side==0 else tuple(reversed(quad)))
 for i in range(count-1):
  for j in [0,across-1]:
   a=i*across+j;b=(i+1)*across+j;faces.append((a,b,b+layer,a+layer))
 for i in [0,count-1]:
  for j in range(across-1):
   a=i*across+j;b=a+1;faces.append((a,b,b+layer,a+layer))
 mesh('Continuous laid mane curtain',pts,faces,'points',ws)
 def head(p):
  q=Vector((p[0],2.39+(p[1]-2.39)*.78,-.95+(p[2]+.95)*.78));return deforms['head']@q
 for i in range(4):
  x=(i-1.5)*.035
  lock('Tapered forelock',[head((x,2.565,-.97)),head((x*1.15,2.55,-1.075)),head((x*.65,2.48,-1.17))],[.050,.045,.002],(1,0,0),'points',{'head':1.0})
 for i in range(6):
  x=(i-2.5)*.027
  lock('Full layered tail',[(x*.4,1.42,1.07),(x,1.18,1.20+.04*math.sin(i*2.1)),(x*1.35,.84,1.26+.04*math.sin(i*2.1)),(x*1.20,.48,1.28+.035*math.sin(i*2.1)),(x*.75,.27+abs(i-2.5)*.020,1.27+.025*math.sin(i*2.1))],[.072,.082,.078,.060,.003],(1,0,.45*math.sin(i)),'points',{'body':1.0})
 def oval(name,center,radius,mat):
  bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1 if name=='Nostril recess' else 2,radius=1)
  o=bpy.context.object;pts=[]
  for ve in o.data.vertices:
   q=ve.co;pts.append(head((center[0]+q.x*radius[0],center[1]+q.y*radius[1],center[2]+q.z*radius[2])))
  faces=[tuple(p.vertices) for p in o.data.polygons];bpy.data.objects.remove(o,do_unlink=True)
  return mesh(name,pts,faces,mat,{'head':1.0})
 for sign in [-1,1]:
  oval('Inset eye', (sign*.116,2.435,-1.07),(.009,.021,.029),'eye')
  # Tiny dark inset follows a real depression in the continuous muzzle surface.
  oval('Nostril recess',(sign*.091,1.925,-1.72),(.003,.026,.038),'points')
 def strap(name,coords,width,depth,mat='leather',weight=None,axis=(0,0,1)):
  weight=weight or {'body':1.0};points=[];n=4
  closed=(Vector(coords[0])-Vector(coords[-1])).length<1e-6
  if closed:coords=coords[:-1]
  axis=Vector(axis)
  for i,p in enumerate(coords):
   p=Vector(p);direction=(Vector(coords[min(i+1,len(coords)-1)])-Vector(coords[max(0,i-1)])).normalized()
   side=direction.cross(axis).normalized()
   for a,b in [(-.5,-.5),(.5,-.5),(.5,.5),(-.5,.5)]:points.append(p+side*a*width+axis*b*depth)
  faces=[(r*n+j,r*n+(j+1)%n,((r+1)%len(coords))*n+(j+1)%n,((r+1)%len(coords))*n+j) for r in range(len(coords) if closed else len(coords)-1) for j in range(n)]
  if not closed:faces.extend([tuple(reversed(range(n))),tuple((len(coords)-1)*n+j for j in range(n))])
  return mesh(name,points,faces,mat,[weight(p) for p in points] if callable(weight) else weight)
 # Solid drape only 76 triangles, fitted to the actual thoracic back.
 pts=[]
 profile=[(-.395,1.25),(-.385,1.51),(-.265,1.64),(0,1.685),(.265,1.64),(.385,1.51),(.395,1.25)]
 for z in [-.40,-.29,.22,.34]:
  for x,y in profile:pts.append((x,y,z))
 faces=[(r*7+j,r*7+j+1,(r+1)*7+j+1,(r+1)*7+j) for r in range(3) for j in range(6)]
 blanket=mesh('Fitted woven saddle cloth',pts,faces,'cloth',{'body':1.0});bpy.context.view_layer.objects.active=blanket
 solid=blanket.modifiers.new('Real cloth thickness','SOLIDIFY');solid.thickness=.012;bpy.ops.object.modifier_apply(modifier=solid.name)
 # Curved shallow saddle seat, no handle-like arches or dangling round tubes.
 pts=[];n=12;rows=[(-.27,.195,1.704,.019),(-.16,.225,1.695,.023),(.03,.224,1.697,.025),(.20,.195,1.74,.029)]
 for z,w,y,h in rows:
  for j in range(n):a=j*math.tau/n;pts.append((math.cos(a)*w,y+math.sin(a)*h,z))
 faces=[(r*n+j,r*n+(j+1)%n,(r+1)*n+(j+1)%n,(r+1)*n+j) for r in range(3) for j in range(n)]
 faces.extend([tuple(reversed(range(n))),tuple(3*n+j for j in range(n))]);mesh('Contoured saddle tree seat',pts,faces,'leather',{'body':1.0})
 for z,height in [(-.26,1.755),(.205,1.795)]:strap('Saddle pommel or cantle',[(-.21,1.69,z),(-.15,height-.012,z),(0,height,z),(.15,height-.012,z),(.21,1.69,z)],.033,.018)
 strap('Flat girth',[(-.29,1.55,-.025),(-.379,1.33,-.025),(-.34,1.04,-.025),(0,.88,-.025),(.34,1.04,-.025),(.379,1.33,-.025),(.29,1.55,-.025)],.008,.065)
 for sign in [-1,1]:
  flap=mesh('Tapered saddle side flap',[(sign*.215,1.708,-.23),(sign*.380,1.55,-.245),(sign*.416,1.35,-.19),(sign*.418,1.27,.08),(sign*.407,1.47,.16),(sign*.215,1.70,.15)],[(0,1,2,3,4,5)],'leather',{'body':1.0})
  bpy.context.view_layer.objects.active=flap;sol=flap.modifiers.new('Leather thickness','SOLIDIFY');sol.thickness=.008;bpy.ops.object.modifier_apply(modifier=sol.name)
  strap('Stirrup leather',[(sign*.410,1.555,-.140),(sign*.423,1.49,-.140),(sign*.435,1.43,-.140)],.026,.008,axis=(1,0,0))
  coords=[(sign*.435+x,y,-.140) for x,y in [(-.060,1.286),(-.054,1.385),(0,1.43),(.054,1.385),(.060,1.286),(-.060,1.286)]]
  strap('Stirrup iron',coords,.009,.009,'brass')
  # Full reins are a separate cosmetic runtime strap: their free ends settle
  # on the saddle without a rider and follow the actual free hand when mounted.
  strap('Flat bridle cheek strap',[head((sign*.13,2.53,-.98)),head((sign*.172,2.37,-1.10)),head((sign*.122,2.03,-1.48)),head((sign*.11,1.92,-1.61))],.014,.006,'leather',{'head':1.0},axis=(1,0,0))
  ring=[head((sign*.120,1.945+.027*math.cos(j*math.tau/10),-1.61+.027*math.sin(j*math.tau/10))) for j in range(11)]
  strap('Bridle bit ring',ring,.006,.006,'brass',{'head':1.0},axis=(1,0,0))
 # Nasal band follows the shorter sloped face, not the old mesh's oversized muzzle.
 coords=[head((.115*math.cos(j*math.tau/12),2.04+.091*math.sin(j*math.tau/12),-1.54)) for j in range(13)]
 strap('Noseband',coords,.018,.005,'leather',{'head':1.0},axis=(0,0,1))
 bpy.ops.object.select_all(action='DESELECT');core.select_set(True)
 for o in objects:o.select_set(True)
 bpy.context.view_layer.objects.active=core;bpy.ops.object.join()
 return {'detail_objects':len(objects),'materials':list(mats),'design':'Solid laid hair clumps, shallow anatomical tack, head-rigid recessed facial inserts'}
