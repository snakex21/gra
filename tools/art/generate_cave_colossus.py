"""Original cave guardian stone ornaments, editable rigid segments. Local Blender only.

Collision and fur stay with the gameplay rig. The exported stone surfaces fit inside
its stone volumes; no model or texture is taken from the reference game.
"""
from pathlib import Path
import sys
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art/source/cave_colossus.blend"
if SOURCE.exists() and "--regenerate" not in sys.argv:
    raise SystemExit("Source exists; export hand edits or explicitly pass -- --regenerate")
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)

stone = bpy.data.materials.new("CaveGuardian_OriginalGranite")
stone.diffuse_color = (0.24, 0.29, 0.3, 1)

def block(name, center, size, bevel):
    # Game local (x,y,z) -> Blender (x,-z,y).
    bpy.ops.mesh.primitive_cube_add(size=1, location=(center[0], -center[2], center[1]))
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    mod = obj.modifiers.new("Authored worn edges", "BEVEL")
    mod.width = bevel
    mod.segments = 2
    bpy.ops.object.modifier_apply(modifier=mod.name)
    obj.data.materials.append(stone)
    return obj

specs = {
    "head": [("brow", (0, 1.68, -1.2), (1.75, .34, .3), .1),
             ("cheek_left", (-.82, 1.05, -1.13), (.3, 1.1, .48), .1),
             ("cheek_right", (.82, 1.05, -1.13), (.3, 1.1, .48), .1),
             ("nose", (0, 1.0, -1.35), (.42, .65, .3), .1)],
    "chest": [("breastplate", (0, 1.45, -1.63), (3.8, 2.2, .3), .12),
              ("rib_left", (-1.9, 1.4, -1.60), (.6, 2.35, .55), .15),
              ("rib_right", (1.9, 1.4, -1.60), (.6, 2.35, .55), .15)],
}
exports = ROOT / "models/cave_colossus"
exports.mkdir(parents=True, exist_ok=True)
for bone, parts in specs.items():
    collection = bpy.data.collections.new("Editable_" + bone)
    bpy.context.scene.collection.children.link(collection)
    nodes = [block(name, center, size, bevel) for name, center, size, bevel in parts]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in nodes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = nodes[0]
    bpy.ops.object.join()
    master = bpy.context.object
    bpy.context.scene.cursor.location = Vector((0, 0, 0))
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    master.name = "cave_" + bone + "_LOD0"
    for old in list(master.users_collection):
        old.objects.unlink(master)
    collection.objects.link(master)
    for level in range(3):
        obj = master if level == 0 else master.copy()
        if level:
            obj.data = master.data.copy()
            collection.objects.link(obj)
            obj.name = "cave_" + bone + f"_LOD{level}"
            bpy.context.view_layer.objects.active = obj
            mod = obj.modifiers.new("LOD", "DECIMATE")
            mod.ratio = .55 if level == 1 else .3
            bpy.ops.object.modifier_apply(modifier=mod.name)
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.export_scene.gltf(filepath=str(exports / f"cave_{bone}_lod{level}.glb"),
                                  export_format="GLB", use_selection=True, export_yup=True)
        obj.hide_set(level != 0)
        obj["original_design"] = "Original cave guardian stone detail"
        obj["game_bone"] = bone
bpy.context.scene.unit_settings.system = "METRIC"
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE))
print("Saved editable cave guardian and six rigid LOD exports")
