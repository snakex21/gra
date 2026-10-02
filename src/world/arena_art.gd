class_name ArenaArt
## Render-only art layer over the greybox arenas and colossi (assets from the art branch:
## Saltward pack, CC0). Gameplay never depends on it: collision shapes, climb patches,
## bones, segments and AI stay exactly as they are, the tests run without it, and every
## scene can switch it off (build_encounter(..., with_art = false)).
##
##   dress_arena()  ground -> terrain shader; greybox pillars -> ruin columns, small boxes
##                  -> rocks (visual only, their box collision stays); terraces / ramps
##                  -> terrain shader; grass, shrubs, trees and cliffs outside the fight
##   dress_valus()  the art pack's rigid part per segment (3 LODs); Valus' own extra
##                  parts (mane, fur cap, armour) stay visible as readable climb cues
##   skin_colossus() textured stone / fur / armour materials for greybox parts (Quadratus
##                  has no model yet)

const Asset = preload("res://art/scripts/art_asset.gd")
const ATLAS := preload("res://materials/environment/shared_atlas.tres")
const FOLIAGE := preload("res://materials/environment/foliage_atlas.tres")
const TERRAIN := preload("res://materials/environment/terrain.tres")
## Sentinel v2 kit (rounded, 17 rigid parts, extended-foot variant for our 3.6 m feet).
const SENTINEL_V2_ATLAS := preload("res://materials/sentinel_v2/atlas.tres")
const VALUS_SEGMENTS := ["hips", "spine", "chest", "neck", "head", "upper_arm_l", "forearm_l", "hand_l", "upper_arm_r", "forearm_r", "hand_r", "thigh_l", "shin_l", "foot_l", "thigh_r", "shin_r", "foot_r"]
## Part kinds, the same order in GreyboxHumanoid.Kind and GreyboxQuadruped.Kind.
enum Kind { FUR, STONE, ARMOR }

static var _materials := {}


## Textured materials per part kind (object-space triplanar: they stick to moving bodies).
static func material(kind: int) -> StandardMaterial3D:
	if _materials.has(kind):
		return _materials[kind]
	var m := StandardMaterial3D.new()
	m.uv1_triplanar = true
	m.uv1_triplanar_sharpness = 2.0
	m.normal_enabled = true
	match kind:
		Kind.FUR:
			m.albedo_texture = load("res://textures/environment/grass_albedo.png")
			m.normal_texture = load("res://textures/environment/grass_normal.png")
			m.albedo_color = Color(0.95, 0.66, 0.42)
			m.uv1_scale = Vector3.ONE * 0.6
			m.roughness = 1.0
		Kind.STONE:
			m.albedo_texture = load("res://textures/environment/rock_albedo.png")
			m.normal_texture = load("res://textures/environment/rock_normal.png")
			m.uv1_scale = Vector3.ONE * 0.25
			m.roughness = 0.9
		_:
			m.albedo_texture = load("res://textures/environment/ruin_stone_albedo.png")
			m.normal_texture = load("res://textures/environment/ruin_stone_normal.png")
			m.albedo_color = Color(0.62, 0.62, 0.66)
			m.uv1_scale = Vector3.ONE * 0.35
			m.roughness = 0.75
	_materials[kind] = m
	return m


## Greybox colossus parts -> textured materials by what they are made of.
static func skin_colossus(c: Colossus) -> int:
	var n := 0
	for seg in c.segments:
		for child in seg.get_children():
			if child is MeshInstance3D and child.has_meta(&"kind"):
				(child as MeshInstance3D).material_override = material(int(child.get_meta(&"kind")))
				n += 1
	return n


## The art pack's Valus: one rigid visual per segment (Sentinel v2 kit, or the first
## Saltward kit with ``v2 = false``), greybox base parts hidden. Valus' own extra parts
## (mane, fur cap, armour) stay visible: they are the climbing cues.
static func dress_valus(v: Colossus, v2 := true) -> int:
	for bone in VALUS_SEGMENTS:
		if v.get_node_or_null("Seg_" + bone) == null:
			push_warning("Valus art not attached: no segment " + bone)
			skin_colossus(v)
			return 0
	var base := _base_part_keys()
	var attached := 0
	for bone in VALUS_SEGMENTS:
		var seg := v.get_node("Seg_" + bone) as BodySegment
		for child in seg.get_children():
			if child is MeshInstance3D and child.has_meta(&"kind"):
				var mi := child as MeshInstance3D
				if base.has(_key(StringName(bone), mi.get_meta(&"part_size"), mi.position)):
					mi.visible = false
				else:
					mi.material_override = material(int(mi.get_meta(&"kind")))
		var art := Node3D.new()
		art.name = "ArtVisual"
		seg.add_child(art)
		var id: String = "sentinel_" + bone
		if v2 and bone in ["foot_l", "foot_r"] and _extended_feet():
			id += "_extended"
		for level in 3:
			var mesh := MeshInstance3D.new()
			mesh.name = "LOD%d" % level
			mesh.mesh = Asset.mesh_for(id, level, "sentinel_v2" if v2 else "colossus")
			mesh.lod_bias = 100.0
			mesh.material_override = SENTINEL_V2_ATLAS if v2 else ATLAS
			mesh.visibility_range_begin = [0.0, 48.0, 100.0][level]
			mesh.visibility_range_end = [48.0, 100.0, 300.0][level]
			art.add_child(mesh)
		attached += 1
	return attached


