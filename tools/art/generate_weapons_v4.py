"""Original crafted weapons, portable Blender source, three LOD and a bow morph.

Run: python tools/run_local.py blender --python tools/art/generate_weapons_v4.py
Rebuilding an existing source requires an explicit trailing -- --regenerate.
All geometry uses metres and the manifest's Godot attachment frames. Nothing
adds collision or gameplay. Source parts remain independently editable.
"""
import bpy
import bmesh
import json
import math
import random
import struct
import sys
from pathlib import Path
from mathutils import Vector
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art/source/weapons_v4.blend"
if SOURCE.exists() and "--regenerate" not in sys.argv:
    raise SystemExit("Source exists; pass -- --regenerate to rebuild explicitly.")
for folder in ["models/weapons_v4", "textures/weapons_v4", "art/source", "assets", "art/screenshots/weapons_v4"]:
    (ROOT/folder).mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1
rng = random.Random(408127)

def v(p):
    return Vector((p[0], -p[2], p[1]))

def gp(p):
    return (p.x, p.z, -p.y)

def mesh(name, pts, faces, mat, smooth=False, uv="project"):
    data = bpy.data.meshes.new(name)
    data.from_pydata([v(p) for p in pts], [], faces)
    data.update()
    bm=bmesh.new();bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(data);bm.free()
    ob=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(ob)
    data.materials.append(mat)
    for poly in data.polygons:
        poly.use_smooth=smooth
    if uv != "project":
        layer=data.uv_layers.new(name="CraftUV")
        for poly in data.polygons:
            for index in poly.loop_indices:
                point=pts[data.loops[index].vertex_index]
                if uv=="blade":
                    value=(point[0]/.065+.5,point[1]/1.1)
                elif uv=="wood":
                    value=(point[0]/.08+.5,point[1]/1.46+.5)
                elif uv=="shaft":
                    value=(math.atan2(point[1],point[0])/math.tau+.5,-point[2]/.8)
                else:
                    value=(point[0]/.24+.5,point[1]/.7+.5)
                layer.data[index].uv=value
    return ob

def image_pixels(name, rgba, data=False):
    size=rgba.shape[0]
    im=bpy.data.images.new(name,width=size,height=size)
    if data:im.colorspace_settings.name="Non-Color"
    im.pixels.foreach_set(rgba.astype(np.float32).ravel())
    im.filepath_raw=str(ROOT/"textures/weapons_v4"/(name+".png"))
    im.file_format="PNG";im.save();im.pack()
    return im

def material(name, color, rough, metallic=0, pattern=None):
    m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
    p=m.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value=(*color,1)
    p.inputs["Metallic"].default_value=metallic
    p.inputs["Roughness"].default_value=rough
    if not pattern:return m
    size=512;y,x=np.mgrid[0:size,0:size]
    noise=np.random.default_rng(sum(map(ord,name))).random((size,size))
    if pattern=="wood":
        grain=np.sin(x*.14+np.sin(y*.023)*2.1+np.sin(y*.009)*5)
        fine=np.sin(x*.81+np.sin(y*.018)*3)
        shade=.80+.11*grain+.036*fine+.045*noise
        height=.08*grain+.025*fine+.020*noise
    elif pattern=="steel":
        shade=.92+.030*np.sin(x*.37+np.sin(y*.024))+.025*noise
        # Satin longitudinal tooling marks, not an exaggerated scratched paint.
        height=.015*np.sin(x*.73)+.012*noise
    elif pattern=="leather":
        shade=.84+.11*noise+.025*np.sin(x*.053)*np.sin(y*.07)
        height=.08*noise
    else:
        shade=.88+.055*np.sin(x*.034+y*.042)+.055*noise
        height=.035*noise
    rgba=np.ones((size,size,4),dtype=np.float32)
    for c in range(3):
        linear=np.clip(color[c]*shade,0,1)
        rgba[:,:,c]=np.where(linear<=.0031308,linear*12.92,1.055*linear**(1/2.4)-.055)
    albedo=image_pixels(name+"_albedo",rgba)
    node=m.node_tree.nodes.new("ShaderNodeTexImage");node.image=albedo
    m.node_tree.links.new(node.outputs["Color"],p.inputs["Base Color"])
    dy,dx=np.gradient(height)
    normal=np.stack((-dx*.8,-dy*.8,np.ones_like(height)),axis=-1)
    normal/=np.linalg.norm(normal,axis=-1)[:,:,None]
    normal_rgba=np.ones_like(rgba);normal_rgba[:,:,:3]=normal*.5+.5
    ni=image_pixels(name+"_normal",normal_rgba,True)
    nt=m.node_tree.nodes.new("ShaderNodeTexImage");nt.image=ni
    nn=m.node_tree.nodes.new("ShaderNodeNormalMap")
    m.node_tree.links.new(nt.outputs["Color"],nn.inputs["Color"])
    m.node_tree.links.new(nn.outputs["Normal"],p.inputs["Normal"])
    rough_rgba=np.ones_like(rgba)
    r=np.clip(rough+(1-shade)*.16,0,1)
    rough_rgba[:,:,:3]=r[:,:,None]
    ri=image_pixels(name+"_roughness",rough_rgba,True)
    rt=m.node_tree.nodes.new("ShaderNodeTexImage");rt.image=ri
    m.node_tree.links.new(rt.outputs["Color"],p.inputs["Roughness"])
    return m

