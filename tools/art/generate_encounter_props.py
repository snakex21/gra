"""Original encounter props, authored in metres in Godot coordinates.

Run: python tools/run_local.py blender --python tools/art/generate_encounter_props.py
The script touches only the Encounter Props source, exports, atlas and manifest.
No physics proxies, original-game models, downloads or external caches are used.
"""
import bpy
import bmesh
import json
import math
import random
import sys
from pathlib import Path
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
SEED = 12093
if (ROOT / "art/source/encounter_props.blend").exists() and "--regenerate" not in sys.argv:
    raise SystemExit("Encounter Props source already exists. Use -- --regenerate to rebuild this pack explicitly.")
for folder in ("art/source", "models/encounter_props", "textures/encounter_props", "materials/encounter_props", "assets"):
    (ROOT / folder).mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
for material in list(bpy.data.materials):
    bpy.data.materials.remove(material)
bpy.context.scene.unit_settings.system = "METRIC"
bpy.context.scene.unit_settings.scale_length = 1.0
rng = random.Random(SEED)

PALETTE = [("limestone", (.64, .61, .51)), ("aged_stone", (.46, .47, .42)),
           ("basalt", (.23, .28, .28)), ("sandstone", (.62, .49, .31)),
           ("calcite", (.72, .75, .65)), ("patina", (.29, .48, .43)),
           ("bronze", (.44, .36, .21)), ("amber", (.91, .64, .30))]
