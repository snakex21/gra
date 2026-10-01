@tool
extends Node3D
## Original art-only crossing. Architecture is level on authored footings, not a
## terrain-relative scatter. This scene never loads player, gameplay, or AI code.
const StoneAsset = preload("res://art/scripts/stonewater_asset.gd")
const ValleyAsset = preload("res://art/scripts/valley_asset.gd")
const TerrainMaterial = preload("res://materials/ancient_valley/terrain.tres")
const ValleyAtlas = preload("res://materials/ancient_valley/atlas.tres")
const KIT_IDS := [
	"aqueduct_span_12m", "aqueduct_broken_end", "causeway_8m",
	"bridge_deck_12m", "bridge_abutment", "bridge_ramp_8m",
	"parapet_4m", "parapet_end", "ribbed_pier_10m",
	"cistern_vault_8m", "oculus_roof_8m", "monumental_portal",
	"sluice_frame_6m", "basin_corner_6m", "spillway_steps_6m",
	"flying_buttress", "water_outlet", "carved_waymarker"
]
@export var include_collision := true
@export var include_catalogue := false
var landscape: Node3D
var catalogue: Node3D
var asset_count := 0
var catalogue_count := 0
var reused_asset_count := 0
var vegetation_instances := 0
var terrain_triangles := 0
var water_material: StandardMaterial3D
var footing_material: StandardMaterial3D

static func height_at(x: float, z: float) -> float:
	# Level dry bearing floor under every pier; central river is cut below it.
	var h := 10.2 * smoothstep(25.6, 32.0, absf(x))
	h -= 1.8 * (1.0 - smoothstep(4.5, 8.0, absf(x)))
	var hills := smoothstep(53.0, 98.0, absf(x))
	# The entire cistern/court precinct is a level shelf; distant hills resume east.
	if x > 0:
		hills *= smoothstep(67.0, 92.0, x)
	h += hills * (3.0 + 3.0 * sin(x * .044) * cos(z * .028))
	h += smoothstep(54.0, 126.0, z) * (5.0 + 3.0 * sin(x * .035))
	return h

func _ready() -> void:
	if get_child_count() == 0:
		build()

func build() -> void:
	landscape = Node3D.new()
	landscape.name = "Landscape"
	add_child(landscape)
	water_material = StandardMaterial3D.new()
	water_material.resource_name = "StillWater_Opaque_NoReflectionPass"
	water_material.albedo_color = Color(.035, .13, .135)
	water_material.roughness = .82
	water_material.metallic = 0.0
	water_material.metallic_specular = 0.0
	footing_material = StandardMaterial3D.new()
	footing_material.resource_name = "RoughLimestoneFootings"
	footing_material.albedo_color = Color(.9, .9, .84)
	footing_material.albedo_texture = preload("res://textures/environment/ruin_stone_albedo.png")
	footing_material.uv1_scale = Vector3(2, 2, 2)
	footing_material.roughness = .95
	_terrain()
	_crossing()
	_cistern()
	_river()
	_landscape_details()
	if include_catalogue:
		_build_catalogue()

func place(id: String, p: Vector3, yaw := 0.0, size := Vector3.ONE, parent: Node3D = null) -> Node3D:
	var n := Node3D.new()
	n.set_script(StoneAsset)
	n.model_id = id
	n.collidable = include_collision if parent == null else false
	n.lod_distances = Vector3(52, 120, 420) if parent == null else Vector3(250, 400, 900)
	n.name = "%s_%03d" % [id, asset_count + catalogue_count]
	n.position = p
	n.rotation.y = yaw
	n.scale = size
	if parent == null:
		landscape.add_child(n)
		asset_count += 1
	else:
		parent.add_child(n)
		catalogue_count += 1
	return n