steel=material("V4_satin_forged_steel",(.48,.55,.57),.25,.94,"steel")
edge=material("V4_honed_steel_edges",(.66,.73,.74),.17,.97)
groove=material("V4_recessed_steel_fuller",(.27,.33,.34),.34,.88)
bronze=material("V4_worn_bronze",(.31,.20,.085),.34,.79,"bronze")
leather=material("V4_oxblood_grip_leather",(.055,.021,.014),.75,0,"leather")
case_leather=material("V4_oiled_scabbard_leather",(.033,.040,.033),.81,0,"leather")
wood=material("V4_walnut_limb_grain",(.23,.094,.033),.48,0,"wood")
laminate=material("V4_pale_heartwood_laminate",(.43,.30,.15),.55,0,"wood")
horn=material("V4_dark_horn_tip",(.017,.021,.024),.36)
thread=material("V4_waxed_linen_stitch",(.31,.24,.15),.88)
feather=material("V4_feather_parchment",(.52,.49,.36),.87)
feather_dark=material("V4_feather_ink_edge",(.05,.061,.049),.85)
dark=material("V4_engraved_recess",(.014,.021,.023),.72,.25)

parts={name:[] for name in ["sword","bow","arrow","scabbard","quiver"]}
def add(item,*objects):parts[item].extend(objects)

def tube(name, points, radii, mat, sides=10, smooth=True):
    points=list(map(Vector,points));verts=[]
    for i,p in enumerate(points):
        d=(points[min(i+1,len(points)-1)]-points[max(i-1,0)]).normalized()
        reference=Vector((0,1,0)) if abs(d.y)<.9 else Vector((1,0,0))
        a=d.cross(reference).normalized();b=d.cross(a).normalized()
        for k in range(sides):verts.append(p+radii[i]*(a*math.cos(k*math.tau/sides)+b*math.sin(k*math.tau/sides)))
    faces=[]
    for j in range(len(points)-1):
        for k in range(sides):faces.append((j*sides+k,j*sides+(k+1)%sides,(j+1)*sides+(k+1)%sides,(j+1)*sides+k))
    faces += [tuple(reversed(range(sides))),tuple((len(points)-1)*sides+k for k in range(sides))]
    return mesh(name,verts,faces,mat,smooth)

def ring(name,center,a,b,radius,mat,count=40):
    center,a,b=Vector(center),Vector(a),Vector(b)
    points=[center+a*math.cos(i*math.tau/count)+b*math.sin(i*math.tau/count) for i in range(count+1)]
    return tube(name,points,[radius]*(count+1),mat,8)

def loft_y(name,rows,mat,count=32,power=2.8,smooth=True):
    verts=[]
    for y,rx,rz,cx,cz in rows:
        for j in range(count):
            a,b=math.cos(j*math.tau/count),math.sin(j*math.tau/count)
            verts.append((cx+rx*math.copysign(abs(a)**(2/power),a),y,cz+rz*math.copysign(abs(b)**(2/power),b)))
    faces=[]
    for i in range(len(rows)-1):
        for j in range(count):faces.append((i*count+j,i*count+(j+1)%count,(i+1)*count+(j+1)%count,(i+1)*count+j))
    faces += [tuple(reversed(range(count))),tuple((len(rows)-1)*count+j for j in range(count))]
    return mesh(name,verts,faces,mat,smooth)

def ribbon_wrap(name,y0,y1,rx,rz,turns,width,mat):
    verts=[];steps=turns*48
    for j in range(steps+1):
        t=j/steps;a=t*math.tau*turns
        for delta in [-width*.5,width*.5]:
            verts.append((math.cos(a)*rx,y0+(y1-y0)*t+delta,math.sin(a)*rz))
    faces=[(i*2,i*2+1,i*2+3,i*2+2) for i in range(steps)]
    ob=mesh(name,verts,faces,mat,True)
    bpy.context.view_layer.objects.active=ob
    mod=ob.modifiers.new("Real leather ribbon thickness","SOLIDIFY");mod.thickness=.0008;mod.offset=0
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return ob

def rosette(name,center,rx,ry,mat):
    cx,cy,cz=center
    points=[]
    for i in range(17):
        a=i*math.tau/16;r=1 if i%2==0 else .58
        points.append((cx+rx*r*math.cos(a),cy+ry*r*math.sin(a),cz))
    return tube(name,points,[.0009]*17,mat,6)

# A real blade cross-section: central recessed fuller, thick flats and two bevels.
blade_rows=[(.12,.022,.0065,0),(.195,.028,.0065,.6),(.26,.0285,.0062,1),
    (.62,.0255,.0055,1),(.86,.0195,.0047,1),(.965,.012,.0035,.6),
    (1.035,.0058,.0022,0),(1.09,.00016,.00016,0)]
cross=[(-1,0),(-.78,.58),(-.23,1),(-.065,.80),(.065,.80),(.23,1),(.78,.58),(1,0),
    (.78,-.58),(.23,-1),(.065,-.80),(-.065,-.80),(-.23,-1),(-.78,-.58)]
verts=[]
for y,w,t,g in blade_rows:
    for x,z in cross:
        if .06<abs(x)<.07:z=math.copysign(1-.20*g,z)
        verts.append((w*x,y,t*z))
faces=[];indices=[];n=len(cross)
for row in range(len(blade_rows)-1):
    for j in range(n):
        faces.append((row*n+j,row*n+(j+1)%n,(row+1)*n+(j+1)%n,(row+1)*n+j))
        indices.append(1 if j in [0,6,7,13] else 2 if j in [3,10] else 0)
