extends Node
## Documentation cameras render the real layout, original props and bounded terrain.
var paths := []

func _ready() -> void:
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	get_window().size = Vector2i(1440, 1440)
	var began := Time.get_ticks_usec()
	var game := GameWorld.new()
	game.layout_version = 3
	game.with_input = false
	game.with_art = true
	game.save_path = ""
	add_child(game)
	game.start(true)
	var startup_usec := Time.get_ticks_usec() - began
	game.build_pending()
	ForbiddenLandsTerrain.finish_art(game.region)
	_freeze_physics(game)
	for ui in game.find_children("*", "CanvasLayer", true, false):
		(ui as CanvasLayer).visible = false
	var terrain := game.region.get_node("ForbiddenLandsTerrain")
	var job: ArenaArtBuild = terrain.get_meta(&"detail_job")
	var report := {"startup_usec": startup_usec, "detail_jobs": job.jobs.size(), "max_detail_job_usec": job.max_step_usec, "terrain_render_chunks": 0, "road_render_chunks": 0, "bounded_detail_meshes": 0, "native_culling": true}
	var ranges := {}
	for mesh: MeshInstance3D in terrain.find_children("*", "MeshInstance3D", true, false):
		if mesh.visibility_range_end > 0:
			ranges[mesh] = mesh.visibility_range_end
			report.terrain_render_chunks += 1 if String(mesh.get_parent().name).begins_with("Land_") else 0
			report.road_render_chunks += 1 if String(mesh.name).begins_with("RoadVisual_") else 0
			report.bounded_detail_meshes += 1 if mesh.visibility_range_end < 500 else 0
			mesh.visibility_range_end = 0 # documentation overview alone shows all regions
	var cam := Camera3D.new()
	cam.far = 12000
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 4200
	add_child(cam)
	cam.look_at_from_position(Vector3(-220, 3600, -220), Vector3(-220, 0, -220), Vector3(0, 0, 1))
	cam.current = true
	var environments := game.find_children("*", "WorldEnvironment", true, false)
	var fog_states := []
	for environment: WorldEnvironment in environments:
		fog_states.append(environment.environment.fog_enabled)
		environment.environment.fog_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# The top camera sees +X to its left when +Z is north. Present this real
	# rendered surface in cartographic orientation, then add documentation labels.
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var map_image := get_viewport().get_texture().get_image()
	map_image.flip_x()
	var labels := CanvasLayer.new()
	labels.layer = 100
	add_child(labels)
	var background := TextureRect.new()
	background.texture = ImageTexture.create_from_image(map_image)
	background.size = get_viewport().get_visible_rect().size
	labels.add_child(background)
	for kind: StringName in BossRoster.PLAYABLE:
		_map_label(labels, String(kind).replace("celosia_cenobia", "Celosia + Cenobia").capitalize(), WorldMap.arena_transform(kind, 3).origin)
	_map_label(labels, "Shrine / F4\nNORTH +Z", Vector3(-20, 0, 25))
	await _capture("01_world_map.png")
	labels.visible = false
	for mesh: MeshInstance3D in ranges:
		mesh.visibility_range_end = ranges[mesh]
	for index in environments.size():
		(environments[index] as WorldEnvironment).environment.fog_enabled = fog_states[index]
	get_window().size = Vector2i(1440, 900)
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 62
	cam.far = 2400
	cam.look_at_from_position(Vector3(-190, 30, 255), Vector3(-235, 0, 445))
	await _capture("02_northern_bridge.png")
	cam.look_at_from_position(Vector3(-715, 14, -410), Vector3(-630, 8, -535))
	await _capture("03_southwestern_forest.png")
	report["captures"] = paths
	var output := FileAccess.open("res://tests/output/forbidden_lands_capture.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "  "))
	output.close()
	print("FORBIDDEN_LANDS_RENDER: ", report)
	get_tree().quit(0)

func _map_label(parent: CanvasLayer, text: String, point: Vector3) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var position := Vector2((point.x + 220) / 4200, -(point.z + 220) / 4200) * viewport_size + viewport_size * .5
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", 20)
	label.add_theme_color_override(&"font_color", Color(.96, .94, .83))
	label.add_theme_color_override(&"font_outline_color", Color(.07, .09, .10))
	label.add_theme_constant_override(&"outline_size", 5)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(230, 50)
	label.position = position - label.size * .5
	parent.add_child(label)

func _capture(label: String) -> void:
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://art/screenshots/forbidden_lands"))
	var path := ProjectSettings.globalize_path("res://art/screenshots/forbidden_lands/" + label)
	var error := get_viewport().get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Capture failed: " + path)
		get_tree().quit(1)
	paths.append(path)

func _freeze_physics(node: Node) -> void:
	node.set_physics_process(false)
	for child in node.get_children():
		_freeze_physics(child)
