class_name EnvironmentGroundcover
extends RefCounted
## Render-only understory. Original meadow patches, opaque materials, spatial MultiMesh LODs.
## No nodes participate in physics, navigation, replay state or gameplay RNG.
const ASSET = preload("res://art/scripts/art_asset.gd")
const MATERIAL = preload("res://materials/environment/groundcover_atlas.tres")
const KINDS := ["grass_tuft", "grass_dry", "shrub_salt"]
const CELL := 64.0
const ROUTE_ROWS := 80
const ROUTE_SPACING := 256.0 / ROUTE_ROWS
static var _roads_by_chunk := {}

static func allowed(p: Vector2, shrub := false, layout := 3, inner_clearance := 210.0, footprint_margin := 0.0) -> bool:
	if maxf(absf(p.x), absf(p.y)) < inner_clearance:
		return false
	var road_clearance := 28.0 if shrub else 22.0
	if footprint_margin > 0:
		road_clearance = maxf(road_clearance, ForbiddenLands.road_half_at(p.x, p.y, layout) + footprint_margin)
	if ForbiddenLandsTerrain.road_distance(p, layout) < road_clearance:
		return false
	for kind: StringName in ForbiddenLands.regions(layout):
		if p.distance_to(ForbiddenLands.regions(layout)[kind][0]) < 218:
			return false
	var h := ForbiddenLandsTerrain.surface_height(p.x, p.y, layout)
	if h < -6 or h > 65:
		return false
	# Reject steep faces using the rendered triangle surface, not analytic hills.
	var dx := ForbiddenLandsTerrain.surface_height(p.x + 2, p.y, layout) - h
	var dz := ForbiddenLandsTerrain.surface_height(p.x, p.y + 2, layout) - h
	return Vector2(dx, dz).length() < 1.35

static func _roads_in_chunk(origin: Vector2i, layout := 3) -> Array:
	if not _roads_by_chunk.has(layout):
		_roads_by_chunk[layout] = {}
		for edge: Array in ForbiddenLands.road_edges(layout):
			var middle: Vector3 = (edge[0] + edge[1]) * .5
			var cell := Vector2i(floori(middle.x / 256) * 256, floori(middle.z / 256) * 256)
			if not _roads_by_chunk[layout].has(cell):
				_roads_by_chunk[layout][cell] = []
			_roads_by_chunk[layout][cell].append(edge)
	return _roads_by_chunk[layout].get(origin, [])

static func tint_at(kind: String, position: Vector3) -> Color:
	# Restrained continuous variation, shared by every LOD and graphics profile.
	var weights := ForbiddenLandsTerrain.biome_weights(position.x, position.z)
	var dry: float = maxf(weights.desert, weights.highland * .65)
	var patch := .5 + .5 * sin(position.x * .037 + sin(position.z * .023) * 2.0)
	var green := Color(.80, .96, .73).lerp(Color(1.0, .95, .79), dry)
	if kind == "grass_meadow_straw":
		green = Color(.82, .92, .90).lerp(Color(.95, .96, .91), patch * .35)
	elif kind == "biome_gravel":
		return Color(.94, .93, .88).lerp(Color(.78, .80, .79), weights.volcanic)
	elif kind == "biome_fern" or kind == "biome_rush":
		green = Color(.80, .96, .82).lerp(Color(.94, .98, .88), patch)
	elif kind == "biome_heather":
		green = Color(.94, .89, .86).lerp(Color(.88, .97, .83), weights.forest)
	elif kind == "biome_dry_scrub":
		green = Color(1.0, .92, .76)
	elif kind == "grass_dry":
		green = Color(.94, .88, .73).lerp(Color(1.0, .97, .86), patch)
	return green.lerp(Color(1, 1, .95), patch * .25)

static func sample_chunk(origin: Vector2i, landmarks: Dictionary = {}, layout := 3) -> Dictionary:
	# A render-only route meadow for layout five. Historical layouts keep the
	# original sampler, including its RNG sequence and quality budget.
	if is_route_chunk(origin, layout):
		return _sample_route_meadow(origin, layout)
	if layout == 5:
		return BiomeGroundcover.sample_chunk(origin, layout)
	return _sample_legacy(origin, landmarks, layout)

static func is_route_chunk(origin: Vector2i, layout: int) -> bool:
	return layout == 5 and origin.x >= 0 and origin.x < 768 and origin.y >= -768 and origin.y < 256