faces += [tuple(reversed(range(n))),tuple((len(blade_rows)-1)*n+j for j in range(n))]
indices += [0,1]
blade=mesh("Forged blade / honed bevels / recessed central fuller",verts,faces,steel,False,"blade")
blade.data.materials.append(edge);blade.data.materials.append(groove)
for poly,index in zip(blade.data.polygons,indices):poly.material_index=index
add("sword",blade)
# Continuous forged guard, turned slightly towards the blade at the ends.
verts=[]
guard_rows=[(-.123,.126,.0045,.007),(-.117,.115,.007,.009),(-.089,.099,.008,.012),
    (-.05,.092,.009,.014),(0,.103,.012,.017),(.05,.092,.009,.014),
    (.089,.099,.008,.012),(.117,.115,.007,.009),(.123,.126,.0045,.007)]
for x,y,hy,hz in guard_rows:
    for j in range(12):
        a,b=math.cos(j*math.tau/12),math.sin(j*math.tau/12)
        verts.append((x,y+hy*math.copysign(abs(a)**.7,a),hz*math.copysign(abs(b)**.7,b)))
faces=[]
for i in range(len(guard_rows)-1):
    for j in range(12):faces.append((i*12+j,i*12+(j+1)%12,(i+1)*12+(j+1)%12,(i+1)*12+j))
faces += [tuple(reversed(range(12))),tuple((len(guard_rows)-1)*12+j for j in range(12))]
add("sword",mesh("Swept forged bronze crossguard",verts,faces,bronze,True),
    loft_y("Continuous steel tang through crossguard",[(.074,.010,.0046,0,0),(.14,.010,.0046,0,0)],steel,12,3.3,False),
    loft_y("Sword grip oval core",[(-.173,.014,.010,0,0),(-.13,.016,.011,0,0),(.045,.0145,.0105,0,0),(.086,.017,.012,0,0)],leather),
    ribbon_wrap("Overlapping diagonal grip wrapping",-.163,.077,.0168,.0123,10,.020,leather),
    loft_y("Upper bronze grip ferrule",[(.073,.018,.013,0,0),(.078,.019,.014,0,0),(.088,.018,.013,0,0)],bronze),
    loft_y("Lower bronze grip ferrule",[(-.185,.016,.012,0,0),(-.179,.018,.014,0,0),(-.166,.018,.013,0,0)],bronze),
    loft_y("Faceted counterweight pommel",[(-.239,.004,.005,0,0),(-.228,.017,.013,0,0),(-.215,.024,.018,0,0),(-.196,.024,.018,0,0),(-.181,.016,.012,0,0)],bronze,24,3.1,False))
for sign in [-1,1]:
    add("sword",rosette("Quiet pommel rosette",(0,-.208,sign*.0183),.014,.015,dark))
    for x in [-.011,.011]:
        add("sword",tube("Ricasso inset tracery",[(x,.140,sign*.00658),(x*.45,.154,sign*.00658),(x,.173,sign*.00658)],[.00065]*3,bronze,6))
for j in range(11):
    y=-.144+j*.019
    add("sword",tube("Hand-sewn grip seam",[(-.006,y,.01285),(.0,y+.0035,.0131),(.006,y+.001,.01285)],[.00055]*3,thread,5))

# One continuous walnut bow, with an S-profile rather than cylindrical limbs.
bow_control=[(0,0,.024,.017),(.08,-.010,.026,.015),(.16,-.035,.032,.012),
    (.27,-.092,.028,.009),(.40,-.164,.024,.0075),(.50,-.179,.020,.0064),
    (.59,-.115,.015,.0054),(.66,-.010,.012,.0047),(.71,.076,.009,.0042),(.735,.060,.006,.004)]
def catmull(a,b,c,d,t):
    return .5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t)
upper=[]
for i in range(len(bow_control)-1):
    for j in range(7):
        t=j/7
        upper.append(tuple(catmull(bow_control[max(0,i-1)][k],bow_control[i][k],bow_control[i+1][k],bow_control[min(len(bow_control)-1,i+2)][k],t) for k in range(4)))
upper.append(bow_control[-1])
rows=[(-y,z,w,t) for y,z,w,t in reversed(upper[1:])]+upper
bow_verts=[];bow_faces=[];bow_mats=[];count=12
for i,(y,z,w,t) in enumerate(rows):
    tangent=Vector((rows[min(i+1,len(rows)-1)][0]-rows[max(0,i-1)][0],rows[min(i+1,len(rows)-1)][1]-rows[max(0,i-1)][1])).normalized()
    ny,nz=-tangent.y,tangent.x
    for j in range(count):
        a,b=math.cos(j*math.tau/count),math.sin(j*math.tau/count)
        cross_w=w*math.copysign(abs(a)**.65,a)
        cross_t=t*math.copysign(abs(b)**.70,b)
        bow_verts.append((cross_w,y+ny*cross_t,z+nz*cross_t))
for i in range(len(rows)-1):
    for j in range(count):
        bow_faces.append((i*count+j,i*count+(j+1)%count,(i+1)*count+(j+1)%count,(i+1)*count+j))
        bow_mats.append(2 if abs(rows[i][0])>.688 else 1 if j in [3,4,5,6,7,8] else 0)