## Our feet are 3.6 m long at z = -0.85 (the kit's extended variant matches them).
static func _extended_feet() -> bool:
	for part in GreyboxHumanoid.PARTS:
		if part[0] == &"foot_l":
			return is_equal_approx((part[2] as Vector3).z, 3.6) and is_equal_approx((part[3] as Vector3).z, -0.85)
	return false


static func _key(bone: StringName, size: Variant, pos: Vector3) -> String:
	return "%s|%s|%s" % [bone, str(size), str(pos.snapped(Vector3.ONE * 0.01))]


## The plain greybox humanoid's parts (what the art pack's models replace).
static func _base_part_keys() -> Dictionary:
	var keys := {}
	for p in GreyboxHumanoid.PARTS:
		keys[_key(p[0], p[2], p[3])] = true
		var bone := String(p[0])
		if bone.ends_with("_l"):
			var c: Vector3 = p[3]
			keys[_key(StringName(bone.trim_suffix("_l") + "_r"), p[2], Vector3(-c.x, c.y, c.z))] = true
	return keys


## Dresses an arena built from TerrainKit boxes. ``entrance`` is the direction (from the
## centre) kept free of backdrop cliffs; ``fight_radius`` is kept free of trees.
static func dress_arena(parent: Node3D, entrance := Vector3(0, 0, 1), fight_radius := 50.0, seed_value := 7013) -> Dictionary:
	var stats := {"columns": 0, "rocks": 0, "terrain": 0, "cliffs": 0, "trees": 0, "grass": 0}
	var ground := parent.get_node_or_null("Ground")
	if ground:
		for c in ground.get_children():
			if c is MeshInstance3D:
				(c as MeshInstance3D).material_override = TERRAIN
	_daylight(parent)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for body in parent.get_children():
		if not body is StaticBody3D or body.name == "Ground":
			continue
		var box := _box_of(body)
		if box.is_empty():
			continue
		var size: Vector3 = box.size
		var mesh: MeshInstance3D = box.mesh
		var b := body as StaticBody3D
		var flat_rot := absf(b.basis.get_euler().x) < 0.01 and absf(b.basis.get_euler().z) < 0.01
		if flat_rot and size.y > 2.0 * maxf(size.x, size.z) and size.x < 3.5:
			mesh.visible = false
			_visual(parent, "ruin_column", b.global_transform, Vector3(size.x / 2.3, size.y / 7.66, size.z / 2.3), size.y)
			stats.columns += 1
		elif flat_rot and size.y < 3.0 and maxf(size.x, size.z) < 7.0 and size.y > 0.5:
			mesh.visible = false
			var id := "rock_%02d" % (rng.randi() % 3 + 1)
			var aabb := Asset.mesh_for(id, 0).get_aabb()
			_visual(parent, id, b.global_transform, Vector3(size.x / aabb.size.x, size.y / aabb.size.y, size.z / aabb.size.z) * 1.08, size.y)
			stats.rocks += 1
		else:
			mesh.material_override = TERRAIN if size.y < 6.0 or not flat_rot else material(Kind.ARMOR)
			stats.terrain += 1
	# Backdrop cliffs on a far ring (outside the fight and the ride in), gap at the entrance.
	var gap := atan2(entrance.z, entrance.x)
	for i in 16:
		var a := i * TAU / 16.0 + 0.1
		if absf(angle_difference(a, gap)) < 0.45:
			continue
		var r := 150.0 + rng.randf_range(-10.0, 15.0)
		var pos := Vector3(cos(a) * r, 0, sin(a) * r)
		_prop(parent, "cliff_buttress", pos, -a + PI * 0.5, rng.randf_range(1.6, 2.3), "hull", Vector3(60, 160, 450))
		stats.cliffs += 1
	# A few trees and shrubs on the rim, never inside the fight.
	for i in 10:
		var a := rng.randf() * TAU
		var r := rng.randf_range(fight_radius + 25.0, fight_radius + 55.0)
		if absf(angle_difference(a, gap)) < 0.3:
			continue
		_prop(parent, "tree_juniper" if i % 2 == 0 else "tree_windward", Vector3(cos(a) * r, 0, sin(a) * r), rng.randf() * TAU, rng.randf_range(1.0, 1.4), "trunk")
		stats.trees += 1
	# Boulders between the fight and the cliffs (their own coarse collision).
	for i in 26:
		var a := rng.randf() * TAU
		var r := rng.randf_range(fight_radius + 12.0, fight_radius + 70.0)
		if absf(angle_difference(a, gap)) < 0.25:
			continue
		_prop(parent, "rock_%02d" % (i % 5 + 1), Vector3(cos(a) * r, 0, sin(a) * r), rng.randf() * TAU, rng.randf_range(0.8, 1.8), "hull")
		stats.rocks += 1
	for i in 40:
		var a := rng.randf() * TAU
		var r := rng.randf_range(20.0, fight_radius + 60.0)
		_prop(parent, "shrub_salt" if i % 2 == 0 else "plant_spear", Vector3(cos(a) * r, 0, sin(a) * r), rng.randf() * TAU, rng.randf_range(0.7, 1.3), "none")
	stats.grass = _grass(parent, rng, fight_radius + 70.0)
	return stats