static func _route_state(origin: Vector2i, layout: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 573191 + origin.x * 157 + origin.y * 313
	return {"origin": origin, "layout": layout, "rng": rng, "cells": {}, "row": 0, "shuffled": false, "batches": [], "batch_cursor": 0}

static func _sample_route_rows(state: Dictionary, row_count: int, candidate_limit := 0) -> bool:
	# Yield points never change the candidate/RNG sequence. The synchronous
	# exporter and bounded runtime queue consume this exact same sampler.
	var origin: Vector2i = state.origin
	var layout: int = state.layout
	var rng: RandomNumberGenerator = state.rng
	var cells: Dictionary = state.cells
	var start_index := int(state.row) * ROUTE_ROWS + int(state.get("column", 0))
	var end_index := mini(ROUTE_ROWS * ROUTE_ROWS, start_index + (candidate_limit if candidate_limit > 0 else row_count * ROUTE_ROWS))
	for candidate in range(start_index, end_index):
		var iz := floori(float(candidate) / ROUTE_ROWS)
		var ix := candidate % ROUTE_ROWS
		var p := Vector2(origin) + Vector2((ix + .5) * ROUTE_SPACING, (iz + .5) * ROUTE_SPACING) + Vector2(rng.randf_range(-1.22, 1.22), rng.randf_range(-1.22, 1.22))
		var field := .5 + .27 * sin(p.x * .021 + sin(p.y * .014) * 2.1) + .20 * cos(p.y * .037 + p.x * .009)
		var edge := smoothstep(0, 65, minf(minf(p.x, 768-p.x), minf(p.y+768,256-p.y)))
		var precinct_edge := maxf(absf(p.x), absf(p.y))
		# The historic 210m square is scenery spacing, not a gameplay trigger.
		# The valley kit ends at172m; keep its180m precinct clear, then fade low
		# grass across the outer shoulder. Roads and arena approaches stay excluded.
		var shoulder := smoothstep(187, 207, precinct_edge)
		var density := lerpf(.08, .98, smoothstep(.20, .48, field)) * edge * shoulder
		if rng.randf() > density:
			continue
		var shrub := precinct_edge >= 217 and field > .32 and rng.randf() < lerpf(.22, .42, smoothstep(.32, .70, field))
		if not allowed(p, shrub, layout, 217.0 if shrub else 187.0, 6.0):
			continue
		var kind := "shrub_meadow" if shrub else ("grass_meadow_straw" if field < .43 or rng.randf() < .14 else "grass_meadow_soft")
		if not shrub and rng.randf() < .035:
			kind = "rock_02"
		var size := rng.randf_range(1.25, 1.70) if not shrub else rng.randf_range(1.4, 2.15)
		if kind == "rock_02":
			size = rng.randf_range(.30, .78)
		var height := ForbiddenLandsTerrain.surface_height(p.x, p.y, layout)
		var dx := (ForbiddenLandsTerrain.surface_height(p.x + 2, p.y, layout) - height) / 2
		var dz := (ForbiddenLandsTerrain.surface_height(p.x, p.y + 2, layout) - height) / 2
		var normal := Vector3(-dx, 1, -dz).normalized()
		var basis := Basis(Quaternion(Vector3.UP, normal)) * Basis(Vector3.UP, rng.randf_range(-PI, PI))
		var vertical := size * rng.randf_range(.65, 1.0) if kind == "rock_02" else (rng.randf_range(.75, 1.05) if shrub else rng.randf_range(1.10, 1.65))
		if not shrub and precinct_edge < 230:
			vertical *= lerpf(.45, 1.0, smoothstep(187, 230, precinct_edge))
		basis = basis.scaled_local(Vector3(size, vertical, size))
		var position := Vector3(p.x, ForbiddenLandsTerrain.surface_height(p.x, p.y, layout) - .035, p.y)
		kind = BiomeGroundcover.route_kind(kind, p)
		var cell := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
		if not cells.has(cell): cells[cell] = {}
		if not cells[cell].has(kind): cells[cell][kind] = []
		cells[cell][kind].append(Transform3D(basis, position))
	state.row = floori(float(end_index) / ROUTE_ROWS)
	state.column = end_index % ROUTE_ROWS
	return end_index == ROUTE_ROWS * ROUTE_ROWS

static func _shuffle_route_cells(cells: Dictionary, rng: RandomNumberGenerator) -> void:
	# Quality profiles draw a prefix. Shuffle within each spatial batch so low
	# and balanced thin evenly instead of exposing z-major grid stripes.
	for cell in cells:
		for kind in cells[cell]:
			_shuffle_route_instances(cells[cell][kind], rng)

static func _shuffle_route_instances(instances: Array, rng: RandomNumberGenerator) -> void:
	for i in range(instances.size() - 1, 0, -1):
		var other := rng.randi_range(0, i)
		var swap: Transform3D = instances[i]
		instances[i] = instances[other]
		instances[other] = swap

static func _sample_route_meadow(origin: Vector2i, layout: int) -> Dictionary:
	var state := _route_state(origin, layout)
	_sample_route_rows(state, ROUTE_ROWS)
	_shuffle_route_cells(state.cells, state.rng)
	return state.cells

static func _sample_legacy(origin: Vector2i, landmarks: Dictionary = {}, layout := 3) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 918273 + origin.x * 157 + origin.y * 313
	var roads := _roads_in_chunk(origin, layout)
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
			if not allowed(p, shrub, layout):
				continue
			var cell := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
			if not cells.has(cell):
				cells[cell] = {}
			if not cells[cell].has(kind):
				cells[cell][kind] = []
			# Sparse short edges and fuller colony hearts remain legible on the road.
			var size := rng.randf_range(.8, 1.35) * colony_scale * lerpf(1.15, .8, radius)
			var basis := Basis(Vector3.UP, rng.randf_range(-PI, PI)).scaled(Vector3(size, size * rng.randf_range(.8, 1.15), size))
			var position := Vector3(p.x, ForbiddenLandsTerrain.surface_height(p.x, p.y, layout) - .04, p.y)
			cells[cell][kind].append(Transform3D(basis, position))
	return cells

static func _profile_for(parent: Node) -> String:
	var profile := "balanced"
	var ancestor: Node = parent
	while ancestor:
		if ancestor.has_meta(&"environment_groundcover_profile"):
			profile = ancestor.get_meta(&"environment_groundcover_profile")
			break
		ancestor = ancestor.get_parent()
	return profile

static func append_chunk(parent: Node3D, origin: Vector2i, landmarks: Dictionary = {}, layout := 3) -> void:
	var route_meadow := is_route_chunk(origin, layout)
	if layout == 5:
		var ancestor: Node = parent
		while ancestor:
			if ancestor.has_meta(&"detail_job"):
				var job: ArenaArtBuild = ancestor.get_meta(&"detail_job")
				var state := _route_state(origin, layout) if route_meadow else BiomeGroundcover.state_for(origin, layout)
				# ArenaArtBuild.add wraps ordinary actions as completed. Append the
				# resumable callable directly so its false result preserves cursor.
				var parent_ref: WeakRef = weakref(parent)
				var continuation := func() -> bool: return _append_route_step(parent_ref.get_ref(), state)
				# Initial chunk jobs finish before any continuations run. Keep the
				# approved near-shrine corridor ahead of distant-world pockets.
				if route_meadow and job.has_meta(&"meadow_start_index") and job.cursor < int(job.get_meta(&"meadow_start_index")):
					job.jobs.insert(int(job.get_meta(&"meadow_start_index")), continuation)
				else:
					job.jobs.append(continuation)
				return
			ancestor = ancestor.get_parent()
	var cells := sample_chunk(origin, landmarks, layout)
	var profile := _profile_for(parent)
	for cell: Vector2i in cells:
		for kind: String in cells[cell]:
			_append_cell_kind(parent, cell, kind, cells[cell][kind], profile, route_meadow)

static func _append_route_step(parent: Node3D, state: Dictionary) -> bool:
	if state.get("done", false):
		return true
	if not is_instance_valid(parent):
		state.clear()
		state.done = true
		return true
	var began := Time.get_ticks_usec()
	# Four candidates and one LOD upload are the atomic
	# units. The soft 1.25ms cap avoids the former whole-chunk 80ms burst.
	var total_rows: int = state.get("total_rows", ROUTE_ROWS)
	while int(state.row) < total_rows:
		if state.get("biome_pockets", false):
			BiomeGroundcover.sample_rows(state, 4)
		else:
			_sample_route_rows(state, 1, 4)
		if int(state.row) == total_rows:
			# Shuffle starts on its own turn, not after an already spent sample budget.
			return false
		if Time.get_ticks_usec() - began >= 1250:
			return false
	if not state.shuffled:
		if not state.has("shuffle_cursor"):
			for cell: Vector2i in state.cells:
				for kind: String in state.cells[cell]:
					state.batches.append([cell, kind, state.cells[cell][kind]])
			state.shuffle_cursor = 0
		while state.shuffle_cursor < state.batches.size():
			_shuffle_route_instances(state.batches[state.shuffle_cursor][2], state.rng)
			state.shuffle_cursor += 1
			if Time.get_ticks_usec() - began >= 1250:
				return false
		state.shuffled = true
		return false
	var profile := _profile_for(parent)
	while int(state.batch_cursor) < state.batches.size():
		var batch: Array = state.batches[state.batch_cursor]
		if not state.has("prepared"):
			state.prepared = _prepare_cell_kind(batch[0], batch[1], batch[2])
			state.batch_lod = 0
			if Time.get_ticks_usec() - began >= 1250:
				return false
		_append_cell_lod(parent, batch[0], batch[1], batch[2], profile, not state.get("biome_pockets", false), state.prepared, state.batch_lod)
		state.batch_lod += 1
		if state.batch_lod == 3:
			state.erase("prepared")
			state.batch_cursor += 1
		if Time.get_ticks_usec() - began >= 1250:
			return false
	# Queue callables live as long as the terrain. Release the sampled CPU
	# transforms after native MultiMeshes own their copies.
	state.clear()
	state.done = true
	return true

static func _append_cell_kind(parent: Node3D, cell: Vector2i, kind: String, transforms: Array, profile: String, route_meadow := false) -> void:
	var prepared := _prepare_cell_kind(cell, kind, transforms)
	for lod in 3:
		_append_cell_lod(parent, cell, kind, transforms, profile, route_meadow, prepared, lod)

static func _prepare_cell_kind(cell: Vector2i, kind: String, transforms: Array) -> Dictionary:
	var anchor := Vector3((cell.x + .5) * CELL, 0, (cell.y + .5) * CELL)
	anchor.y = 0
	if kind.begins_with("biome_"):
		anchor = Vector3.ZERO
	for xf: Transform3D in transforms:
		if kind.begins_with("biome_"):
			anchor += xf.origin / transforms.size()
		else:
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
	return {"anchor": anchor, "bounds": shared_bounds, "colors": colors}

static func _append_cell_lod(parent: Node3D, cell: Vector2i, kind: String, transforms: Array, profile: String, route_meadow: bool, prepared: Dictionary, lod: int) -> void:
	var anchor: Vector3 = prepared.anchor
	var shared_bounds: AABB = prepared.bounds
	var colors: PackedColorArray = prepared.colors
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
	if route_meadow:
		batch.set_meta(&"route_meadow", true)
	batch.position = anchor
	batch.multimesh = multi
	batch.material_override = MATERIAL
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Explicit silhouette LODs must not receive a second aggressive mesh simplification.
	batch.lod_bias = 100.0 if route_meadow or kind.begins_with("biome_") else 1.0
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
	var landmark: bool = batch.get_meta(&"authored_landmark", false)
	# Keep the small authored rock/ruin silhouettes on every profile. Only their
	# LOD distance changes; foliage still uses the existing density budget.
	batch.multimesh.visible_instance_count = batch.multimesh.instance_count if landmark else maxi(1, ceili(batch.multimesh.instance_count * density))
	var lod: int = batch.get_meta(&"groundcover_lod")
	# Optional range authored by an isolated render layer; existing world biomes
	# keep the exact default quality ranges and placement/density behaviour.
	var ranges: Array = batch.get_meta(&"groundcover_ranges", quality_ranges(batch.get_meta(&"groundcover_kind"), batch.get_meta(&"route_meadow", false), landmark))
	batch.visibility_range_begin = ranges[lod] * distance_scale
	batch.visibility_range_end = ranges[lod + 1] * distance_scale

static func quality_ranges(kind: String, route_meadow := false, landmark := false) -> Array:
	if landmark:
		return [0.0, 55.0, 120.0, 260.0]
	var shrub := kind.begins_with("shrub_")
	if route_meadow:
		# Far clustered silhouettes preserve meadow mass at balanced settings.
		# Low/high still change density and distance, never replace a patch with
		# a handful of near-invisible individual sticks.
		return [0.0, 55.0, 135.0, 360.0] if shrub else [0.0, 42.0, 110.0, 330.0]
	if kind.begins_with("biome_"):
		return [0.0, 90.0, 155.0, 240.0]
	return [0.0, 45.0, 85.0, 140.0] if shrub else [0.0, 28.0, 55.0, 85.0]
