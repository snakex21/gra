extends Node
var failures := 0
var world: Node3D
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func ticks(n: int) -> void:
	for i in n: await get_tree().physics_frame
func _ready() -> void:
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	await test_phalanx()
	world.free()
	await ticks(2)
	await test_malus()
	world.free()
	await ticks(2)
	print("Phalanx/Malus: %d failure(s)" % failures)
	get_tree().quit(1 if failures else 0)
func test_phalanx() -> void:
	world = Node3D.new()
	world.position = Vector3(44, 0, -70)
	world.rotation.y = 0.65
	add_child(world)
	var refs := PhalanxArena.build_encounter(world)
	var c: Phalanx = refs.phalanx
	var bot := PhalanxBot.new()
	world.add_child(bot)
	bot.setup(refs.player, c, refs.encounter, refs.horse)
	bot.verbose = false
	for i in 60 * 300:
		await ticks(1)
		if c.is_defeated(): break
	check(c.is_defeated(), "Phalanx did not finish: %s p %s horse %s bot %s" % [c.debug_text(), refs.player.global_position, refs.horse.global_position, bot.stats])
	check(c.stats.sac_hits == 3 and c.stats.horse_boardings > 0 and c.stats.wing_grabs > 0 and c.stats.weak_point_hits == 3, "Phalanx skipped bags/Agro/wing/sigils")
	refs.encounter.reset_encounter()
	await ticks(2)
	check(c.weak_points_left() == 3 and not c.popped.has(true) and c.flight == Phalanx.Flight.PATROL, "Phalanx reset failed")
	print("PASS Phalanx sacs, Agro boarding, wing climb, three sigils, reset")

func test_malus() -> void:
	world = Node3D.new()
	world.position = Vector3(-54, 0, 110)
	world.rotation.y = -0.72
	add_child(world)
	var refs := MalusArena.build_encounter(world)
	var c: Malus = refs.malus
	await ticks(3)
	var bot := MalusBot.new()
	world.add_child(bot)
	bot.setup(refs.player, c, refs.encounter)
	bot.verbose = false
	for i in 60 * 260:
		await ticks(1)
		if c.is_defeated(): break
	check(c.is_defeated(), "Malus did not finish: %s p %s bot %s" % [c.debug_text(), refs.player.global_position, bot.stats])
	check(c.stats.pressure_hits == 1 and c.stats.wrist_hits > 0 and c.stats.hand_riders > 0 and c.stats.weak_point_hits >= 3 and bot.stats.cover_visits >= 6 and c.stats.cover_blocks > 0, "Malus skipped siege/pressure/hand/bow/crown")
	check(bot.stats.cover_order == [0, 1, 2, 3, 4, 5], "Malus counted transit waypoints as cover visits")
	refs.encounter.reset_encounter()
	await ticks(2)
	check(c.hand_phase == Malus.Hand.SEALED and c.weak_point.health == c.weak_point.max_health, "Malus reset failed")
	print("PASS Malus cover route, back pressure, hand boarding, bow wrist, crown, reset")
