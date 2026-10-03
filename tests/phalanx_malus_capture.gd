extends Node3D
## Renderer smoke test at a state reached by the normal action bot.
func _ready() -> void:
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	var args := OS.get_cmdline_user_args()
	var kind := args[0] if not args.is_empty() else "worm"
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.28, 0.33, 0.37)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.74)
	env.environment.ambient_light_energy = 0.75
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	add_child(sun)
	var refs: Dictionary
	var bot: Node
	match kind:
		"phalanx":
			refs = PhalanxArena.build_encounter(self)
			bot = PhalanxBot.new()
			add_child(bot)
			bot.setup(refs.player, refs.phalanx, refs.encounter, refs.horse)
		"malus":
			refs = MalusArena.build_encounter(self)
			bot = MalusBot.new()
			add_child(bot)
			bot.setup(refs.player, refs.malus, refs.encounter)
		_:
			refs = WormArena.build_encounter(self)
			bot = WormBot.new()
			add_child(bot)
			bot.setup(refs.player, refs.worm, refs.encounter)
	var reached := false
	for i in 60 * 120:
		await get_tree().physics_frame
		if kind == "phalanx": reached = refs.phalanx.flight == Phalanx.Flight.CARRY
		elif kind == "malus": reached = refs.malus.hand_phase == Malus.Hand.DOCKED
		else: reached = refs.worm.cycle == Worm.Cycle.EXPOSED
		if reached: break
	if not reached:
		push_error("Capture bot did not reach playable guardian window")
		get_tree().quit(1)
		return
	bot.set_physics_process(false)
	refs.player.actions.clear()
	for i in 3: await get_tree().physics_frame
	refs.player.set_physics_process(false)
	refs.colossus.set_physics_process(false)
	refs.horse.set_physics_process(false)
	refs.camera.set_process(false)
	refs.camera.current = false
	refs.hud.visible = false
	var cam := Camera3D.new()
	cam.far = 400
	add_child(cam)
	var c: Colossus = refs.colossus
	var focus := c.global_position
	var offset := Vector3(40, 30, 50)
	if kind == "malus":
		focus += Vector3.UP * 17
		offset = Vector3(38, 17, -56)
	elif kind == "worm":
		focus += Vector3.UP * 6
		offset = Vector3(14, 10, 20)
	cam.global_position = focus + offset
	cam.look_at(focus, Vector3.UP)
	cam.current = true
	for i in 3: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://data/captures")
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join(kind + "_prototype.png")
	var err := get_viewport().get_texture().get_image().save_png(path)
	if err != OK: push_error("Failed to save capture: %d" % err)
	print("Saved ", path)
	get_tree().quit(0 if err == OK else 1)
