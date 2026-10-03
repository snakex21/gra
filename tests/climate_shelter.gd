extends Node
## Real physics roof queries and per-camera fog layering, independent of art quality.
var failures := 0
var game: GameWorld

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func ticks(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func _ready() -> void:
	get_tree().create_timer(120.0, true, false, true).timeout.connect(func() -> void:
		push_error("CLIMATE_SHELTER watchdog")
		get_tree().quit(2))
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	game = GameWorld.new()
	game.with_art = false
	game.with_input = false
	game.save_path = ""
	add_child(game)
	game.start(true)
	game.set_physics_process(false)
	var p := game.player()
	p.set_physics_process(false)
	p.global_position = Vector3(100, 15, 100)
	var camera: PlayerCamera = game.refs.camera
	camera.set_process(false)
	camera.global_position = p.global_position + Vector3(0, 3, 3)
	var effects := camera.get_node("WaterCameraEffects") as WaterCameraEffects
	# Find an actual seeded rain front; no special weather override for this test.
	for step in 80:
		if float(game.state.climate.sample().rain) > 0.5:
			break
		game.state.climate.advance(60.0)
	await ticks(3)
	game.refresh_climate(true)
	check(float(game.climate_view.last_sample.rain) > 0.5 and game.climate_view.rain.visible, "open sky rain missing")
	check(game.climate_view.environment.background_mode == Environment.BG_SKY, "open path lost sky")
	var roof := StaticBody3D.new()
	roof.name = "TestRoof"
	roof.collision_layer = Layers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 1, 30)
	shape.shape = box
	roof.add_child(shape)
	game.region.add_child(roof)
	roof.global_position = p.global_position + Vector3.UP * 10.0
	await ticks(3)
	game.refresh_climate(true)
	check(game.climate_view.last_sample.sheltered and not game.climate_view.rain.visible, "roof leaked rain")
	check(game.climate_view.environment.background_mode == Environment.BG_SKY and game._sun.light_energy > 0.0, "outdoor roof darkened sky/sun")
	game.region_kind = &"barba"
	game.refresh_climate(true)
	check(game.climate_view.last_sample.exposure == 1.0 and game.climate_view.environment.background_mode == Environment.BG_SKY, "Barba's cover arch became a dark cave")
	game.region_kind = &"devil"
	p.beam.lantern = true
	roof.set_meta(&"cave_shell", true)
	game.refresh_climate(true)
	effects._process(0.0)
	check(game.climate_view.last_sample.exposure == 0.0 and camera.environment == effects._cave, "closed cave lost camera fog")
	check(effects._cave.fog_density == game.climate_view.environment.fog_density, "cave kept stale climate fog")
	roof.free()
	await ticks(3)
	game.refresh_climate(true)
	effects._process(0.0)
	check(game.climate_view.last_sample.exposure == 1.0 and game.climate_view.rain.visible, "open cave approach was treated as indoors")
	check(camera.environment == null, "lantern darkened open cave approach")
	var water := WaterBody.new()
	water.show_surface = false
	water.radius = 30.0
	game.region.add_child(water)
	water.global_position = camera.global_position + Vector3.UP * 3.0
	game.refresh_climate(true)
	effects._process(0.0)
	check(effects.underwater and camera.environment == effects._underwater, "underwater camera fog missing")
	check(not game.climate_view.rain.visible, "rain emitter followed camera underwater")
	for height in [-0.04, 0.04]:
		camera.global_position.y = water.surface() + height
		game.refresh_climate(true)
		effects._process(0.0)
		check(effects.underwater and not game.climate_view.rain.visible, "rain/env disagreed in surface hysteresis band")
	var fog := effects._underwater.fog_density
	game.state.climate.advance(700.0)
	game.refresh_climate(true)
	effects._process(0.0)
	check(effects._underwater.fog_density == fog and is_equal_approx(fog, 0.12), "weather overwrote underwater fog")
	camera.global_position.y = water.surface() + 1.0
	game.refresh_climate(true)
	effects._process(0.0)
	check(not effects.underwater and camera.environment == null, "surfacing retained underwater environment")
	game.stop()
	check(not game.climate_view.rain.visible and game.climate_view.last_sample.is_empty(), "title kept weather emitter")
	game.free()
	await ticks(2)
	print("CLIMATE_SHELTER failures=%d" % failures)
	get_tree().quit(1 if failures else 0)
