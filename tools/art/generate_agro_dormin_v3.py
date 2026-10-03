"""Original bone-local art for the existing Agro and Dormin simulation rigs.

Run through tools/run_local.py; all generated data stays in this project.
The exported pieces contain meshes and PBR materials, never physics or hit logic.
"""
import bpy
import bmesh
import json
import math
import random
import sys
from pathlib import Path
from mathutils import Vector, Matrix
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art/source/agro_dormin_v3.blend"
if SOURCE.exists() and "--regenerate" not in sys.argv:
    raise SystemExit("Source exists: pass -- --regenerate to rebuild explicitly.")
for folder in ["models/agro_v3", "models/dormin_v3", "textures/agro_dormin_v3", "assets", "art/source"]:
    (ROOT / folder).mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
rng = random.Random(271127)
bpy.context.scene.unit_settings.system = "METRIC"
bpy.context.scene.unit_settings.scale_length = 1

def v(p):
    return Vector((p[0], -p[2], p[1]))

def mesh(name, points, faces, mat, smooth=True):
    data = bpy.data.meshes.new(name)
    data.from_pydata([v(p) for p in points], [], faces)
    data.update()
    bm = bmesh.new(); bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(data); bm.free()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    for face in data.polygons:
        face.use_smooth = smooth
    return obj

def material(name, color, roughness, metallic=0, pattern=None, emission=0):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = (*color, 1)
    p.inputs["Roughness"].default_value = roughness
    p.inputs["Metallic"].default_value = metallic
    if emission:
        p.inputs["Emission Color"].default_value = (*color, 1)
        p.inputs["Emission Strength"].default_value = emission
    if pattern:
        # Real PNG inputs survive GLB import; no unsupported procedural shader nodes.
        size = 256
        y, x = np.mgrid[0:size, 0:size]
        noise = np.random.default_rng(sum(ord(c) for c in name)).random((size, size))
        if pattern == "hair":
            shade = .84 + .07*np.sin(x*.38 + np.sin(y*.045)*1.1) + .09*noise
        elif pattern == "woven":
            shade = .84 + .08*np.sin(x*math.pi*.5)*np.sin(y*math.pi*.5) + .07*noise
            shade += .035*np.sin(x*.11)
        elif pattern == "stone":
            shade = .85 + .065*np.sin(x*.054+y*.079) + .045*np.sin(x*.28-y*.23) + .10*noise
        else:
            shade = .88 + .12*noise
        rgba = np.ones((size, size, 4), dtype=np.float32)
        for channel in range(3):
            # PNG pixels are sRGB; convert the chosen linear material tint accordingly.
            linear = np.clip(color[channel]*shade, 0, 1)
            rgba[:,:,channel] = np.where(linear <= .0031308, linear*12.92, 1.055*linear**(1/2.4)-.055)
        image = bpy.data.images.new(name+" albedo", width=size, height=size)
        image.pixels.foreach_set(rgba.ravel())
        image.filepath_raw = str(ROOT / ("textures/agro_dormin_v3/"+name+"_albedo.png"))
        image.file_format = "PNG"; image.save(); image.pack()
        tex = m.node_tree.nodes.new("ShaderNodeTexImage"); tex.image = image
        m.node_tree.links.new(tex.outputs["Color"], p.inputs["Base Color"])
        # Small baked normal detail changes grazing light without adding vertices.
        # Non-colour data is independent of the chosen coat/stone tint.
        height = shade
        dy, dx = np.gradient(height)
        detail = .55 if pattern == "stone" else .20
        normal = np.stack((-dx*detail, -dy*detail, np.ones_like(height)), axis=-1)
        normal /= np.linalg.norm(normal, axis=-1)[:,:,None]
        normal_pixels = np.ones((size,size,4), dtype=np.float32)
        normal_pixels[:,:,:3] = normal*.5+.5
        normal_image = bpy.data.images.new(name+" normal", width=size, height=size)
        normal_image.colorspace_settings.name = "Non-Color"
        normal_image.pixels.foreach_set(normal_pixels.ravel())
        normal_image.filepath_raw = str(ROOT/("textures/agro_dormin_v3/"+name+"_normal.png"))
        normal_image.file_format="PNG";normal_image.save();normal_image.pack()
        normal_tex = m.node_tree.nodes.new("ShaderNodeTexImage");normal_tex.image=normal_image
        normal_node = m.node_tree.nodes.new("ShaderNodeNormalMap")
        m.node_tree.links.new(normal_tex.outputs["Color"],normal_node.inputs["Color"])
        m.node_tree.links.new(normal_node.outputs["Normal"],p.inputs["Normal"])
    return m

