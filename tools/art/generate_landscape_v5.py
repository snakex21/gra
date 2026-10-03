"""Original landscape craft pack. Export an existing .blend without replacing edits.

python tools/run_local.py blender --python tools/art/generate_landscape_v5.py
Add -- --regenerate only to deliberately rebuild the editable source.
Geometry-only GLBs share the external 1024px Godot atlas material. No colliders.
"""
import bpy
import bmesh
import hashlib
import json
import math
import random
import struct
import sys
from pathlib import Path
from mathutils import Vector
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art/source/landscape_v5.blend"
for name in ["art/source", "art/screenshots/landscape_v5", "models/landscape_v5", "textures/landscape_v5", "materials/landscape_v5", "assets"]:
    (ROOT / name).mkdir(parents=True, exist_ok=True)
KINDS = ["oak", "wind_tree", "pine", "dead_tree", "rock_shelf", "rock_split", "ruin_arch", "ruin_support", "ruin_parapet"]
LIMITS = [3000, 1000, 200]

def v(p):
    return Vector((p[0], -p[2], p[1]))

def gp(p):
    return (p.x, p.z, -p.y)

def uv_tile(tile, u, w):
    # Tile-edge padding keeps coarse mip levels from bleeding bright stone into leaves.
    return ((tile % 4 + .04 + .92 * u) / 4, (tile // 4 + .04 + .92 * w) / 2)

def mesh(name, points, faces, tile, smooth=False):
    data = bpy.data.meshes.new(name)
    data.from_pydata([v(p) for p in points], [], faces)
    data.update()
    bm = bmesh.new(); bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces)); bm.to_mesh(data); bm.free()
    ob = bpy.data.objects.new(name, data); bpy.context.collection.objects.link(ob)
    data.materials.append(bpy.data.materials["Landscape V5 shared atlas"])
    layer = data.uv_layers.new(name="LandscapeAtlasUV")
    for poly in data.polygons:
        poly.use_smooth = smooth
        # Continuous world projection within a part, scaled to its dominant face.
        indices = [data.loops[index].vertex_index for index in poly.loop_indices]
        coords = [Vector(points[i]) for i in indices]
        normal = (coords[1] - coords[0]).cross(coords[2] - coords[0])
        axis = max(range(3), key=lambda i: abs(normal[i]))
        axes = [i for i in range(3) if i != axis]
        lo = [min(p[i] for p in points) for i in axes]
        span = [max(.01, max(p[i] for p in points) - lo[j]) for j, i in enumerate(axes)]
        for index in poly.loop_indices:
            p = points[data.loops[index].vertex_index]
            layer.data[index].uv = uv_tile(tile, (p[axes[0]]-lo[0])/span[0], (p[axes[1]]-lo[1])/span[1])
    return ob

def tube(name, path, radii, tile=0, sides=6):
    path = [Vector(p) for p in path]; points = []
    for i, p in enumerate(path):
        direction = (path[min(i+1, len(path)-1)] - path[max(0, i-1)]).normalized()
        reference = Vector((0, 1, 0)) if abs(direction.y) < .9 else Vector((1, 0, 0))
        a = direction.cross(reference).normalized(); b = direction.cross(a).normalized()
        for j in range(sides):
            points.append(p + radii[i] * (a*math.cos(j*math.tau/sides)+b*math.sin(j*math.tau/sides)))
    faces = []
    for i in range(len(path)-1):
        for j in range(sides):
            faces.append((i*sides+j, i*sides+(j+1)%sides, (i+1)*sides+(j+1)%sides, (i+1)*sides+j))
    faces += [tuple(reversed(range(sides))), tuple((len(path)-1)*sides+j for j in range(sides))]
    return mesh(name, points, faces, tile, True)

