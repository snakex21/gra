extends Node
var failures := 0
var world: Node3D
func ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error(what)
func _ready() -> void:
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	if "--capture" in OS.get_cmdline_user_args():
		await capture()
		get_tree().quit()
		return
	await test_galleries()
	world.free()
	await ticks(2)
	await test_poison()
	world.free()
	await ticks(2)
	await test_kuromori()
	world.free()
	await ticks(2)
	print("Kuromori: %d failure(s)" % failures)
	get_tree().quit(1 if failures else 0)
func test_galleries() -> void:
	world = Node3D.new()
	add_child(world)
	var refs := KuromoriArena.build_encounter(world)
	refs.kuromori.set_physics_process(false)
	var player: PlayerCharacter = refs.player
	player.global_position = Vector3(19.6, 0.95, 21.5)
	player.actions.view_basis = Basis.IDENTITY
	player.actions.move = Vector2(0, 1)
	for i in 900:
		await ticks(1)
		if player.global_position.y > 12.7:
			break
	check(player.global_position.y > 12.7, "Kuromori stairs did not reach the upper gallery: %s" % str(player.global_position))
	player.actions.view_basis = Basis.looking_at(Vector3.RIGHT)
	await ticks(45)
	player.actions.move = Vector2.ZERO
	await ticks(30)
	check(player.global_position.y > 12.5 and player.state == PlayerCharacter.State.GROUND, "Upper gallery was not a usable landing")
	print("PASS Kuromori galleries: ascent by player actions and stable upper landing")
func test_poison() -> void:
	world = Node3D.new()
	add_child(world)
	var refs := KuromoriArena.build_encounter(world)
	var boss: Kuromori = refs.kuromori
	var player: PlayerCharacter = refs.player
	await ticks(305)
	check(boss._poison_time >= 0.0 and boss._poison_time < boss.poison_telegraph and player.health == 100.0, "Poison did not telegraph before damage")
	var where := boss._poison_at
	await ticks(110)
	check(player.health <= 90.0 and boss._poison_at == where, "Poison did not activate at its committed location")
	player.global_position += Vector3.RIGHT * 10.0
	var health := player.health
	await ticks(100)
	check(player.health == health, "Poison followed the evading player")
	check(boss.weak_point.state == WeakPoint.State.PROTECTED, "Standing/wall Kuromori exposed belly without bow puzzle")
	refs.encounter.reset_encounter()
	check(boss._poison_time < 0.0 and not boss._poison_visual.visible and boss.phase == Kuromori.Phase.DORMANT, "Reset left poison active")
	print("PASS Kuromori poison: telegraph, stationary area, escape, reset")
func test_kuromori() -> void:
	world = Node3D.new()
	add_child(world)
	var refs := KuromoriArena.build_encounter(world)
	var boss: Kuromori = refs.kuromori
	var player: PlayerCharacter = refs.player
	var bot := KuromoriBot.new()
	world.add_child(bot)
	bot.setup(player, boss, refs.encounter)
	for i in 60 * 200:
		await ticks(1)
		if not bot.result.is_empty():
			break
	check(bool(bot.result.get("won", false)), "Kuromori actions bot failed: phase %s, player %s, bow %s, stats %s" % [boss.debug_text(), str(player.global_position), player.bow.state_name(), str(bot.stats)])
	check(int(boss.stats.arrow_hits) >= 2 and int(boss.stats.falls) >= 1 and int(boss.stats.weak_point_hits) >= 3, "Kuromori skipped bow/fall/belly loop")
	check(int(bot.stats.grabs) >= 1 and refs.encounter.resets == 0, "Kuromori bot did not actually climb or required a reset")
	print("Kuromori bot: %s" % str(bot.result))
	refs.encounter.reset_encounter()
	check(boss.phase == Kuromori.Phase.DORMANT and boss.weak_point.health == 120.0 and not boss.marks_hit[0], "Kuromori reset incomplete")

func capture() -> void:
	world = Node3D.new()
	add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.18, 0.24, 0.25)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.76, 0.78, 0.71)
	env.environment.ambient_light_energy = 0.7
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -25, 0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var refs := KuromoriArena.build_encounter(world)
	refs.hud.show_debug = false
	refs.hud.show_help = false
	refs.hud.message = ""
	refs.kuromori.phase_changed.disconnect(refs.kuromori.phase_changed.get_connections()[0].callable)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.current = true
	camera.global_position = Vector3(17, 15, 17)
	camera.look_at(Vector3(0, 7, -14))
	await ticks(500)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tests/output/kuromori_wall.png"))
	var bot := KuromoriBot.new()
	world.add_child(bot)
	bot.setup(refs.player, refs.kuromori, refs.encounter)
	for i in 600:
		await ticks(1)
		if refs.kuromori.phase == Kuromori.Phase.BELLY:
			break
	camera.global_position = Vector3(15, 12, 9)
	camera.look_at(Vector3(0, 1.6, -6))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tests/output/kuromori_belly.png"))
	print("Saved Kuromori wall/belly render captures")