## The art pack's daylight preset on the scene's sun and environment (if there are any).
static func _daylight(parent: Node3D) -> void:
	for c in parent.get_children():
		if c is DirectionalLight3D:
			var sun := c as DirectionalLight3D
			sun.light_color = Color(1.0, 0.94, 0.78)
			sun.light_energy = 1.15
		elif c is WorldEnvironment and (c as WorldEnvironment).environment:
			var env := (c as WorldEnvironment).environment
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = Color(0.61, 0.70, 0.77)
			env.ambient_light_energy = 0.6
			env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
			env.fog_enabled = true
			env.fog_density = 0.0011
			env.fog_light_color = Color(0.66, 0.70, 0.69)
			env.fog_sky_affect = 0.15
			env.fog_height = 0.0
			env.fog_height_density = 0.018
			var sky := env.sky.sky_material as ProceduralSkyMaterial if env.sky else null
			if sky:
				sky.sky_top_color = Color(0.30, 0.45, 0.52)
				sky.sky_horizon_color = Color(0.76, 0.77, 0.67)
				sky.ground_horizon_color = sky.sky_horizon_color


static func _box_of(body: Node) -> Dictionary:
	var shape: BoxShape3D = null
	var mesh: MeshInstance3D = null
	for c in body.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
			shape = (c as CollisionShape3D).shape
		elif c is MeshInstance3D:
			mesh = c
	if shape == null or mesh == null:
		return {}
	return {"size": shape.size, "mesh": mesh}


## Visual-only art standing on the bottom of a greybox box (its collision stays).
static func _visual(parent: Node3D, id: String, xf: Transform3D, scale: Vector3, height: float) -> void:
	var node := Node3D.new()
	node.name = "Art_" + id
	parent.add_child(node)
	node.global_transform = Transform3D(xf.basis.orthonormalized() * Basis.from_scale(scale), xf.origin - Vector3.UP * height * 0.5)
	for level in 3:
		var mi := MeshInstance3D.new()
		mi.mesh = Asset.mesh_for(id, level)
		mi.lod_bias = 100.0
		mi.material_override = ATLAS
		mi.visibility_range_begin = [0.0, 40.0, 110.0][level]
		mi.visibility_range_end = [40.0, 110.0, 400.0][level]
		node.add_child(mi)


## A full art prop (visual + its own coarse collision, or none).
static func _prop(parent: Node3D, id: String, pos: Vector3, yaw: float, size: float, collision: String, lods := Vector3(35, 90, 260)) -> void:
	var p := Node3D.new()
	p.set_script(Asset)
	p.model_id = id
	p.collidable = collision != "none"
	p.collision_kind = collision
	p.lod_distances = lods
	p.position = pos
	p.rotation.y = yaw
	p.scale = Vector3.ONE * size
	parent.add_child(p)