func _crossing() -> void:
	# Aqueduct rhythm: 3 x 16m bays, genuine 12m arches, spring at 6m.
	for x in [-16.0, 0.0, 16.0]:
		place("aqueduct_span_12m", Vector3(x, 0, 6))
	# Inner arch piers straddle the incised river edge on buried pad footings.
	for x in [-6.8, 6.8]:
		_slab("AqueductRiverFooting", Vector3(x, -.8, 6), Vector3(2.4, 1.6, 3.6))
	# Pedestrian crossing is separate from the elevated water channel.
	# Every 10m support starts at Y=0; every deck bottom is exactly Y=10.
	for x in [-24.0, -12.0, 0.0, 12.0, 24.0]:
		place("ribbed_pier_10m", Vector3(x, 0, -4.5))
		_slab("BridgeBearingCap", Vector3(x, 10.1, -4.5), Vector3(3.0, .2, 3.0))
	for x in [-18.0, -6.0, 6.0, 18.0]:
		place("bridge_deck_12m", Vector3(x, 10, -4.5))
	for x in range(-22, 24, 4):
		for z in [-7.25, -1.75]:
			place("parapet_4m", Vector3(x, 11.2, z))
	for x in [-24.0, 24.0]:
		for z in [-7.25, -1.75]:
			place("parapet_end", Vector3(x, 11.2, z))
	place("bridge_ramp_8m", Vector3(-28, 10, -4.5))
	place("bridge_ramp_8m", Vector3(28, 10, -4.5), PI)
	# The river pier has a submerged footing down to the carved riverbed.
	place("bridge_abutment", Vector3(0, -1.92, -4.5), 0, Vector3(.55, .32, .48))
	# Transition blocks are partly buried in the bank, never suspended above it.
	for x in [-28.0, 28.0]:
		place("bridge_abutment", Vector3(x, 0, 6), 0, Vector3(1, 11.0 / 6.0, 1))
		place("causeway_8m", Vector3(x, 11.0, 6))
	place("monumental_portal", Vector3(-38, 10.2, -4.5), PI * .5)
	place("carved_waymarker", Vector3(-33.5, 10.2, -9.0), -.14)
	place("carved_waymarker", Vector3(34.5, 10.2, -9.0), .12)
	# A short retained vestige on the distant bank shows a broken termination.
	place("aqueduct_broken_end", Vector3(70, height_at(65, 33) - .25, 33), -.15)
	_scale_staff(Vector3(28.8, 10.6, -6.7))

func _cistern() -> void:
	# Two open barrel vaults share their floor and spring heights on a flat shelf.
	for x in [43.0, 51.0]:
		place("cistern_vault_8m", Vector3(x, 10.2, 1))
	# An oculus court is connected to the eastern end of the vaulted run.
	# Four 6m piers directly support the underside of the ring roof at Y16.2.
	for x in [56.0, 62.0]:
		for z in [-2.0, 4.0]:
			place("ribbed_pier_10m", Vector3(x, 10.2, z), 0, Vector3(.42, .6, .42))
	place("oculus_roof_8m", Vector3(59, 16.2, 1))
	_slab("OculusCourtFloor", Vector3(59, 10.33, 1), Vector3(8, .26, 8))
	# Keep the entrance clear; buttresses flank the wall rather than the aisle.
	place("flying_buttress", Vector3(46, 10.2, 5.5), PI * .5, Vector3(.8, .75, .8))
	place("flying_buttress", Vector3(52, 10.2, 5.5), PI * .5, Vector3(.8, .75, .8))
	place("sluice_frame_6m", Vector3(65.0, 10.2, 1), PI * .5, Vector3(.8, .82, .85))
	place("water_outlet", Vector3(37.0, 10.2, 6), PI)
	# In the hall, a shallow, static water strip reads as a runnel between paths.
	_water_plane("CisternRunnel", Vector3(49.0, 10.515, 1), Vector2(19.8, 1.05))
	for p in [Vector3(59.6, 10.46, -.3), Vector3(59.6, 10.46, 2.3)]:
		place("carved_waymarker", p, 0, Vector3(.38, .56, .38))
	# An exterior settling basin and stepped spillway sit clear of circulation.
	for entry in [[Vector3(43, 10.2, 17), 0.0], [Vector3(49, 10.2, 17), -PI * .5], [Vector3(49, 10.2, 23), PI], [Vector3(43, 10.2, 23), PI * .5]]:
		place("basin_corner_6m", entry[0], entry[1])
	_water_plane("SettlingBasin", Vector3(46, 10.7, 20), Vector2(10.4, 10.4))
	place("spillway_steps_6m", Vector3(37, 10.2, 20), -PI * .5, Vector3(1, .5, 1))

func _slab(node_name: String, p: Vector3, size: Vector3, parent: Node3D = null, mat: Material = null) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = p
	mesh.material_override = mat if mat != null else footing_material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(landscape if parent == null else parent).add_child(mesh)