TILES = {name: i for i, (name, _) in enumerate(PALETTE)}
atlas = np.zeros((512, 1024, 3), np.float32)
emission = np.zeros_like(atlas)
for index, (name, colour) in enumerate(PALETTE):
    y, x = np.mgrid[0:256, 0:256].astype(float) / 256
    field = np.zeros((256, 256))
    nrng = np.random.default_rng(SEED + index)
    for frequency, amplitude in [(3, .06), (9, .025), (23, .012), (57, .004)]:
        grid = nrng.uniform(-1, 1, (frequency, frequency))
        xx, yy = x * frequency, y * frequency
        xi, yi = xx.astype(int), yy.astype(int)
        fx, fy = xx - xi, yy - yi
        fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
        field += amplitude * ((1 - fy) * ((1 - fx) * grid[yi % frequency, xi % frequency] + fx * grid[yi % frequency, (xi + 1) % frequency]) + fy * ((1 - fx) * grid[(yi + 1) % frequency, xi % frequency] + fx * grid[(yi + 1) % frequency, (xi + 1) % frequency]))
    field += nrng.normal(0, .004, (256, 256))
    # Fine strata in rock; a separate bronze tile avoids stone-like metal grain.
    if name not in ("bronze", "patina", "amber"):
        field -= .012 * (np.sin(y * 75 + np.sin(x * 11) * 2.4) > .97)
    at_y, at_x = (index // 4) * 256, (index % 4) * 256
    atlas[at_y:at_y + 256, at_x:at_x + 256] = np.clip(np.asarray(colour)[None, None, :] + field[:, :, None], .025, .96)
    if name == "amber":
        emission[at_y:at_y + 256, at_x:at_x + 256] = np.array((.77, .43, .12))


def image_file(name, pixels):
    image = bpy.data.images.new(name, width=pixels.shape[1], height=pixels.shape[0], alpha=True)
    rgba = np.ones((*pixels.shape[:2], 4), np.float32)
    rgba[:, :, :3] = np.where(pixels <= .04045, pixels / 12.92, ((pixels + .055) / 1.055) ** 2.4)
    image.pixels.foreach_set(rgba.ravel())
    image.filepath_raw = str(ROOT / "textures/encounter_props" / (name + ".png"))
    image.file_format = "PNG"
    image.save()
    return image


atlas_image = image_file("encounter_atlas", atlas)
emission_image = image_file("encounter_emission", emission)
mat = bpy.data.materials.new("EncounterProps_OriginalAtlas")
mat.use_nodes = True
nodes = mat.node_tree.nodes
principled = nodes.get("Principled BSDF")
principled.inputs["Roughness"].default_value = .88
albedo_node = nodes.new("ShaderNodeTexImage")
albedo_node.image = atlas_image
mat.node_tree.links.new(albedo_node.outputs["Color"], principled.inputs["Base Color"])
emission_node = nodes.new("ShaderNodeTexImage")
emission_node.image = emission_image
mat.node_tree.links.new(emission_node.outputs["Color"], principled.inputs["Emission Color"])
principled.inputs["Emission Strength"].default_value = 1.4


def vec(point):
    return Vector((point[0], -point[2], point[1]))


def uv_project(obj, tile):
    uv = obj.data.uv_layers.new(name="UVMap") if not obj.data.uv_layers else obj.data.uv_layers[0]
    index = TILES[tile]
    for face in obj.data.polygons:
        axis = max(range(3), key=lambda a: abs(face.normal[a]))
        axes = [a for a in range(3) if a != axis]
        coords = [obj.data.vertices[obj.data.loops[li].vertex_index].co for li in face.loop_indices]
        lows = [min(co[a] for co in coords) for a in axes]
        highs = [max(co[a] for co in coords) for a in axes]
        for li, co in zip(face.loop_indices, coords):
            u, v = [(co[a] - lo) / max(hi - lo, .001) for a, lo, hi in zip(axes, lows, highs)]
            # Four pixels of tile padding prevent mip bleeding into lamp emission.
            uv.data[li].uv = ((index % 4 + .035 + u * .93) / 4, (index // 4 + .035 + v * .93) / 2)


def mesh_object(name, verts, faces, tile):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([vec(v) for v in verts], [], faces)
    mesh.update()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    obj["atlas_tile"] = tile
    uv_project(obj, tile)
    return obj


def block(name, position, size, tile="limestone", bevel=.065, rotation=0, chip=.008):
    bpy.ops.mesh.primitive_cube_add(size=1, location=vec(position))
    obj = bpy.context.object
    obj.name = name
    obj.scale = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.rotation_euler.z = -rotation
    if bevel:
        modifier = obj.modifiers.new("Worn stone edges", "BEVEL")
        modifier.width = min(bevel, min(size) * .18)
        modifier.segments = 1
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    if chip:
        for vertex in obj.data.vertices:
            vertex.co += Vector([rng.uniform(-chip, chip) for _ in range(3)])
    obj.data.materials.append(mat)
    obj.data.update()
    obj["atlas_tile"] = tile
    uv_project(obj, tile)
    return obj


def rings(name, radii, heights, tile="limestone", sides=12, center=(0, 0, 0)):
    verts = [(center[0] + radius * math.cos(j * math.tau / sides), center[1] + height, center[2] + radius * math.sin(j * math.tau / sides)) for radius, height in zip(radii, heights) for j in range(sides)]
    faces = [tuple(reversed(range(sides))), tuple((len(radii) - 1) * sides + j for j in range(sides))]
    faces += [(i * sides + j, i * sides + (j + 1) % sides, (i + 1) * sides + (j + 1) % sides, (i + 1) * sides + j) for i in range(len(radii) - 1) for j in range(sides)]
    return mesh_object(name, verts, faces, tile)


def rock(name, size, position=(0, 0, 0), tile="sandstone", detail=2):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=detail, radius=1)
    obj = bpy.context.object
    obj.name = name
    phase = rng.uniform(0, 50)
    for vertex in obj.data.vertices:
        x, y, z = vertex.co
        factor = 1 + .055 * math.sin(x * 8 + phase) + .045 * math.cos(y * 6 - phase)
        vertex.co = (x * size[0] * .5 * factor, y * size[2] * .5 * factor, max(0, z + .71) * size[1] / 1.71 * factor)
    obj.location = vec(position)
    obj.data.update()
    obj.data.materials.append(mat)
    obj["atlas_tile"] = tile
    uv_project(obj, tile)
    return obj


records = []
variants_for_catalogue = []


def finish(name, objects, placement, details):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    base = bpy.context.object
    base.name = name + "_LOD0"
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    base.data.materials.clear()
    base.data.materials.append(mat)
    for face in base.data.polygons:
        face.material_index = 0
    triangulate = base.modifiers.new("Export triangles", "TRIANGULATE")
    bpy.ops.object.modifier_apply(modifier=triangulate.name)
    base["source_seed"] = SEED
    base["original_design"] = "Encounter Props / authored procedural geometry"
    triangles, paths, variants = [], [], []
    for level, ratio in enumerate([1.0, .52, .24]):
        obj = base
        if level:
            obj = base.copy()
            obj.data = base.data.copy()
            bpy.context.collection.objects.link(obj)
            obj.name = name + f"_LOD{level}"
            bpy.context.view_layer.objects.active = obj
            modifier = obj.modifiers.new("Distant silhouette", "DECIMATE")
            modifier.ratio = ratio
            bpy.ops.object.modifier_apply(modifier=modifier.name)
        obj.data.validate(verbose=False, clean_customdata=False)
        obj.data.update()
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        path = f"models/encounter_props/{name}_lod{level}.glb"
        bpy.ops.export_scene.gltf(filepath=str(ROOT / path), export_format="GLB", use_selection=True, export_materials="NONE", export_yup=True, export_normals=True, export_texcoords=True, export_cameras=False, export_lights=False, export_animations=False)
        triangles.append(sum(len(face.vertices) - 2 for face in obj.data.polygons))
        paths.append(path)
        obj.hide_set(level > 0)
        variants.append(obj)
    points = [[v[0], v[2], -v[1]] for v in base.bound_box]
    lo = [min(v[i] for v in points) for i in range(3)]
    hi = [max(v[i] for v in points) for i in range(3)]
    records.append({"id": name, "units": "metres", "aabb": {"min": lo, "max": hi}, "model_paths": paths, "triangle_counts": triangles, "collision": "none", "placement": placement, "details": details})
    variants_for_catalogue.append(variants)


# BARBA: long shelter piers and roof wrap the existing 13 x 1 x 9 roof centred
# at y4.6. All rubble remains outside the 9m clear passage between the piers.
objects = []
for side in [-1, 1]:
    for row in range(6):
        for depth in range(6):
            objects.append(block("Long shelter ashlar", (side * 5.5, .37 + row * .735, (depth - 2.5) * 1.49), (1.96, .71, 1.45), "aged_stone" if row % 3 == 0 else "limestone", chip=.009))
    objects.append(block("Shelter capital", (side * 5.5, 4.29, 0), (2.10, .24, 9.02), "calcite", chip=.008))
    for depth in [-3.4, .7, 3.4]:
        objects.append(block("Exterior fallen fragments", (side * 6.82, .27, depth), (.75, .51, 1.25), "aged_stone", rotation=rng.uniform(-.5, .5), chip=.035))
for i in range(7):
    objects.append(block("Shelter roof block", ((i - 3) * 1.875, 4.61, 0), (1.84, 1.015, 9.06), "limestone", chip=.009))
for z in [-4.57, 4.57]:
    for i in range(11):
        x0, x1 = -5.50 + i, -4.53 + i
        low0 = 5.10 + 1.35 * (1 - (x0 / 5.5) ** 2)
        low1 = 5.10 + 1.35 * (1 - (x1 / 5.5) ** 2)
        verts = [(x, y, depth) for depth in [z - .15, z + .15] for x, y in [(x0, low0), (x1, low1), (x1, low1 + .46), (x0, low0 + .46)]]
        objects.append(mesh_object("Broken arch facing", verts, [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)], "calcite" if i == 5 else "aged_stone"))
finish("barba_shelter", objects, {"origin": "floor centre of shelter", "recommended_position": [0, 0, -27], "roof_gameplay_center_y": 4.6, "clear_passage": {"min_x": -4.45, "max_x": 4.45, "min_y": 0, "max_y": 4.09}, "notes": "Visual wrapper only. Existing shelter supports and roof supply all collision."}, "Weathered long piers, segmented roof, arched carved fascia and exterior rubble.")

# BASARAN: a real open ring. No cap triangles or rocks enter the jet radius.
objects = []
segments = 24
for i in range(segments):
    a, b = i * math.tau / segments + .002, (i + 1) * math.tau / segments - .002
    inner_a, inner_b = 3.14 + rng.uniform(0, .08), 3.14 + rng.uniform(0, .08)
    outer_a, outer_b = 4.35 + rng.uniform(-.15, .15), 4.35 + rng.uniform(-.15, .15)
    top_a, top_b = rng.uniform(.30, .58), rng.uniform(.30, .58)
    verts = []
    for angle, inner, outer, top in [(a, inner_a, outer_a, top_a), (b, inner_b, outer_b, top_b)]:
        verts.extend([(math.cos(angle) * inner, -.055, math.sin(angle) * inner), (math.cos(angle) * outer, -.055, math.sin(angle) * outer), (math.cos(angle) * outer, top, math.sin(angle) * outer), (math.cos(angle) * inner, top * .6, math.sin(angle) * inner)])
    objects.append(mesh_object("Vented basalt wedge", verts, [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)], "basalt"))
    if i % 3 == 0:
        angle = (a + b) * .5
        objects.append(rock("Mineral crust", (.55, .18, .42), (math.cos(angle) * 4.02, .25, math.sin(angle) * 4.02), "calcite", 1))