## Grass tufts in chunked multimeshes (two LODs), no collision.
static func _grass(parent: Node3D, rng: RandomNumberGenerator, radius: float) -> int:
	var chunks := {}
	var n := 0
	for i in 3200:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * radius
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		if sin(p.x * 0.11) * cos(p.z * 0.09) < -0.35 and i % 4 != 0:
			continue
		var key := Vector3i(floori(p.x / 20.0), floori(p.z / 20.0), i % 3)
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.4)), p))
		n += 1
	for key: Vector3i in chunks:
		var center := Vector3(key.x * 20 + 10, 0, key.y * 20 + 10)
		var xfs: Array = chunks[key]
		for level in 2:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = Asset.mesh_for(["grass_tuft", "grass_dry", "grass_low"][key.z], level * 2)
			mm.instance_count = xfs.size()
			for j in xfs.size():
				var xf: Transform3D = xfs[j]
				xf.origin -= center
				mm.set_instance_transform(j, xf)
			var node := MultiMeshInstance3D.new()
			node.multimesh = mm
			node.lod_bias = 100.0
			node.position = center
			node.material_override = FOLIAGE
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.visibility_range_begin = 0.0 if level == 0 else 30.0
			node.visibility_range_end = 30.0 if level == 0 else 80.0
			parent.add_child(node)
	return n


## Phaedra's fen: the shared arena dressing plus the Mirewood kit (CC0), render only.
## Mossy walls along the tunnels and moss over their mouths; old trees, logs, reeds,
## sedge and ferns, peat hummocks between the fight and the rim, a waystone at the way
## in and a drowned shrine on the far side. Nothing here collides: the tunnels, the
## ground and the rim are the greybox ones.
static func dress_fen(parent: Node3D, tunnels: Array, fight_radius := 70.0, seed_value := 6047) -> Dictionary:
	var stats := dress_arena(parent, Vector3(0, 0, 1), fight_radius, seed_value)
	stats.mire = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 1
	var keep_clear: Array[Vector3] = []
	for t in tunnels:
		var c: Vector3 = t.center
		var along_x: bool = t.along_x
		var length: float = t.length
		var side := Vector3.BACK if along_x else Vector3.RIGHT
		var yaw := 0.0 if along_x else PI * 0.5
		for s in [-1.0, 1.0]:
			_mire(parent, "moss_retaining_wall", c + side * s * (PhaedraArena.TUNNEL_WIDTH * 0.5 + 0.75), yaw + (0.0 if s > 0.0 else PI), Vector3(length / 11.15, 1.0, 0.45))
			stats.mire += 1
		for m in t.mouths:
			var out: Vector3 = m[1]
			_mire(parent, "hanging_moss", (m[0] as Vector3) + out * 0.15 + Vector3.UP * 1.4, atan2(out.x, out.z) + PI * 0.5, Vector3(1.4, 1.0, 1.0))
			stats.mire += 1
			# The mouth and the spot Phaedra stands on to look in stay free.
			keep_clear.append(m[0] as Vector3)
			keep_clear.append((m[0] as Vector3) + out * 11.0)
		keep_clear.append(c)
	var clear := func(p: Vector3, r: float) -> bool:
		for k in keep_clear:
			if Vector2(p.x - k.x, p.z - k.z).length() < r:
				return false
		return Vector2(p.x, p.z - 70.0).length() > 14.0   # the way in from the entrance
	# Plants and hummocks in the fen (between the tunnels and the rim).
	var small := ["cattail_rush", "broad_sedge", "marsh_fern", "cypress_knees", "peat_hummock"]
	for i in 70:
		var a := rng.randf() * TAU
		var r := rng.randf_range(18.0, fight_radius - 4.0)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		if not clear.call(p, 9.0):
			continue
		var id: String = small[i % small.size()]
		_mire(parent, id, p, rng.randf() * TAU, Vector3.ONE * rng.randf_range(0.8, 1.3))
		stats.mire += 1
	# Old trees and fallen logs on the rim; landmarks.
	for i in 7:
		var a := i * TAU / 7.0 + rng.randf_range(-0.2, 0.2)
		var p := Vector3(cos(a) * (fight_radius + 12.0), 0, sin(a) * (fight_radius + 12.0))
		if not clear.call(p, 16.0):
			continue
		_mire(parent, "fen_elder_tree" if i % 2 == 0 else "hollow_fallen_log", p, rng.randf() * TAU, Vector3.ONE * rng.randf_range(0.8, 1.1))
		stats.mire += 1
	_mire(parent, "fen_waystone", Vector3(9, 0, 66), 0.3, Vector3.ONE)
	_mire(parent, "drowned_shrine", Vector3(0, 0, -fight_radius - 6.0), PI, Vector3.ONE * 1.2)
	stats.mire += 2
	return stats


static func _mire(parent: Node3D, id: String, pos: Vector3, yaw: float, scale: Vector3) -> void:
	var n := Node3D.new()
	n.set_script(load("res://art/scripts/mirewood_asset.gd"))
	n.set(&"model_id", id)
	n.set(&"collidable", false)
	n.name = "Mire_" + id
	n.set_meta(&"mire", true)
	n.position = pos
	n.rotation.y = yaw
	n.scale = scale
	parent.add_child(n)