bow_faces += [tuple(reversed(range(count))),tuple((len(rows)-1)*count+j for j in range(count))]
bow_mats += [2,2]
bow=mesh("Continuous carved recurve limbs / laminated belly",bow_verts,bow_faces,wood,True,"wood")
bow.data.materials.append(laminate);bow.data.materials.append(horn)
for poly,index in zip(bow.data.polygons,bow_mats):poly.material_index=index
add("bow",bow,ribbon_wrap("Bow leather hand grip",-.078,.075,.0262,.0188,7,.019,leather))
for sign in [-1,1]:
    add("bow",ring("Bound horn tip string groove",(0,sign*.709,.077),(.0103,0,0),(0,.0035,.0055),.0014,thread,24))
    # Grip edges stay inside the non-deforming central section.
    add("bow",ring("Bow grip edge binding",(0,sign*.083,-.01),(.027,0,0),(0,0,.016),.0015,thread,32))
add("bow",tube("Inset side arrow-rest shelf",[(.020,.06,.017),(.015,.06,.032),(.005,.06,.034)],[.0037,.0037,.0025],horn,8),
    rosette("Grip maker's medallion",(0,-.014,.020),.009,.016,bronze))

# Arrow frame: the string notch is at origin, the pointed head finishes at -Z .8.
shaft_points=[(0,0,-.016),(0,0,-.13),(0,0,-.42),(0,0,-.73)]
arrow_shaft=tube("Straight tapered wood arrow shaft",shaft_points,[.0037,.0035,.0032,.0028],laminate,16)
shaft_uv=arrow_shaft.data.uv_layers.new(name="LengthwiseWoodGrain")
for poly in arrow_shaft.data.polygons:
    for index in poly.loop_indices:
        point=gp(arrow_shaft.data.vertices[arrow_shaft.data.loops[index].vertex_index].co)
        shaft_uv.data[index].uv=(math.atan2(point[1],point[0])/math.tau+.5,-point[2]/.8)
add("arrow",arrow_shaft)
for sign in [-1,1]:
    add("arrow",tube("Split horn self-nock",[(0,sign*.0028,0),(0,sign*.0037,-.008),(0,sign*.0025,-.023)],[.0014,.0017,.0015],horn,8))
add("arrow",ring("Nock reinforced linen collar",(0,0,-.029),(.0042,0,0),(0,.0042,0),.00065,thread,20))
for blade_index in range(3):
    angle=blade_index*math.tau/3
    radial=Vector((math.cos(angle),math.sin(angle),0));normal=Vector((-math.sin(angle),math.cos(angle),0))
    profile=[(.0035,-.036),(.012,-.044),(.020,-.066),(.0205,-.105),(.014,-.142),(.0035,-.157)]
    pts=[]
    for side in [-1,1]:
        for radius,z in profile:pts.append(radial*radius+normal*(side*.00035)+Vector((0,0,z)))
    n=len(profile);faces=[tuple(reversed(range(n))),tuple(n+j for j in range(n))]
    faces += [(j,(j+1)%n,n+(j+1)%n,n+j) for j in range(n)]
    fin=mesh("Curved feather fletching",pts,faces,feather,False)
    add("arrow",fin)
    for k in range(7):
        z=-.061-k*.010
        add("arrow",tube("Fine feather barb",[radial*.004+normal*.0005+Vector((0,0,z)),radial*.015+normal*.0005+Vector((0,0,z+.007))],[.00032]*2,feather_dark,4))
arrow_rows=[(-.724,.003,.003),(-.737,.005,.0032),(-.747,.013,.0028),(-.773,.008,.002),(-.8,.00013,.00013)]
pts=[]
for z,rx,ry in arrow_rows:
    pts += [(-rx,0,z),(0,ry,z),(rx,0,z),(0,-ry,z)]
faces=[]
for i in range(len(arrow_rows)-1):
    for j in range(4):faces.append((i*4+j,i*4+(j+1)%4,(i+1)*4+(j+1)%4,(i+1)*4+j))
faces += [(3,2,1,0),tuple((len(arrow_rows)-1)*4+j for j in range(4))]
add("arrow",mesh("Forged leaf arrowhead / four cutting facets",pts,faces,steel))
add("arrow",ring("Arrowhead haft binding",(0,0,-.722),(.0034,0,0),(0,.0034,0),.0007,thread,20))

# Hollow scabbard has a genuinely open mouth matched to the blade at the guard.
case_rows=[(.125,.035,.012),(.16,.0355,.012),(.24,.035,.011),(.61,.031,.010),(.87,.025,.009),(1.02,.014,.007),(1.113,.002,.002)]
pts=[];count=24
for inner in [False,True]:
    for y,rx,rz in case_rows:
        for j in range(count):
            a,b=math.cos(j*math.tau/count),math.sin(j*math.tau/count)
            xx=math.copysign(abs(a)**.67,a)*max(.0005,rx-(.003 if inner else 0))
            zz=math.copysign(abs(b)**.67,b)*max(.0005,rz-(.003 if inner else 0))
            pts.append((xx,y,zz))
faces=[];offset=len(case_rows)*count
for k in range(2):
    base=k*offset
    for i in range(len(case_rows)-1):
        for j in range(count):faces.append((base+i*count+j,base+i*count+(j+1)%count,base+(i+1)*count+(j+1)%count,base+(i+1)*count+j))
for j in range(count):
    faces.append((j,(j+1)%count,offset+(j+1)%count,offset+j))
