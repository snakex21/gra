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
	await fight()
	world.free()
	await ticks(2)
	await transformed()
	world.free()
	print("Celosia+Cenobia: %d failure(s)" % failures)
	get_tree().quit(1 if failures else 0)
func fight() -> void:
	world = Node3D.new()
	add_child(world)
	var refs := CelosiaCenobiaArena.build_encounter(world)
	var boss: CelosiaCenobia = refs.colossus
	check(boss.guardians.size() == 2 and boss.weak_points.all(func(w: WeakPoint) -> bool: return w.state == WeakPoint.State.PROTECTED), "Pair must have two armoured active guardians")
	var bot := CelosiaCenobiaBot.new()
	world.add_child(bot)
	bot.verbose = false
	bot.setup(refs.player, boss, refs.encounter)
	var one_only_seen := false
	for i in 60 * 245:
		await ticks(1)
		var count := 0
		for guardian in boss.guardians:
			count += 1 if guardian.is_defeated() else 0
		if count == 1:
			one_only_seen = true
			check(not boss.is_defeated() and (refs.encounter as BossEncounter).state == BossEncounter.State.RUNNING, "One guardian prematurely completed the encounter")
		if not bot.result.is_empty():
			break
	print("PAIR result %s" % str(bot.result))
	check(bool(bot.result.get("won", false)), "Pair bot failed")
	check(one_only_seen and bool(bot.stats.both_open_before_hit) and bot.stats.weak_hits == 4, "Pair did not combine both armour puzzles and independent sigils")
	check(boss.stats.armour_breaks == 2 and boss.guardians[1].stats.charges > 0, "Pair puzzle skipped a physical impact")
	bot.set_physics_process(false)
	(refs.encounter as BossEncounter).reset_encounter()
	check(boss.guardians.all(func(g: PairedSentinel) -> bool: return not g.armour_open and g.weak_point.health == 80 and g.weak_point.state == WeakPoint.State.PROTECTED), "Pair reset failed")
	var companion := PlayerCharacter.new()
	world.add_child(companion)
	companion.global_position = boss.to_global(CelosiaCenobia.FIRE) + Vector3.UP * 0.95
	companion.spawn_transform = companion.global_transform
	companion.auto_respawn = false
	(refs.encounter as BossEncounter).players.append(companion)
	boss.guardians[0].open_armour()
	boss.guardians[0].weak_point.health = 40
	(refs.player as PlayerCharacter).dead = true
	await ticks(300)
	check((refs.encounter as BossEncounter).resets == 1 and boss.guardians[0].armour_open and boss.guardians[0].weak_point.health == 40, "A dead partner reset living player's armour/sigil progress")
	check(boss.guardians.any(func(g: PairedSentinel) -> bool: return g.target == companion), "Pair ignored the living player")
func transformed() -> void:
	world = Node3D.new()
	world.position = Vector3(700, 12, -550)
	world.rotation.y = 0.8
	add_child(world)
	var refs := CelosiaCenobiaArena.build_encounter(world)
	var boss: CelosiaCenobia = refs.colossus
	check(boss.guardians[0].global_position.distance_to(world.to_global(CelosiaCenobia.STARTS[0])) < 0.01, "Pair child spawn ignored parent transform")
	check((refs.player as PlayerCharacter).global_position.distance_to(world.to_global(CelosiaCenobiaArena.PLAYER_START)) < 0.01, "Pair player transform wrong")
	await ticks(2)
	var entry := world.to_global(Vector3(0, 0.95, 170))
	var hit := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(entry, entry + Vector3.DOWN * 3, Layers.WORLD))
	check(not hit.is_empty() and (hit.collider as Node).name == &"Ground", "Pair +Z170 entrance inaccessible")
	var bot := CelosiaCenobiaBot.new()
	world.add_child(bot)
	bot.setup(refs.player, boss, refs.encounter)
	for i in 60 * 245:
		await ticks(1)
		if not bot.result.is_empty():
			break
	check(bool(bot.result.get("won", false)), "Pair cannot be won in rotated/translated arena")
	print("PAIR transformed result %s" % str(bot.result))
