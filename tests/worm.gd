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
	world = Node3D.new()
	world.position = Vector3(51, 0, -40)
	world.rotation.y = 0.8
	add_child(world)
	var refs := WormArena.build_encounter(world)
	var c: Worm = refs.worm
	var bot := WormBot.new()
	world.add_child(bot)
	bot.setup(refs.player, c, refs.encounter)
	bot.verbose = false
	for i in 60 * 300:
		await ticks(1)
		if c.is_defeated(): break
	check(c.is_defeated(), "Worm full route failed: %s p %s bot %s" % [c.debug_text(), refs.player.global_position, bot.stats])
	check(c.stats.rhythms >= 3 and c.stats.emergences >= 3 and c.stats.armor_hits >= 18 and c.stats.arrow_armor_hits >= 12 and c.stats.sword_armor_hits >= 6 and c.stats.climb_entries >= 3 and c.stats.weak_point_hits == 3, "Worm skipped rhythm/real arrows/mineral sword/climbing/sigils: %s" % c.stats)
	check(c.stats.hits_on_player == 0, "Worm safe slab failed to protect the waiting player")
	refs.encounter.reset_encounter()
	await ticks(2)
	check(c.cycle == Worm.Cycle.LISTEN and not c.completed.has(true) and c.plates[0].hits == 0 and c.weak_points[0].health == 40, "Worm reset did not restore collar/sigils/listening")
	# A second participant waits at the unsafe front edge. The host summons the
	# guardian through the same actions; the warning must hurt the late player
	# while preserving the host's safe position and the shared encounter.
	var second := PlayerCharacter.new()
	second.name = "Player2"
	world.add_child(second)
	second.global_position = world.global_transform * (WormArena.PLATFORMS[0] + Vector3(0, 0.95, -3.0))
	second.spawn_transform = second.global_transform
	second.auto_respawn = false
	refs.encounter.players.append(second)
	for i in 60 * 35:
		await ticks(1)
		if c.cycle == Worm.Cycle.TELEGRAPH: break
	await ticks(180)
	check(c.stats.hits_on_player == 1 and second.health < 100 and refs.player.health == 100, "Worm warning did not distinguish unsafe player2 from the safe host")
	check(refs.encounter.resets == 1 and refs.encounter.players.size() == 2, "Worm participant2 changed the shared encounter")
	second.free()
	await ticks(2)
	check(refs.encounter.players.size() == 1 and refs.encounter.resets == 1, "Worm participant departure reset the host")
	print("PASS Worm rhythm, real bow/sword mineral hits, three climb windows, safe descent, reset, players[] warning/departure")
	world.free()
	await ticks(2)
	print("Worm: %d failure(s)" % failures)
	get_tree().quit(1 if failures else 0)
