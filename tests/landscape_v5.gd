extends Node3D
## Actual imported geometry, shared GPU material and unchanged physical terrain.
var failures := 0
var deadline := Time.get_ticks_msec() + 120000

func _process(_delta: float) -> void:
	if Time.get_ticks_msec() > deadline:
		push_error("Landscape v5 test timed out or stopped after a runtime error")
		get_tree().quit(1)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _ready() -> void:
	get_window().size = Vector2i(1440, 900)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/landscape_v5_manifest.json"))
	var material: StandardMaterial3D = load("res://materials/landscape_v5/atlas.tres")
	var atlas_payload_bytes := 0
	check(material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "Landscape foliage uses transparent overdraw")
	for path: String in manifest.atlas_images:
		var texture: Texture2D = load(path)
		var image := texture.get_image()
		atlas_payload_bytes += image.get_data().size()
		check(image.get_width() == 1024 and image.get_height() == 1024, "Landscape atlas exceeded 1024: " + path)
		var config := ConfigFile.new()
		check(config.load(path + ".import") == OK, "Landscape import sidecar missing: " + path)
		check(config.get_value("params", "compress/mode", -1) == 2 and config.get_value("params", "mipmaps/generate", false), "Landscape atlas has no VRAM compression/mipmaps: " + path)
		if DisplayServer.get_name() != "headless":
			check(image.is_compressed() and image.has_mipmaps(), "Actual imported atlas was uncompressed or lacked mips: " + path)
	for item: Dictionary in manifest.items:
		ForbiddenLandsTerrain._prime_landscape(item.kind)
		for lod in 3:
			var scene: PackedScene = load(item.model_paths[lod])
			var model := scene.instantiate()
			check(model.find_children("*", "CollisionObject3D", true, false).is_empty(), "Landscape art adds colliders: " + item.kind)
			model.free()
			var mesh: Mesh = ForbiddenLandsTerrain._landscape_meshes[item.kind][lod]
			check(mesh.get_surface_count() == 1, "Landscape asset has multiple draw surfaces: " + item.kind)
			var arrays := mesh.surface_get_arrays(0)
			var count: int = arrays[Mesh.ARRAY_INDEX].size() / 3
			check(count == int(item.triangle_counts[lod]) and count <= [3000, 1000, 200][lod], "Actual imported mesh triangle budget mismatch: " + item.kind)
			check(not (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).is_empty(), "Landscape mesh lost atlas UV: " + item.kind)
			check(mesh.get_aabb().size.y > .3 and mesh.get_aabb().position.y > -.6, "Landscape geometry has wrong foot/Y-up frame: " + item.kind)
		check(item.triangle_counts[0] > item.triangle_counts[1] and item.triangle_counts[1] > item.triangle_counts[2], "Landscape LOD does not reduce geometry: " + item.kind)
	var region := Node3D.new()
	region.name = "LandscapePhysicalFixture"
	add_child(region)
	var began := Time.get_ticks_usec()
	ForbiddenLandsTerrain.build(region, true)
	var physical_before := physical_bytes(region)
	var surface_before := terrain_bytes(region)
	var heights := []
	for p: Vector2 in [Vector2(-235, 450), Vector2(-650, -480), Vector2(-1200, -100), Vector2(1100, -300)]:
		heights.append(ForbiddenLandsTerrain.height_at(p.x, p.y))
	ForbiddenLandsTerrain.finish_art(region)
	var terrain := region.get_node("ForbiddenLandsTerrain")
	var job: ArenaArtBuild = terrain.get_meta(&"detail_job")
	check(physical_bytes(region) == physical_before, "Landscape dressing changed physical shapes/transforms/layers")
	check(terrain_bytes(region) == surface_before, "Landscape dressing changed terrain/road vertex geometry")
	var index := 0
	for p: Vector2 in [Vector2(-235, 450), Vector2(-650, -480), Vector2(-1200, -100), Vector2(1100, -300)]:
		check(heights[index] == ForbiddenLandsTerrain.height_at(p.x, p.y), "Landscape dressing changed analytical heights")
		index += 1
	var batches := terrain.find_children("*", "MultiMeshInstance3D", true, false)
	var meshes := {}
	var instances := 0
	for batch: MultiMeshInstance3D in batches:
		check(batch.material_override == material, "Landscape batch duplicated its shared material")
		check(batch.visibility_range_end > 0 and batch.visibility_range_end <= 550, "Landscape batch has unbounded visibility")
		check(batch.multimesh.instance_count > 0, "Landscape batch is empty")
		check(batch.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Landscape batch unexpectedly adds shadow draw cost")
		meshes[batch.multimesh.mesh.get_instance_id()] = true
		instances += batch.multimesh.instance_count
	check(batches.size() > 100 and meshes.size() <= 27, "Landscape cache/chunk batching was not used")
	check(job.jobs.size() == 266 and job.cursor == 266, "Landscape lost its 256 bounded terrain jobs and 10 cache/bridge jobs")
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(.43, .54, .57)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(.58, .66, .65)
	environment.ambient_light_energy = .65
	environment.fog_enabled = true
	environment.fog_light_color = Color(.47, .56, .57)
	environment.fog_density = .0012
	env.environment = environment
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-43, -24, 0)
	sun.light_color = Color(.91, .90, .82)
	sun.light_energy = 1.2
	add_child(sun)
	var camera := Camera3D.new()
	camera.far = 1900
	camera.fov = 62
	add_child(camera)
	camera.current = true
	var captures := []
	if DisplayServer.get_name() != "headless":
		camera.look_at_from_position(Vector3(-700, 11, -424), Vector3(-730, 7, -515))
		captures.append(await capture("forest_route.png"))
		camera.look_at_from_position(Vector3(-190, 24, 285), Vector3(-235, -4, 405))
		captures.append(await capture("northern_bridge.png"))
		camera.look_at_from_position(Vector3(-797, 11, -317), Vector3(-780, 7, -345))
		captures.append(await capture("forest_ruin.png"))
	var report := {"failures": failures, "renderer": RenderingServer.get_current_rendering_method(), "atlas_payload_bytes": atlas_payload_bytes, "physical_shape_bytes": physical_before.size(), "terrain_vertex_bytes": surface_before.size(), "unchanged_physics": true, "unchanged_terrain": true, "unique_meshes": meshes.size(), "batches": batches.size(), "lod_instances": instances, "detail_jobs": job.jobs.size(), "max_detail_job_usec": job.max_step_usec, "fixture_build_and_dress_usec": Time.get_ticks_usec() - began, "captures": captures}
	var output := FileAccess.open("res://tests/output/landscape_v5.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "  ")); output.close()
	print("LANDSCAPE_V5: ", JSON.stringify(report))
	get_tree().quit(1 if failures else 0)

func physical_bytes(parent: Node) -> PackedByteArray:
	var records := []
	for shape: CollisionShape3D in parent.find_children("*", "CollisionShape3D", true, false):
		var resource := shape.shape
		var geometry: Variant = resource.get_faces() if resource is ConcavePolygonShape3D else resource.size if resource is BoxShape3D else resource.get_class()
		records.append([String(parent.get_path_to(shape)), shape.global_transform, shape.disabled, shape.get_parent().collision_layer, shape.get_parent().collision_mask, geometry])
	return var_to_bytes(records)

func terrain_bytes(parent: Node) -> PackedByteArray:
	var records := []
	for visual: MeshInstance3D in parent.find_children("*", "MeshInstance3D", true, false):
		if String(visual.name).begins_with("RoadVisual_") or String(visual.get_parent().name).begins_with("Land_"):
			var arrays := visual.mesh.surface_get_arrays(0)
			records.append([String(parent.get_path_to(visual)), visual.global_transform, arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_INDEX]])
	return var_to_bytes(records)

func capture(label: String) -> String:
	for i in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "res://art/screenshots/landscape_v5/" + label
	check(get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path)) == OK, "Landscape capture failed: " + label)
	return path
