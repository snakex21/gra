extends Node
## Independent end-to-end companion checks in the actual GameWorld and physics tree.
const AutoSave := preload("res://src/game/auto_save.gd")
const SLOT := "res://data/tests/companion_world.json"
var failures := 0
var deadline := Time.get_ticks_msec() + 180000
var cases: Array[String] = []

func _process(_delta: float) -> void:
	if Time.get_ticks_msec() > deadline:
		push_error("Companion world test timed out or stopped after a runtime error")
		cleanup()
		get_tree().quit(1)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func ticks(count: int) -> void:
	for i in count: await get_tree().physics_frame

func make_world(mode: StringName = &"off") -> GameWorld:
	var game := GameWorld.new()
	game.with_art = false
	game.with_input = false
	game.save_path = ""
	game.settings.companion_mode = mode
	add_child(game)
	game.start(true)
	return game

func at_ground(actor: PlayerCharacter, position: Vector3) -> void:
	actor.global_position = position
	actor.velocity = Vector3.ZERO
	actor.actions.clear()
	actor.spawn_transform = actor.global_transform
	actor.reset_physics_interpolation()

func cleanup() -> void:
	AutoSave.clear(SLOT)
	DirAccess.remove_absolute(PortablePaths.resolve(SLOT))
	DirAccess.remove_absolute(AutoSave.world_path(SLOT) + ".tmp")

func _ready() -> void:
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	cleanup()
	await basic_follow_and_encounter()
	await regroup_branch()
	await cave_layers_and_boundaries()
	await checkpoint_and_autosave()
	cleanup()
	print("COMPANION_WORLD: %d failure(s); cases=%s" % [failures, str(cases)])
	get_tree().quit(1 if failures else 0)

func basic_follow_and_encounter() -> void:
	var game := make_world()
	await ticks(10)
	check(game.companion_mode == &"off" and game.companion() == null, "Fresh solo world created a companion")
	check(game.region.get_node_or_null("Player2") == null and game.region.get_node_or_null("CompanionController") == null, "Solo world contains companion nodes")
	var host := game.player()
	var horse: Horse = game.refs.horse
	game.set_companion_mode(&"programmed")
	var actor := game.companion()
	var controller: CompanionController = game.refs.companion_controller
	check(actor != null and actor != host and actor.player_index == 1 and actor.name == "Player2", "Programmed companion was not a separate PlayerCharacter")
	check(controller.actor == actor and controller.mode == &"programmed", "Controller was not linked to live Player2")
	# Dry, ordinary valley terrain, away from temple stairs and the lake. Movement
	# must be caused by PlayerActions and CharacterBody physics, not regroup teleport.
	at_ground(host, Valley.on_ground(Vector3(-65, 0, -65), .95))
	at_ground(actor, Valley.on_ground(Vector3(-65, 0, -43), .95))
	host.facing = Vector3.FORWARD
	await ticks(12)
	var distance_before := actor.global_position.distance_to(host.global_position)
	var actor_before := actor.global_position
	await ticks(180)
	check(actor.global_position.distance_to(actor_before) > 3.0 and actor.global_position.distance_to(host.global_position) < distance_before - 3.0, "Companion did not follow through actual ground physics")
	check(controller.navigation_updates > 10 and controller.policy.decisions > 0 and not actor.dead, "Companion ground policy/navigation did not run safely")
	cases.append("solo default and real follow")
	game._wake(&"valus")
	at_ground(host, game.arenas[&"valus"].xf * ValusArena.PLAYER_START)
	at_ground(actor, host.global_position + game.arenas[&"valus"].xf.basis.x * 2.5)
	await ticks(5)
	var boss := game.colossus() as HumanoidBoss
	boss.set_physics_process(false) # isolate participant lifecycle from random attacks
	var encounter: BossEncounter = game.refs.encounter
	encounter.death_pause = .2
	var wp := boss.weak_point
	wp.health = wp.max_health * .6
	var health := wp.health
	var host_id := host.get_instance_id()
	var horse_id := horse.get_instance_id()
	var encounter_id := encounter.get_instance_id()
	var host_xf := host.global_transform
	var horse_xf := horse.global_transform
	var horse_rider := horse.current_rider
	game.set_companion_mode(&"off")
	check(encounter.players == [host] and encounter.resets == 0 and wp.health == health, "Leaving companion reset/damaged encounter or retained participant")
	game.set_companion_mode(&"programmed")
	actor = game.companion()
	check(encounter.players.size() == 2 and encounter.players.has(actor), "Live companion did not join the running encounter")
	check(host.get_instance_id() == host_id and horse.get_instance_id() == horse_id and encounter.get_instance_id() == encounter_id, "Join/leave recreated host/horse/encounter")
	check(host.global_transform == host_xf and horse.global_transform == horse_xf and horse.current_rider == horse_rider and wp.health == health and encounter.resets == 0, "Join/leave changed host, Agro, boss health or reset count")
	at_ground(actor, host.global_position + Vector3.RIGHT * 2.5)
	check(actor.apply_hit(999.0, Vector3.ZERO), "Companion death fixture could not apply a real hit")
	await ticks(2)
	check(actor.dead and encounter.state == BossEncounter.State.RUNNING, "One participant death ended encounter")
	await ticks(18)
	check(not actor.dead and actor.health > 0 and not host.dead and wp.health == health and encounter.resets == 0, "Companion death did not revive independently with boss progress retained")
	check(host.apply_hit(999.0, Vector3.ZERO), "Host death fixture could not apply a real hit")
	await ticks(2)
	check(host.dead and not actor.dead and encounter.state == BossEncounter.State.RUNNING, "Living companion did not preserve encounter when host died")
	await ticks(18)
	check(not host.dead and wp.health == health and encounter.resets == 0, "Host revive with living companion reset boss progress")
	check(host.apply_hit(999.0, Vector3.ZERO) and actor.apply_hit(999.0, Vector3.ZERO), "All-dead fixture could not damage both participants")
	await ticks(2)
	check(encounter.state == BossEncounter.State.PLAYER_DEAD, "All participants dead did not enter reset pause")
	await ticks(18)
	check(encounter.resets == 1 and encounter.state == BossEncounter.State.RUNNING and not host.dead and not actor.dead and wp.health == wp.max_health, "All-dead encounter did not reset both participants and boss once")
	cases.append("live join/leave and independent/all-dead revival")
	game.free()
	await ticks(2)

