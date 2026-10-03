extends Node3D
## Optional static render benchmark, not gameplay FPS or a minimum-hardware claim.
## Run without --fixed-fps. Output stays local; use the same resolution/GPU to compare.
const OUT := "res://tests/output/render_budget.json"
var deadline := Time.get_ticks_msec() + 600000

func _process(_delta: float) -> void:
	if Time.get_ticks_msec() > deadline:
		push_error("Render benchmark exceeded 10 minutes or stopped after a runtime error")
		get_tree().quit(1)

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Render benchmark needs a real renderer")
		get_tree().quit(1)
		return
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var game := GameWorld.new()
	game.layout_version = 3
	game.with_input = false
	game.with_art = true
	game.save_path = ""
	add_child(game)
	var start_at := Time.get_ticks_usec()
	game.start(true)
	var start_ms := float(Time.get_ticks_usec() - start_at) / 1000
	start_at = Time.get_ticks_usec()
	# For this comparison, complete dressing once before all measured samples.
	game.build_pending()
	ForbiddenLandsTerrain.finish_art(game.region)
	var dressing_ms := float(Time.get_ticks_usec() - start_at) / 1000
	game.process_mode = Node.PROCESS_MODE_DISABLED
	(game.refs.hud as PlayerHud).visible = false
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	camera.fov = 65
	camera.far = 3500
	var samples := []
	var views := {
		"temple": [Vector3(22, 4, -42), Vector3(0, 5, 0)],
		"north_bridge": [Vector3(-270, 9, 260), Vector3(-230, 2, 570)],
		"western_road": [Vector3(-1080, 8, 140), Vector3(-1540, 3, 150)],
	}
	for profile in ["low", "balanced", "high"]:
		GraphicsQuality.apply(game, profile)
		for view: String in views:
			camera.position = views[view][0]
			camera.look_at(views[view][1])
			# Engine counters can refresh once a second. Warm up shaders/counters.
			await get_tree().create_timer(1.2).timeout
			var intervals: Array[float] = []
			var began := Time.get_ticks_usec()
			var previous := began
			for i in 180:
				await RenderingServer.frame_post_draw
				var now := Time.get_ticks_usec()
				intervals.append(float(now - previous) / 1000)
				previous = now
			intervals.sort()
			samples.append({"profile": profile, "view": view,
				"frames": intervals.size(), "elapsed_ms": float(previous - began) / 1000,
				"frame_interval_median_ms": intervals[intervals.size() / 2],
				"frame_interval_p95_ms": intervals[int(intervals.size() * .95)],
				"visible_objects_reported": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
				"render_primitives_reported": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
				"draw_calls_reported": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				"video_memory_reported_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
				"texture_memory_reported_bytes": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)})
	var result := {"scope": "Static world render comparison; simulation frozen; not gameplay FPS or old-GPU validation",
		"counter_note": "Godot monitors may omit allocations or return zero; render primitives can include multiple passes and are not unique scene triangles",
		"gpu": RenderingServer.get_video_adapter_name(), "engine": Engine.get_version_info().string,
		"renderer": RenderingServer.get_current_rendering_method(), "resolution": get_viewport().size,
		"world_start_ms": start_ms, "remaining_full_dressing_ms": dressing_ms, "samples": samples}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	if not file:
		push_error("Cannot save render benchmark beside project")
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("Render budget: ", JSON.stringify(result))
	game.free()
	await get_tree().process_frame
	get_tree().quit(0)