faces += [tuple((len(case_rows)-1)*count+j for j in range(count)),tuple(offset+(len(case_rows)-1)*count+j for j in reversed(range(count)))]
add("scabbard",mesh("Open stitched leather blade sheath",pts,faces,case_leather,True),
    loft_y("Scabbard antique bronze chape",[(1.016,.0155,.008,0,0),(1.05,.011,.007,0,0),(1.11,.004,.004,0,0),(1.124,.0008,.001,0,0)],bronze,24,2.7))
for y in [.145,.31]:
    add("scabbard",ring("Scabbard bronze suspension band",(0,y,0),(.037,0,0),(0,0,.013),.002,bronze,32),
        ring("Scabbard belt suspension ring",(.043,y,.004),(.009,0,0),(0,.012,0),.0022,bronze,24))
for k in range(25):
    y=.19+k*.032
    width=.034-(max(0,y-.35)*.012)
    add("scabbard",tube("Scabbard side saddle stitch",[(width-.002,y,.012),(width-.001,y+.006,.012),(width-.004,y+.01,.012)],[.00055]*3,thread,4))
for sign in [-1,1]:
    add("scabbard",tube("Fine mouth bronze inset",[(-.026,.163,sign*.0122),(0,.180,sign*.0126),(.026,.163,sign*.0122)],[.0008]*3,bronze,6))

# Quiver uses an oval shell with a sloped, open rim and visible inner leather.
quiver_rows=[(-.31,.053,.043),(-.27,.064,.050),(.02,.070,.053),(.30,.073,.054),(.355,.077,.057)]
pts=[];count=40
for inner in [False,True]:
    for row,(y,rx,rz) in enumerate(quiver_rows):
        for j in range(count):
            a=j*math.tau/count
            yy=y+(.030*math.sin(a) if row==len(quiver_rows)-1 else .006 if inner and row==0 else 0)
            pts.append((math.cos(a)*(rx-(.005 if inner else 0)),yy,math.sin(a)*(rz-(.005 if inner else 0))))
offset=len(quiver_rows)*count;faces=[]
for k in range(2):
    base=k*offset
    for i in range(len(quiver_rows)-1):
        for j in range(count):faces.append((base+i*count+j,base+i*count+(j+1)%count,base+(i+1)*count+(j+1)%count,base+(i+1)*count+j))
for j in range(count):faces.append(((len(quiver_rows)-1)*count+j,(len(quiver_rows)-1)*count+(j+1)%count,offset+(len(quiver_rows)-1)*count+(j+1)%count,offset+(len(quiver_rows)-1)*count+j))
faces += [tuple(reversed(range(count))),tuple(offset+j for j in range(count))]
add("quiver",mesh("Open oval quiver / sloped reinforced mouth",pts,faces,case_leather,True))
rim=[(.077*math.cos(j*math.tau/64),.355+.030*math.sin(j*math.tau/64),.057*math.sin(j*math.tau/64)) for j in range(65)]
add("quiver",tube("Quiver braided leather rim",rim,[.0035]*65,leather,8),
    ring("Quiver leather base seam",(0,-.268,0),(.066,0,0),(0,0,.051),.0023,leather,48))
for y in [-.20,.17]:
    add("quiver",ring("Quiver suspension strap",(0,y,0),(.074,0,0),(0,0,.056),.003,leather,48),
        ring("Quiver belt ring",(.081,y,.006),(.013,0,0),(0,.017,0),.0025,bronze,28))
for j in range(18):
    y=-.25+j*.029
    add("quiver",tube("Quiver visible hand stitching",[(-.035,y,.047),(-.030,y+.006,.051),(-.025,y+.002,.052)],[.00075]*3,thread,5))
patch_points=[]
for y,width in [(-.175,.014),(-.15,.030),(-.05,.038),(.10,.041),(.235,.034),(.25,.021)]:
    for k in range(9):
        x=(k/8*2-1)*width
        z=.054*math.sqrt(max(0,1-(x/.071)**2))+.0011
        patch_points.append((x,y,z))
patch_faces=[]
for row in range(5):
    for k in range(8):patch_faces.append((row*9+k,row*9+k+1,(row+1)*9+k+1,(row+1)*9+k))
patch=mesh("Curved stitched quiver reinforcement panel",patch_points,patch_faces,leather,True,"leather")
bpy.context.view_layer.objects.active=patch
panel_thickness=patch.modifiers.new("Reinforcing leather thickness","SOLIDIFY");panel_thickness.thickness=.0012;panel_thickness.offset=0
bpy.ops.object.modifier_apply(modifier=panel_thickness.name)
add("quiver",patch,rosette("Small bronze quiver maker seal",(0,.07,.0562),.019,.024,bronze))

MARKERS={
    "sword":{"Grip":(0,0,0),"BladeTip":(0,1.09,0)},
    "bow":{"Grip":(0,0,0),"StringTop":(0,.709,.084),"StringBottom":(0,-.709,.084),"NockRest":(0,.06,.20),"ArrowRest":(0,.06,.034)},
    "arrow":{"Nock":(0,0,0),"ArrowTip":(0,0,-.8)},
    "scabbard":{"Attachment":(0,0,0),"Mouth":(0,.125,0)},
    "quiver":{"Attachment":(0,0,0),"Mouth":(0,.355,0)}
}
def draw_point(point):
    x,y,z=point
    weight=max(0,min(1,(abs(y)-.10)/.635))**1.65
    return (x,y-math.copysign(.015*weight,y),z+.075*weight)