func stage_regroup(game: GameWorld, host_at: Vector3, actor_at: Vector3) -> void:
	var host := game.player()
	var actor := game.companion()
	if host.riding.is_active():
		host.riding._finish(Vector3.ZERO)
	at_ground(host, host_at)
	at_ground(actor, actor_at)
	host.state = PlayerCharacter.State.GROUND
	actor.state = PlayerCharacter.State.GROUND
	host.facing = Vector3.FORWARD
	var camera: Camera3D = game.refs.camera
	camera.global_position = host.global_position + Vector3.UP * 2.0
	camera.look_at(camera.global_position + Vector3.FORWARD)
	game._regroup_t = 0.0

func rejects_regroup(game: GameWorld, events: Array[Vector3], reason: String) -> void:
	var before := game.companion().global_position
	var count := events.size()
	game._regroup_t = 0.0
	game._companion_tick(5.01)
	check(events.size() == count and game.companion().global_position == before, "Regroup teleported or emitted an event while " + reason)

func regroup_branch() -> void:
	var game := make_world(&"programmed")
	await ticks(10)
	var host := game.player()
	var actor := game.companion()
	var horse: Horse = game.refs.horse
	var controller: CompanionController = game.refs.companion_controller
	var camera: Camera3D = game.refs.camera
	# Freeze movement and automatic ticks, retaining the real terrain, capsule
	# collision queries and camera frustum. Only GameWorld's actual catch-up branch
	# may move Player2; this fixture never calls regroup_companion directly.
	for node: Node in [game, host, actor, horse, controller, camera]:
		node.set_physics_process(false)
		if node == camera: node.set_process(false)
	var events: Array[Vector3] = []
	game.companion_regrouped.connect(func(position: Vector3) -> void: events.append(position))
	var host_at := Valley.on_ground(Vector3(-65, 0, -65), .95)
	var far_at := Valley.on_ground(Vector3(-65, 0, 100), .95)
	stage_regroup(game, host_at, far_at)
	await ticks(2)
	var target := game._companion_join_position(host.global_position, true, camera)
	check(actor.global_position.distance_to(host.global_position) > 75.0 and not camera.is_position_in_frustum(actor.global_position), "Regroup fixture did not put distant companion outside the actual frustum")
	check(target != Vector3.INF and not camera.is_position_in_frustum(target), "Regroup fixture has no dry, clear hidden destination")
	actor.velocity = Vector3(2, 0, 1)
	game._companion_tick(4.99)
	check(events.is_empty() and actor.global_position == far_at, "Regroup happened before five seconds")
	game._companion_tick(.02)
	check(events.size() == 1 and actor.global_position.distance_to(target) < .001 and actor.velocity == Vector3.ZERO and actor.spawn_transform == actor.global_transform, "Actual regroup branch did not teleport once to the safe destination and reset motion/spawn")
	game._companion_tick(5.01)
	check(events.size() == 1, "Already nearby companion emitted a repeated regroup event")
	# At the midpoint between the first and second authored offsets, look directly
	# at the first. A visible safe candidate must not hide the second safe choice.
	stage_regroup(game, host_at, far_at)
	var first := game._companion_join_position(host.global_position, true)
	camera.global_position = host.global_position + Vector3(0, 0, 8)
	camera.look_at(first)
	target = game._companion_join_position(host.global_position, true, camera)
	check(camera.is_position_in_frustum(first) and not camera.is_position_in_frustum(far_at) and target != Vector3.INF and not camera.is_position_in_frustum(target) and target.distance_to(first) > 1.0, "Alternate regroup fixture did not produce visible-first/hidden-second safe candidates")
	game._companion_tick(5.01)
	check(events.size() == 2 and actor.global_position.distance_to(target) < .001, "Regroup stopped at a visible first candidate instead of using a later hidden candidate")
	# Real riding state, saddle and horse ownership, with the horse physics frozen.
	stage_regroup(game, host_at, far_at)
	horse.teleport(Valley.on_ground(Vector3(-65, 0, -65), 0.0), 0.0)
	host.riding.mount_now(horse)
	camera.global_position = host.global_position + Vector3.UP * 2.0
	camera.look_at(camera.global_position + Vector3.FORWARD)
	await ticks(2)
	target = game._companion_join_position(host.global_position, true, camera)
	check(host.state == PlayerCharacter.State.RIDE and host.is_riding() and horse.current_rider == host and target != Vector3.INF, "Mounted regroup fixture has no real rider or safe destination")
	game._companion_tick(5.01)
	check(events.size() == 3 and actor.global_position.distance_to(target) < .001 and horse.current_rider == host and host.is_riding(), "Mounted host could not regroup its companion without changing the rider")
	cases.append("real regroup after 5s, alternate hidden candidate and mounted host")
	stage_regroup(game, host_at, Valley.on_ground(Vector3(-65, 0, -180), .95))
	check(camera.is_position_in_frustum(actor.global_position), "Visible companion refusal fixture is outside frustum")
	rejects_regroup(game, events, "companion is visible")
	stage_regroup(game, host_at, far_at)
	actor._enter_swim()
	rejects_regroup(game, events, "companion is swimming")
	stage_regroup(game, host_at, far_at)
	host.state = PlayerCharacter.State.AIR
	rejects_regroup(game, events, "host is airborne")
	stage_regroup(game, host_at + Vector3.UP * 100.0, far_at)
	check(game._companion_join_position(host.global_position, true) == Vector3.INF, "Unsafe destination fixture still found supporting terrain")
	rejects_regroup(game, events, "host has no safe nearby ground")
	stage_regroup(game, host_at, far_at)
	# A solid occupying the destination must be rejected by capsule clearance;
	# exclude WORLD so the floor ray cannot mistake its top for new walkable ground.
	var occupied := StaticBody3D.new()
	occupied.collision_layer = Layers.COLOSSUS
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(26, 4, 26)
	shape.shape = box
	occupied.add_child(shape)
	game.region.add_child(occupied)
	occupied.global_position = host_at
	await ticks(2)
	check(game._companion_join_position(host.global_position, true) == Vector3.INF, "Occupied destination fixture bypassed actual capsule clearance")
	rejects_regroup(game, events, "all nearby destinations are occupied")
	occupied.free()
	await ticks(2)
	stage_regroup(game, host_at, far_at)
	var wet := WaterBody.new()
	wet.radius = 20.0
	wet.show_surface = false
	game.region.add_child(wet)
	wet.global_position = host_at + Vector3.UP * 4.0
	check(game._companion_join_position(host.global_position, true) == Vector3.INF, "Wet destination fixture still returned dry ground")
	rejects_regroup(game, events, "all nearby ground is underwater")
	wet.free()
	stage_regroup(game, host_at, far_at)
	var victories := game.state.defeated.duplicate()
	game._wake(&"valus")
	check(game.region_kind == &"valus" and game.colossus() != null, "Combat regroup refusal fixture did not wake a real boss")
	actor.set_physics_process(false)
	rejects_regroup(game, events, "an actual encounter is active")
	game._sleep()
	actor.set_physics_process(false)
	stage_regroup(game, host_at, far_at)
	var generation := game._decision_generation
	check(host.apply_hit(999.0, Vector3.ZERO) and host.dead, "Dead-host regroup refusal fixture did not apply a real fatal hit")
	rejects_regroup(game, events, "host is dead")
	check(game._decision_generation > generation and game.state.defeated == victories, "Regroup/death changed victories or did not invalidate host decision generation")
	cases.append("regroup rejects visible, swimming, airborne, unsupported, occupied, wet, combat and dead-host states")
	if DisplayServer.get_name() != "headless":
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	game.free()
	await ticks(2)

