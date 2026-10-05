extends SceneTree
## Actual imported mesh and production placement cost, not measured GPU time.
## Counts distance-selected 64m batches before frustum/occlusion/automatic mesh LOD.
## Every world chunk is sampled so neighboring cells are never silently omitted.

const CAMERAS := {
	"close": Vector3(201, 24, -179),
	"gameplay": Vector3(280, 7, -160),
	"forest": Vector3(-525,10,-507),
	"forest_slope": Vector3(-830,24.364,-580),
	"highland": Vector3(-1090,12.118,570),
	"desert": Vector3(-300,5.987,-1470),
	"eastern": Vector3(910,13.617,-430),
	"volcanic": Vector3(1154,5.955,162),
}
const PROFILES := {
	"low": {"density": .35, "distance_scale": .7},
	"balanced": {"density": .65, "distance_scale": .85},
	"high": {"density": 1.0, "distance_scale": 1.0},
}
# Explicit geometry regression ceilings for fuller opaque grass/canopy meshes.
# Observed close/gameplay maxima at adoption: low 185106, balanced 484386,
# high 907770 triangles. These pre-frustum upper bounds are NOT GPU/FPS budgets.
const TRIANGLE_CEILINGS := {"low": 225000, "balanced": 550000, "high": 1050000}
var failures := 0
var mesh_info := {}

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func vector(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func check_quality_contract() -> void:
	# Check the evidence configuration against real production batch settings.
	# This requires no GPU timing or headless transform readback.
	for kind: String in ["grass_tuft", "grass_meadow_soft", "grass_meadow_straw", "shrub_salt", "shrub_meadow", "rock_02"]:
		for route_meadow: bool in [false, true]:
			for landmark: bool in [false, true]:
				var ranges := EnvironmentGroundcover.quality_ranges(kind, route_meadow, landmark)
				check(ranges.size() == 4 and ranges[0] == 0, "Invalid production LOD ranges: " + kind)
				for lod in 3:
					check(ranges[lod + 1] > ranges[lod], "Non-monotonic production LOD ranges: " + kind)
					var batch := MultiMeshInstance3D.new()
					batch.multimesh = MultiMesh.new()
					batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
					batch.multimesh.mesh = BoxMesh.new()
					batch.multimesh.instance_count = 100
					batch.set_meta(&"groundcover_kind", kind)
					batch.set_meta(&"groundcover_lod", lod)
					batch.set_meta(&"route_meadow", route_meadow)
					batch.set_meta(&"authored_landmark", landmark)
					for profile: String in PROFILES:
						EnvironmentGroundcover.apply_quality(batch, profile)
						var config: Dictionary = PROFILES[profile]
						check(is_equal_approx(batch.visibility_range_begin, ranges[lod] * config.distance_scale), "Evidence/production LOD begin differs: " + kind + "/" + profile)
						check(is_equal_approx(batch.visibility_range_end, ranges[lod + 1] * config.distance_scale), "Evidence/production LOD end differs: " + kind + "/" + profile)
						check(batch.multimesh.visible_instance_count == (100 if landmark else ceili(100 * config.density)), "Evidence/production density differs: " + kind + "/" + profile)
					batch.free()

func capture_generator() -> GDScript:
	# Reuse the real landmark generator, including all RNG calls. Instrument only
	# output sinks in memory; never rewrite source or read dummy-renderer transforms.
	var source := FileAccess.get_file_as_string("res://src/world/forbidden_lands_terrain.gd")
	var start := source.find("static func _landscape_batch(")
	var end := source.find("static func _bridge_art(", start)
	if start < 0 or end <= start:
		check(false, "Cannot locate production landscape output sink")
		return null
	source = source.substr(0, start) + "static func _landscape_batch(_parent: Node3D, _kind: String, _origin: Vector3, _transforms: Array[Transform3D]) -> void:\n\tpass\n\n" + source.substr(end)
	var sink := "\tEnvironmentGroundcover.append_chunk(details, origin, groups, layout)"
	if not source.contains(sink):
		check(false, "Cannot locate production groundcover output sink")
		return null
	source = source.replace(sink, "\tcaptured[origin] = {\"current\": EnvironmentGroundcover.sample_chunk(origin, groups, layout), \"legacy\": EnvironmentGroundcover._sample_legacy(origin, groups, layout)}")
	source = source.replace("\t\tAuthoredNature.append_chunk(details, origin)", "\t\tpass")
	source = source.replace("class_name ForbiddenLandsTerrain\n", "")
	source += "\nstatic var captured := {}\n"
	var script := GDScript.new()
	script.source_code = source
	if script.reload() != OK:
		check(false, "Production sampler instrumentation did not compile")
		return null
	return script

func info_for(kind: String) -> Dictionary:
	if mesh_info.has(kind):
		return mesh_info[kind]
	var triangles := []
	var surfaces := []
	var bounds := AABB()
	for lod in 3:
		var mesh: Mesh = EnvironmentGroundcover.ASSET.mesh_for(kind, lod)
		check(mesh != null, "Missing mesh: %s LOD%d" % [kind, lod])
		if mesh == null:
			return {}
		var count := 0
		for surface in mesh.get_surface_count():
			if mesh is ArrayMesh:
				check(mesh.surface_get_primitive_type(surface) == Mesh.PRIMITIVE_TRIANGLES, "Non-triangle groundcover surface")
			var arrays := mesh.surface_get_arrays(surface)
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			var vertices: Variant = arrays[Mesh.ARRAY_VERTEX]
			count += int(indices.size() / 3) if indices != null and not indices.is_empty() else int(vertices.size() / 3)
		triangles.append(count)
		surfaces.append(mesh.get_surface_count())
		bounds = mesh.get_aabb() if lod == 0 else bounds.merge(mesh.get_aabb())
	mesh_info[kind] = {"triangles_by_lod": triangles, "surfaces_by_lod": surfaces, "merged_bounds": bounds}
	return mesh_info[kind]

func batches_for(captured: Dictionary, variant: String) -> Array:
	var batches := []
	for origin: Vector2i in captured:
		var cells: Dictionary = captured[origin][variant]
		for cell: Vector2i in cells:
			for kind: String in cells[cell]:
				var transforms: Array = cells[cell][kind]
				var info := info_for(kind)
				if info.is_empty():
					continue
				var anchor := Vector3((cell.x + .5) * EnvironmentGroundcover.CELL, 0, (cell.y + .5) * EnvironmentGroundcover.CELL)
				for xf: Transform3D in transforms:
					anchor.y += xf.origin.y / transforms.size()
				var shared_bounds := AABB()
				for index in transforms.size():
					var local: Transform3D = transforms[index]
					local.origin -= anchor
					var transformed: AABB = local * info.merged_bounds
					shared_bounds = transformed if index == 0 else shared_bounds.merge(transformed)
				# This is the same combined AABB used by all three production LODs,
				# across profiles, including instances omitted by the density prefix.
				batches.append({"kind": kind, "route_meadow": variant == "current" and EnvironmentGroundcover.is_route_chunk(origin, 5), "chunk": [origin.x, origin.y], "cell": [cell.x, cell.y], "count": transforms.size(),
					"center": anchor + shared_bounds.get_center(), "aabb_size": shared_bounds.size,
					"triangles_by_lod": info.triangles_by_lod, "surfaces_by_lod": info.surfaces_by_lod})
	return batches

func camera_cost(batches: Array, camera: Vector3, profile: String) -> Dictionary:
	var config: Dictionary = PROFILES[profile]
	var draws := 0
	var triangles := 0
	var placements := 0
	var selected := []
	var per_kind := {}
	var per_lod := [0, 0, 0]
	var nearby_chunks := {}
	for batch: Dictionary in batches:
		var ranges := EnvironmentGroundcover.quality_ranges(batch.kind, batch.route_meadow, false)
		var distance: float = camera.distance_to(batch.center)
		for lod in 3:
			if distance < ranges[lod] * config.distance_scale or distance >= ranges[lod + 1] * config.distance_scale:
				continue
			var visible := maxi(1, ceili(batch.count * config.density))
			var batch_triangles: int = visible * batch.triangles_by_lod[lod]
			var batch_draws: int = batch.surfaces_by_lod[lod]
			placements += visible
			triangles += batch_triangles
			draws += batch_draws
			per_lod[lod] += 1
			nearby_chunks[str(batch.chunk)] = true
			if not per_kind.has(batch.kind):
				per_kind[batch.kind] = {"batches": 0, "draw_surfaces": 0, "instances": 0, "triangles": 0}
			per_kind[batch.kind].batches += 1
			per_kind[batch.kind].draw_surfaces += batch_draws
			per_kind[batch.kind].instances += visible
			per_kind[batch.kind].triangles += batch_triangles
			selected.append({"kind": batch.kind, "chunk": batch.chunk, "cell": batch.cell,
				"aabb_center": vector(batch.center), "aabb_size": vector(batch.aabb_size), "distance": distance,
				"lod": lod, "total_instances": batch.count, "visible_instances": visible,
				"triangles": batch_triangles, "draw_surfaces": batch_draws})
	return {"selected_batches": selected.size(), "draw_surfaces": draws, "visible_instances": placements,
		"triangles": triangles, "batches_by_lod": per_lod, "nearby_chunk_count": nearby_chunks.size(),
		"by_kind": per_kind, "batch_details": selected}

func prefix_coverage(captured: Dictionary) -> Dictionary:
	# A z-major source prefix would shift dense cell means by roughly 10–20m.
	# Report the deterministic shuffle's actual aggregate bias without requiring
	# every small random prefix to cover every quarter of an irregular clearing.
	var result := {}
	for profile: String in ["low", "balanced"]:
		var groups := 0
		var mean_delta := Vector2.ZERO
		var mean_absolute_delta := Vector2.ZERO
		for origin: Vector2i in captured:
			if not EnvironmentGroundcover.is_route_chunk(origin, 5):
				continue
			var cells: Dictionary = captured[origin].current
			for cell: Vector2i in cells:
				for kind: String in cells[cell]:
					var transforms: Array = cells[cell][kind]
					if not kind.begins_with("grass_") or transforms.size() < 32:
						continue
					var full_mean := Vector2.ZERO
					var prefix_mean := Vector2.ZERO
					var prefix_count := maxi(1, ceili(transforms.size() * PROFILES[profile].density))
					for index in transforms.size():
						var position: Vector3 = transforms[index].origin
						full_mean += Vector2(position.x, position.z) / transforms.size()
						if index < prefix_count:
							prefix_mean += Vector2(position.x, position.z) / prefix_count
					var delta := prefix_mean - full_mean
					mean_delta += delta
					mean_absolute_delta += delta.abs()
					groups += 1
		if groups > 0:
			mean_delta /= groups
			mean_absolute_delta /= groups
		check(groups >= 10, "Insufficient dense route groups for quality-prefix coverage check")
		check(absf(mean_delta.y) < 5.0, "Groundcover quality prefix has systematic z bias: " + profile)
		result[profile] = {"dense_grass_groups": groups, "mean_prefix_minus_full_center_xz_m": [mean_delta.x, mean_delta.y],
			"mean_absolute_prefix_center_delta_xz_m": [mean_absolute_delta.x, mean_absolute_delta.y]}
	return result

func run() -> void:
	var started := Time.get_ticks_usec()
	check_quality_contract()
	var capture := capture_generator()
	if capture == null:
		quit(1)
		return
	var world := Node3D.new()
	root.add_child(world)
	for z in range(ForbiddenLandsTerrain.MINIMUM.y, ForbiddenLandsTerrain.MAXIMUM.y, ForbiddenLandsTerrain.CHUNK):
		for x in range(ForbiddenLandsTerrain.MINIMUM.x, ForbiddenLandsTerrain.MAXIMUM.x, ForbiddenLandsTerrain.CHUNK):
			capture._detail_chunk(world, Vector2i(x, z), 5)
	var prefix_metrics := prefix_coverage(capture.captured)
	var variants := {}
	for variant: String in ["current", "legacy"]:
		var batches := batches_for(capture.captured, variant)
		var population := 0
		for batch: Dictionary in batches:
			population += batch.count
		var cameras := {}
		for camera_name: String in CAMERAS:
			var costs := {}
			for profile: String in PROFILES:
				costs[profile] = camera_cost(batches, CAMERAS[camera_name], profile)
			cameras[camera_name] = {"position": vector(CAMERAS[camera_name]), "profiles": costs}
		variants[variant] = {"all_world_placements": population, "spatial_kind_groups": batches.size(), "allocated_lod_batches": batches.size() * 3,
			"transform_color_payload_bytes": population * 3 * 64, "cameras": cameras}
	var summary := {}
	for camera_name: String in CAMERAS:
		summary[camera_name] = {}
		for profile: String in PROFILES:
			var current: Dictionary = variants.current.cameras[camera_name].profiles[profile]
			var legacy: Dictionary = variants.legacy.cameras[camera_name].profiles[profile]
			check(current.triangles <= TRIANGLE_CEILINGS[profile], "Route reference-camera geometry exceeds explicit profile ceiling: " + camera_name + "/" + profile)
			summary[camera_name][profile] = {"current_triangles": current.triangles, "legacy_triangles": legacy.triangles,
				"current_batches": current.selected_batches, "legacy_batches": legacy.selected_batches,
				"current_instances": current.visible_instances, "legacy_instances": legacy.visible_instances,
				"triangle_ratio": float(current.triangles) / legacy.triangles if legacy.triangles > 0 else null}
	var models := {}
	for kind: String in mesh_info:
		var info: Dictionary = mesh_info[kind]
		models[kind] = {"triangles_by_lod": info.triangles_by_lod, "surfaces_by_lod": info.surfaces_by_lod,
			"merged_bounds_position": vector(info.merged_bounds.position), "merged_bounds_size": vector(info.merged_bounds.size)}
	var report := {"failures": failures, "layout": 5, "world_chunks_sampled": capture.captured.size(),
		"comparison": "Current sampler versus legacy sampler on identical layout-5 surface and production landmarks; legacy cost uses the current imported legacy meshes",
		"production_ranges_source_sha256": FileAccess.get_file_as_string("res://src/world/environment_groundcover.gd").sha256_text(),
		"counting_method": "Actual imported base triangles, shared production AABB centers, exact profile density and LOD distance selection; pre-frustum/occlusion/automatic mesh LOD upper bound, not measured GPU draws or FPS",
		"profiles": PROFILES, "triangle_regression_ceilings": TRIANGLE_CEILINGS, "quality_prefix_coverage": prefix_metrics, "models": models, "summary": summary, "variants": variants,
		"gpu_fps_measured": false, "elapsed_usec": Time.get_ticks_usec() - started}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	var output := FileAccess.open("res://tests/output/route_density_cost.json", FileAccess.WRITE)
	check(output != null, "Could not open route density cost report")
	if output:
		report.failures = failures
		output.store_string(JSON.stringify(report, "  "))
		output.close()
	print("ROUTE_DENSITY_COST: ", JSON.stringify({"failures": failures, "models": models, "summary": summary, "quality_prefix_coverage": prefix_metrics, "world_chunks_sampled": capture.captured.size(), "gpu_fps_measured": false}))
	world.free()
	quit(1 if failures else 0)