coat = material("agro_dark_bay", (.080,.043,.025), .78, pattern="hair")
points = material("agro_black_points", (.026,.026,.025), .72, pattern="hair")
muzzle = material("agro_soft_muzzle", (.058,.049,.039), .70, pattern="leather")
hoof = material("agro_keratin", (.081,.078,.063), .36)
leather = material("agro_worn_leather", (.17,.09,.041), .72, pattern="leather")
cloth = material("agro_woven_blanket", (.24,.155,.095), .94, pattern="woven")
trim = material("agro_blanket_border", (.36,.28,.15), .87)
metal = material("agro_aged_brass", (.30,.23,.12), .42, .80)
eye = material("agro_gloss_eye", (.009,.007,.005), .12)
cream = material("agro_cream_star", (.64,.58,.43), .75)
ear = material("agro_inner_ear", (.15,.097,.079), .82)
dark = material("dormin_shadow_fibre", (.045,.061,.064), .91, pattern="hair")
stone = material("dormin_weathered_stone", (.15,.19,.18), .90, pattern="stone")
edge = material("dormin_fracture_edges", (.25,.29,.26), .96, pattern="stone")
obsidian = material("dormin_dense_obsidian", (.035,.050,.052), .59, .12, pattern="stone")
horn = material("dormin_ancient_horn", (.23,.26,.20), .88, pattern="stone")
seam = material("dormin_deep_fissures", (.012,.024,.029), 1)
amber = material("dormin_ember_eyes", (.60,.25,.042), .38, emission=1.2)
blue = material("dormin_residual_light", (.07,.19,.21), .62, emission=.25)

