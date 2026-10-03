extends Node3D
## Renderer smoke + bounded allocation + per-camera underwater isolation.
const ClimateView := preload("res://src/world/world_climate_view.gd")
var failures := 0
var _started := 0
var captures := []
var measurements := {}

func _process(_delta: float) -> void:
	if _started > 0 and Time.get_ticks_msec() - _started > 180000:
		push_error("CLIMATE_VIEW wall-clock watchdog: runtime error or stalled renderer")
		get_tree().quit(1)

func _ready() -> void:
	_started = Time.get_ticks_msec()
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	var world := Node3D.new()
	world.name = "ClimateFixture"
	add_child(world)
	var environment_node := WorldEnvironment.new()
	environment_node.environment = Environment.new()
	environment_node.environment.sky = Sky.new()
	environment_node.environment.sky.sky_material = ProceduralSkyMaterial.new()
	var authored_sky := environment_node.environment.sky
	world.add_child(environment_node)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	world.add_child(sun)
	var view := ClimateView.new()
	world.add_child(view)
	view.setup(world)
	_check(view.environment.sky == authored_sky, "reuse authored Sky before its first render")
	var observer := Vector3(-190, 8, 255)
	var noon := _sample(12.0, 1.0)
	view.refresh(noon, observer, "northern_canyon", "low", true)
	_check(view.rain.amount == 96, "low rain budget")
	_check(view.rain.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "rain never casts shadows")
	_check(not view.rain.emitting and not view.rain.visible, "clear sky stops rain")
	_check(view.environment.sky.radiance_size == Sky.RADIANCE_SIZE_32, "small sky cubemap")
	_check(not view.environment.volumetric_fog_enabled and not view.environment.ssr_enabled and not view.environment.sdfgi_enabled, "no expensive atmospheric passes")
	var rainy := _sample(14.0, 1.0, 0.9, 0.94, 0.4)
	view.refresh(rainy, observer, "northern_canyon", "balanced", true)
	_check(view.rain.amount == 176 and view.rain.visible and view.rain.emitting, "balanced rain visible and bounded")
	_check(view.rain.global_position.distance_to(observer + Vector3(0, 5.5, 0)) < 0.0001, "rain follows observer only")
	_check(view.rain.use_fixed_seed and view.rain.fixed_fps == 30, "fixed cosmetic seed and bounded particle updates")
	view.refresh(rainy, observer, "northern_canyon", "high")
	_check(view.rain.amount == 256, "high rain allocation cap")
	var roof := rainy.duplicate()
	roof.sheltered = true
	view.refresh(roof, observer, "valley", "balanced")
	_check(not view.rain.visible and not view.rain.emitting, "physical roof hides precipitation independently of daylight")
	_check(view.environment.background_mode == Environment.BG_SKY and sun.light_energy > 0.3, "an open bridge or temple roof preserves daylight and sky")
	var night := _sample(23.0, 0.0, 0.0, 0.27)
	view.refresh(night, observer, "northern_canyon", "balanced")
	_check(view.environment.ambient_light_energy >= 0.27, "night keeps readable ambient")
	_check(sun.light_energy > 0.10, "existing sun supplies dim moonlight")
	_check(world.find_children("*", "DirectionalLight3D", true, false).size() == 1, "no second shadow light")
	var cave := rainy.duplicate()
	cave.exposure = 0.0
	view.refresh(cave, observer, "cave", "balanced")
	_check(not view.rain.visible and not view.rain.emitting, "roof removes active and surviving rain immediately")
	_check(view.environment.background_mode == Environment.BG_COLOR and sun.light_energy == 0.0, "closed cave blocks sky and directional light")
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 62.0
	camera.far = 2400.0
	world.add_child(camera)
	var underwater := Environment.new()
	underwater.fog_enabled = true
	underwater.fog_density = 0.12
	underwater.fog_light_color = Color(0.06, 0.23, 0.27)
	underwater.background_mode = Environment.BG_COLOR
	camera.environment = underwater
	view.refresh(noon, observer, "hydrus", "balanced", true)
	_check(camera.environment == underwater and is_equal_approx(underwater.fog_density, 0.12) and underwater.fog_light_color.is_equal_approx(Color(0.06, 0.23, 0.27)), "climate leaves active camera underwater fog untouched")
	var dry := view.dry_environment_state()
	_check(dry.fog_density < 0.01 and dry.sky == view.environment.sky, "dry environment integration baseline")
	dry.fog_density = 7.0
	_check(view.dry_environment_state().fog_density < 0.01, "dry state dictionary cannot mutate the view")
	camera.environment = null
	if DisplayServer.get_name() != "headless":
		_check(RenderingServer.get_current_rendering_method() == "gl_compatibility", "real Compatibility renderer")
		get_window().size = Vector2i(1280, 800)
		Valley.build(world, &"valus", true, true, 3)
		ForbiddenLandsTerrain.build(world, true)
		ForbiddenLandsTerrain.finish_art(world)
		GraphicsQuality.apply(world, "balanced")
		camera.look_at_from_position(observer, Vector3(-235, 3, 445))
		view.refresh(noon, observer, "northern_canyon", "balanced", true)
		measurements.noon = await _capture("01_day.png")
		view.refresh(_sample(18.3, 0.17, 0.0, 0.28), observer, "northern_canyon", "balanced", true)
		measurements.dusk = await _capture("02_dusk.png")
		view.refresh(night, observer, "northern_canyon", "balanced", true)
		measurements.night = await _capture("03_night.png")
		view.refresh(rainy, observer, "northern_canyon", "balanced", true)
		await get_tree().create_timer(0.6).timeout
		measurements.rain = await _capture("04_rain.png")
		var corrupted := _sample(23.0, 0.0, 0.0, 0.64, 0.45, 1.0)
		view.refresh(corrupted, observer, "northern_canyon", "balanced", true)
		measurements.anomaly = await _capture("05_anomaly.png")
		_check(float(measurements.night.world_luminance) > 0.009, "night terrain remains legible in actual rendered pixels")
		_check(float(measurements.noon.world_luminance) > float(measurements.night.world_luminance) * 1.25, "day and night differ in actual rendered terrain")
		_check(float(measurements.noon.primitives) > 2000.0, "captures contain actual map geometry")
		# Close view proves the actual moon disc; it is not a scene marker.
		view.refresh(night, observer, "northern_canyon", "balanced", true)
		var moon: Vector3 = view.sky_material.get_shader_parameter("moon_direction")
		camera.look_at_from_position(observer, observer + moon * 100.0)
		await _capture("06_moon.png")
	view.clear()
	_check(not view.rain.visible and not view.rain.emitting, "title/stop clears cosmetic weather")
	var report := {"failures": failures, "renderer": RenderingServer.get_current_rendering_method(), "captures": captures, "measurements": measurements, "max_rain_particles": 256, "rain_emitters": 1, "directional_lights": 1, "sky_texture_assets": 0}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	var output := FileAccess.open("res://tests/output/climate_view.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "  "))
	output.close()
	print("CLIMATE_VIEW: ", JSON.stringify(report))
	world.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if failures > 0 else 0)

func _sample(hour: float, daylight: float, rain: float = 0.0, cloud: float = 0.20, fog: float = 0.0, anomaly: float = 0.0) -> Dictionary:
	return {"hour": hour, "daylight": daylight, "rain": rain, "cloud": cloud, "fog": fog, "wind_strength": 0.50, "wind_direction": Vector3(0.7, 0, 0.3).normalized(), "anomaly": anomaly, "exposure": 1.0, "haze": 0.0, "weather_id": "rain" if rain > 0.0 else "clear", "day_index": 0}

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("CLIMATE_VIEW: " + message)

func _capture(filename: String) -> Dictionary:
	for frame in 5:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var directory := ProjectSettings.globalize_path("res://art/screenshots/climate")
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join(filename)
	_check(image.save_png(path) == OK, "save capture " + filename)
	captures.append(path)
	var luminance := 0.0
	var samples := 0
	# Lower central half samples rendered road/terrain, away from most of the sky.
	for y in range(image.get_height() / 2, image.get_height() - 40, 12):
		for x in range(image.get_width() / 4, image.get_width() * 3 / 4, 12):
			luminance += image.get_pixel(x, y).get_luminance()
			samples += 1
	return {"world_luminance": luminance / maxi(samples, 1), "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}
