"""Original rigid bat and firebird visuals; not reconstructed source-game assets."""
import bpy
import bmesh
import math
import random
import json
import sys
from pathlib import Path
from mathutils import Vector
ROOT = Path(__file__).resolve().parents[2]
if (ROOT / "art/source/cut_winged_guardians.blend").exists() and "--regenerate" not in sys.argv:
    raise SystemExit("Source exists; pass -- --regenerate to rebuild explicitly.")
for path in ["models/devil", "models/phoenix", "art/source", "assets"]:
    (ROOT / path).mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
rng = random.Random(120109)
bpy.context.scene.unit_settings.system = "METRIC"
def vec(p): return Vector((p[0], -p[2], p[1]))
def material(name, colour, emission=0):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*colour, 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = (*colour, 1)
    p.inputs["Roughness"].default_value = .88
    if emission:
        p.inputs["Emission Color"].default_value = (*colour, 1)
        p.inputs["Emission Strength"].default_value = emission
    return m
slate = material("Devil violet slate", (.27, .25, .33))
membrane = material("Devil blue membrane", (.19, .26, .30))
fur = material("Devil soft ridges", (.20, .17, .21))
ivory = material("Devil weathered horn", (.61, .59, .50))
bronze = material("Phoenix stone gold", (.58, .42, .21))
red = material("Phoenix crimson feather", (.58, .17, .05))
ember = material("Phoenix ember tips", (.96, .52, .08), .4)
warm_fur = material("Phoenix warm fur", (.39, .25, .10))
def mesh(name, vertices, faces, mat):
    data = bpy.data.meshes.new(name)
    data.from_pydata([vec(v) for v in vertices], [], faces)
    data.update()
    bm = bmesh.new(); bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(data); bm.free()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj
def block(name, center, size, mat, bevel=.06):
    bpy.ops.mesh.primitive_cube_add(size=1, location=vec(center))
    obj = bpy.context.object; obj.name = name
    obj.scale = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    mod = obj.modifiers.new("Worn edges", "BEVEL")
    mod.width = bevel; mod.segments = 1
    bpy.ops.object.modifier_apply(modifier=mod.name)
    obj.data.materials.append(mat)
    return obj
def rod(name, a, b, radius, mat):
    bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=radius, depth=(vec(b)-vec(a)).length, location=(vec(a)+vec(b))/2)
    obj = bpy.context.object; obj.name = name
    obj.rotation_euler = (vec(b)-vec(a)).to_track_quat("Z", "Y").to_euler()
    obj.data.materials.append(mat)
    return obj
def feather(name, start, end, width, mat):
    a, b = Vector(start), Vector(end)
    d = (b-a).normalized()
    side = d.cross(Vector((0,1,0))).normalized()*width/2
    middle = a.lerp(b,.40)
    verts = [a-side*.3, a+side*.3, middle+side, b, middle-side, middle+Vector((0,.11,0))]
    return mesh(name, verts, [(0,1,5),(1,2,5),(2,3,5),(3,4,5),(4,0,5),(0,4,3,2,1)], mat)
