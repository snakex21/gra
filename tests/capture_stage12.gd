extends Node3D
## Real renderer smoke test; the player uses the sword in a closed Hollowvault chamber.
func _ready() -> void:
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.015, 0.025, 0.03)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.2, 0.28, 0.32)
	env.environment.ambient_light_energy = 0.12
	add_child(env)
	var refs := CaveArena.build_encounter(self, false, true)
	var p: PlayerCharacter = refs.player
	var c: CaveColossus = refs.colossus
	var cam: PlayerCamera = refs.camera
	(refs.hud as PlayerHud).show_debug = false
	(refs.hud as PlayerHud).show_help = false
	(refs.hud as PlayerHud).message = ""
	p.global_position = Vector3(0, 0.95, 19)
	p.spawn_transform = p.global_transform
	c.debug_override = &"frozen"
	p.actions.beam_held = true
	p.actions.view_basis = Basis.looking_at(Vector3(0, 9, 0) - SwordBeam.tip(p))
	cam.yaw = 0.0
	cam.pitch = 0.06
	for i in 100:
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://tests/output/stage12_cave.png")
	get_viewport().get_texture().get_image().save_png(path)
	print("Saved ", path)
	var lit := get_viewport().get_texture().get_image()
	p.set_physics_process(false)
	(p.visual.get_node("SwordLantern") as SpotLight3D).visible = false
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var dark := get_viewport().get_texture().get_image()
	# Catch a visible light that contributes nothing (e.g. a flare casting a shadow
	# over its own source). Read central arena pixels, excluding the HUD and avatar.
	var lit_energy := 0.0
	var dark_energy := 0.0
	for y in range(100, 360, 8):
		for x in range(440, 840, 8):
			lit_energy += lit.get_pixel(x, y).get_luminance()
			dark_energy += dark.get_pixel(x, y).get_luminance()
	if lit_energy < dark_energy * 1.5:
		push_error("Sword light does not visibly illuminate the cave")
		get_tree().quit(1)
		return
	print("PASS sword illumination: ", snappedf(lit_energy / maxf(dark_energy, 0.001), 0.01), " x ambient")
	# A second real view verifies the water shader and camera fog together.
	for child in get_children():
		remove_child(child)
		child.queue_free()
	await get_tree().process_frame
	var outside := WorldEnvironment.new()
	outside.environment = Environment.new()
	outside.environment.background_mode = Environment.BG_SKY
	outside.environment.sky = Sky.new()
	outside.environment.sky.sky_material = ProceduralSkyMaterial.new()
	add_child(outside)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -25, 0)
	add_child(sun)
	ArenaArt._daylight(self)
	refs = HydrusArena.build_encounter(self, false, 29, false)
	(refs.hud as PlayerHud).show_debug = false
	(refs.hud as PlayerHud).show_help = false
	p = refs.player
	cam = refs.camera
	p.global_position = Vector3(0, HydrusArena.WATER_Y - 3.0, 20)
	p.actions.dive_held = true
	cam.pitch = -0.08
	for i in 50:
		await get_tree().physics_frame
	cam.global_position.y = HydrusArena.WATER_Y - 2.0
	cam.set_process(false)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	path = ProjectSettings.globalize_path("res://tests/output/stage12_underwater.png")
	get_viewport().get_texture().get_image().save_png(path)
	print("Saved ", path)
	get_tree().quit()
