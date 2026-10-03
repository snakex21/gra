extends Node
## Behavioral acceptance tests: real physics, replay resume, playable cave and water.
var failures := 0
var world: Node3D

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func cleanup() -> void:
	get_tree().paused = false
	if is_instance_valid(world):
		world.free()
	await ticks(2)

func game() -> GameWorld:
	world = Node3D.new()
	add_child(world)
	var g := GameWorld.new()
	g.with_input = false
	g.with_art = false
	g.save_path = ""
	world.add_child(g)
	g.start(true)
	return g

func _ready() -> void:
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	await test_paths()
	await test_cave()
	await cleanup()
	await test_cave_completion_and_companion_death()
	await cleanup()
	await test_route()
	await cleanup()
	await test_water()
	await cleanup()
	await test_snapshot()
	await cleanup()
	await test_replay_checkpoint_and_clip()
	await cleanup()
	await test_art_budget()
	await cleanup()
	print("Stage 12: %d failure(s)" % failures)
	get_tree().quit(1 if failures else 0)

func test_paths() -> void:
	var path := PortablePaths.resolve("user://stage12/test.json")
	check(path.begins_with(ProjectSettings.globalize_path("res://")) and "/data/" in path.replace("\\", "/"), "data did not stay in the game folder")
	check(OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")), "engine user data escaped the portable launcher")
	var state := GameState.new()
	check(state.save(path), "portable save failed")
	check(GameState.new().load_from(path), "portable save did not load")
	DirAccess.remove_absolute(path)
	print("PASS portable data and legacy path mapping")

func test_cave() -> void:
	world = Node3D.new()
	add_child(world)
	var refs := CaveArena.build_encounter(world, false, false)
	var c: CaveColossus = refs.colossus
	var p: PlayerCharacter = refs.player
	p.global_position = Vector3(0, 0.95, 15)
	p.actions.beam_held = true
	p.actions.view_basis = Basis.looking_at(c.get_focus_point() - SwordBeam.tip(p))
	await ticks(300)
	check(p.beam.lantern and p.beam.lit and p.beam.raise == 1.0 and p.beam.focus == 0.0, "sword flashlight did not work under the ceiling")
	check((p.visual.get_node("SwordLantern") as SpotLight3D).visible, "flashlight has no visible spot light")
	check(c.encounter == HumanoidBoss.Encounter.COMBAT, "cave boss did not engage")
	# Light exposes it early, while the timeout guarantees that solo cannot get stuck.
	c.shelter = CaveColossus.Shelter.HIDDEN
	c.shelter_t = 0.0
	c.attack = null
	c.intent = ColossusIntent.make(CaveColossus.HIDE)
	c._think_left = 0.0
	p.actions.view_basis = Basis.looking_at(c.get_focus_point() - SwordBeam.tip(p))
	await ticks(110)
	check(c.shelter == CaveColossus.Shelter.EXPOSED, "sword light did not lure the cave boss out")
	check(c.weak_point.state == WeakPoint.State.OPEN, "lured weak point stayed shielded")
	check(ResourceLoader.exists("res://scenes/cave_arena.tscn") and BossRoster.ORDER[-1] == &"dormin", "cave trial or planned final boss is absent")
	print("PASS cave engagement, sword light and exposure window")

func test_cave_completion_and_companion_death() -> void:
	world = Node3D.new()
	add_child(world)
	var refs := CaveArena.build_encounter(world, false, false)
	var p: PlayerCharacter = refs.player
	var c: CaveColossus = refs.colossus
	var e: BossEncounter = refs.encounter
	var companion := PlayerCharacter.new()
	world.add_child(companion)
	companion.global_position = CaveArena.PLAYER_START + Vector3.RIGHT * 2.0
	companion.spawn_transform = companion.global_transform
	e.players.append(companion)
	companion.auto_respawn = false
	companion.dead = true
	companion.health = 0.0
	await ticks(180)
	check(e.resets == 0 and e.state == BossEncounter.State.RUNNING and not companion.dead, "companion death reset the ongoing fight")
	e.players.erase(companion)
	companion.free()
	var leaving := PlayerCharacter.new()
	world.add_child(leaving)
	e.players.append(leaving)
	leaving.free()
	await ticks(3)
	check(e.resets == 0 and e.players.size() == 1, "leaving companion reset or blocked the fight")
	var bot := CaveBot.new()
	world.add_child(bot)
	bot.setup(p, c, e)
	for i in 60 * 240:
		await ticks(1)
		if not bot.result.is_empty():
			break
	check(bool(bot.result.get("won", false)), "cave climbing route was not completable by actions (%s)" % str(bot.result))
	print("PASS cave fight completion and companion death isolation")

func test_route() -> void:
	world = Node3D.new()
	add_child(world)
	var refs := AvionArena.build_encounter(world, false, 41, false)
	var a: Avion = refs.avion
	var p: PlayerCharacter = refs.player
	p.global_position = AvionArena.TOWERS[0][0] + Vector3.UP * (AvionArena.TOWER_TOP + 0.95)
	var passes := 0
	var last := Avion.Swoop.NONE
	var low := Vector3.ZERO
	var drift := 0.0
	for i in 60 * 75:
		await ticks(1)
		if a.swoop == Avion.Swoop.DIVE and last != a.swoop:
			low = a.low_point
		if a.swoop == Avion.Swoop.DIVE:
			drift = maxf(drift, a.low_point.distance_to(low))
		if a.swoop == Avion.Swoop.PASS and last != a.swoop:
			passes += 1
			check(absf(a.global_position.y - a.low_point.y) < 0.2, "planned dive missed its low pass height")
		last = a.swoop
	check(passes >= 2 and int(a.stats.get("swoops_aborted", 0)) == 0, "planned swoops did not finish (%d passes)" % passes)
	check(drift < 0.001, "dive retargeted in flight")
	print("PASS Avion planned route: %d complete passes, no retargeting" % passes)

func test_water() -> void:
	world = Node3D.new()
	add_child(world)
	var refs := HydrusArena.build_encounter(world, false, 29, false)
	var p: PlayerCharacter = refs.player
	var water := world.get_node("Lake") as WaterBody
	var y := water.surface()
	p.global_position = Vector3(0, y + 4, 20)
	p.velocity = Vector3.DOWN * 10.0
	await ticks(100)
	check(water.splashes > 0 and water.surface() == y, "entering water gave no splash or changed gameplay height")
	check(water.clock > 0.0 and Array(water.ripple_events).any(func(v: Vector4) -> bool: return v.w > 0), "water ripple was not recorded")
	print("PASS water entry ripples and fixed swimming surface")

func test_snapshot() -> void:
	var g := game()
	g._wake(&"avion")
	g.player().global_position = WorldMap.arena_transform(&"avion") * AvionArena.PLAYER_START
	await ticks(240)
	var c := g.colossus() as Avion
	var before := c.global_transform
	var rng := (c.brain as AvionBrain)._rng.state
	var snapshot := WorldSnapshot.capture(g)
	# Verify that checkpoints survive the same binary codec used by replay files.
	snapshot = bytes_to_var(var_to_bytes(snapshot))
	await ticks(60)
	check(WorldSnapshot.restore(g, snapshot), "checkpoint did not restore")
	c = g.colossus() as Avion
	check(c.global_transform == before and (c.brain as AvionBrain)._rng.state == rng, "checkpoint lost flight pose / RNG state")
	await ticks(120)
	check(is_instance_valid(g.player()) and not g.player().dead, "resumed world did not simulate")
	print("PASS binary world checkpoint: transforms, timers and RNG restored")

func test_replay_checkpoint_and_clip() -> void:
	var g := game()
	var rec := ActionReplay.recorder(null, {"progress": g.state.to_dict()})
	rec.player_source = g.player
	g.add_child(rec)
	await ticks(1802)
	var data := rec.to_dict()
	check(data.checkpoints.size() >= 4, "recorder did not capture periodic checkpoints")
	var saved: Vector3 = g.player().global_position
	g.remove_child(rec)
	rec.free()
	var viewer := ReplayViewer.new()
	viewer.setup(g, data)
	world.add_child(viewer)
	viewer.seek(1800)
	check(viewer.tick() >= 1200, "seek restarted the recording at tick zero")
	await ticks(4)
	var path := PortablePaths.resolve("res://data/tests/stage12_clip.replay")
	check(viewer.save_clip(1800, path) == path, "checkpoint clip did not save")
	var clip := ActionReplay.load_file(path)
	check(not clip.get("checkpoints", []).is_empty(), "clip omitted its starting world checkpoint")
	check(clip.frames.size() <= data.frames.size(), "clip did not trim the frame prefix")
	check(g.player().global_position.distance_to(saved) < 0.1, "seek restored the wrong player position")
	DirAccess.remove_absolute(path)
	print("PASS checkpoint seek and compact clip")

func test_art_budget() -> void:
	var g := game()
	g.stop()
	g.with_art = true
	g.start(true)
	var steps := 0
	while not g.arenas_ready() and steps < 3000:
		g._build_step()
		steps += 1
	check(g.arenas_ready() and steps > 30, "arena art was not split into small jobs")
	print("PASS incremental art: %d small build steps" % steps)