def make_empty(name,parent=None,at=(0,0,0)):
    ob=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(ob)
    ob.empty_display_type="PLAIN_AXES";ob.empty_display_size=.025
    if parent:ob.parent=parent
    ob.location=v(at)
    return ob

def bounds(data):
    points=[gp(vertex.co) for vertex in data.vertices]
    return {"min":[round(min(p[i] for p in points),7) for i in range(3)],"max":[round(max(p[i] for p in points),7) for i in range(3)]}

manifest=[];exports={};source_roots={}
for item,objects in parts.items():
    source_collection=bpy.data.collections.new(item.title()+" editable craft parts")
    scene.collection.children.link(source_collection)
    root=make_empty(item.title()+"_Editable_Source")
    for old in list(root.users_collection):old.objects.unlink(root)
    source_collection.objects.link(root);source_roots[item]=root
    for ob in objects:
        for old in list(ob.users_collection):old.objects.unlink(ob)
        source_collection.objects.link(ob);ob.parent=root
        if not ob.data.uv_layers:
            bpy.ops.object.select_all(action="DESELECT");ob.select_set(True);bpy.context.view_layer.objects.active=ob
            bpy.ops.object.mode_set(mode="EDIT");bpy.ops.mesh.select_all(action="SELECT")
            bpy.ops.uv.smart_project(angle_limit=.85,island_margin=.006)
            bpy.ops.object.mode_set(mode="OBJECT")
    copies=[]
    for ob in objects:
        clone=ob.copy();clone.data=ob.data.copy();clone.parent=None
        bpy.context.collection.objects.link(clone);copies.append(clone)
    bpy.ops.object.select_all(action="DESELECT")
    for clone in copies:clone.select_set(True)
    bpy.context.view_layer.objects.active=copies[0]
    if len(copies)>1:bpy.ops.object.join()
    base=bpy.context.object
    scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    tr=base.modifiers.new("Export game triangles","TRIANGULATE");bpy.ops.object.modifier_apply(modifier=tr.name)
    paths=[];counts=[];aabbs=[];draw_aabbs=[];variants=[]
    for lod,ratio in enumerate([1,.46,.18]):
        ob=base if lod==0 else base.copy()
        if lod:
            ob.data=base.data.copy();bpy.context.collection.objects.link(ob)
            # Do not inherit LOD0 morph keys before mesh reduction.
            if ob.data.shape_keys:
                bpy.context.view_layer.objects.active=ob;bpy.ops.object.shape_key_remove(all=True)
            bpy.context.view_layer.objects.active=ob
            dec=ob.modifiers.new("Runtime LOD reduction","DECIMATE");dec.ratio=ratio
            bpy.ops.object.modifier_apply(modifier=dec.name)
        ob.name=item.title()+"Mesh_LOD"+str(lod)
        ob.data.validate(verbose=False,clean_customdata=False);ob.data.update();ob.data.calc_loop_triangles()
        counts.append(len(ob.data.loop_triangles));aabbs.append(bounds(ob.data))
        if item=="bow":
            basis=ob.shape_key_add(name="Basis",from_mix=False)
            key=ob.shape_key_add(name="BowDraw",from_mix=False)
            for vertex,point in zip(key.data,basis.data):vertex.co=v(draw_point(gp(point.co)))
            key.value=0
            draw_points=[gp(vertex.co) for vertex in key.data]
            draw_aabbs.append({"min":[round(min(p[i] for p in draw_points),7) for i in range(3)],"max":[round(max(p[i] for p in draw_points),7) for i in range(3)]})
        asset_root=make_empty("Weapon_"+item.title()+"_V4")
        ob.parent=asset_root
        marker_objects=[make_empty(name,asset_root,position) for name,position in MARKERS[item].items()]
        bpy.ops.object.select_all(action="DESELECT")
        for selected in [asset_root,ob,*marker_objects]:selected.select_set(True)
        bpy.context.view_layer.objects.active=ob
        path="models/weapons_v4/"+item+"_lod"+str(lod)+".glb"
        paths.append("res://"+path)
        bpy.ops.export_scene.gltf(filepath=str(ROOT/path),export_format="GLB",use_selection=True,
            export_yup=True,export_materials="EXPORT",export_animations=False,export_morph=True,
            export_morph_normal=True,export_morph_tangent=False,export_cameras=False,export_lights=False)
        # Blender object names are unique; release exported names for the next
        # LOD while preserving the same un-suffixed hierarchy inside every GLB.
        asset_root.name="Export_"+item+"_LOD"+str(lod)
        for marker in marker_objects:marker.name=item+"_"+marker.name+"_LOD"+str(lod)
        variants.append((asset_root,ob,marker_objects))
    exports[item]=variants
    manifest.append({"item":item,"units":"metres","render_only":True,"grip_origin":[0,0,0],"root":"Weapon_"+item.title()+"_V4",
        "model_paths":paths,"triangle_counts":counts,"aabb_per_lod":aabbs,"markers":MARKERS[item],
        "morph_target":"BowDraw" if item=="bow" else None,"draw_aabb_per_lod":draw_aabbs,
        "draw_markers":{name:draw_point(position) for name,position in MARKERS[item].items()} if item=="bow" else {},
        "glb_bytes":sum((ROOT/path.removeprefix("res://")).stat().st_size for path in paths)})

