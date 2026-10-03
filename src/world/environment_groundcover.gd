class_name EnvironmentGroundcover
extends RefCounted
## Render-only understory. Existing opaque Saltward assets, spatial MultiMesh LODs.
## No nodes participate in physics, navigation, replay state or gameplay RNG.
const ASSET = preload("res://art/scripts/art_asset.gd")
const MATERIAL = preload("res://materials/environment/groundcover_atlas.tres")
const KINDS := ["grass_tuft", "grass_dry", "shrub_salt"]
const CELL := 64.0
static var _roads_by_chunk := {}

static func allowed(p: Vector2, shrub := false) -> bool:
	if maxf(absf(p.x), absf(p.y)) < 210:
		return false
	if ForbiddenLandsTerrain.road_distance(p) < (28.0 if shrub else 22.0):
		return false
	for kind: StringName in ForbiddenLands.REGIONS:
		if p.distance_to(ForbiddenLands.REGIONS[kind][0]) < 218:
			return false
	var h := ForbiddenLandsTerrain.surface_height(p.x, p.y)
	if h < -6 or h > 65:
		return false
	# Reject steep faces using the rendered triangle surface, not analytic hills.
	var dx := ForbiddenLandsTerrain.surface_height(p.x + 2, p.y) - h
	var dz := ForbiddenLandsTerrain.surface_height(p.x, p.y + 2) - h
	return Vector2(dx, dz).length() < 1.35

static func _roads_in_chunk(origin: Vector2i) -> Array:
	if _roads_by_chunk.is_empty():
		for edge: Array in ForbiddenLands.road_edges():
			var middle: Vector3 = (edge[0] + edge[1]) * .5
			var cell := Vector2i(floori(middle.x / 256) * 256, floori(middle.z / 256) * 256)
			if not _roads_by_chunk.has(cell):
				_roads_by_chunk[cell] = []
			_roads_by_chunk[cell].append(edge)
	return _roads_by_chunk.get(origin, [])

static func tint_at(kind: String, position: Vector3) -> Color:
	# Restrained continuous variation, shared by every LOD and graphics profile.
	var weights := ForbiddenLandsTerrain.biome_weights(position.x, position.z)
	var dry: float = maxf(weights.desert, weights.highland * .65)
	var patch := .5 + .5 * sin(position.x * .037 + sin(position.z * .023) * 2.0)
	var green := Color(.80, .96, .73).lerp(Color(1.0, .95, .79), dry)
	if kind == "grass_dry":
		green = Color(.94, .88, .73).lerp(Color(1.0, .97, .86), patch)
	return green.lerp(Color(1, 1, .95), patch * .25)

static func sample_chunk(origin: Vector2i, landmarks: Dictionary = {}) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 918273 + origin.x * 157 + origin.y * 313
	var roads := _roads_in_chunk(origin)
	var anchors: Array[Vector4] = []
	for kind: String in landmarks:
		var radius := 5.0
		if kind in ForbiddenLandsTerrain.LANDSCAPE_KINDS:
			ForbiddenLandsTerrain._prime_landscape(kind)
			var bounds: AABB = ForbiddenLandsTerrain._landscape_meshes[kind][0].get_aabb()
			radius = Vector2(bounds.size.x, bounds.size.z).length() * .5
		for xf: Transform3D in landmarks[kind]:
			anchors.append(Vector4(xf.origin.x, xf.origin.z, radius * xf.basis.get_scale().length() / sqrt(3.0), 0))
	var cells := {}
	# A fixed candidate budget redistributes detail toward authored landscape,
	# instead of adding more instances. Eight colonies replace the first pass's ten.
	for colony in 8:
		var centre := Vector2(origin) + Vector2(rng.randf_range(8, 248), rng.randf_range(8, 248))
		var axis := Vector2.from_angle(rng.randf_range(-PI, PI))
		var spread := Vector2(rng.randf_range(8, 15), rng.randf_range(3, 7))
		if colony < 2 and not anchors.is_empty():
			var landmark := anchors[rng.randi_range(0, anchors.size() - 1)]
			centre = Vector2(landmark.x, landmark.y) + axis * (landmark.z + 5.0)
			axis = axis.orthogonal()
			spread = Vector2(8, 3)
		elif colony < 4 and not roads.is_empty():
			var edge: Array = roads[rng.randi_range(0, roads.size() - 1)]
			var a: Vector3 = edge[0]
			var b: Vector3 = edge[1]
			axis = Vector2(b.x - a.x, b.z - a.z).normalized()
			var on_road := a.lerp(b, rng.randf())
			centre = Vector2(on_road.x, on_road.z) + axis.orthogonal() * (34.0 if colony % 2 == 0 else -34.0)
			spread = Vector2(18, 5)
		var weights := ForbiddenLandsTerrain.biome_weights(centre.x, centre.y)
		var dry: float = maxf(weights.desert, weights.highland * .7)
		var density: float = lerpf(1.0, .35, dry) * lerpf(1.0, .2, weights.volcanic)
		if rng.randf() > density:
			continue
		var shrub := colony % 5 == 0
		var kind := "shrub_salt" if shrub else ("grass_dry" if rng.randf() < dry else "grass_tuft")
		var count := 4 if shrub else 14
		var colony_scale := rng.randf_range(.85, 1.2)
		for item in count:
			var angle := rng.randf_range(-PI, PI)
			var radius := sqrt(rng.randf())
			var p := centre + (axis * cos(angle) * spread.x + axis.orthogonal() * sin(angle) * spread.y) * radius
			if p.x < origin.x or p.x >= origin.x + 256 or p.y < origin.y or p.y >= origin.y + 256:
				continue
			if not allowed(p, shrub):
				continue
			var cell := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
			if not cells.has(cell):
				cells[cell] = {}
			if not cells[cell].has(kind):
				cells[cell][kind] = []
			# Sparse short edges and fuller colony hearts remain legible on the road.
			var size := rng.randf_range(.8, 1.35) * colony_scale * lerpf(1.15, .8, radius)
			var basis := Basis(Vector3.UP, rng.randf_range(-PI, PI)).scaled(Vector3(size, size * rng.randf_range(.8, 1.15), size))
			var position := Vector3(p.x, ForbiddenLandsTerrain.surface_height(p.x, p.y) - .04, p.y)
			cells[cell][kind].append(Transform3D(basis, position))
	return cells

