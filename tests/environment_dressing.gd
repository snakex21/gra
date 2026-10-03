extends Node3D
## Rebuildable, visual-only groundcover and continuous regional tint regression.
var failures := 0
var deadline := Time.get_ticks_msec() + 120000
var tested_instances := 0
var tested_batches := 0
var kinds_seen := {}
var mesh_ids := {}
var quality_populations := {"low": 0, "balanced": 0, "high": 0}

func _process(_delta: float) -> void:
	if Time.get_ticks_msec() > deadline:
		push_error("Environment dressing test timed out")
		get_tree().quit(1)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _ready() -> void:
	var started := Time.get_ticks_usec()
	check_biomes()
	var foliage: StandardMaterial3D = load("res://materials/environment/groundcover_atlas.tres")
	check(foliage.vertex_color_use_as_albedo, "Groundcover tint material ignores instance colors")
	check(foliage.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "Groundcover must use opaque foliage")
	for z in range(ForbiddenLandsTerrain.MINIMUM.y, ForbiddenLandsTerrain.MAXIMUM.y, ForbiddenLandsTerrain.CHUNK):
		for x in range(ForbiddenLandsTerrain.MINIMUM.x, ForbiddenLandsTerrain.MAXIMUM.x, ForbiddenLandsTerrain.CHUNK):
			var origin := Vector2i(x, z)
			var fixture := Node3D.new()
			add_child(fixture)
			EnvironmentGroundcover.append_chunk(fixture, origin)
			inspect_chunk(fixture, origin, foliage)
			if x % 512 == 0 and z % 512 == 0:
				var repeat := Node3D.new()
				add_child(repeat)
				EnvironmentGroundcover.append_chunk(repeat, origin)
				check(snapshot(fixture) == snapshot(repeat), "Groundcover rebuild is nondeterministic: " + str(origin))
				repeat.free()
			check_live_quality(fixture)
			fixture.free()
	check(tested_instances > 100 and tested_instances <= 8840, "Groundcover placement count outside its explicit world budget")
	check(tested_batches <= 2988, "Groundcover exceeds its 2988-batch world budget")
	for kind: String in ["grass_tuft", "grass_dry", "shrub_salt"]:
		check(kinds_seen.has(kind), "Groundcover never populated " + kind)
	check(mesh_ids.size() == 9, "Groundcover should share exactly nine meshes across the world")
	check_incremental_quality()
	check_contextual_landmarks(foliage)
	check(quality_populations.low < quality_populations.balanced and quality_populations.balanced < quality_populations.high, "Quality presets do not reduce world foliage populations")
	var quality_lod_totals := {}
	for profile: String in quality_populations:
		quality_lod_totals[profile] = quality_populations[profile] * 3
	var report := {"quality_visible_placements": quality_populations, "quality_visible_all_lod_instances": quality_lod_totals, "allocated_all_lod_instances": tested_instances * 3, "estimated_raw_transform_color_buffer_bytes": tested_instances * 3 * 64, "failures": failures, "placements": tested_instances, "batches": tested_batches, "unique_meshes": mesh_ids.size(), "kinds": kinds_seen, "elapsed_usec": Time.get_ticks_usec() - started}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	var file := FileAccess.open("res://tests/output/environment_dressing.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("ENVIRONMENT_DRESSING: ", JSON.stringify(report))
	get_tree().quit(1 if failures else 0)

func snapshot(root: Node3D) -> PackedByteArray:
	var records := []
	for batch: MultiMeshInstance3D in root.find_children("*", "MultiMeshInstance3D", true, false):
		var placements := []
		for index in batch.multimesh.instance_count:
			placements.append(batch.multimesh.get_instance_transform(index))
		records.append([String(root.get_path_to(batch)), batch.transform, batch.visibility_range_begin, batch.visibility_range_end, placements])
	return var_to_bytes(records)

func inspect_chunk(root: Node3D, origin: Vector2i, foliage: Material, landmarks: Dictionary = {}, count_totals := true) -> void:
	var samples := EnvironmentGroundcover.sample_chunk(origin, landmarks)
	check(var_to_bytes(samples) == var_to_bytes(EnvironmentGroundcover.sample_chunk(origin, landmarks)), "Groundcover sample transforms changed on rebuild: " + str(origin))
	check(root.find_children("*", "CollisionObject3D", true, false).is_empty(), "Groundcover added a collision body")
	check(root.find_children("*", "CollisionShape3D", true, false).is_empty(), "Groundcover added a collision shape")
	for batch: MultiMeshInstance3D in root.find_children("*", "MultiMeshInstance3D", true, false):
		if count_totals: tested_batches += 1
		var kind := ""
		for candidate: String in ["grass_tuft", "grass_dry", "shrub_salt"]:
			if String(batch.name).contains(candidate):
				kind = candidate
		check(not kind.is_empty(), "Groundcover batch must identify its kind: " + String(batch.name))
		var shrub := kind == "shrub_salt"
		check(batch.material_override == foliage, "Groundcover duplicated or replaced its shared opaque material")
		check(batch.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Groundcover unexpectedly casts shadows")
		check(batch.visibility_range_end > batch.visibility_range_begin and batch.visibility_range_end <= (140.0 if shrub else 85.0), "Groundcover visibility exceeds its LOD budget")
		check(batch.visibility_range_begin_margin == 0 and batch.visibility_range_end_margin == 0, "Independent groundcover LODs have hysteresis gaps")
		check(batch.multimesh.use_colors, "Groundcover MultiMesh has no color payload")
		check(batch.multimesh.instance_count > 0, "Groundcover created an empty batch")
		mesh_ids[batch.multimesh.mesh.get_instance_id()] = true
		check(batch.multimesh.mesh.get_surface_count() == 1, "Groundcover mesh has multiple draw surfaces")
		for index in batch.multimesh.instance_count:
			var local := batch.multimesh.get_instance_transform(index).origin
			check(absf(local.x) <= 32.001 and absf(local.z) <= 32.001, "Groundcover escaped its 64m rendering subcell")
		if String(batch.name).contains("LOD0"):
			for lod in [1, 2]:
				var peer := batch.get_parent().get_node_or_null(String(batch.name).replace("LOD0", "LOD%d" % lod)) as MultiMeshInstance3D
				check(peer != null, "Groundcover LOD sibling is missing")
				if peer:
					check(peer.multimesh.custom_aabb == batch.multimesh.custom_aabb, "Groundcover LODs have different visibility centers")
					check(peer.position == batch.position, "Groundcover LOD anchors differ")
					check(peer.multimesh.instance_count == batch.multimesh.instance_count, "Groundcover LOD populations differ")
					if peer.multimesh.instance_count == batch.multimesh.instance_count:
						for index in batch.multimesh.instance_count:
							check(peer.multimesh.get_instance_transform(index) == batch.multimesh.get_instance_transform(index), "Groundcover shifts during an LOD transition")
		var anchor_cell := Vector2i(floori(batch.position.x / 64.0), floori(batch.position.z / 64.0))
		var expected_y := 0.0
		for xf: Transform3D in samples[anchor_cell][kind]:
			expected_y += xf.origin.y / samples[anchor_cell][kind].size()
		check(absf(batch.position.y - expected_y) < .001, "Groundcover anchor is not at the placement mean height")
		if not String(batch.name).contains("LOD0"):
			continue
		if count_totals: kinds_seen[kind] = int(kinds_seen.get(kind, 0)) + batch.multimesh.instance_count
		for index in batch.multimesh.instance_count:
			if count_totals: tested_instances += 1
			var cell := Vector2i(floori(batch.position.x / 64.0), floori(batch.position.z / 64.0))
			var expected: Transform3D = samples[cell][kind][index]
			var p := expected.origin
			var tint := EnvironmentGroundcover.tint_at(kind, p)
			check(tint == EnvironmentGroundcover.tint_at(kind, p), "Groundcover tint is nondeterministic")
			check(tint.a == 1.0 and minf(tint.r, minf(tint.g, tint.b)) >= 0 and maxf(tint.r, maxf(tint.g, tint.b)) <= 1.0, "Groundcover tint is not bounded opaque color")
			var local_expected := expected
			local_expected.origin -= batch.position
			check(absf(local_expected.origin.x) <= 32.001 and absf(local_expected.origin.z) <= 32.001, "Sample escaped its 64m subcell")
			for lod in 3:
				var bounds: AABB = local_expected * EnvironmentGroundcover.ASSET.mesh_for(kind, lod).get_aabb()
				check(batch.multimesh.custom_aabb.grow(.001).encloses(bounds), "Common visibility bounds exclude groundcover geometry")
			# Dummy headless rendering does not retain MultiMesh transforms. Test the
			# authoritative placement samples there, and GPU uploads with a renderer.
			if DisplayServer.get_name() != "headless":
				var actual: Vector3 = batch.global_transform * batch.multimesh.get_instance_transform(index).origin
				check(actual.distance_to(p) < .001, "GPU groundcover transform differs from its sample")
				for lod in 3:
					var peer := batch.get_parent().get_node(String(batch.name).replace("LOD0", "LOD%d" % lod)) as MultiMeshInstance3D
					var actual_tint := peer.multimesh.get_instance_color(index)
					# Compatibility stores per-channel half floats; values near one can
					# differ by up to one 1/1024 step from the authored float32 tint.
					var epsilon := 1.0 / 1024.0 if RenderingServer.get_current_rendering_method() == "gl_compatibility" else .00001
					check(tint_close(actual_tint, tint, epsilon), "GPU instance tint differs from the sample beyond renderer precision")
					check(actual_tint.is_equal_approx(batch.multimesh.get_instance_color(index)), "GPU instance tint differs across LODs")
			var flat := Vector2(p.x, p.z)
			check(p.x >= origin.x and p.x < origin.x + ForbiddenLandsTerrain.CHUNK and p.z >= origin.y and p.z < origin.y + ForbiddenLandsTerrain.CHUNK, "Groundcover escaped its chunk")
			check(maxf(absf(p.x), absf(p.z)) >= 210, "Groundcover entered the central playable valley")
			check(ForbiddenLandsTerrain.road_distance(flat) >= (28.0 if shrub else 22.0) - .001, "Groundcover entered a road clearance")
			for arena: StringName in ForbiddenLands.REGIONS:
				check(flat.distance_to(ForbiddenLands.REGIONS[arena][0]) >= 218.0 - .001, "Groundcover entered an arena clearance")
			var height := ForbiddenLandsTerrain.surface_height(p.x, p.z)
			check(height >= -6.001 and height <= 65.001, "Groundcover was planted outside its permitted height band")
			check(absf(p.y - height) < .5, "Groundcover does not follow the triangulated terrain surface")
			var dx := ForbiddenLandsTerrain.surface_height(p.x + 2, p.z) - height
			var dz := ForbiddenLandsTerrain.surface_height(p.x, p.z + 2) - height
			check(Vector2(dx, dz).length() < 1.351, "Groundcover was planted on excessively steep terrain")

func tint_close(actual: Color, expected: Color, epsilon: float) -> bool:
	return absf(actual.r - expected.r) <= epsilon and absf(actual.g - expected.g) <= epsilon and absf(actual.b - expected.b) <= epsilon and absf(actual.a - expected.a) <= epsilon

func check_biomes() -> void:
	for z in range(-2000, 1800, 100):
		for x in range(-2200, 1800, 100):
			var weights := ForbiddenLandsTerrain.biome_weights(x, z)
			for key: String in ["forest", "desert", "highland", "eastern", "volcanic"]:
				check(weights.has(key), "Missing soft biome weight " + key)
				check(float(weights.get(key, -1)) >= 0 and float(weights.get(key, 2)) <= 1, "Biome weight outside [0, 1]")
	# Fixed height isolates regional tint from topographic shading. The old hard
	# biome conditions jump at these borders; a centimetre should not change tint.
	for p: Vector2 in [Vector2(-650, 0), Vector2(-350, -600), Vector2(-800, -300), Vector2(-800, -1050), Vector2(700, 0), Vector2(1100, 0), Vector2(1200, 300), Vector2(0, 750)]:
		var left := ForbiddenLandsTerrain.biome_color(p.x - .01, p.y - .01, 0)
		var right := ForbiddenLandsTerrain.biome_color(p.x + .01, p.y + .01, 0)
		check(Vector3(left.r, left.g, left.b).distance_to(Vector3(right.r, right.g, right.b)) < .005, "Regional tint has a hard seam at " + str(p))

func geometry_snapshot(root: Node3D) -> PackedByteArray:
	var records := []
	for batch: MultiMeshInstance3D in root.find_children("*", "MultiMeshInstance3D", true, false):
		var transforms := []
		for index in batch.multimesh.instance_count:
			transforms.append([batch.multimesh.get_instance_transform(index), batch.multimesh.get_instance_color(index)])
		records.append([batch.get_instance_id(), batch.multimesh.get_instance_id(), batch.multimesh.mesh.get_instance_id(), batch.transform, batch.multimesh.instance_count, batch.multimesh.custom_aabb, transforms])
	return var_to_bytes(records)

func inspect_quality(root: Node3D, profile: String, count_population := false) -> void:
	var density := .35 if profile == "low" else (1.0 if profile == "high" else .65)
	var distance_scale := .7 if profile == "low" else (1.0 if profile == "high" else .85)
	for batch: MultiMeshInstance3D in root.find_children("*", "MultiMeshInstance3D", true, false):
		var kind: String = batch.get_meta(&"groundcover_kind")
		var lod: int = batch.get_meta(&"groundcover_lod")
		var expected := maxi(1, ceili(batch.multimesh.instance_count * density))
		check(batch.multimesh.visible_instance_count == expected, "Incorrect visible population for " + profile)
		var ranges := [0.0, 45.0, 85.0, 140.0] if kind == "shrub_salt" else [0.0, 28.0, 55.0, 85.0]
		check(is_equal_approx(batch.visibility_range_begin, ranges[lod] * distance_scale) and is_equal_approx(batch.visibility_range_end, ranges[lod + 1] * distance_scale), "Incorrect quality LOD range")
		if lod < 2:
			var peer := batch.get_parent().get_node(String(batch.name).replace("LOD%d" % lod, "LOD%d" % (lod + 1))) as MultiMeshInstance3D
			check(is_equal_approx(batch.visibility_range_end, peer.visibility_range_begin), "Quality LOD ranges overlap or leave a gap")
			check(peer.multimesh.visible_instance_count == expected, "Quality LOD populations differ")
		if lod == 0: check_lod_boundaries(batch)
		if lod == 0 and count_population:
			quality_populations[profile] += expected

func check_live_quality(root: Node3D) -> void:
	var before := geometry_snapshot(root)
	for profile: String in ["low", "balanced", "high", "low"]:
		GraphicsQuality.apply(root, profile)
		check(root.get_meta(&"environment_groundcover_profile") == profile, "Graphics quality did not retain its incremental profile")
		inspect_quality(root, profile, profile != "low")
		check(geometry_snapshot(root) == before, "Live quality changed placement geometry or rebuilt render objects")
	# Count low only once, after returning to it from high.
	for batch: MultiMeshInstance3D in root.find_children("*", "MultiMeshInstance3D", true, false):
		if batch.get_meta(&"groundcover_lod") == 0:
			quality_populations.low += batch.multimesh.visible_instance_count

func check_incremental_quality() -> void:
	for profile: String in ["low", "balanced", "high"]:
		var world := Node3D.new()
		add_child(world)
		GraphicsQuality.apply(world, profile)
		var nested := Node3D.new()
		world.add_child(nested)
		var details := Node3D.new()
		nested.add_child(details)
		EnvironmentGroundcover.append_chunk(details, Vector2i(-768, -768))
		check(not details.get_children().is_empty(), "Incremental quality fixture has no samples")
		inspect_quality(details, profile)
		world.free()

func check_contextual_landmarks(foliage: Material) -> void:
	var origin := Vector2i(-768, -768)
	var landmarks := {
		"oak": [Transform3D(Basis.IDENTITY, Vector3(-710, 0, -700))],
		"rock_shelf": [Transform3D(Basis.IDENTITY, Vector3(-605, 0, -675))],
		"ruin_arch": [Transform3D(Basis.IDENTITY, Vector3(-650, 0, -585))],
	}
	var before := var_to_bytes(landmarks)
	var fixture := Node3D.new()
	add_child(fixture)
	EnvironmentGroundcover.append_chunk(fixture, origin, landmarks)
	check(not fixture.get_children().is_empty(), "Contextual landmark fixture has no groundcover")
	inspect_chunk(fixture, origin, foliage, landmarks, false)
	check(var_to_bytes(landmarks) == before, "Groundcover mutated its landmark transforms")
	fixture.free()

func initial_lod_visible(distance: float, batch: MultiMeshInstance3D) -> bool:
	# Computational regression for initially hidden Godot visibility ranges;
	# this does not claim to measure actual GPU drawing or rendered appearance.
	return not ((batch.visibility_range_end > 0 and distance > batch.visibility_range_end - batch.visibility_range_end_margin) or (batch.visibility_range_begin > 0 and distance < batch.visibility_range_begin + batch.visibility_range_begin_margin))

func check_lod_boundaries(first: MultiMeshInstance3D) -> void:
	var peers: Array[MultiMeshInstance3D] = [first]
	for lod in [1, 2]:
		peers.append(first.get_parent().get_node(String(first.name).replace("LOD0", "LOD%d" % lod)) as MultiMeshInstance3D)
	var center := first.position + first.multimesh.custom_aabb.get_center()
	for boundary: float in [peers[0].visibility_range_end, peers[1].visibility_range_end]:
		for offset: float in [-.01, 0.0, .01]:
			var camera := center + Vector3(boundary + offset, 0, 0)
			var visible := 0
			for peer in peers:
				var peer_center := peer.position + peer.multimesh.custom_aabb.get_center()
				if initial_lod_visible(camera.distance_to(peer_center), peer): visible += 1
			check(visible > 0, "All groundcover LODs are hidden near an adjacent threshold")
			if offset != 0: check(visible == 1, "Groundcover LODs overlap away from the exact boundary")