# Read the actual GLB structure: one mesh, named marker nodes, correct morph.
def read_glb(path):
    raw=path.read_bytes();magic,version,size=struct.unpack_from("<4sII",raw)
    assert magic==b"glTF" and version==2 and size==len(raw)
    length,kind=struct.unpack_from("<I4s",raw,12);assert kind==b"JSON"
    doc=json.loads(raw[20:20+length])
    binary_offset=20+length
    binary_length,binary_kind=struct.unpack_from("<I4s",raw,binary_offset)
    assert binary_kind==b"BIN\0"
    return doc,raw[binary_offset+8:binary_offset+8+binary_length]

def accessor(doc,blob,index):
    access=doc["accessors"][index]
    dtypes={5126:"<f4",5125:"<u4",5123:"<u2",5121:"u1"}
    dtype=dtypes[access["componentType"]]
    count={"SCALAR":1,"VEC2":2,"VEC3":3,"VEC4":4}[access["type"]]
    byte_size=np.dtype(dtype).itemsize
    if "bufferView" in access:
        view=doc["bufferViews"][access["bufferView"]]
        result=np.ndarray((access["count"],count),dtype=dtype,buffer=blob,
            offset=view.get("byteOffset",0)+access.get("byteOffset",0),
            strides=(view.get("byteStride",count*byte_size),byte_size)).copy()
    else:
        result=np.zeros((access["count"],count),dtype=dtype)
    if "sparse" in access:
        sparse=access["sparse"];indices=sparse["indices"];values=sparse["values"]
        index_view=doc["bufferViews"][indices["bufferView"]]
        value_view=doc["bufferViews"][values["bufferView"]]
        ids=np.frombuffer(blob,dtype=dtypes[indices["componentType"]],count=sparse["count"],offset=index_view.get("byteOffset",0)+indices.get("byteOffset",0))
        changed=np.frombuffer(blob,dtype=dtype,count=sparse["count"]*count,offset=value_view.get("byteOffset",0)+values.get("byteOffset",0)).reshape((-1,count))
        result[ids]=changed
    return result

