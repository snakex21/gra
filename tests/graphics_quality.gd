extends Node3D
## Real world, actual renderer setters, settings JSON and immutable simulation.
var failures := 0
const SETTINGS_PATH := "res://tests/output/graphics_settings.json"
var deadline := Time.get_ticks_msec() + 120000

func _process(_delta: float) -> void:
	if Time.get_ticks_msec() > deadline:
		push_error("Graphics profile test timed out or stopped after a runtime error")
		get_tree().quit(1)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func ticks(count: int) -> void:
	for i in count: await get_tree().physics_frame

func _ready() -> void:
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	test_settings()
	var game := GameWorld.new()
	game.with_art = true
	game.with_input = false
	game.save_path = ""
	add_child(game)
	game.start(true)
	await ticks(3)
	# Disable every descendant script so comparison includes no physics, action,
	# simulation clock or incremental render dressing step between snapshots.
	game.process_mode = Node.PROCESS_MODE_DISABLED
	var p := game.player()
	var actions := p.actions
	var state_before := p.state
	var at := p.global_transform
	var before := var_to_bytes(WorldSnapshot.capture(game))
	var geometry := geometry_state(game)
	var lantern := p.visual._lantern
	var lantern_before := illumination(lantern)
	var environment := game.find_child("*", true, false) as WorldEnvironment
	var envs := game.find_children("*", "WorldEnvironment", true, false)
	environment = envs[0] as WorldEnvironment if not envs.is_empty() else null
	var fog_before: Dictionary = fog_state(environment.environment) if environment else {}
	check(environment != null and lantern != null, "Real world did not contain its environment and sword light")
	var sun := game.find_child("Sun", true, false) as DirectionalLight3D
	check(sun != null, "Real world sun was not found")
	# Authored distance fade is exercised separately; applying a preset may change
	# its shadow cutoff but must preserve its light attenuation and on/off state.
	var local_light := OmniLight3D.new()
	local_light.name = "AuthoredFadeLight"
	local_light.light_energy = 3.0
	local_light.distance_fade_enabled = true
	local_light.distance_fade_begin = 80.0
	local_light.distance_fade_length = 12.0
	local_light.shadow_enabled = true
	game.add_child(local_light)
	var local_before := illumination(local_light)
	# Native cosmetic lights are outside region, so the checkpoint stays identical.
	var subordinate := SubViewport.new()
	subordinate.size = Vector2i(64, 64)
	subordinate.render_target_update_mode = SubViewport.UPDATE_DISABLED
	game.add_child(subordinate)
	GraphicsQuality.apply(null, "low")
	check(GraphicsQuality.normalize("unknown") == "balanced" and GraphicsQuality.normalize(" HIGH ") == "high", "Invalid graphics profile did not use balanced")
	var balanced: Dictionary
	for profile in ["balanced", "low", "high", "low", "balanced"]:
		game.settings.graphics_profile = profile
		game.apply_settings(game.settings)
		var config := GraphicsQuality.parameters(profile)
		check_parameters(get_viewport(), sun, lantern, config, profile)
		check(subordinate.msaa_3d == config.msaa and subordinate.positional_shadow_atlas_size == config.positional_atlas, "Nested viewport did not receive " + profile)
		check(illumination(lantern) == lantern_before and illumination(local_light) == local_before, "Profile changed cave light or authored light attenuation: " + profile)
		check(not environment or fog_state(environment.environment) == fog_before, "Profile changed fog, ambient light or GI: " + profile)
		check(p.actions == actions and p.state == state_before and p.global_transform == at, "Profile changed actions/player state or position: " + profile)
		check(geometry_state(game) == geometry, "Profile changed mesh/collider resources or transforms: " + profile)
		check(var_to_bytes(WorldSnapshot.capture(game)) == before, "Profile changed binary simulation checkpoint: " + profile)
		var render_state := current_parameters(get_viewport(), sun, lantern)
		if profile == "balanced":
			if balanced.is_empty(): balanced = render_state
			else: check(render_state == balanced, "Graphics low/high/balanced roundtrip accumulated changes")
		if DisplayServer.get_name() != "headless":
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
	GraphicsQuality.apply(game, "broken")
	check(current_parameters(get_viewport(), sun, lantern) == balanced, "Applying invalid profile did not restore balanced")
	print("Graphics quality: %d failure(s); renderer=%s, 3 presets, actual atlases/MSAA/cascades, settings JSON, roundtrip, unchanged cave/fog/geometry/actions and identical checkpoint %d bytes" % [failures, RenderingServer.get_current_rendering_method(), before.size()])
	get_tree().quit(1 if failures else 0)