def foliage(name, center, scale, seed, tile=2, pine=False):
    rng = random.Random(seed); points = []; faces = []; sides = 10 if not pine else 8
    # Uneven, flattened lobes form separated foliage masses rather than spherical crowns.
    rings = [(-.78, .27), (-.20, .93), (.23, 1.0), (.78, .24)] if not pine else [(-.75, .92), (-.36, 1), (.25, .64), (.9, .08)]
    phase = rng.random()*math.tau
    for j, (height, radius) in enumerate(rings):
        for i in range(sides):
            angle = i*math.tau/sides+phase; wobble = rng.uniform(.70, 1.19)
            points.append((center[0]+math.cos(angle)*scale[0]*radius*wobble,
                center[1]+(height+rng.uniform(-.13,.13))*scale[1], center[2]+math.sin(angle)*scale[2]*radius*wobble))
    for ring in range(len(rings)-1):
        for i in range(sides): faces.append((ring*sides+i, ring*sides+(i+1)%sides, (ring+1)*sides+(i+1)%sides, (ring+1)*sides+i))
    faces += [tuple(reversed(range(sides))), tuple((len(rings)-1)*sides+i for i in range(sides))]
    return mesh(name, points, faces, tile, not pine)

def chipped_block(name, center, size, seed, tile=5, bevel=.10):
    rng = random.Random(seed)
    points = [(center[0]+x*size[0]/2+rng.uniform(-.045,.045), center[1]+y*size[1]/2+rng.uniform(-.045,.045), center[2]+z*size[2]/2+rng.uniform(-.045,.045)) for z in [-1,1] for y in [-1,1] for x in [-1,1]]
    ob = mesh(name, points, [(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)], tile)
    bpy.context.view_layer.objects.active = ob
    mod = ob.modifiers.new("Worn broken edges", "BEVEL"); mod.width=bevel; mod.segments=1
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return ob