catalogue = []
manifest_items = []
def finish(kind, part, objects):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects: obj.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    bpy.ops.object.join()
    base=bpy.context.object; base.name=f"{kind}_{part}_LOD0"
    bpy.context.scene.cursor.location=(0,0,0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    tri=base.modifiers.new("Triangles","TRIANGULATE")
    bpy.ops.object.modifier_apply(modifier=tri.name)
    variants=[]
    for lod,ratio in enumerate([1,.55,.28]):
        obj=base
        if lod:
            obj=base.copy();obj.data=base.data.copy();bpy.context.collection.objects.link(obj)
            obj.name=f"{kind}_{part}_LOD{lod}"
            bpy.context.view_layer.objects.active=obj
            mod=obj.modifiers.new("LOD reduction","DECIMATE");mod.ratio=ratio
            bpy.ops.object.modifier_apply(modifier=mod.name)
        obj.data.validate(verbose=False, clean_customdata=False)
        obj.data.update()
        bpy.ops.object.select_all(action="DESELECT");obj.select_set(True)
        bpy.ops.export_scene.gltf(filepath=str(ROOT/f"models/{kind}/{part}_lod{lod}.glb"),export_format="GLB",use_selection=True,export_materials="EXPORT",export_yup=True,export_animations=False,export_lights=False,export_cameras=False)
        obj.hide_set(lod>0);obj.hide_render=lod>0
        variants.append(obj)
    catalogue.append((kind,part,variants))
    bounds = [tuple((v.co.x, v.co.z, -v.co.y)) for v in base.data.vertices]
    counts = []
    for obj in variants:
        obj.data.calc_loop_triangles()
        counts.append(len(obj.data.loop_triangles))
    manifest_items.append({
        "guardian": kind, "bone": part, "render_only": True,
        "model_paths": [f"res://models/{kind}/{part}_lod{lod}.glb" for lod in range(3)],
        "triangle_counts": counts,
        "aabb_min": [round(min(p[a] for p in bounds), 5) for a in range(3)],
        "aabb_max": [round(max(p[a] for p in bounds), 5) for a in range(3)],
        "lod_distances_m": [45, 100, 800],
        "placement": "Attach at identity transform to the named WingedGuardian BodySegment; gameplay shapes belong to the rig."
    })
for kind in ["devil","phoenix"]:
    stone, fluff = (slate,fur) if kind=="devil" else (bronze,warm_fur)
    obs=[block("Rigid fur climb volume",(0,0,0),(3.38,2.38,4.98),fluff,.07)]
    for x in [-1,1]:
        obs += [block("Stone shoulder plate",(x*1.63,.22,-.68),(.24,1.75,2.7),stone,.05), block("Skull cheek",(x*.62,.31,-2.83),(.34,.99,1.30),stone,.06)]
    obs.append(block("Brow crown",(0,.70,-3.15),(1.52,.33,1.10),stone,.06))
    obs.append(block("Blind face",(0,.22,-3.53),(.69,.86,.24),stone,.035))
    for row in range(11):
        for col in range(6):
            if abs(row-5)<2 and abs(col-2.5)<1.1: continue
            x=(col-2.5)*.47;z=-2.28+row*.44
            obs.append(mesh("Short fur seam",[(x-.19,1.19,z-.16),(x+.19,1.19,z-.16),(x+.13,1.24,z+.05),(x,1.27,z+.25),(x-.13,1.24,z+.05)],[(0,1,2,3,4)],fluff))
    if kind=="devil":
        for x in [-.62,.62]:
            obs.append(feather("Raised horn",(x,.82,-3.05),(x*1.22,2.05,-2.67),.52,ivory))
        for z in [-1.8,-.7,.7,1.8]:
            obs.append(block("Back carved ring",(0,1.205,z),(2.9,.035,.035),stone,.006))
    else:
        for x in [-.34,0,.34]:
            obs.append(feather("Flame crest",(x,.8,-2.9),(x*1.3,2.15,-2.2),.44,ember))
        for i in range(5):
            obs.append(feather("Low tail feather",((i-2)*.42,-.65,2.0),((i-2)*.92,-.74,4.0+(.7 if i==2 else 0)),.77,red if i%2 else ember))
    finish(kind,"body",obs)
    for side,label in [(-1,"wing_l"),(1,"wing_r")]:
        obs=[]
        if kind=="devil":
            edge=[(0,0,-1.1),(side*1.7,.04,-2.1),(side*3.2,.06,-3.15),(side*6.4,-.08,-2.7),(side*4.9,-.01,-.3),(side*5.8,-.02,2.2),(side*3.8,0,1.13),(side*3.0,0,2.08),(side*1.4,0,.9),(0,0,1.3)]
            center=(side*2.4,.07,-.12)
            skin = mesh("Scalloped bat membrane",[center]+edge,[(0,j+1,(j+1)%len(edge)+1) for j in range(len(edge))],membrane)
            bpy.context.view_layer.objects.active = skin
            shell = skin.modifiers.new("Membrane thickness", "SOLIDIFY")
            shell.thickness = .035
            shell.offset = 0
            bpy.ops.object.modifier_apply(modifier=shell.name)
            obs.append(skin)
            for tip in [edge[2],edge[3],edge[5],edge[7]]:
                obs.append(rod("Wing finger",(0,.1,-.7),tip,.085,slate))
        else:
            obs.append(rod("Splayed stone wing spar",(0,0,-.7),(side*5.7,.04,-1.7),.17,bronze))
            for i in range(10):
                start=(side*(.4+i*.47),.02,-.75-i*.055)
                end=(side*(1.3+i*.46),-.02,2.35-i*.24)
                obs.append(feather("Layered fire feather",start,end,.94,red if i%3 else ember))
        finish(kind,label,obs)
for kind,part,variants in catalogue:
    origin=vec((0 if kind=="devil" else 22,0,0))
    if part=="wing_l":origin+=vec((-1.6,.4,-.3))
    if part=="wing_r":origin+=vec((1.6,.4,-.3))
    for obj in variants:obj.location=origin
bpy.context.scene["pipeline"]="Original cut guardian interpretations; generate_cut_guardians.py"
bpy.context.scene["unit"]="metres; exported Godot Y-up"
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art/source/cut_winged_guardians.blend"),compress=True)
(ROOT / "assets/cut_winged_guardians_manifest.json").write_text(json.dumps({
    "units": "metres", "axes": "Godot Y up, local -Z toward head", "original_designs": True,
    "source": "res://art/source/cut_winged_guardians.blend",
    "generator": "tools/art/generate_cut_guardians.py", "items": manifest_items
}, indent=2) + "\n", encoding="utf-8")
print("CUT_GUARDIANS_OK",len(catalogue),"parts / 18 GLB")