func check_parameters(viewport: Viewport, sun: DirectionalLight3D, lantern: SpotLight3D, config: Dictionary, profile: String) -> void:
	check(viewport.msaa_3d == config.msaa and viewport.positional_shadow_atlas_size == config.positional_atlas and viewport.positional_shadow_atlas_16_bits == config.depth_16_bits, "Viewport did not apply AA/positional atlas: " + profile)
	check(is_equal_approx(viewport.mesh_lod_threshold, config.mesh_lod_threshold), "Viewport automatic mesh LOD did not apply: " + profile)
	check(GraphicsQuality.directional_atlas_size == config.directional_atlas and GraphicsQuality.directional_atlas_16_bits == config.depth_16_bits, "Global directional atlas was not configured: " + profile)
	if sun:
		check(sun.directional_shadow_mode == config.directional_mode and is_equal_approx(sun.directional_shadow_max_distance, config.directional_distance) and sun.directional_shadow_blend_splits == config.blend_splits, "Directional shadow cascades/distance did not apply: " + profile)
	check(is_equal_approx(lantern.distance_fade_shadow, config.positional_shadow_distance), "Positional shadow cutoff did not apply: " + profile)

func current_parameters(viewport: Viewport, sun: DirectionalLight3D, lantern: SpotLight3D) -> Dictionary:
	return {"msaa": viewport.msaa_3d, "pos_atlas": viewport.positional_shadow_atlas_size,
		"depth": viewport.positional_shadow_atlas_16_bits, "lod": viewport.mesh_lod_threshold,
		"dir_atlas": GraphicsQuality.directional_atlas_size, "mode": sun.directional_shadow_mode,
		"distance": sun.directional_shadow_max_distance, "fade": sun.directional_shadow_fade_start,
		"splits": sun.directional_shadow_blend_splits, "pos_fade": lantern.distance_fade_shadow}

func illumination(light: Light3D) -> Dictionary:
	return {"enabled": light.visible, "shadow": light.shadow_enabled, "energy": light.light_energy,
		"color": light.light_color, "mask": light.light_cull_mask, "transform": light.transform,
		"fade_enabled": light.distance_fade_enabled, "begin": light.distance_fade_begin,
		"length": light.distance_fade_length,
		"range": light.spot_range if light is SpotLight3D else (light.omni_range if light is OmniLight3D else 0.0)}

func fog_state(env: Environment) -> Dictionary:
	return {"fog": env.fog_enabled, "density": env.fog_density, "color": env.fog_light_color,
		"height": env.fog_height, "height_density": env.fog_height_density,
		"volumetric": env.volumetric_fog_enabled, "ambient": env.ambient_light_energy,
		"ssao": env.ssao_enabled, "ssil": env.ssil_enabled, "sdfgi": env.sdfgi_enabled}

func geometry_state(root: Node) -> Dictionary:
	var out := {}
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is CollisionShape3D:
			out[node.get_instance_id()] = [(node as CollisionShape3D).shape, (node as CollisionShape3D).transform, (node as CollisionShape3D).disabled]
		elif node is MeshInstance3D:
			out[node.get_instance_id()] = [(node as MeshInstance3D).mesh, (node as MeshInstance3D).transform, (node as MeshInstance3D).visible]
		for child in node.get_children(): pending.append(child)
	return out

func test_settings() -> void:
	for profile in ["low", "balanced", "high"]:
		var settings := Settings.new()
		settings.graphics_profile = profile
		check(settings.save(SETTINGS_PATH), "Graphics settings could not save beside the project")
		var restored := Settings.new()
		check(restored.load_from(SETTINGS_PATH) and restored.graphics_profile == profile, "Graphics settings JSON roundtrip failed: " + profile)
	var older := Settings.new()
	older.from_dict({"version": 1, "volume": 0.4})
	check(older.graphics_profile == "balanced", "Old settings without a graphics field did not default to balanced")
	var broken := Settings.new()
	broken.from_dict({"version": 1, "graphics_profile": "corrupt"})
	check(broken.graphics_profile == "balanced", "Broken saved graphics profile did not keep the default")
