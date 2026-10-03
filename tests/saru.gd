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
	await fight(false)
	world.free()
	await ticks(2)
	await fight(true)
	world.free()
	print("Saru: %d failure(s)" % failures)
	get_tree().quit(1 if failures else 0)
func fight(transformed: bool) -> void:
	world = Node3D.new()
	if transformed:
		world.position = Vector3(700, 12, -550)
		world.rotation.y = 0.8
	add_child(world)
	var refs := SaruArena.build_encounter(world)
	var boss: Saru = refs.saru
	check(not boss.bridge.route_open and boss.bridge.opened == [false, false] and boss.weak_points.all(func(w: WeakPoint) -> bool: return w.state == WeakPoint.State.PROTECTED), "Saru starts with an open bridge/sigil")
	check(boss.global_position.distance_to(world.to_global(SaruArena.SARU_START)) < 0.01, "Saru spawn ignored parent transform")
	await ticks(2)
	var pit := world.to_global(Vector3(0, 6.8, 0))
	var hit := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(pit, pit + Vector3.DOWN * 10, Layers.WORLD))
	check(hit.is_empty(), "Saru bridge has a ground shortcut before solving the throws")
	var bot := SaruBot.new()
	world.add_child(bot)
	bot.verbose = false
	bot.setup(refs.player, boss, refs.encounter)
	for i in 60 * 225:
		await ticks(1)
		if not bot.result.is_empty():
			break
	print("SARU transformed%s result %s p%s %s" % [str(transformed), str(bot.result), str(world.to_local((refs.player as PlayerCharacter).global_position)), (refs.player as PlayerCharacter).get_display_state()])
	check(bool(bot.result.get("won", false)), "Saru bot failed")
	check(boss.stats.counterweight_hits == 2 and boss.bridge.impacts == 2 and bot.stats.bridge_crossings > 0 and bot.stats.grabs > 0 and bot.stats.weak_hits == 4, "Saru fight skipped physical stone, span manipulation, bridge or a sigil")
	bot.set_physics_process(false)
	(refs.encounter as BossEncounter).reset_encounter()
	check(not boss.bridge.route_open and boss.bridge.impacts == 0 and boss.bridge.opened == [false, false] and boss.weak_points.all(func(w: WeakPoint) -> bool: return w.health == 80 and w.state == WeakPoint.State.PROTECTED), "Saru reset did not restore bridge and sigils")
	await ticks(2)
	var entry := world.to_global(Vector3(0, 0.95, 170))
	hit = world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(entry, entry + Vector3.DOWN * 3, Layers.WORLD))
	check(not hit.is_empty() and (hit.collider as Node).name == &"Ground", "Saru +Z170 entrance inaccessible")
	var companion := PlayerCharacter.new()
	world.add_child(companion)
	companion.global_position = world.to_global(Vector3(20, 6.95, 39))
	companion.spawn_transform = companion.global_transform
	companion.auto_respawn = false
	(refs.encounter as BossEncounter).players.append(companion)
	boss.weak_points[0].health = 40
	(refs.player as PlayerCharacter).dead = true
	await ticks(420)
	check((refs.encounter as BossEncounter).resets == 1 and boss.weak_points[0].health == 40 and boss.stats.throws > 0, "Saru death handling reset progress / ignored living companion")