func cave_layers_and_boundaries() -> void:
	var game := make_world(&"programmed")
	await ticks(8)
	game._wake(&"devil")
	check(game.companion().beam.lantern and game.player().beam.lantern, "Cave wake did not enable both sword lanterns")
	check(actor_layer(game.companion(), 2) and actor_layer(game.player(), 2), "Cave wake did not put both actor meshes on cave light layer")
	check((game.companion().visual._lantern.light_cull_mask & 2) != 0, "Companion lantern does not illuminate cave layer")
	game._sleep()
	check(not game.companion().beam.lantern and actor_layer(game.companion(), 1), "Cave exit left companion lantern/layer enabled")
	check(game.companion().auto_respawn, "Sleeping encounter left companion autonomous respawn disabled")
	cases.append("cave lantern/layer wake and sleep")
	# A victory transition cancels a half-drawn arrow and freezes its owner. Drive
	# this fixture through real actions while the controller is temporarily paused.
	var actor := game.companion()
	var controller: CompanionController = game.refs.companion_controller
	controller.set_physics_process(false)
	actor.actions.press_switch_weapon()
	await ticks(2)
	actor.actions.attack_held = true
	await ticks(12)
	check(actor.weapon == PlayerCharacter.Weapon.BOW and actor.bow.is_aiming(), "Fade fixture did not start a real companion bow draw")
	game._go(GameWorld.VALLEY, false)
	check(game.phase == GameWorld.Phase.FADE_OUT and not actor.is_physics_processing() and not actor.bow.is_aiming() and not actor.actions.attack_held, "Victory fade retained companion draw/action or active physics")
	await ticks(90)
	check(game.phase == GameWorld.Phase.PLAYING and game.companion().is_physics_processing(), "Companion physics did not resume after victory fade rebuild")
	cases.append("fade cancels bow and freezes/resumes companion")
	game.set_companion_mode(&"local_model")
	controller = game.refs.companion_controller
	controller.accept_decision(&"follow")
	var before_generation := game._decision_generation
	get_tree().paused = true
	# Test itself runs while paused long enough for notification cancellation.
	await get_tree().create_timer(.02, true, false, true).timeout
	check(game._decision_generation > before_generation, "Pause did not invalidate pending local decisions")
	game._on_companion_decision(&"hold", before_generation)
	check(controller.accepted_intent == &"follow", "Paused/stale local decision changed companion intent")
	get_tree().paused = false
	before_generation = game._decision_generation
	game.stop()
	check(game.region == null and game.companion() == null and game._decision_generation > before_generation, "Title did not remove companion/cancel local decisions")
	game._on_companion_decision(&"support", before_generation)
	check(game.companion() == null, "Late title decision recreated a companion")
	game.settings.companion_mode = &"off"
	var progress := GameState.new()
	for i in 20: progress.mark_defeated(BossRoster.PLAYABLE[i])
	game.start_from(progress.to_dict())
	check(game.state.defeated.size() == 20 and game.companion() == null and game.companion_mode == &"off", "Late campaign/new build forced an AI companion")
	cases.append("pause/title cancellation and 20-victory solo build")
	game.free()
	await ticks(2)