def build_textures():
    size=1024; yy,xx=np.mgrid[0:512,0:256]; noise=np.random.default_rng(85091).random((512,256))
    colors=[(.18,.135,.087),(.29,.275,.225),(.11,.17,.073),(.19,.235,.095),(.31,.335,.31),(.43,.455,.40),(.16,.225,.10),(.25,.29,.265)]
    albedo=np.ones((size,size,4), dtype=np.float32); normals=np.ones_like(albedo); roughness=np.ones_like(albedo)
    for tile, color in enumerate(colors):
        if tile<2:
            grain=np.sin(xx*.28+np.sin(yy*.028)*2.6)+.35*np.sin(xx*.87+yy*.012)
            shade=.83+.095*grain+.055*noise; height=.12*grain+.022*noise
        elif tile<4:
            leaf=np.sin(xx*.23+yy*.35)*np.sin(xx*.41-yy*.19)
            shade=.82+.16*leaf+.09*noise; height=.02*leaf
        else:
            broad=np.sin(xx*.057+np.sin(yy*.018)*4)*np.sin(yy*.051)
            cracks=np.minimum(np.abs(np.sin(xx*.068+np.sin(yy*.041)*1.8)),np.abs(np.sin(yy*.075+xx*.014)))
            shade=.90+.09*broad+.07*noise-.22*(cracks<.045); height=.09*broad+.025*noise-.07*(cracks<.045)
            if tile==6: shade=.76+.19*broad+.10*noise
        region=np.s_[tile//4*512:(tile//4+1)*512, tile%4*256:(tile%4+1)*256]
        for c in range(3):
            linear=np.clip(color[c]*shade,0,1)
            albedo[region][:,:,c]=np.where(linear<=.0031308,linear*12.92,1.055*linear**(1/2.4)-.055)
        dy,dx=np.gradient(height); normal=np.stack((-dx*.8,-dy*.8,np.ones_like(height)),axis=-1)
        normal/=np.linalg.norm(normal,axis=-1)[:,:,None]
        normals[region][:,:,:3]=normal*.5+.5
        roughness[region][:,:,:3]=np.clip(.86+.09*(1-shade),.78,.99)[:,:,None]
    for suffix, rgba in [("albedo",albedo),("normal",normals),("roughness",roughness)]:
        image=bpy.data.images.new("landscape_atlas_"+suffix,width=size,height=size)
        if suffix!="albedo": image.colorspace_settings.name="Non-Color"
        image.pixels.foreach_set(rgba.ravel()); image.file_format="PNG"
        image.filepath_raw=str(ROOT/"textures/landscape_v5"/("landscape_atlas_"+suffix+".png")); image.save();image.pack()
    mat=bpy.data.materials.new("Landscape V5 shared atlas"); mat.use_nodes=True;mat.diffuse_color=(.25,.31,.20,1)
    principled=mat.node_tree.nodes.get("Principled BSDF"); principled.inputs["Roughness"].default_value=.92
    for suffix, socket in [("albedo","Base Color"),("roughness","Roughness")]:
        node=mat.node_tree.nodes.new("ShaderNodeTexImage");node.image=bpy.data.images["landscape_atlas_"+suffix]
        mat.node_tree.links.new(node.outputs["Color"],principled.inputs[socket])
    node=mat.node_tree.nodes.new("ShaderNodeTexImage");node.image=bpy.data.images["landscape_atlas_normal"]
    normal=mat.node_tree.nodes.new("ShaderNodeNormalMap")
    mat.node_tree.links.new(node.outputs["Color"],normal.inputs["Color"]);mat.node_tree.links.new(normal.outputs["Normal"],principled.inputs["Normal"])

def make_source():
    bpy.ops.object.select_all(action="SELECT");bpy.ops.object.delete(use_global=False)
    build_textures(); rng=random.Random(9917)
    source=bpy.data.collections.new("Landscape V5 editable originals");bpy.context.scene.collection.children.link(source)
    parts={kind:[] for kind in KINDS}
    for kind in ["oak","wind_tree","dead_tree"]:
        dead=kind=="dead_tree"; wind=kind=="wind_tree"; height=12 if kind=="oak" else 15
        tile=1 if dead else 0
        main=[(math.sin(i*.5)*.3+(i/8)**2*(2.8 if wind else .5),height*i/8,math.sin(i*.8)*.28) for i in range(9)]
        parts[kind].append(tube(kind+" twisted trunk",main,[.64*(1-i/9)**.8+.02 for i in range(9)],tile,8))
        for i in range(5):
            angle=i*math.tau/5+.21
            parts[kind].append(tube(kind+" spreading root",[(0,.4,0),(math.cos(angle)*.85,.17,math.sin(angle)*.85),(math.cos(angle)*1.8,-.05,math.sin(angle)*1.8)],[.28,.20,.03],tile,5))
        for i in range(7):
            angle=i*2.4; origin=Vector(main[3+i%4]); length=3.2+rng.random()*2.2
            direction=Vector((math.cos(angle),.22 if dead else .40,math.sin(angle)))
            end=origin+direction*length+Vector((1.8 if wind else 0,2.3,0))
            path=[origin,origin+direction*.7,origin.lerp(end,.48),origin.lerp(end,.77),end]
            parts[kind].append(tube(kind+" main bough "+str(i),path,[.23,.21,.16,.09,.025],tile,6))
            if not dead: parts[kind].append(foliage(kind+" outer crown "+str(i),end,(2.0,1.3,1.8),i+21,3 if wind else 2))
            for j in range(2):
                side_angle=angle+(1 if j else -1)*.7
                begin=path[2+j]; distal=begin+Vector((math.cos(side_angle)*2.1,1.2,math.sin(side_angle)*2.1))
                parts[kind].append(tube(kind+" branching twig "+str(i)+" "+str(j),[begin,begin.lerp(distal,.65),distal],[.095,.055,.012],tile,5))
                if not dead:parts[kind].append(foliage(kind+" leaf lobe "+str(i)+" "+str(j),distal,(1.7,1.05,1.5),i*13+j+62,2 if j else 3))
                elif i<3:
                    tip=distal+Vector((.65,1.1,-.1));parts[kind].append(tube("dead slender fork",[distal,tip],[.04,.006],tile,4))
        if dead:
            parts[kind].append(tube("dead snapped exposed heartwood",[(.25,10,.18),(1.1,13.5,.2),(1.4,14.0,.1)],[.26,.13,.01],1,6))
    parts["pine"].append(tube("pine crooked trunk",[(0,0,0),(.15,4,-.1),(-.1,8,.25),(.1,12,0),(.2,16,0)],[.48,.35,.25,.13,.015],0,8))
    for tier in range(5):
        y=4.2+tier*2.1; reach=4.5-tier*.65
        for j in range(4):
            angle=j*math.tau/4+tier*.6; end=(math.cos(angle)*reach,y+.3,math.sin(angle)*reach)
            parts["pine"].append(tube("pine tier branch",[(0,y,0),(end[0]*.6,y-.3,end[2]*.6),end],[.11,.065,.015],0,5))
            parts["pine"].append(foliage("pine ragged needle spire",end,(reach*.56,1.6,reach*.52),tier*7+j+299,2,True))
    parts["pine"].append(foliage("pine tapered leader",(.2,14.8,0),(1.6,2.3,1.4),993,2,True))
    for kind in ["rock_shelf","rock_split"]:
        seed=551 if kind=="rock_shelf" else 881; rng=random.Random(seed)
        for piece in range(2 if kind=="rock_split" else 1):
            points=[]; sides=10
            rows=[(-.15,1.0),(.35,1.12),(1.05,.98),(1.65,.88),(2.15,.54)]
            for ring,(y,r) in enumerate(rows):
                for i in range(sides):
                    angle=i*math.tau/sides;dist=r*rng.uniform(.91,1.10)
                    points.append((math.cos(angle)*dist*(2.0 if kind=="rock_shelf" else 1.2)+piece*2.05,
                        y+rng.uniform(-.10,.10),math.sin(angle)*dist*(1.5 if kind=="rock_shelf" else 1.1)))
            faces=[]
            for ring in range(len(rows)-1):
                for i in range(sides):faces.append((ring*sides+i,ring*sides+(i+1)%sides,(ring+1)*sides+(i+1)%sides,(ring+1)*sides+i))
            faces += [tuple(reversed(range(sides))),tuple((len(rows)-1)*sides+i for i in range(sides))]
            parts[kind].append(mesh(kind+" angular stratified mass",points,faces,4))
            # Low patches are actual opaque moss geometry, without leaf alpha cards.
            parts[kind].append(foliage(kind+" low moss crust",(piece*2.05+.4,1.9,.2),(.72,.075,.7),seed+3,6))
    for tier in range(7):
        for side in [-1,1]:
            parts["ruin_arch"].append(chipped_block("arch aged pier course",(side*3.2,tier*.78+.39,0),(1.3,.75,1.65),tier*13+int(side),5))
    for i in range(13):
        a0=i*math.pi/13; a1=(i+1)*math.pi/13; points=[]
        for z in [-.82,.82]:
            for radius,angle in [(2.55,a0+.012),(3.82,a0+.008),(3.82,a1-.008),(2.55,a1-.012)]:
                points.append((math.cos(angle)*radius,5.22+math.sin(angle)*radius,z))
        parts["ruin_arch"].append(mesh("arch cracked voussoir "+str(i),points,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],6 if i in [0,3,8] else 5))
    for tier in range(7):
        width=3.0-tier*.11
        parts["ruin_support"].append(chipped_block("support weathered masonry",(0,tier*.82+.40,0),(width,.80,2.7),920+tier,6 if tier==2 else 5))
    parts["ruin_support"].append(chipped_block("support carved cap",(0,6.0,0),(3.5,.52,3.1),940,7,.08))
    for tier in range(3):
        for i in range(2):
            parts["ruin_parapet"].append(chipped_block("parapet split course",(0,tier*.67+.335,(i-.5)*2.0),(2.0,.65,1.98),1200+tier*7+i,6 if tier==0 and i==0 else 5,.045))
    parts["ruin_parapet"].append(chipped_block("parapet chamfered cap",(0,2.13,0),(2.13,.26,4.0),1301,5,.07))
    for index,kind in enumerate(KINDS):
        collection=bpy.data.collections.new("Editable "+kind);source.children.link(collection)
        root=bpy.data.objects.new("LandscapeSource_"+kind,None);collection.objects.link(root);root["asset_kind"]=kind
        root.location=v(((index%5)*10,0,-(index//5)*15))
        for ob in parts[kind]:
            for old in list(ob.users_collection):old.objects.unlink(ob)
            collection.objects.link(ob);ob.parent=root
    bpy.context.scene.unit_settings.system="METRIC"
    bpy.context.scene.unit_settings.scale_length=1
    bpy.context.scene["contract"]="Original render-only landscape craft. Godot Y-up, one shared opaque external atlas, three LOD. Root foot at Y=0."

def silhouette_lod(kind, lod):
    """Solid silhouettes for masonry, avoiding collapsed/disconnected stone slivers."""
    if kind=="ruin_arch":
        steps=13 if lod==1 else 9; points=[];faces=[]
        for i in range(steps+1):
            angle=math.pi*i/steps
            for radius,z in [(2.55,-.82),(3.82,-.82),(2.55,.82),(3.82,.82)]:
                points.append((math.cos(angle)*radius,5.22+math.sin(angle)*radius,z))
        for i in range(steps):
            a=i*4;b=(i+1)*4
            faces += [(a,b,b+1,a+1),(a+2,a+3,b+3,b+2),(a,a+2,b+2,b),(a+1,b+1,b+3,a+3)]
        faces += [(0,1,3,2),(steps*4,steps*4+2,steps*4+3,steps*4+1)]
        for side in [-1,1]:
            start=len(points)
            points += [(side*3.2+x*.65,y,z) for z in [-.82,.82] for y in [0,5.22] for x in [-1,1]]
            faces += [tuple(start+i for i in f) for f in [(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)]]
        return mesh("Solid arch silhouette LOD"+str(lod),points,faces,5)
    if kind=="ruin_support":
        rows=[(0,3,2.7),(1.7,2.78,2.7),(3.4,2.56,2.7),(5.73,2.34,2.7),(5.74,3.5,3.1),(6.26,3.5,3.1)] if lod==1 else [(0,3,2.7),(5.73,2.34,2.7),(5.74,3.5,3.1),(6.26,3.5,3.1)]
    else:
        rows=[(0,2,4),(2,2,4),(2,2.13,4),(2.26,2.13,4)] if lod==1 else [(0,2,4),(2.26,2.13,4)]
    points=[];faces=[]
    for y,width,depth in rows:points += [(-width/2,y,-depth/2),(width/2,y,-depth/2),(width/2,y,depth/2),(-width/2,y,depth/2)]
    for i in range(len(rows)-1):
        for j in range(4):faces.append((i*4+j,i*4+(j+1)%4,(i+1)*4+(j+1)%4,(i+1)*4+j))
    faces += [(3,2,1,0),tuple((len(rows)-1)*4+j for j in range(4))]
    return mesh("Solid masonry silhouette LOD"+str(lod),points,faces,5)

if SOURCE.exists() and "--regenerate" not in sys.argv:
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    preserved_sha=hashlib.sha256(SOURCE.read_bytes()).hexdigest()
else:
    make_source();bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE),compress=True)
    preserved_sha=hashlib.sha256(SOURCE.read_bytes()).hexdigest()

# Export evaluated copies, leaving artist source geometry and materials untouched.
placeholder=bpy.data.materials.new("Landscape external atlas placeholder")
placeholder.diffuse_color=(.32,.36,.26,1);placeholder.use_nodes=True
records=[];temporary=[]
for kind in KINDS:
    root=next(ob for ob in bpy.data.objects if ob.get("asset_kind")==kind)
    copies=[]
    for source in root.children_recursive:
        if source.type!="MESH":continue
        evaluated=source.evaluated_get(bpy.context.evaluated_depsgraph_get())
        data=bpy.data.meshes.new_from_object(evaluated)
        ob=bpy.data.objects.new("Export_"+kind,data);bpy.context.scene.collection.objects.link(ob)
        ob.matrix_world=root.matrix_world.inverted() @ source.matrix_world
        copies.append(ob)
    bpy.ops.object.select_all(action="DESELECT")
    for ob in copies:ob.select_set(True)
    bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();base=bpy.context.object
    bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    base.data.materials.clear();base.data.materials.append(placeholder)
    for poly in base.data.polygons:poly.material_index=0
    tr=base.modifiers.new("Export triangles","TRIANGULATE");bpy.ops.object.modifier_apply(modifier=tr.name)
    base.data.calc_loop_triangles(); original_count=len(base.data.loop_triangles)
    paths=[];counts=[]
    for lod,limit in enumerate(LIMITS):
        if lod and kind.startswith("ruin_"):
            ob=silhouette_lod(kind,lod);ob.data.materials.clear();ob.data.materials.append(placeholder)
        else:
            ob=base.copy();ob.data=base.data.copy();bpy.context.scene.collection.objects.link(ob)
        bpy.context.view_layer.objects.active=ob
        target=min(original_count, limit if lod==0 else min(limit-12, max(48, int(original_count * (.40 if lod==1 else .12)))))
        if original_count>target and not (lod and kind.startswith("ruin_")):
            dec=ob.modifiers.new("Explicit affordable LOD","DECIMATE");dec.ratio=target/original_count
            bpy.ops.object.modifier_apply(modifier=dec.name)
        ob.name=kind+"_LOD"+str(lod)
        # Collapse can leave zero-area twig corners; clean those before counting
        # rather than allowing the exporter to silently discard triangles.
        bm=bmesh.new();bm.from_mesh(ob.data)
        bmesh.ops.dissolve_degenerate(bm,dist=.000001,edges=list(bm.edges))
        bmesh.ops.triangulate(bm,faces=list(bm.faces));bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
        bm.to_mesh(ob.data);bm.free();ob.data.validate();ob.data.update();ob.data.calc_loop_triangles()
        count=len(ob.data.loop_triangles);assert count<=limit,(kind,lod,count,limit)
        bpy.ops.object.select_all(action="DESELECT");ob.select_set(True)
        path="models/landscape_v5/"+kind+"_lod"+str(lod)+".glb"
        bpy.ops.export_scene.gltf(filepath=str(ROOT/path),export_format="GLB",use_selection=True,
            export_yup=True,export_materials="EXPORT",export_animations=False,export_cameras=False,export_lights=False)
        raw=(ROOT/path).read_bytes();length=struct.unpack_from("<I",raw,12)[0];doc=json.loads(raw[20:20+length])
        assert len(doc["meshes"])==1 and len(doc["meshes"][0]["primitives"])==1
        assert not doc.get("images"),(kind,"embedded texture")
        assert all("TEXCOORD_0" in p["attributes"] for p in doc["meshes"][0]["primitives"])
        assert sum(doc["accessors"][p["indices"]]["count"]//3 for p in doc["meshes"][0]["primitives"])==count
        paths.append("res://"+path);counts.append(count);temporary.append(ob)
    records.append({"kind":kind,"model_paths":paths,"triangle_counts":counts,"surfaces":1,
        "glb_bytes":sum((ROOT/path.removeprefix("res://")).stat().st_size for path in paths),
        "foot_origin":[0,0,0],"colliders":False,"embedded_images":0})
    temporary.append(base)
for ob in temporary:bpy.data.objects.remove(ob,do_unlink=True)
assert preserved_sha==hashlib.sha256(SOURCE.read_bytes()).hexdigest(),"Editable source changed during export"
report={"source":"res://art/source/landscape_v5.blend","source_sha256":preserved_sha,"units":"metres",
    "generator":"tools/art/generate_landscape_v5.py","original_designs":True,"render_only":True,
    "atlas_size":1024,"atlas_images":["res://textures/landscape_v5/landscape_atlas_"+s+".png" for s in ["albedo","normal","roughness"]],
    "material":"res://materials/landscape_v5/atlas.tres","opacity":"Opaque closed geometry; no alpha foliage cards",
    "triangle_limits":LIMITS,"items":records,"validation":"Actual indexed GLB triangles, one mesh/surface, UV stream, no embedded image, source SHA unchanged on export"}
(ROOT/"assets/landscape_v5_manifest.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
print("LANDSCAPE_V5_EXPORT_OK",[(r["kind"],r["triangle_counts"]) for r in records],flush=True)

# A separate catalogue render uses the editable source, never alters the .blend.
scene=bpy.context.scene;scene.render.engine="BLENDER_EEVEE_NEXT";scene.render.resolution_x=1600;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
scene.world.use_nodes=True;scene.world.node_tree.nodes["Background"].inputs["Color"].default_value=(.13,.16,.18,1);scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value=.45
data=bpy.data.lights.new("Landscape catalogue sun","SUN");data.energy=2.3;light=bpy.data.objects.new("Landscape catalogue sun",data);scene.collection.objects.link(light);light.rotation_euler=(.55,-.3,-.6)
camera=bpy.data.objects.new("Landscape catalogue camera",bpy.data.cameras.new("Landscape catalogue camera"));scene.collection.objects.link(camera);scene.camera=camera
camera.location=v((45,27,48));camera.rotation_euler=(v((20,5,-5))-camera.location).to_track_quat("-Z","Y").to_euler();camera.data.type="ORTHO";camera.data.ortho_scale=61
scene.render.image_settings.file_format="PNG";scene.render.filepath=str(ROOT/"art/screenshots/landscape_v5/catalogue.png")
bpy.ops.render.render(write_still=True)
print("LANDSCAPE_V5_COMPLETE",flush=True)
