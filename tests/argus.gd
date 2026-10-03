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
	await fight_test()
	world.free()
	await ticks(2)
	await transformed_spawn_test()
	world.free()
	await ticks(2)
	print("Argus: %d failure(s)" % failures)
	get_tree().quit(1 if failures else 0)
func fight_test() -> void:
	world = Node3D.new()
	add_child(world)
	var refs := ArgusArena.build_encounter(world)
	var boss: Argus = refs.argus
	var ruins: ArgusRuins = refs.ruins
	check(not ruins.route_open and ruins.ramp.basis == Basis.IDENTITY, "Gallery ramp starts raised")
	check(boss.weak_points.size() == 2 and boss.weak_points.all(func(w: WeakPoint) -> bool: return w.state == WeakPoint.State.PROTECTED), "Argus sigils bypass the terrain puzzle")
	var climbable_legs := false
	for segment in boss.segments:
		if String(segment.bone_name).begins_with("shin") or String(segment.bone_name).begins_with("thigh"):
			for child in segment.get_children():
				climbable_legs = climbable_legs or child is ClimbPatch
	check(not climbable_legs, "Argus has a ground-level fur shortcut")
	var bot := ArgusBot.new()
	world.add_child(bot)
	bot.verbose = false
	bot.setup(refs.player, boss, refs.encounter)
	for i in 60 * 160:
		await ticks(1)
		if not bot.result.is_empty():
			break
	check(bool(bot.result.get("won", false)), "Argus bot did not win: %s" % str(bot.result))
	check(ruins.impacts > 0 and ruins.route_open and bot.gallery_entries > 0 and boss.weak_points.all(func(w: WeakPoint) -> bool: return w.state == WeakPoint.State.DESTROYED), "Argus fight skipped impact, gallery or a sigil")
	print("ARGUS result %s" % str(bot.result))
	bot.set_physics_process(false)
	(refs.encounter as BossEncounter).reset_encounter()
	check(not ruins.route_open and ruins.weight == 0.0 and ruins.impacts == 0 and boss.weak_points.all(func(w: WeakPoint) -> bool: return w.state == WeakPoint.State.PROTECTED and w.health == w.max_health), "Argus terrain / sigils did not reset")
	var companion := PlayerCharacter.new()
	world.add_child(companion)
	companion.global_position = ruins.to_global(ArgusRuins.PLATE) + Vector3.UP * 0.87
	companion.spawn_transform = companion.global_transform
	companion.auto_respawn = false
	(refs.encounter as BossEncounter).players.append(companion)
	boss.back_point.health = 40.0
	(refs.player as PlayerCharacter).dead = true
	await ticks(300)
	check((refs.encounter as BossEncounter).resets == 1 and boss.back_point.health == 40.0, "Companion death reset terrain fight progress")
	check(int(boss.stats.attacks.get(HumanoidBoss.STOMP, 0)) > 0 and boss.last_attack.target_player == companion, "Argus did not attack the living player from players[]")
func transformed_spawn_test() -> void:
	world = Node3D.new()
	world.position = Vector3(700, 0, -550)
	world.rotation.y = 0.8
	add_child(world)
	var refs := ArgusArena.build_encounter(world)
	var boss: Argus = refs.argus
	check(boss.global_position.distance_to(world.global_transform * ArgusArena.ARGUS_START) < 0.1, "Argus did not spawn in transformed arena: %s expected %s" % [str(boss.global_position), str(world.global_transform * ArgusArena.ARGUS_START)])
	check(absf(angle_difference(boss.global_rotation.y, world.global_rotation.y + ArgusArena.ARGUS_YAW)) < 0.01, "Argus spawn yaw ignored arena basis")
	check((refs.player as PlayerCharacter).global_position.distance_to(world.global_transform * ArgusArena.PLAYER_START) < 0.01, "Player transform wrong")
	var entry := world.to_global(Vector3(0, 0.95, 170))
	var hit := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(entry, entry + Vector3.DOWN * 3, Layers.WORLD))
	check(not hit.is_empty() and (hit.collider as Node).name == &"Ground", "+Z170 arena entrance is inaccessible")