finish("basaran_vent_ring", objects, {"origin": "ground centre of geyser", "minimum_inner_radius": 3.05, "notes": "Minimum clear radius includes LOD simplification. Keep existing warning, water jet and triggers. This ring has no collision or lights."}, "Low fractured basalt crust with pale hydrothermal deposits and a completely open centre.")

# KUROMORI: facade and corbels only, no floor deck or collision surface.
objects = []
for i in range(7):
    x = (i - 3) * 1.15
    objects.append(block("Broken moulded cornice", (x, -.19, -.05), (1.11, .36, .92), "limestone"))
    objects.append(block("Drip moulding", (x, -.43, .26), (1.07, .16, .28), "aged_stone", bevel=.028))
for x in [-3.1, -.85, 1.45]:
    objects.append(block("Corbel outer", (x, -.72, -.10), (.7, .43, .68), "aged_stone", bevel=.07))
    objects.append(block("Corbel taper", (x, -1.04, -.29), (.48, .32, .32), "limestone", bevel=.035))
for i, height in enumerate([1.36, 1.34, .65, 0, .85, 1.34]):
    if height == 0:
        continue
    x = -3.15 + i * 1.10
    objects.append(rings("Baluster base", [.26, .26, .18], [0, .16, .24], "aged_stone", 8, (x, 0, 0)))
    objects.append(rings("Baluster body", [.16, .22, .21, .14], [.24, .44, height - .17, height], "limestone", 8, (x, 0, 0)))
