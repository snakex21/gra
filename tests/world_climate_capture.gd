extends Node3D
## Optional rendered acceptance capture of the integrated campaign (no player saves).
var deadline := Time.get_ticks_msec() + 180000
var game: GameWorld
var failures := 0

func _process(_delta: float) -> void:
	if Time.get_ticks_msec() > deadline:
		push_error("WORLD_CLIMATE_CAPTURE watchdog")
		get_tree().quit(2)

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("WORLD_CLIMATE_CAPTURE needs a real renderer")
		get_tree().quit(1)
		return
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	game = GameWorld.new()
	game.layout_version = 3
	game.with_input = false
	game.with_art = true
	game.save_path = ""
	add_child(game)
	game.start(true)
	game.build_pending()
	ForbiddenLandsTerrain.finish_art(game.region)
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.climate_view.process_mode = Node.PROCESS_MODE_ALWAYS
	(game.refs.hud as PlayerHud).visible = false
	var camera: PlayerCamera = game.refs.camera
	camera.current = true
	game.settings.graphics_profile = "balanced"
	game.apply_settings(game.settings)
	_pose(Vector3(-600, 7, -530), Vector3(-760, 3, -570))
	_clock(300.0)
	await _capture("forest_day.png")
	_clock(1125.0)
	await _capture("forest_night.png")
	_pose(Vector3(-190, 8, 255), Vector3(-235, 3, 445))
	_clock(300.0)
	await _capture("bridge_day.png")
	var rainy := WorldClimate.new()
	for i in 80:
		if float(rainy.sample().rain) > 0.55:
			break
		rainy.advance(60.0)
	game.state.climate.from_dict(rainy.to_dict())
	game.refresh_climate(true)
	if not game.climate_view.rain.visible:
		failures += 1
		push_error("WORLD_CLIMATE_CAPTURE integrated rain missing")
	await get_tree().create_timer(0.6).timeout
	await _capture("bridge_rain.png")
	game.state.defeated.assign(BossRoster.PLAYABLE.slice(0, 20))
	_clock(1125.0)
	await _capture("bridge_anomaly.png")
	print("WORLD_CLIMATE_CAPTURE failures=%d renderer=%s" % [failures, RenderingServer.get_current_rendering_method()])
	game.queue_free()
	for i in 4:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	get_tree().quit(1 if failures else 0)

func _pose(observer: Vector3, target: Vector3) -> void:
	game.player().global_position = observer - Vector3.UP * 3.0
	(game.refs.camera as PlayerCamera).look_at_from_position(observer, target)

func _clock(elapsed: float) -> void:
	game.state.climate.from_dict({"version": 1, "seed": WorldClimate.DEFAULT_SEED, "elapsed": elapsed, "compensation": 0.0})
	game.refresh_climate(true)

func _capture(filename: String) -> void:
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://art/screenshots/world_climate/" + filename)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if get_viewport().get_texture().get_image().save_png(path) != OK:
		failures += 1
		push_error("WORLD_CLIMATE_CAPTURE could not save " + filename)