def ellipsoid(name, center, radius, mat, segments=24, rings=12):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=1, location=v(center))
    obj = bpy.context.object; obj.name = name
    obj.scale = (radius[0],radius[2],radius[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    for face in obj.data.polygons: face.use_smooth=True
    return obj

def loft_y(name, rows, mat, count=24, power=2):
    # Rows: height, half-width, half-depth, centre X, centre Z. A continuous silhouette.
    vertices=[]
    for y,rx,rz,cx,cz in rows:
        for i in range(count):
            angle = i*math.tau/count
            a,b=math.cos(angle),math.sin(angle)
            x=math.copysign(abs(a)**(2/power),a)*rx
            z=math.copysign(abs(b)**(2/power),b)*rz
            vertices.append((cx+x,y,cz+z))
    faces=[]
    for j in range(len(rows)-1):
        for i in range(count): faces.append((j*count+i,j*count+(i+1)%count,(j+1)*count+(i+1)%count,(j+1)*count+i))
    faces.extend([tuple(reversed(range(count))),tuple((len(rows)-1)*count+i for i in range(count))])
    return mesh(name, vertices, faces, mat)

def loft_z(name, rows, mat, count=32):
    vertices=[]
    for z,rx,ry,cy in rows:
        for i in range(count):
            t=i*math.tau/count
            vertices.append((rx*math.cos(t),cy+ry*math.sin(t),z))
    faces=[]
    for j in range(len(rows)-1):
        for i in range(count): faces.append((j*count+i,j*count+(i+1)%count,(j+1)*count+(i+1)%count,(j+1)*count+i))
    faces.extend([tuple(reversed(range(count))),tuple((len(rows)-1)*count+i for i in range(count))])
    return mesh(name,vertices,faces,mat)

def tube(name, coords, radii, mat, sides=8, smooth=True):
    coords=[Vector(p) for p in coords]; verts=[]
    for i,p in enumerate(coords):
        d=(coords[min(i+1,len(coords)-1)]-coords[max(i-1,0)]).normalized()
        axis=Vector((0,1,0)) if abs(d.y)<.9 else Vector((1,0,0))
        a=d.cross(axis).normalized(); b=d.cross(a).normalized()
        for j in range(sides): verts.append(p+(a*math.cos(j*math.tau/sides)+b*math.sin(j*math.tau/sides))*radii[i])
    faces=[]
    for i in range(len(coords)-1):
        for j in range(sides): faces.append((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j))
    faces += [tuple(reversed(range(sides))),tuple((len(coords)-1)*sides+j for j in range(sides))]
    return mesh(name,verts,faces,mat,smooth)

def loop(name, center, a, b, radius, mat, n=24):
    center,a,b=Vector(center),Vector(a),Vector(b)
    coords=[center+a*math.cos(i*math.tau/n)+b*math.sin(i*math.tau/n) for i in range(n+1)]
    return tube(name,coords,[radius]*(n+1),mat,6)

def tuft(name, start, end, width, mat):
    a,b=Vector(start),Vector(end)
    d=b-a; axis=d.cross(Vector((0,0,1)))
    if axis.length < .01: axis=d.cross(Vector((1,0,0)))
    axis.normalize(); side=axis*width*.5
    lift=d.cross(axis).normalized()*width*.15
    mid=a.lerp(b,.55)
    pts=[a-side,a+side,mid+side*.62,b,mid-side*.62,mid+lift]
    return mesh(name,pts,[(0,1,5),(1,2,5),(2,3,5),(3,4,5),(4,0,5),(0,4,3,2,1)],mat)

parts={"agro":{},"dormin":{}}
def add(actor,bone,*objects):
    parts[actor].setdefault(bone,[]).extend(objects)

# Agro: connected chest, barrel and hindquarters; silhouette is not a box.
add("agro","body",loft_z("Agro barrel and withers",[
    (-1.05,.09,.15,-.06),(-.94,.25,.28,-.035),(-.77,.34,.37,.015),
    (-.47,.355,.385,-.005),(-.1,.37,.395,-.02),(.25,.36,.36,.0),
    (.59,.37,.36,.015),(.85,.30,.30,.02),(1.05,.12,.16,.0)],coat))
add("agro","neck",loft_y("Tapering equine neck",[
    (-.10,.17,.21,0,.0),(.05,.215,.24,0,.025),(.23,.205,.23,0,.015),
    (.45,.175,.195,0,-.005),(.66,.135,.16,0,-.025),(.87,.105,.125,0,-.035),(.98,.085,.095,0,-.035)],coat))
for i in range(20):
    y=.07+i*.044
    x=rng.uniform(-.045,.045)
    length=rng.uniform(.20,.34)
    add("agro","neck",tube("Flowing neck mane",[(x,y,.22-.075*y),(x+.038,y-length*.28,.27-.075*y),(x+.06,y-length*.65,.26-.075*y),(x+.075,y-length,.24-.075*y)],[.018,.017,.011,.002],points,8))
skull=loft_z("Continuous equine skull and nose",[
    (.09,.095,.135,.085),(-.035,.16,.205,.06),(-.22,.176,.205,.035),
    (-.38,.148,.160,-.005),(-.53,.135,.140,-.075),(-.69,.13,.103,-.13),
    (-.78,.10,.075,-.135),(-.82,.025,.025,-.13)],coat,28)
skull.data.materials.append(muzzle)
for face in skull.data.polygons:
    if face.center.y > .64:
        face.material_index=1
add("agro","head",skull,ellipsoid("Defined lower jaw",(0,-.186,-.33),(.12,.049,.20),muzzle))
for sign in [-1,1]:
    add("agro","head",ellipsoid("Dark attentive eye",(sign*.163,.073,-.292),(.019,.024,.032),eye,16,8),
        ellipsoid("Nostril hollow",(sign*.112,-.093,-.735),(.027,.018,.033),points,16,8),
        tube("Sculpted ear",[(sign*.12,.19,-.05),(sign*.137,.31,-.04),(sign*.142,.43,-.01),(sign*.13,.50,.01)],[.063,.058,.035,.004],points,8),
        tuft("Soft inner ear",(sign*.125,.28,-.09),(sign*.136,.445,-.045),.058,ear),
        tube("Bridle cheek strap",[(sign*.17,.20,-.06),(sign*.193,.09,-.24),(sign*.172,-.08,-.52),(sign*.158,-.155,-.60)],[.012]*4,leather,6),
        loop("Bridle bit ring",(sign*.166,-.166,-.59),(0,.034,0),(0,0,.034),.006,metal,16))
add("agro","head",tuft("Small cream forehead star",(0,.227,-.25),(0,.095,-.49),.065,cream),
    loop("Leather noseband",(0,-.065,-.58),(.155,0,0),(0,.087,0),.014,leather),
    tube("Lip seam",[(-.124,-.166,-.72),(0,-.175,-.785),(.124,-.166,-.72)],[.004]*3,points,6))
for i in range(7):
    add("agro","head",tuft("Forelock",((i-3)*.022,.24,-.18),((i-3)*.023,.08,-.38),.045,points))
# Rigid leg pieces remain centred on the existing IK joints.
for side in ["fl","fr","rl","rr"]:
    rear=side.startswith("r")
    add("agro",side+"_up",loft_y("Muscular thigh" if rear else "Shoulder and forearm",[
        (.075,.125 if rear else .098,.18 if rear else .13,0,.01),
        (-.07,.15 if rear else .12,.195 if rear else .15,0,.015),
        (-.24,.14 if rear else .103,.17 if rear else .13,0,.015),
        (-.43,.096 if rear else .080,.12 if rear else .095,0,.01),
        (-.62,.060,.074,0,0)],coat,20))
    add("agro",side+"_low",loft_y("Cannon bone and ankle",[
        (.035,.062,.076,0,0),(-.08,.063,.073,0,0),(-.27,.047,.053,0,.007),
        (-.47,.045,.052,0,0),(-.58,.060,.072,0,0)],points,16))
    for sign in [-1,1]:
        add("agro",side+"_low",tube("Raised flexor tendon",[(sign*.044,-.10,.03),(sign*.043,-.30,.045),(sign*.05,-.51,.025)],[.007,.006,.009],muzzle,6))
    add("agro",side+"_hoof",loft_y("Sloped hoof wall",[(.014,.067,.088,0,-.012),(-.055,.082,.105,0,-.027),(-.10,.086,.112,0,-.03)],hoof,20))
    add("agro",side+"_hoof",tube("Worn horseshoe",[(-.073,-.098,.02),(-.074,-.098,-.07),(-.049,-.098,-.121),(0,-.098,-.137),(.049,-.098,-.121),(.074,-.098,-.07),(.073,-.098,.02)],[.008]*7,metal,6))
# Cloth wraps over the curved back, leaving the real rider anchor unchanged.
cloth_verts=[]
for z in [-.44,-.3,.20,.34]:
    for x,y in [(-.395,-.02),(-.385,.24),(-.27,.36),(0,.383),(.27,.36),(.385,.24),(.395,-.02)]:
        cloth_verts.append((x,y,z))
cloth_faces=[]
for j in range(3):
    for i in range(6): cloth_faces.append((j*7+i,j*7+i+1,(j+1)*7+i+1,(j+1)*7+i))
blanket=mesh("Draped saddle blanket",cloth_verts,cloth_faces,cloth)
bpy.context.view_layer.objects.active=blanket
th=blanket.modifiers.new("Fabric thickness","SOLIDIFY");th.thickness=.014;th.offset=0
bpy.ops.object.modifier_apply(modifier=th.name)
add("agro","body",blanket,ellipsoid("Leather saddle seat",(0,.389,-.05),(.26,.041,.275),leather))
for z in [-.43,.33]:
    add("agro","body",tube("Blanket embroidered rim",[(x,y,z) for x,y in [(-.40,-.03),(-.39,.24),(-.27,.367),(0,.395),(.27,.367),(.39,.24),(.40,-.03)]],[.009]*7,trim,6))
for z,high in [(-.30,.50),(.23,.55)]:
    add("agro","body",tube("Raised saddle pommel and cantle",[(-.25,.40,z),(-.17,high,z),(0,high+.026,z),(.17,high,z),(.25,.40,z)],[.037]*5,leather,8))
add("agro","body",tube("Broad belly girth",[(-.30,.27,-.05),(-.379,.05,-.05),(-.35,-.24,-.05),(0,-.408,-.05),(.35,-.24,-.05),(.379,.05,-.05),(.30,.27,-.05)],[.022]*7,leather,8))
for sign in [-1,1]:
    add("agro","body",tube("Stirrup leather",[(sign*.31,.35,.06),(sign*.425,.08,.06),(sign*.435,-.25,.065)],[.012]*3,leather,6),
        loop("Stirrup iron",(sign*.44,-.32,.065),(.052,0,0),(0,.08,0),.009,metal,16),
        tube("Short rein at saddle",[(sign*.22,.46,-.26),(sign*.29,.45,-.61),(sign*.20,.33,-.97)],[.006]*3,leather,6))
for i in range(7):
    s=(i-3)*.023
    add("agro","body",tube("Full hanging tail",[(s,.15,.92),(s*1.5,-.11,1.18),(s*1.65,-.42,1.25),(s*1.2,-.69,1.29),(s*.4,-.83,1.30)],[.045,.041,.035,.026,.007],points,7))

# Dormin: tapered, massive torso, shaggy climbing routes and broken mineral plates.
add("dormin","hips",loft_y("Broad shadow pelvis",[
    (-.59,1.38,.97,0,0),(-.30,1.9,1.20,0,0),(.12,2.04,1.27,0,0),(.67,1.93,1.24,0,0),(.97,1.65,1.12,0,0)],dark,32,2.3))
add("dormin","spine",loft_y("Tapered abdominal trunk",[
    (-.10,1.64,1.15,0,0),(.22,1.70,1.19,0,0),(1.12,1.32,1.18,0,0),(1.95,1.66,1.19,0,0),(2.28,1.69,1.18,0,0)],dark,32,2.6))
add("dormin","chest",loft_y("Vaulted ribcage",[
    (-.02,1.77,1.37,0,0),(.38,2.09,1.46,0,0),(1.12,2.44,1.49,0,0),(2.14,2.47,1.46,0,0),(2.76,2.22,1.37,0,0)],dark,36,2.5))
add("dormin","chest",loft_y("Continuous shaggy back mantle",[
    (-.23,1.80,.18,0,1.59),(.22,2.02,.22,0,1.59),(1.18,2.16,.235,0,1.59),(2.12,2.05,.23,0,1.59),(2.65,1.86,.18,0,1.59)],dark,28,3.5))
add("dormin","neck",ellipsoid("Powerful neck core",(0,.65,.1),(.775,1.06,.78),dark),
    loft_y("Back neck climbing mane",[(-.57,.88,.23,0,1.08),(.0,.98,.28,0,1.08),(.96,.96,.28,0,1.08),(1.96,.82,.23,0,1.08)],dark,24,3))
add("dormin","head",ellipsoid("Ancient hollow skull",(0,1.14,0),(1.0,1.10,1.07),obsidian,32,18),
    loft_y("Open crown climbing pad",[(2.12,.91,1.04,0,.15),(2.32,1.01,1.16,0,.15),(2.46,.98,1.13,0,.15)],dark,32,3.4),
    loft_y("Back head shaggy climbing panel",[(.16,.85,.17,0,1.12),(1.25,.99,.20,0,1.12),(2.26,.95,.17,0,1.12)],dark,28,3))

def plate(name, center, sx, sy, depth, mat=stone, seed=0):
    local_rng=random.Random(7301+seed)
    cx,cy,cz=center; n=local_rng.choice([5,6,7,8])
    ring=[]
    rotation=local_rng.uniform(-.4,.4)
    for i in range(n):
        t=(i+.1)*math.tau/n+rotation
        rr=local_rng.uniform(.72,1.12)
        ring.append((cx+sx*math.cos(t)*rr,cy+sy*math.sin(t)*rr,cz-depth*.64))
    pts=ring+[(cx,cy,cz-depth*.77)]+[(x,y,z+depth*.85) for x,y,z in ring]
    faces=[(i,(i+1)%n,n) for i in range(n)]
    faces += [(i,n+1+i,n+1+(i+1)%n,(i+1)%n) for i in range(n)]
    faces.append(tuple(n+1+i for i in reversed(range(n))))
    return mesh(name,pts,faces,mat,False)

for index,(x,y,sx,sy) in enumerate([(-1.22,2.12,.63,.54),(-.13,2.17,.49,.49),(1.15,2.15,.64,.52),
    (-1.54,1.13,.53,.60),(-.58,1.25,.58,.68),(.49,1.23,.52,.61),(1.48,1.07,.60,.59),
    (-.89,.38,.61,.37),(.40,.41,.63,.40)]):
    z=-1.43+.12*(abs(x)/2.2)**2
    add("dormin","chest",plate("Broken irregular pectoral slabs",(x,y,z),sx,sy,.19,stone,index))
for k,(x,y,sx,sy) in enumerate([(-.50,.42,.73,.33),(.26,1.12,.77,.47),(-.34,1.91,.64,.26)]):
    add("dormin","spine",plate("Broken abdominal slates",(x,y,-1.15),sx,sy,.11,obsidian,k+19))
for sign in [-1,1]:
    add("dormin","chest",ellipsoid("Rounded shoulder mineral cap",(sign*2.15,2.0,-.02),(.59,.72,1.17),stone,20,12))
    add("dormin","head",plate("Fractured cheek",(sign*.59,.82,-.91),.42,.66,.17,stone,1 if sign<0 else 2),
        plate("Heavy slanted brow",(sign*.48,1.60,-.99),.48,.22,.15,edge,3 if sign<0 else 4),
        ellipsoid("Burning recessed eye",(sign*.41,1.37,-1.091),(.16,.075,.027),amber,16,8),
        tube("Sweeping ramlike horn",[(sign*.91,1.72,-.18),(sign*1.28,2.16,-.12),(sign*1.70,2.62,.03),(sign*1.95,3.18,.13),(sign*1.80,3.72,.18),(sign*1.52,4.13,.26)],[.34,.30,.255,.19,.105,.008],horn,12))
add("dormin","head",plate("Angular nose bridge",(0,1.07,-1.05),.21,.47,.25,stone,9),
    tube("Recessed mouth fissure",[(-.50,.55,-1.02),(0,.47,-1.10),(.50,.55,-1.02)],[.055,.041,.055],seam,7),
    plate("Heavy broken chin",(0,.24,-.9),.51,.30,.15,obsidian,17))
for sign,side in [(1,"l"),(-1,"r")]:
    add("dormin","upper_arm_"+side,loft_y("Long sinewy upper arm",[
        (.11,.58,.61,0,0),(-.25,.77,.75,0,0),(-1.1,.78,.71,0,0),(-2.4,.61,.62,0,0),(-3.75,.55,.56,0,0),(-4.15,.47,.49,0,0)],dark,24))
    add("dormin","forearm_"+side,loft_y("Heavy tapered forearm",[
        (.1,.54,.53,0,0),(-.45,.67,.62,0,0),(-1.2,.70,.69,0,0),(-2.5,.61,.58,0,0),(-3.8,.42,.43,0,0),(-4.15,.36,.39,0,0)],dark,24))
    for k,(x,y,sx,sy) in enumerate([(sign*.31,-1.1,.51,.90),(sign*.21,-2.71,.40,.73)]):
        add("dormin","forearm_"+side,plate("Layered wrist armour",(x,y,-.62),sx,sy,.17,stone,k+30))
    add("dormin","hand_"+side,ellipsoid("Broad articulated palm",(0,-.54,0),(.64,.72,.54),obsidian,24,12))
    for k in range(4):
        x=(k-1.5)*.265
        add("dormin","hand_"+side,tube("Long knuckled finger",[(x,-.82,-.22),(x*1.12,-1.19,-.27),(x*1.19,-1.53,-.39),(x*1.15,-1.72,-.51)],[.145,.132,.105,.04],stone,8))
    add("dormin","hand_"+side,tube("Opposing hooked thumb",[(sign*.49,-.22,.03),(sign*.77,-.63,-.16),(sign*.81,-.97,-.28)],[.21,.18,.095],stone,9))
    add("dormin","thigh_"+side,loft_y("Muscular pillar thigh",[
        (.04,.65,.69,0,0),(-.35,.90,.90,0,0),(-1.17,.95,.92,0,0),(-2.3,.82,.81,0,0),(-3.45,.59,.61,0,0),(-3.82,.52,.53,0,0)],dark,28))
    add("dormin","shin_"+side,loft_y("Tapered calf and ankle",[
        (.10,.52,.55,0,0),(-.37,.76,.78,0,.02),(-1.18,.82,.81,0,0),(-2.24,.60,.61,0,0),(-3.15,.43,.45,0,0),(-3.48,.38,.4,0,0)],dark,28))
    for k,(x,y,sx,sy) in enumerate([(-.16,-.69,.52,.71),(.12,-1.77,.49,.64),(-.10,-2.8,.31,.40)]):
        add("dormin","shin_"+side,plate("Cracked shin greave",(x,y,-.78),sx,sy,.17,stone,k+44))
    for k in range(3):
        add("dormin","thigh_"+side,plate("Broken thigh carapace",(0,-.83-k*.78,-.92),.69,.57,.17,obsidian,k+51))
    add("dormin","foot_"+side,loft_y("Weight-bearing rock foot",[
        (-.38,.72,1.57,0,-.85),(-.20,.81,1.72,0,-.85),(.07,.78,1.64,0,-.80),(.31,.61,1.24,0,-.59)],obsidian,28,2.8))
    for k in range(3):
        add("dormin","foot_"+side,ellipsoid("Heavy split stone toe",((k-1)*.48,-.01,-1.99),(.26,.275,.59),stone,16,10))
    # Route fur remains below the analytic grip surface, never hiding a sigil.
    for bone,span,radius,count in [("shin_"+side,3.05,.81,34),("thigh_"+side,3.35,.95,31)]:
        control=[(-3.48,.40),(-3.15,.45),(-2.24,.61),(-1.18,.82),(-.37,.78),(.10,.55)] if bone.startswith("shin") else [(-3.82,.53),(-3.45,.61),(-2.3,.81),(-1.17,.92),(-.35,.90),(.04,.69)]
        def contour(at):
            for a,b in zip(control,control[1:]):
                if a[0]<=at<=b[0]:
                    t=(at-a[0])/(b[0]-a[0]);return a[1]*(1-t)+b[1]*t
            return control[0][1]
        for k in range(count):
            y=-.22-rng.random()*span; angle=rng.uniform(.35,math.pi-.35)
            coords=[(math.cos(angle)*(contour(y-d)+.016),y-d,math.sin(angle)*(contour(y-d)+.016)) for d in [0,.13,.26]]
            add("dormin",bone,tube("Laid calf climbing hair",coords,[.023,.017,.003],dark,5))
    for k in range(14):
        y=-.7-k*.21
        add("dormin","upper_arm_"+side,tuft("Arm shadow fringe",(sign*.61,y,.19),(sign*.86,y-.43,.20),.31,dark))
# Baked hair normals finish the continuous rear climbing mantle. Tiny partly
# embedded filaments are omitted to avoid self-shadow streaks along the route.
# A ragged mane frames the shoulders; the central rear route and crown remain open.
for sign in [-1,1]:
    for k in range(18):
        x=sign*(1.24+k*.047)
        length=rng.uniform(1.2,2.3)
        add("dormin","chest",tube("Long draping shoulder mane",[(x,2.47,1.53),(x+sign*.10,2.0,1.83),(x+sign*.08,2.47-length*.72,1.92),(x+sign*.045,2.47-length,1.86)],[.065,.068,.041,.003],dark,7))
for k in range(14):
    x=(k-6.5)*.15
    add("dormin","hips",tuft("Uneven loin fringe",(x,-.45,-1.03),(x*1.05,-1.14,-1.1),.28,dark))
add("dormin","chest",tube("Cool fissure on mineral front",[(-.08,.20,-1.60),(.12,.51,-1.63),(-.06,.98,-1.61),(.19,1.37,-1.64),(-.05,1.90,-1.60),(.09,2.45,-1.59)],[.013,.014,.009,.011,.008,.003],blue,5))

HORSE_REST={"body":(0,1.27,0),"neck":(0,1.49,-.95),"head":(0,2.39,-.95)}
for side,x,z in [("fl",-.24,-.78),("fr",.24,-.78),("rl",-.24,.78),("rr",.24,.78)]:
    for suffix,y in [("up",1.17),("low",.55),("hoof",-.03)]: HORSE_REST[side+"_"+suffix]=(x,y,z)
DORMIN_REST={"hips":(0,8,0),"spine":(0,9,0),"chest":(0,11.2,0),"neck":(0,14,0),"head":(0,15,0)}
for side,sign in [("l",1),("r",-1)]:
    for bone,y,x in [("upper_arm",13.5,2.9),("forearm",9.3,2.9),("hand",5.1,2.9),("thigh",7.6,1.3),("shin",3.8,1.3),("foot",.4,1.3)]:
        DORMIN_REST[bone+"_"+side]=(sign*x,y,0)

manifest=[]; source_variants=[]
for actor,bones in parts.items():
    for bone,objects in bones.items():
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objects: obj.select_set(True)
        bpy.context.view_layer.objects.active=objects[0]
        if len(objects)>1:
            bpy.ops.object.join()
        base=bpy.context.object; base.name=f"{actor}_{bone}_LOD0"
        bpy.context.scene.cursor.location=(0,0,0)
        bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
        bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
        if actor=="agro" and bone=="head":
            # Equine ears and skull keep human-scale proportions in the existing rig.
            for vert in base.data.vertices:
                vert.co.y *= .88
                if vert.co.z>.20:
                    vert.co.z=.20+(vert.co.z-.20)*.70
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=1.05, island_margin=.008)
        bpy.ops.object.mode_set(mode="OBJECT")
        tr=base.modifiers.new("Game triangles","TRIANGULATE");bpy.ops.object.modifier_apply(modifier=tr.name)
        variants=[]; counts=[]; bounds=[]; paths=[]
        for lod,ratio in enumerate([1,.46,.18]):
            obj=base
            if lod:
                obj=base.copy();obj.data=base.data.copy();bpy.context.collection.objects.link(obj)
                obj.name=f"{actor}_{bone}_LOD{lod}"
                bpy.context.view_layer.objects.active=obj
                dec=obj.modifiers.new("LOD reduction","DECIMATE");dec.ratio=ratio
                bpy.ops.object.modifier_apply(modifier=dec.name)
            if actor=="dormin" and bone=="chest":
                # The spine disc crosses the neighbouring segment's lower edge.
                # Sculpt a rear scallop after each reduction; thin fibres keep
                # real thickness instead of overlapping Boolean shell fragments.
                for vert in obj.data.vertices:
                    x,y,z=vert.co.x,vert.co.z,-vert.co.y
                    distance=math.hypot(x,y+.4)
                    if z>1.13 and distance<1.08:
                        t=max(0,min(1,(distance-.93)/.15))
                        blend=1-t*t*(3-2*t)
                        recessed=1.13+(z-1.13)*.02
                        vert.co.y=-(z*(1-blend)+recessed*blend)
            obj.data.validate(verbose=False,clean_customdata=False);obj.data.update();obj.data.calc_loop_triangles()
            counts.append(len(obj.data.loop_triangles))
            p=[(vert.co.x,vert.co.z,-vert.co.y) for vert in obj.data.vertices]
            bounds.append({"min":[round(min(a[i] for a in p),5) for i in range(3)],"max":[round(max(a[i] for a in p),5) for i in range(3)]})
            bpy.ops.object.select_all(action="DESELECT");obj.select_set(True)
            rel=f"models/{actor}_v3/{bone}_lod{lod}.glb";paths.append("res://"+rel)
            bpy.ops.export_scene.gltf(filepath=str(ROOT/rel),export_format="GLB",use_selection=True,export_materials="EXPORT",export_yup=True,export_animations=False,export_lights=False,export_cameras=False)
            obj.hide_set(lod>0);obj.hide_render=lod>0;variants.append(obj)
        manifest.append({"actor":actor,"bone":bone,"units":"metres","render_only":True,"triangle_counts":counts,"model_paths":paths,"aabb_per_lod":bounds,"bone_rest_origin":(HORSE_REST if actor=="agro" else DORMIN_REST)[bone]})
        source_variants.append((actor,bone,variants))

# Keep source geometry editable, grouped by bone and displayed in a clear rest pose.
for actor in ["agro","dormin"]:
    collection=bpy.data.collections.new(actor.title()+" V3 bone-local source");bpy.context.scene.collection.children.link(collection)
    for act,bone,variants in source_variants:
        if act!=actor:continue
        empty=bpy.data.objects.new(actor+"_"+bone+"_frame",None);collection.objects.link(empty)
        at=(HORSE_REST if actor=="agro" else DORMIN_REST)[bone]
        empty.location=v((at[0]+(-5 if actor=="agro" else 5),at[1],at[2]))
        if actor=="agro" and bone=="neck":
            empty.rotation_euler.x=-.75
        if actor=="agro" and bone=="head":
            # Blender X rotation has the same handedness after the axis conversion.
            p=Vector(HORSE_REST["neck"])+Matrix.Rotation(-.75,3,"X")@Vector((0,.9,0))
            empty.location=v((p.x-5,p.y,p.z));empty.rotation_euler.x=.125
        for obj in variants:
            for old in list(obj.users_collection):old.objects.unlink(obj)
            collection.objects.link(obj);obj.parent=empty
scene=bpy.context.scene
scene["pipeline"]="Original organic Agro and Dormin interpretation, rigid bone-local 3LOD GLB"
scene["runtime"]="No collision or gameplay. Agro saddle top y=.43 in body bone; Dormin crown y=2.46 < sigil y=2.52; back fibre <=z1.22 < sigil z1.31."
scene.render.engine="BLENDER_EEVEE_NEXT"
scene.world.color=(.18,.18,.18)
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE),compress=True)
totals={}
for actor in parts:
    actor_items=[item for item in manifest if item["actor"]==actor]
    totals[actor]={"bone_pieces":len(actor_items),"triangle_counts":[sum(item["triangle_counts"][lod] for item in actor_items) for lod in range(3)],
        "glb_bytes":sum((ROOT/path.removeprefix("res://")).stat().st_size for item in actor_items for path in item["model_paths"])}
(ROOT/"assets/agro_dormin_v3_manifest.json").write_text(json.dumps({
    "units":"metres","axes":"Godot Y up; forward -Z","source":"res://art/source/agro_dormin_v3.blend",
    "generator":"tools/art/generate_agro_dormin_v3.py","original_designs":True,"lod_ratios":[1,.46,.18],
    "render_only":True,"agro_saddle_top_local":[0,.43,-.05],"dormin_sigil_clearance":{"crown_max_y":2.46,"crown_sigil_y":2.52,"back_max_z":1.22,"back_sigil_z":1.31,"neighbouring_chest_recess_z":1.15},
    "totals":totals,"materials":"PBR roughness/metallic, baked 256px albedo and tangent normal PNG inputs, embedded in GLB and packed in Blender source",
    "texture_sources":["res://"+path.relative_to(ROOT).as_posix() for path in sorted((ROOT/"textures/agro_dormin_v3").glob("*.png"))],
    "items":manifest
},indent=2)+"\n",encoding="utf-8")
print("AGRO_DORMIN_V3_OK",len(manifest),"bone pieces;",sum(a["triangle_counts"][0] for a in manifest),"LOD0 triangles")
print("AGRO_DORMIN_V3_TOTALS",json.dumps(totals))