for x, width in [(-2.61, 2.17), (2.36, 1.08)]:
    objects.append(block("Interrupted handrail", (x, 1.45, 0), (width, .20, .48), "calcite", bevel=.04))
objects.append(rings("Broken column shaft", [.46, .45, .40, .39], [0, .22, 2.54, 2.75], "limestone", 12, (3.55, 0, -.13)))
objects.append(block("Fractured column capital", (3.57, 2.72, -.10), (1.18, .22, 1.05), "aged_stone", rotation=.08, chip=.06))
finish("kuromori_gallery_fragment", objects, {"origin": "existing gallery outer edge at walkable height", "facing": "+Z points away from the gallery wall", "notes": "Only cornice, broken balustrade, corbels and column trim. Never replace the walkable gallery or attach a collider."}, "Open broken gallery silhouette with separated rail sections, octagonal balusters and chipped corbels.")

# DIRGE: actual rounded cavities, cut into a wide stratified sandstone boulder.
objects = []
stone = rock("Wind-carved porous boulder", (6.3, 3.7, 4.15), detail=3)
for index, (at, size) in enumerate([((-2.0, 1.2, 1.5), (.90, .58, .75)), ((-.85, 1.9, 1.65), (1.15, .73, 1.1)), ((.8, 1.15, 1.92), (1.25, .77, 1.0)), ((1.6, 2.15, 1.16), (.98, .65, .85)), ((2.6, .8, .4), (.8, .55, .8)), ((-.9, 2.95, .42), (.68, .53, .70)), ((-.4, 1.25, -1.9), (1.25, .7, 1.05)), ((1.0, 2.35, -1.47), (.75, .58, .73))]):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1, location=vec(at))
    cutter = bpy.context.object
    cutter.name = "Pore cutter " + str(index)
    cutter.scale = (size[0], size[2], size[1])
    bpy.context.view_layer.objects.active = stone
    modifier = stone.modifiers.new("Wind cavity", "BOOLEAN")
    modifier.operation = "DIFFERENCE"
    modifier.solver = "EXACT"
    modifier.object = cutter
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    bpy.data.objects.remove(cutter, do_unlink=True)
stone.data.update()
uv_project(stone, "sandstone")
objects.append(stone)
for position, size in [((-2.7, 0, .8), (1.6, .67, 1.2)), ((1.8, 0, 1.7), (1.5, .65, 1.0)), ((2.8, 0, -.6), (1.0, .52, 1.2))]:
    objects.append(rock("Scree at sandstone foot", size, position, detail=1))
finish("dirge_porous_rock", objects, {"origin": "ground at boulder centre", "notes": "Use outside the main chase lane. Decorative cavities and boulder are render-only; retain independent gameplay obstacles if needed."}, "Wide wind-eroded sandstone with eight boolean-cut pores, a rough flat base and scattered scree.")

# CAVE: a restrained amber reliquary lamp and a separate damaged offering marker.
objects = [rings("Lamp stone socket", [.36, .38, .31, .24], [0, .12, .28, .33], "aged_stone", 10),
           rings("Bronze lamp foot", [.25, .25, .17, .16], [.32, .43, .48, .91], "bronze", 12),
           rings("Patinated lower collar", [.27, .31, .31], [.89, .94, 1.00], "patina", 12),
           rings("Patinated upper collar", [.31, .31, .26], [1.46, 1.51, 1.57], "patina", 12)]
