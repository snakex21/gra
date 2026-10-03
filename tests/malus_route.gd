extends Node
var failures := 0
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
	await trial(false)
	await trial(true)
	print("Malus route timing: %d failure(s)" % failures)
	get_tree().quit(1 if failures else 0)
func trial(late: bool) -> void:
	var world := Node3D.new()
	world.position = Vector3(650, 12, 1300)
	world.rotation.y = 0.63
	add_child(world)
	var refs := MalusArena.build_encounter(world)
	var c: Malus = refs.malus
	await ticks(3)
	if late:
		for i in 60 * 20:
			await ticks(1)
			if c.stats.volleys >= 2: break
		check(c.stats.volleys >= 2 and c.stats.cover_blocks + c.stats.hits_on_player > 0, "Delayed Malus fixture did not start after an actual siege shot")
	var bot := MalusBot.new()
	world.add_child(bot)
	bot.setup(refs.player, c, refs.encounter)
	await complete(refs, bot, "late volley" if late else "three settled ticks")
	refs.encounter.reset_encounter()
	await ticks(3)
	check(c.hand_phase == Malus.Hand.SEALED and c.weak_point.health == c.weak_point.max_health and c.stats.pressure_hits == 0 and bot.phase == MalusBot.Phase.SIEGE, "Malus route reset did not restore boss and navigation")
	if not late:
		await complete(refs, bot, "full replay after reset")
	world.free()
	await ticks(3)
func complete(refs: Dictionary, bot: MalusBot, label: String) -> void:
	var c: Malus = refs.malus
	var visits_before: int = bot.stats.cover_visits
	var resets_before: int = refs.encounter.resets
	var start := bot.time
	for i in 60 * 180:
		await ticks(1)
		if c.is_defeated(): break
	check(c.is_defeated(), "Malus %s failed: phase=%s route=%d local=%s %s" % [label, MalusBot.Phase.keys()[bot.phase], bot._route_index, refs.player.position, c.debug_text()])
	check(refs.encounter.resets == resets_before and bot.stats.cover_visits - visits_before == 6 and bot.stats.cover_order.slice(visits_before) == [0, 1, 2, 3, 4, 5], "Malus %s skipped a real cover or needed a death reset" % label)
	check(c.stats.cover_blocks > 0 and c.stats.pressure_hits == 1 and c.stats.wrist_hits == 1 and c.stats.hand_riders > 0 and c.stats.weak_point_hits == 3, "Malus %s did not complete cover/pressure/wrist/hand/crown actions" % label)
	print("Malus %s: %.2f s, six covers, full fight" % [label, bot.time - start])
