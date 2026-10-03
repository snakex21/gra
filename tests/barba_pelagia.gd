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
		await capture_scenes()
		get_tree().quit()
		return
	await test_barba()
	world.free()
	await ticks(2)
	await test_pelagia()
	world.free()
	await ticks(2)
	await test_pelagia_pulse()
	world.free()
	await ticks(2)
	print("Barba/Pelagia: %d failure(s)" % failures)
	get_tree().quit(1 if failures else 0)
func test_barba() -> void:
	world = Node3D.new()
	add_child(world)
	var refs := BarbaArena.build_encounter(world)
	var c: Barba = refs.barba
	var p: PlayerCharacter = refs.player
	await ticks(2)
	check(c.weak_point.state == WeakPoint.State.PROTECTED, "Barba crown is exposed before cover inspection")
	for seg in c.segments:
		if seg.bone_name != &"head":
			check(not seg.get_children().any(func(child: Node) -> bool: return child is ClimbPatch), "Barba has a Valus leg/arm bypass")
	var bot := BarbaBot.new()
	world.add_child(bot)
	bot.setup(p, c, refs.encounter)
	bot.verbose = false
	for i in 60 * 220:
		await ticks(1)
		if c.is_defeated():
			break
	check(c.is_defeated(), "Barba beard route failed: phase %s, state %s, p %s, head %s, bot %s" % [bot.phase, c.search_phase, p.global_position, c._seg_by_bone[&"head"].target_transform.origin, bot.stats])
	check(c.inspections > 0 and bot.cover_reached and c.beard_grabs > 0, "Barba skipped cover/beard puzzle")
	check(c.stats.weak_point_hits >= 3, "Barba won without sword weak point hits")
	refs.encounter.reset_encounter()
	await ticks(2)
	check(c.weak_point.health == c.weak_point.max_health and c.search_phase == Barba.SearchPhase.HUNT, "Barba reset did not restore puzzle")
	for i in 60 * 100:
		await ticks(1)
		if c.is_defeated():
			break
	check(c.is_defeated() and c.inspections > 0, "Barba bot could not repeat the encounter after reset")
	print("PASS Barba actions, inspection, beard, sword, reset")

func test_pelagia() -> void:
	world = Node3D.new()
	add_child(world)
	var refs := PelagiaArena.build_encounter(world)
	var c: Pelagia = refs.pelagia
	var p: PlayerCharacter = refs.player
	var bot := PelagiaBot.new()
	world.add_child(bot)
	bot.setup(p, c, refs.encounter)
	bot.verbose = false
	for i in 60 * 260:
		await ticks(1)
		if c.is_defeated():
			break
	check(c.is_defeated(), "Pelagia steering route failed: phase %s, p %s, body %s, state %s, stats %s" % [bot.phase, p.global_position, c.global_position, c.debug_text(), bot.stats])
	check(c.stats.tooth_hits >= 3 and c.stats.ruin_impacts >= 3 and c.stats.weak_point_hits >= 3, "Pelagia skipped steering/ruin/sigil loop")
	check(bot.stats.grabs > 0, "Pelagia never climbed from water")
	refs.encounter.reset_encounter()
	await ticks(2)
	check(c.weak_point.health == c.weak_point.max_health and not c.broken_ruins.has(true) and c.ruin_phase == Pelagia.RuinPhase.WAIT, "Pelagia reset did not restore ruins")
	check(not refs.ruins.any(func(ruin: Node) -> bool: return ruin.get_meta(&"broken", false)), "Pelagia visual ruins were not reset")
	print("PASS Pelagia swim, rear climb, steering teeth, three ruin impacts, sword, reset")

func test_pelagia_pulse() -> void:
	world = Node3D.new()
	add_child(world)
	var refs := PelagiaArena.build_encounter(world)
	var c: Pelagia = refs.pelagia
	var p: PlayerCharacter = refs.player
	p.global_position = Vector3(0, -0.95, -21)
	# The guardian commits to a visible position, leaving time to swim aside.
	for i in 600:
		await ticks(1)
		if c._pulse_active:
			break
	check(c._pulse_active and c._pulse_warning.visible and not c.get_danger_zones().is_empty(), "Pelagia pulse has no visible telegraph")
	var hp := p.health
	p.actions.view_basis = Basis.looking_at(Vector3.RIGHT)
	p.actions.move = Vector2(0, 1)
	await ticks(160)
	check(p.health >= hp, "Pelagia locked pulse could not be evaded during its telegraph")
	p.actions.move = Vector2.ZERO
	for i in 600:
		await ticks(1)
		if c.stats.hits_on_player > 0:
			break
	check(c.stats.hits_on_player > 0, "Pelagia did not actively challenge an approaching swimmer")
	print("PASS Pelagia locked warning, evade window and guardian damage")

func capture_scenes() -> void:
	for id in ["barba", "pelagia"]:
		if "--barba-only" in OS.get_cmdline_user_args() and id != "barba":
			continue
		if "--pelagia-only" in OS.get_cmdline_user_args() and id != "pelagia":
			continue
		world = load("res://scenes/%s_arena.tscn" % id).instantiate()
		add_child(world)
		var refs: Dictionary = world.refs
		refs.hud.show_debug = false
		refs.hud.show_help = false
		refs.hud.message = ""
		refs.input.set_physics_process(false)
		if id == "barba":
			var bot := BarbaBot.new()
			world.add_child(bot)
			bot.setup(refs.player, refs.barba, refs.encounter)
			await ticks(60 * 29)
			refs.camera.yaw = refs.player.actions.view_basis.get_euler().y
		else:
			var bot := PelagiaBot.new()
			world.add_child(bot)
			bot.setup(refs.player, refs.pelagia, refs.encounter)
			await ticks(60 * 41)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := PortablePaths.prepare("res://data/captures/%s_prototype.png" % id)
		var err := get_viewport().get_texture().get_image().save_png(path)
		check(err == OK, "capture did not save")
		print("CAPTURE %s" % path)
		world.free()
		await ticks(2)