func _water_plane(node_name: String, p: Vector3, size: Vector2) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var plane := PlaneMesh.new()
	plane.size = size
	mesh.mesh = plane
	mesh.position = p
	mesh.material_override = water_material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	landscape.add_child(mesh)

func _river() -> void:
	_water_plane("River_OneOpaqueSurface", Vector3(0, -.25, 0), Vector2(12.0, 300))
	_water_plane("Aqueduct_StillWater", Vector3(0, 13.48, 6), Vector2(48, 1.45))

func _terrain() -> void:
	# 12 spatial chunks. No collision triangle soup and no per-frame terrain work.
	for cz in 4:
		for cx in 3:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for z in 24:
				for x in 24:
					for c in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]:
						var px: float = -144.0 + cx * 96.0 + (x + c.x) * 4.0
						var pz: float = -144.0 + cz * 72.0 + (z + c.y) * 3.0
						st.set_uv(Vector2(px, pz) * .2)
						st.set_normal(Vector3(height_at(px - .5, pz) - height_at(px + .5, pz), 1.0, height_at(px, pz - .5) - height_at(px, pz + .5)).normalized())
						st.add_vertex(Vector3(px, height_at(px, pz), pz))
			var mesh := MeshInstance3D.new()
			mesh.name = "CanyonTerrain_%d_%d" % [cx, cz]
			mesh.mesh = st.commit()
			mesh.material_override = TerrainMaterial
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			landscape.add_child(mesh)
			terrain_triangles += 1152
	if include_collision:
		var body := StaticBody3D.new()
		body.name = "CanyonHeightfield_StaticOnly"
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := HeightMapShape3D.new()
		shape.map_width = 97
		shape.map_depth = 97
		var heights := PackedFloat32Array()
		for z in 97:
			for x in 97:
				heights.append(height_at((x - 48) * 3.0, (z - 48) * 3.0))
		shape.map_data = heights
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.scale = Vector3(3, 1, 3)
		body.add_child(collision)
		landscape.add_child(body)
	# Exact shared boundary samples prevent cracks at the near/far terrain join.
	# Outer coordinates coarsen to 24m, while the 4m X / 3m Z edge samples match
	# every near-terrain vertex. No overlap, skirt, gap, or coplanar terrain ring.
	var xs: Array[float] = []
	var zs: Array[float] = []
	for x in range(-336, -144, 24):
		xs.append(float(x))
	for x in range(-144, 145, 4):
		xs.append(float(x))
	for x in range(168, 337, 24):
		xs.append(float(x))
	for z in range(-336, -144, 24):
		zs.append(float(z))
	for z in range(-144, 145, 3):
		zs.append(float(z))
	for z in range(168, 337, 24):
		zs.append(float(z))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for zi in zs.size() - 1:
		for xi in xs.size() - 1:
			if xs[xi] >= -144 and xs[xi] < 144 and zs[zi] >= -144 and zs[zi] < 144:
				continue
			for c in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var px: float = xs[xi + c.x]
				var pz: float = zs[zi + c.y]
				st.set_normal(Vector3(height_at(px - .5, pz) - height_at(px + .5, pz), 1.0, height_at(px, pz - .5) - height_at(px, pz + .5)).normalized())
				st.set_uv(Vector2(px, pz) * .2)
				st.add_vertex(Vector3(px, height_at(px, pz), pz))
	var horizon := MeshInstance3D.new()
	horizon.name = "StitchedDistantGround_NoCollision"
	horizon.mesh = st.commit()
	horizon.material_override = TerrainMaterial
	horizon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	landscape.add_child(horizon)

func _old_asset(id: String, p: Vector3, size := Vector3.ONE, yaw := 0.0) -> Node3D:
	var n := Node3D.new()
	n.set_script(ValleyAsset)
	n.model_id = id
	n.collidable = false
	n.name = "Reused_%s_%02d" % [id, reused_asset_count]
	n.position = p
	n.scale = size
	n.rotation.y = yaw
	n.lod_distances = Vector3(48, 110, 370)
	landscape.add_child(n)
	reused_asset_count += 1
	return n