for i in range(8):
    angle = i * math.tau / 8
    objects.append(block("Open lantern rib", (math.cos(angle) * .285, 1.23, math.sin(angle) * .285), (.045, .52, .045), "bronze", bevel=.006, chip=0))
objects.append(rings("Warm amber vessel", [.10, .19, .20, .10], [1.04, 1.11, 1.35, 1.43], "amber", 16))
objects.append(rings("Lantern vented cap", [.26, .23, .075], [1.58, 1.67, 1.76], "bronze", 12))
finish("cave_relic_lamp", objects, {"origin": "floor at lamp socket", "emission": "Only amber atlas tile glows; no automatic light or collider", "notes": "Optional small OmniLight3D may be supplied separately by the arena. Sword light remains the primary visibility mechanic."}, "Bronze cage, verdigris collars, stone socket and contained amber vessel.")
objects = [block("Offering marker foot", (0, .1, 0), (.91, .20, .82), "aged_stone", chip=.015),
           block("Offering marker stele", (-.03, .46, -.08), (.63, .61, .37), "limestone", rotation=.04, chip=.04)]
for x in [-.21, .0, .21]:
    objects.append(block("Small patina incision", (x, .49, .121), (.034, .36 if x != 0 else .47, .012), "patina", bevel=0, chip=0))
objects.append(rock("Broken marker shard", (.31, .16, .36), (.42, 0, .29), "limestone", 1))
finish("cave_offering_marker", objects, {"origin": "floor beside cave paths", "notes": "Small render-only relic. Keep clear of the climbing and traversal route."}, "Damaged squat stele with three original inlay cuts and a fallen corner.")

# PELAGIA: a low octagonal decorative cap, open walkable centre and corner stubs.
objects = [rings("Flooded shrine broad base", [4.14, 4.14, 3.84], [0, .27, .47], "aged_stone", 8),
           rings("Shrine cap moulding", [3.87, 3.98, 3.98], [.47, .59, .73], "calcite", 8),
           rings("Shrine worn crown", [3.79, 3.79, 3.60], [.73, 1.05, 1.16], "limestone", 8)]
for i in range(8):
    angle = (i + .5) * math.tau / 8
    x, z = math.cos(angle) * 3.62, math.sin(angle) * 3.62
    objects.append(block("Wet mineral relief", (x, .43, z), (.58, .33, .12), "patina", rotation=-angle - math.pi / 2, bevel=.018, chip=.01))
for i in [0, 2, 4, 6]:
    angle = i * math.tau / 8
    x, z = math.cos(angle) * 3.3, math.sin(angle) * 3.3
    objects.append(rings("Broken corner finial", [.26, .26, .19], [1.10, 1.24, 1.24 + (.38 if i != 4 else .65)], "aged_stone", 8, (x, 0, z)))
finish("pelagia_shrine_cap", objects, {"origin": "base of decorative ruin crown", "recommended_offset_from_RUINS_LOCAL": [0, 6.85, 0], "notes": "Decorative cap only. Existing pillars retain collision and ruin-impact metadata; do not attach the cap to the boss skeleton."}, "Octagonal shrine cap, mineral tide stains, stepped lip and broken corner finials with a clear centre.")

# Catalogue remains editable, with every LOD in a named per-asset collection.
scene = bpy.context.scene
scene.name = "Encounter_Props_Catalogue"
for index, (record, variants) in enumerate(zip(records, variants_for_catalogue)):
    collection = bpy.data.collections.new(record["id"])
    scene.collection.children.link(collection)
    offset = vec(((index % 3) * 20, 0, (index // 3) * 18))
    for obj in variants:
        for previous in list(obj.users_collection):
            previous.objects.unlink(obj)
        collection.objects.link(obj)
        obj.location = offset
        obj.hide_viewport = not obj.name.endswith("LOD0")
        obj.hide_render = not obj.name.endswith("LOD0")
scene["pipeline"] = "Original authored encounter props: tools/art/generate_encounter_props.py"
scene["coordinate_contract"] = "Godot X right, Y up, +Z front; Blender X right, Z up, -Y front"
scene["source_seed"] = SEED
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "art/source/encounter_props.blend"), compress=True)
manifest = {"pack": "Encounter Props / original procedural geometry", "source": "art/source/encounter_props.blend", "generator": "tools/art/generate_encounter_props.py", "seed": SEED, "units": "metres", "up": "+Y", "forward": "-Z", "collision": "none", "material": "materials/encounter_props/atlas.tres", "assets": records}
(ROOT / "assets/encounter_props_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
print("ENCOUNTER_PROPS_OK", len(records), "assets; LOD triangles:", {r["id"]: r["triangle_counts"] for r in records})