for record in manifest:
    for lod,path in enumerate(record["model_paths"]):
        doc,blob=read_glb(ROOT/path.removeprefix("res://"))
        assert len(doc.get("meshes",[]))==1,(path,"mesh count")
        names={node.get("name") for node in doc["nodes"]}
        assert set(record["markers"]).issubset(names),(path,"missing markers")
        assert record["root"] in names,(path,"root")
        vertices=np.concatenate([accessor(doc,blob,primitive["attributes"]["POSITION"]) for primitive in doc["meshes"][0]["primitives"]])
        assert np.all(np.isfinite(vertices)),(path,"finite positions")
        assert np.max(np.abs(vertices.min(axis=0)-np.array(record["aabb_per_lod"][lod]["min"])))<.000002,(path,"Y-up minimum bounds")
        assert np.max(np.abs(vertices.max(axis=0)-np.array(record["aabb_per_lod"][lod]["max"])))<.000002,(path,"Y-up maximum bounds")
        actual_triangles=sum(doc["accessors"][primitive["indices"]]["count"]//3 for primitive in doc["meshes"][0]["primitives"])
        assert actual_triangles==record["triangle_counts"][lod],(path,"actual indexed triangles")
        if record["item"]=="bow":
            assert doc["meshes"][0].get("extras",{}).get("targetNames")==["BowDraw"],(path,"morph name")
            assert all(len(p.get("targets",[]))==1 for p in doc["meshes"][0]["primitives"]),(path,"morph streams")
            assert all("POSITION" in p["targets"][0] and "NORMAL" in p["targets"][0] for p in doc["meshes"][0]["primitives"]),(path,"morph position/normal")
            deltas=np.concatenate([accessor(doc,blob,primitive["targets"][0]["POSITION"]) for primitive in doc["meshes"][0]["primitives"]])
            assert np.max(deltas[:,2])>.07,(path,"real +Z draw displacement")
            assert np.max(np.abs(deltas[np.abs(vertices[:,1])<.099]))<.000001,(path,"stationary physical grip")
        assert all(record["triangle_counts"][i]>record["triangle_counts"][i+1] for i in [0,1]),(path,"LOD order")

# Lay out the editable source and the exported variants separately. The saved
# scene opens on its catalogue camera with the source parts ready to modify.
placements={"sword":(-.63,.25,0),"bow":(.50,.76,-.01),"arrow":(1.02,.12,.015),"scabbard":(-.96,.04,-.018),"quiver":(-1.38,.325,-.01)}
for item,root in source_roots.items():
    root.location=v(placements[item])
    if item=="arrow":root.rotation_euler.x=math.pi/2
for item,variants in exports.items():
    for lod,(root,ob,markers) in enumerate(variants):
        root.hide_render=True;root.hide_set(True)
        ob.hide_render=True;ob.hide_set(True)
        for marker in markers:marker.hide_render=True;marker.hide_set(True)
        root.location=v((placements[item][0]+4+lod*2,placements[item][1],0))

stage=bpy.data.collections.new("Studio / render only, excluded from all GLB")
scene.collection.children.link(stage)
def stage_object(ob):
    for old in list(ob.users_collection):old.objects.unlink(ob)
    stage.objects.link(ob)
    return ob
background=material("Studio charcoal",(.028,.032,.036),.94)
floor=stage_object(mesh("Studio floor",[(-12,-.015,-8),(12,-.015,-8),(12,-.015,8),(-12,-.015,8)],[(0,1,2,3)],background))
wall=stage_object(mesh("Studio background",[(-12,-.015,-.50),(12,-.015,-.50),(12,8,-.50),(-12,8,-.50)],[(0,1,2,3)],background))
def area(name,position,energy,size,color,target):
    data=bpy.data.lights.new(name,"AREA");data.energy=energy;data.shape="DISK";data.size=size;data.color=color
    ob=bpy.data.objects.new(name,data);stage.objects.link(ob);ob.location=v(position)
    ob.rotation_euler=(v(target)-ob.location).to_track_quat("-Z","Y").to_euler()
    return ob
area("Broad warm steel highlight",(-2.6,2.8,2.4),210,3.2,(1,.88,.74),(0,.7,0))
area("Narrow cool edge reflection",(2.1,1.7,.65),130,1.7,(.74,.84,1),(0,.6,0))
area("Upper silk light",(.1,3.1,-.2),150,1.7,(1,.96,.85),(0,.7,0))
scene.world.use_nodes=True;scene.world.node_tree.nodes["Background"].inputs["Color"].default_value=(.10,.12,.14,1)
scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value=.33
cam_data=bpy.data.cameras.new("Weapons V4 catalogue camera")
camera=bpy.data.objects.new("Weapons V4 catalogue camera",cam_data);stage.objects.link(camera);scene.camera=camera
def camera_at(position,target,scale):
    camera.location=v(position);camera.rotation_euler=(v(target)-camera.location).to_track_quat("-Z","Y").to_euler()
    camera.data.type="ORTHO";camera.data.ortho_scale=scale;camera.data.lens=52
scene.render.engine="BLENDER_EEVEE_NEXT"
scene.render.resolution_x=1800;scene.render.resolution_y=1200;scene.render.resolution_percentage=100
scene.render.image_settings.file_format="PNG";scene.render.film_transparent=False
scene.view_settings.view_transform="AgX"
scene.view_settings.look="AgX - Medium High Contrast"
scene.render.image_settings.color_mode="RGBA"
camera_at((1.7,1.05,4.4),(-.2,.74,0),3.15)
scene["contract"]="Godot Y up; sword +Y, blade thickness Z; bow YZ, aim -Z, string +Z; arrow -Z. No collision."
scene["bow_morph"]="BowDraw in every GLB LOD. Central |Y|<=.1 remains stationary; marker target positions in manifest."
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE),compress=True)
report={"units":"metres","axes":"Godot Y up; forward -Z; Blender source uses Z up",
    "source":"res://art/source/weapons_v4.blend","generator":"tools/art/generate_weapons_v4.py",
    "original_designs":True,"render_only":True,"colliders":False,"lod_ratios":[1,.46,.18],
    "sword_frame":"Grip origin; blade +Y starting .12, lower handle -Y, thickness Z",
    "bow_frame":"Grip origin; limbs in YZ, aim -Z, string +Z; no static string mesh",
    "arrow_frame":"Nock origin; tip -Z at .8m; three feather vanes",
    "scabbard_frame":"Aligned to sword grip frame; open mouth at Y+.125; blade cavity extends +Y",
    "quiver_frame":"Attachment origin midway on body; open sloped mouth around Y+.355",
    "bow_draw":"BowDraw morph target per LOD, stationary grip. Move string marker nodes to draw_markers at full draw.",
    "texture_sources":["res://"+path.relative_to(ROOT).as_posix() for path in sorted((ROOT/"textures/weapons_v4").glob("*.png"))],
    "items":manifest,"validation":"Actual GLB JSON and binary accessors: 15 GLB, one mesh each, named markers, exact indexed triangle counts, Y-up bounds, BowDraw POSITION/NORMAL streams, real +Z draw displacement and stationary physical grip",
    "renders":["res://art/screenshots/weapons_v4/"+name+".png" for name in ["catalogue","sword_detail","blade_profile","bow_profile","bow_drawn","arrow_quiver"]]}
(ROOT/"assets/weapons_v4_manifest.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
print("WEAPONS_V4_EXPORT_OK",[(item["item"],item["triangle_counts"]) for item in manifest],flush=True)
render_dir=ROOT/"art/screenshots/weapons_v4"
def render(name):
    scene.render.filepath=str(render_dir/(name+".png"));bpy.ops.render.render(write_still=True)
    print("WEAPONS_V4_RENDER",name,flush=True)
render("catalogue")
def show_source(names):
    for item,objects in parts.items():
        for ob in objects:ob.hide_render=item not in names
show_source(["sword"])
camera_at((-.27,.28,1.18),(-.63,.23,0),.85)
render("sword_detail")
camera_at((-.19,1.01,1.32),(-.63,.92,0),.96)
render("blade_profile")
show_source(["bow"])
camera_at((1.92,.90,.73),(.50,.76,0),2.38)
render("bow_profile")
show_source([])
draw_root,draw_mesh,_=exports["bow"][0]
draw_root.location=v(placements["bow"]);draw_root.hide_render=False;draw_mesh.hide_render=False
draw_mesh.data.shape_keys.key_blocks["BowDraw"].value=1
render("bow_drawn")
draw_mesh.data.shape_keys.key_blocks["BowDraw"].value=0;draw_mesh.hide_render=True;draw_root.hide_render=True
show_source(["arrow","quiver"])
source_roots["arrow"].location=v((-1.09,.12,.13))
camera_at((-.61,.62,1.6),(-1.30,.49,0),1.52)
render("arrow_quiver")
print("WEAPONS_V4_COMPLETE",str(SOURCE),flush=True)