func actor_layer(actor: PlayerCharacter, expected: int) -> bool:
	var visuals := actor.find_children("*", "GeometryInstance3D", true, false)
	if visuals.is_empty(): return false
	for mesh: GeometryInstance3D in visuals:
		if mesh.layers != expected: return false
	return true

func checkpoint_and_autosave() -> void:
	var game := make_world(&"programmed")
	await ticks(8)
	var host := game.player()
	var actor := game.companion()
	at_ground(host, Valley.on_ground(Vector3(-95, 0, -65), .95))
	at_ground(actor, Valley.on_ground(Vector3(-95, 0, -47), .95))
	host.facing = Vector3.FORWARD
	await ticks(90)
	var controller: CompanionController = game.refs.companion_controller
	var checkpoint: Dictionary = bytes_to_var(var_to_bytes(WorldSnapshot.capture(game)))
	var at_host := host.global_position
	var at_actor := actor.global_position
	var actions := actor.actions.snapshot()
	var random_state := controller.policy.rng.state
	var decisions := controller.policy.decisions
	check(checkpoint.companion_mode == "programmed", "Checkpoint omitted active session companion mode")
	await ticks(120)
	var expected_actor := actor.global_position
	var expected_host := host.global_position
	var expected_rng := controller.policy.rng.state
	var expected_decisions := controller.policy.decisions
	game.settings.companion_mode = &"off"
	check(WorldSnapshot.restore(game, checkpoint), "Programmed companion world could not restore full binary checkpoint")
	host = game.player()
	actor = game.companion()
	controller = game.refs.companion_controller
	check(game.companion_mode == &"programmed" and actor != null and controller.actor == actor, "Checkpoint did not reconstruct Player2/controller independent of current settings")
	check(host.global_position.distance_to(at_host) < .001 and actor.global_position.distance_to(at_actor) < .001 and actor.actions.snapshot() == actions, "Checkpoint lost participant positions or action frame")
	check(controller.policy.rng.state == random_state and controller.policy.decisions == decisions, "Checkpoint lost companion RNG or policy state")
	await ticks(120)
	var drift := actor.global_position.distance_to(expected_actor)
	check(drift < .10 and host.global_position.distance_to(expected_host) < .10 and controller.policy.rng.state == expected_rng and controller.policy.decisions == expected_decisions, "Restored companion continuation diverged: %.6fm" % drift)
	cases.append("full checkpoint positions/actions/RNG and continuation %.6fm" % drift)
	# A checkpoint from before companions must remain solitary even when the user's
	# current preferences enable AI for the next new session.
	game.set_companion_mode(&"off")
	var legacy: Dictionary = bytes_to_var(var_to_bytes(WorldSnapshot.capture(game)))
	legacy.erase("companion_mode")
	game.settings.companion_mode = &"programmed"
	check(WorldSnapshot.restore(game, legacy) and game.companion() == null and game.companion_mode == &"off", "Old checkpoint without companion mode enabled AI from current preferences")
	game.set_companion_mode(&"programmed")
	await ticks(20)
	check(AutoSave.safe_to_checkpoint(game), "Companion autosave fixture did not settle on safe ground")
	var saved_actor := game.companion().global_position
	check(AutoSave.save(game, SLOT) and FileAccess.file_exists(AutoSave.world_path(SLOT)), "Safe companion world checkpoint was not saved locally")
	game.free()
	await ticks(2)
	game = make_world(&"off")
	check(AutoSave.restore(game, SLOT), "Companion autosave could not restore")
	check(game.settings.companion_mode == &"off" and game.companion_mode == &"programmed" and game.companion() != null and game.companion().global_position.distance_to(saved_actor) < .001, "AutoSave applied current off preference over recorded session mode/position")
	game.apply_settings(game.settings)
	check(game.companion_mode == &"off" and game.companion() == null, "Explicit settings apply could not switch a restored session to solo")
	cases.append("legacy checkpoint off and AutoSave current-preference isolation")
	# Native rendering must finish one frame for the freshly reconstructed sky
	# before fixture teardown; a headless renderer never emits frame_post_draw.
	if DisplayServer.get_name() != "headless":
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	game.free()
	await ticks(2)
