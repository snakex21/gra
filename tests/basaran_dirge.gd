extends Node
var failures := 0
var world: Node3D
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
func _ready() -> void:
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	if "--capture" in OS.get_cmdline_user_args():
		await capture_prototypes()
		get_tree().quit()
		return
	await basaran_test()
	world.free()
	await ticks(2)
	await dirge_test()
	world.free()
	await ticks(2)
	print("Basaran/Dirge: %d failure(s)" % failures)
	get_tree().quit(1 if failures else 0)
func basaran_test() -> void:
	world = Node3D.new()
	add_child(world)
	var refs := BasaranArena.build_encounter(world)
	var boss: Basaran = refs.basaran
	check(get_tree().get_nodes_in_group(&"basaran_geysers").size() == 2, "Two geysers missing")
	check(boss.rump.state == WeakPoint.State.PROTECTED and not boss.sole_exposed(2), "Basaran bypasses geyser puzzle")
	var bot := BasaranBot.new()
	world.add_child(bot)
	bot.verbose = false
	bot.setup(refs.player, boss, refs.encounter, refs.horse)
	for i in 60 * 360:
		await ticks(1)
		if not bot.result.is_empty():
			break
	check(bool(bot.result.get("won", false)), "Basaran actions-only bot did not win: %s" % str(bot.result))
	check(boss.geyser_lifts > 0 and int(boss.stats.foot_hits) > 0 and int(bot.stats.grabs) > 0, "Basaran solution did not use geyser, arrow and climbing")
	print("BASARAN result %s" % str(bot.result))
	bot.set_physics_process(false)
	(refs.encounter as BossEncounter).reset_encounter()
	check(boss.geyser_lifts == 0 and boss.rump.health == boss.rump.max_health and boss.rump.state == WeakPoint.State.PROTECTED, "Basaran reset incomplete")
	(refs.player as PlayerCharacter).global_position = boss.global_position - boss.global_basis.z * 13.0 + Vector3.UP * 0.95
	await ticks(300)
	check(not boss.stats.attacks.is_empty(), "Basaran never actively attacks an intruder")
	(refs.encounter as BossEncounter).reset_encounter()
	boss.teleport(BasaranArena.GEYSERS[1], PI)
	boss._set_encounter(QuadrupedBoss.Encounter.COMBAT)
	await ticks(130)
	check(boss.geyser == world.get_node("Geyser2") and boss.sole_exposed(2), "Second geyser does not expose Basaran's feet")

func dirge_test() -> void:
	world = Node3D.new()
	add_child(world)
	var refs := DirgeArena.build_encounter(world)
	var boss: Dirge = refs.dirge
	check(boss.weak_points.all(func(w: WeakPoint) -> bool: return w.state == WeakPoint.State.PROTECTED), "Dirge starts with an accessible weak point")
	var bot := DirgeBot.new()
	world.add_child(bot)
	bot.verbose = false
	bot.setup(refs.player, boss, refs.encounter, refs.horse)
	for i in 60 * 300:
		await ticks(1)
		if not bot.result.is_empty():
			break
	check(bool(bot.result.get("won", false)), "Dirge actions-only bot did not win: %s" % str(bot.result))
	check(bot.mounted_shots > 0 and boss.eye_hits > 0 and boss.wall_impacts > 0 and int(bot.stats.grabs) > 0, "Dirge did not require Agro, eye shot, wall impact and climb")
	print("DIRGE result %s" % str(bot.result))
	bot.set_physics_process(false)
	(refs.encounter as BossEncounter).reset_encounter()
	check(boss.eye_hits == 0 and boss.wall_impacts == 0 and boss.pursuit == Dirge.Pursuit.WAITING and boss.weak_points.all(func(w: WeakPoint) -> bool: return w.state == WeakPoint.State.PROTECTED and w.health == w.max_health), "Dirge reset incomplete")
	var companion := PlayerCharacter.new()
	world.add_child(companion)
	companion.global_position = boss.global_position - boss.global_basis.z * 18.0 + Vector3.UP * 0.95
	companion.spawn_transform = companion.global_transform
	(refs.player as PlayerCharacter).dead = true
	(refs.encounter as BossEncounter).players.append(companion)
	companion.auto_respawn = false
	await ticks(170)
	check(boss.focus == companion and boss.pursuit == Dirge.Pursuit.CHASING, "Dirge did not target the living player from players[]")
	check((refs.encounter as BossEncounter).resets == 1, "A dead first player reset the living companion's fight")

func capture_prototypes() -> void:
	for key in [&"basaran", &"dirge"]:
		world = Node3D.new()
		add_child(world)
		var environment := WorldEnvironment.new()
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.43, 0.41, 0.33)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.8, 0.82, 0.76)
		env.ambient_light_energy = 0.65
		environment.environment = env
		world.add_child(environment)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-42, -35, 0)
		sun.light_energy = 1.5
		sun.shadow_enabled = true
		world.add_child(sun)
		var refs := BasaranArena.build_encounter(world) if key == &"basaran" else DirgeArena.build_encounter(world)
		var cam: PlayerCamera = refs.camera
		cam.set_physics_process(false)
		cam.set_process(false)
		if key == &"basaran":
			var boss: Basaran = refs.basaran
			boss.teleport(Vector3.ZERO, PI)
			boss.vent_state = Basaran.VentState.EXPOSED
			boss._lift = 1.0
			boss._set_encounter(QuadrupedBoss.Encounter.COMBAT)
			(world.get_node("Geyser1") as BasaranGeyser).clock = 9.0
			cam.global_position = Vector3(24, 16, 27)
			cam.look_at(Vector3(0, 7, 0))
		else:
			var boss: Dirge = refs.dirge
			boss.teleport(Vector3.ZERO, PI)
			boss._set_encounter(Hydrus.Encounter.COMBAT)
			boss._set_pursuit(Dirge.Pursuit.STUNNED)
			boss._exposure = 1.0
			cam.global_position = Vector3(24, 18, -35)
			cam.look_at(Vector3(0, 2, -18))
		await ticks(50)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/output/%s_prototype.png" % key)
		world.free()
		await ticks(2)
