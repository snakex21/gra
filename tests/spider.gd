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
	await ticks(2)
	await sword_knot()
	world.free()
	print("Spider: %d failure(s)" % failures)
	get_tree().quit(1 if failures else 0)
func fight(transformed: bool) -> void:
	world = Node3D.new()
	if transformed:
		world.position = Vector3(700, 12, -550)
		world.rotation.y = 0.8
	add_child(world)
	var refs := SpiderArena.build_encounter(world)
	var boss: Spider = refs.spider
	check(boss.anchors.size() == 3 and not boss.route_open and boss.weak_points.all(func(w: WeakPoint) -> bool: return w.state == WeakPoint.State.PROTECTED), "Spider starts with an unguarded sigil / missing web")
	check(boss.global_position.distance_to(world.to_global(SpiderArena.SPIDER_START)) < 0.01, "Spider root did not honor parent transform")
	var bot := SpiderBot.new()
	world.add_child(bot)
	bot.setup(refs.player, boss, refs.encounter)
	for i in 60 * 185:
		await ticks(1)
		if not bot.result.is_empty():
			break
	print("SPIDER transformed%s result %s p%s %s" % [str(transformed), str(bot.result), str(world.to_local((refs.player as PlayerCharacter).global_position)), (refs.player as PlayerCharacter).get_display_state()])
	check(bool(bot.result.get("won", false)), "Spider bot failed")
	check(boss.stats.anchors_cut == 3 and boss.route_open and bot.stats.grabs > 0 and bot.stats.weak_hits == 4 and boss.stats.web_casts > 0, "Spider fight skipped anchors, leg climb, web attacks or sigils")
	bot.set_physics_process(false)
	(refs.encounter as BossEncounter).reset_encounter()
	check(not boss.route_open and boss.lowering == 0 and boss.anchors.all(func(a: WebAnchor) -> bool: return not a.is_cut and a.arrow_target.enabled) and boss.weak_points.all(func(w: WeakPoint) -> bool: return w.state == WeakPoint.State.PROTECTED and w.health == 80), "Spider reset failed")
	await ticks(2)
	var entry := world.to_global(Vector3(0, 0.95, 170))
	var hit := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(entry, entry + Vector3.DOWN * 3, Layers.WORLD))
	check(not hit.is_empty() and (hit.collider as Node).name == &"Ground", "Spider +Z170 entrance inaccessible")
	var companion := PlayerCharacter.new()
	world.add_child(companion)
	companion.global_position = world.to_global(Vector3(28, 0.95, 25))
	companion.spawn_transform = companion.global_transform
	companion.auto_respawn = false
	(refs.encounter as BossEncounter).players.append(companion)
	boss.weak_points[0].health = 40
	(refs.player as PlayerCharacter).dead = true
	await ticks(300)
	check((refs.encounter as BossEncounter).resets == 1 and boss.weak_points[0].health == 40 and boss.stats.web_casts > 0, "Spider death handling reset progress / ignored living companion")
func sword_knot() -> void:
	world = Node3D.new()
	add_child(world)
	var refs := SpiderArena.build_encounter(world)
	var boss: Spider = refs.spider
	var p: PlayerCharacter = refs.player
	p.global_position = boss.to_global(Spider.ANCHORS[0] + Vector3(0, -0.45, 0.75))
	p.actions.view_basis = Basis.IDENTITY
	p.facing = Vector3.FORWARD
	await ticks(3)
	p.actions.attack_held = true
	await ticks(78)
	p.actions.attack_held = false
	await ticks(18)
	check(boss.anchors[0].is_cut and boss.stats.anchors_cut == 1 and not boss.route_open, "Sword PlayerActions did not cut a knot / one knot opened route")
