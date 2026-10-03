extends Node
## A real temple/corridor arrival, followed by a fight in a moved, rotated arena.
## Diagnostics are collected by the simulation and printed only after each run ends.

var completed := {}
var shots: Array = []
var cases: Array = []


func _ready() -> void:
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	cases.append(await _arrival())
	if not OS.get_cmdline_user_args().has("--arrival-only"):
		cases.append(await _rotated())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	var file := FileAccess.open("res://tests/output/avion_arrival.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(cases, "  "))
	file.close()
	for test: Dictionary in cases:
		print("Avion %s: %s at %.2f s; result %s" % [test.name, "WIN" if test.won else "FAIL", test.time, str(test.result)])
		if not test.won:
			print(JSON.stringify(test, "  "))
	get_tree().quit(0 if cases.all(func(test: Dictionary) -> bool: return test.won) else 1)


func _arrival() -> Dictionary:
	completed = {}
	shots.clear()
	var g := GameWorld.new()
	g.with_input = false
	g.with_art = false
	g.save_path = ""
	g.seed_offset = 101
	add_child(g)
	g.start(true)
	if not OS.get_cmdline_user_args().has("--full-arrival"):
		g.state.from_dict({"version": GameState.VERSION, "defeated": GameState.ORDER.slice(0, 4).map(func(k: StringName) -> String: return String(k))})
		g._build_world()
	var bot := GameBot.new()
	add_child(bot)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	bot._heading = Basis(Vector3.UP, rng.randf() * TAU) * Vector3.FORWARD
	bot.wander = rng.randf_range(0.0, 15.0)
	bot.wander_dir = Basis(Vector3.UP, rng.randf() * TAU) * Vector3.FORWARD
	var horse: Horse = g.refs.horse
	horse.teleport(Valley.on_ground(Valley.HORSE_SPAWN + Vector3(rng.randf_range(-14.0, 14.0), 0, rng.randf_range(-12.0, 6.0))), rng.randf() * TAU)
	bot.setup(g)
	var fighter: AvionBot = null
	var tick := 0
	while completed.is_empty() and bot.phase != GameBot.Phase.DONE and tick < 2200 * 60:
		await get_tree().physics_frame
		tick += 1
		if is_instance_valid(bot.boss_bot) and bot.boss_bot is AvionBot:
			if fighter == null:
				fighter = bot.boss_bot
				fighter.finished.connect(func(result: Dictionary) -> void: completed = result.duplicate(true))
				shots.append(_snapshot(fighter))
			if tick % (30 * 60) == 0:
				shots.append(_snapshot(fighter))
	var out := {"name": "campaign-arrival-seed142", "won": completed.get("won", false), "time": tick / 60.0, "result": completed.duplicate(true), "game_result": bot.result.duplicate(true), "game_events": bot.events.slice(-20), "shots": shots.duplicate(true)}
	if is_instance_valid(fighter):
		out["events"] = fighter.events.duplicate()
		out["final"] = _snapshot(fighter)
	bot.queue_free()
	g.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	return out


func _rotated() -> Dictionary:
	completed = {}
	shots.clear()
	var root := Node3D.new()
	root.transform = Transform3D(Basis(Vector3.UP, 0.8), Vector3(700, 12, -550))
	add_child(root)
	var refs := AvionArena.build_encounter(root, false, 142, false)
	var bot := AvionBot.new()
	root.add_child(bot)
	bot.setup(refs.player, refs.avion, refs.encounter, refs.towers)
	bot.finished.connect(func(result: Dictionary) -> void: completed = result.duplicate(true))
	var tick := 0
	while completed.is_empty() and tick < 720 * 60:
		await get_tree().physics_frame
		tick += 1
		if tick % (30 * 60) == 0:
			shots.append(_snapshot(bot))
	var out := {"name": "rotated-root-seed142", "won": completed.get("won", false), "time": tick / 60.0, "result": completed.duplicate(true), "events": bot.events.duplicate(), "shots": shots.duplicate(true), "final": _snapshot(bot)}
	root.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	return out


func _snapshot(bot: AvionBot) -> Dictionary:
	var p := bot.player
	var out := {"time": bot.time, "phase": AvionBot.Phase.keys()[bot.phase], "phase_time": bot.phase_time, "world": str(p.global_position), "arena": str(bot.avion.get_parent().to_local(p.global_position)), "state": p.get_display_state(), "velocity": str(p.velocity), "stamina": p.stamina.ratio(), "tower": bot._tower, "grab": p.actions.grab_held, "move": str(p.actions.move), "view": str(-p.actions.view_basis.z), "stats": bot.stats.duplicate(true), "flight": bot.avion.swoop_name(), "intent": str(bot.avion.intent.kind)}
	if bot._tower >= 0:
		out["base"] = str(bot._tower_base(bot._tower))
		out["tower_center"] = str(bot.towers[bot._tower].center)
	if p.grip:
		out["grip"] = str(p.grip.body.get_path())
		out["grip_normal"] = str(p.grip.world_normal())
		out["grip_point"] = str(p.grip.world_point())
	return out