static func append_chunk(parent: Node3D, origin: Vector2i, landmarks: Dictionary = {}) -> void:
	var cells := sample_chunk(origin, landmarks)
	var profile := "balanced"
	var ancestor: Node = parent
	while ancestor:
		if ancestor.has_meta(&"environment_groundcover_profile"):
			profile = ancestor.get_meta(&"environment_groundcover_profile")
			break
		ancestor = ancestor.get_parent()
	for cell: Vector2i in cells:
		var anchor := Vector3((cell.x + .5) * CELL, 0, (cell.y + .5) * CELL)
		for kind: String in cells[cell]:
			var transforms: Array = cells[cell][kind]
			anchor.y = 0
			for xf: Transform3D in transforms:
				anchor.y += xf.origin.y / transforms.size()
			var mesh_bounds: AABB = ASSET.mesh_for(kind, 0).get_aabb()
			for lod in [1, 2]:
				mesh_bounds = mesh_bounds.merge(ASSET.mesh_for(kind, lod).get_aabb())
			var shared_bounds := AABB()
			var colors := PackedColorArray()
			for index in transforms.size():
				var local: Transform3D = transforms[index]
				colors.append(tint_at(kind, local.origin))
				local.origin -= anchor
				var bounds: AABB = local * mesh_bounds
				shared_bounds = bounds if index == 0 else shared_bounds.merge(bounds)
			for lod in 3:
				var multi := MultiMesh.new()
				multi.transform_format = MultiMesh.TRANSFORM_3D
				multi.use_colors = true
				multi.custom_aabb = shared_bounds
				multi.mesh = ASSET.mesh_for(kind, lod)
				multi.instance_count = transforms.size()
				for i in transforms.size():
					var xf: Transform3D = transforms[i]
					xf.origin -= anchor
					multi.set_instance_transform(i, xf)
					multi.set_instance_color(i, colors[i])
				var batch := MultiMeshInstance3D.new()
				batch.name = "Groundcover_%s_%d_%d_LOD%d" % [kind, cell.x, cell.y, lod]
				batch.set_meta(&"groundcover_kind", kind)
				batch.set_meta(&"groundcover_lod", lod)
				batch.position = anchor
				batch.multimesh = multi
				batch.material_override = MATERIAL
				batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				var ranges := [0.0, 45.0, 85.0, 140.0] if kind == "shrub_salt" else [0.0, 28.0, 55.0, 85.0]
				batch.visibility_range_begin = ranges[lod]
				batch.visibility_range_end = ranges[lod + 1]
				# Independent LODs need zero hysteresis and identical AABB centres:
				# nonzero margins can leave all initially hidden at a boundary.
				batch.visibility_range_begin_margin = 0
				batch.visibility_range_end_margin = 0
				apply_quality(batch, profile)
				parent.add_child(batch)

static func apply_quality(batch: MultiMeshInstance3D, profile: String) -> void:
	# Existing Settings applies this explicitly; no per-frame scripts or rebuild.
	var density := .35 if profile == "low" else (1.0 if profile == "high" else .65)
	var distance_scale := .7 if profile == "low" else (1.0 if profile == "high" else .85)
	batch.multimesh.visible_instance_count = maxi(1, ceili(batch.multimesh.instance_count * density))
	var shrub: bool = batch.get_meta(&"groundcover_kind") == "shrub_salt"
	var lod: int = batch.get_meta(&"groundcover_lod")
	var ranges := [0.0, 45.0, 85.0, 140.0] if shrub else [0.0, 28.0, 55.0, 85.0]
	batch.visibility_range_begin = ranges[lod] * distance_scale
	batch.visibility_range_end = ranges[lod + 1] * distance_scale