func _landscape_details() -> void:
	# Restrained edge clusters frame a large, intentionally empty river foreground.
	for row in [[-51, 29, 1.0, .2], [-60, 38, 1.15, -.3], [51, 49, 1.1, .5], [62, 54, 1.0, .7], [-78, -31, .95, 1.0], [77, -9, .75, -.4]]:
		var p := Vector3(row[0], 0, row[1])
		p.y = INF
		for ox in [-14.0, 0.0, 14.0]:
			for oz in [-14.0, 0.0, 14.0]:
				p.y = minf(p.y, height_at(p.x + ox, p.z + oz) - .35)
		_old_asset("cliff", p, Vector3(row[2] * 1.15, row[2] * .72, row[2]), row[3])
	for row in [[-35, 15, "tree_cypress"], [-37, 19, "tree_cypress"], [-57, -9, "tree_oak"], [66, 13, "tree_cypress"], [69, 17, "tree_cypress"], [45, -21, "tree_dead"]]:
		var p := Vector3(row[0], 0, row[1])
		p.y = height_at(p.x, p.z)
		_old_asset(row[2], p, Vector3.ONE * .82, .3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41027
	for i in 24:
		var side := -1.0 if i % 2 == 0 else 1.0
		var p := Vector3(side * rng.randf_range(33, 65), 0, rng.randf_range(-42, 55))
		if absf(p.z + 4.5) < 7 or (p.x > 33 and p.z > -5 and p.z < 29):
			continue
		p.y = height_at(p.x, p.z) - .12
		_old_asset("slate_%d" % (i % 3), p, Vector3.ONE * rng.randf_range(.55, 1.0), rng.randf() * TAU)
	# A single static MultiMesh per foliage type, hard culled at 150m, no shadows.
	for typ in 2:
		var transforms: Array[Transform3D] = []
		for i in 145:
			var p := Vector3(rng.randf_range(-63, 74), 0, rng.randf_range(-46, 61))
			if absf(p.x) < 32 or absf(p.z + 4.5) < 7 or (p.x > 33 and p.z > -5 and p.z < 30):
				continue
			if sin(p.x * .21) * cos(p.z * .14) < .25:
				continue
			p.y = height_at(p.x, p.z)
			transforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(.55, 1.0)), p))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = ValleyAsset.mesh_for("grass_dry_v2" if typ == 0 else "shrub_heather", 1)
		mm.instance_count = transforms.size()
		for i in transforms.size():
			mm.set_instance_transform(i, transforms[i])
		var instance := MultiMeshInstance3D.new()
		instance.name = "StaticEdgeVegetation_%d" % typ
		instance.multimesh = mm
		instance.material_override = ValleyAtlas
		instance.visibility_range_end = 150
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		landscape.add_child(instance)
		vegetation_instances += transforms.size()

func _scale_staff(p: Vector3) -> void:
	var dark := StandardMaterial3D.new()
	dark.resource_name = "ScaleStaff_Dark"
	dark.albedo_color = Color(.12, .17, .17)
	var pale := StandardMaterial3D.new()
	pale.resource_name = "ScaleStaff_Pale"
	pale.albedo_color = Color(.83, .78, .63)
	for i in 8:
		_slab("ScaleStaff_2m_%d" % i, p + Vector3(0, .125 + i * .25, 0), Vector3(.13, .25, .13), null, dark if i % 2 == 0 else pale)

func _build_catalogue() -> void:
	catalogue = Node3D.new()
	catalogue.name = "KitCatalogue"
	catalogue.position = Vector3(0, 0, 620)
	add_child(catalogue)
	var ground := StandardMaterial3D.new()
	ground.resource_name = "CatalogueSlate"
	ground.albedo_color = Color(.16, .20, .21)
	ground.roughness = 1
	_slab("CatalogueBackdrop", Vector3(0, -.4, 0), Vector3(146, .5, 82), catalogue, ground)
	for i in KIT_IDS.size():
		var p := Vector3((2.5 - i % 6) * 23.0, 0, (1 - i / 6) * 25.0)
		place(KIT_IDS[i], p, 0, Vector3.ONE, catalogue)
		var label := Label3D.new()
		label.name = "Label_%s" % KIT_IDS[i]
		label.text = "%02d  %s" % [i + 1, KIT_IDS[i].replace("_", " ").to_upper()]
		label.font_size = 36
		label.pixel_size = .04
		label.outline_size = 5
		label.modulate = Color(.85, .86, .79)
		label.position = p + Vector3(0, .85, -7.4)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		catalogue.add_child(label)
	catalogue.visible = false

func show_catalogue(enabled: bool) -> void:
	landscape.visible = not enabled
	if catalogue != null:
		catalogue.visible = enabled
