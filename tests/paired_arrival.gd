extends Node
## Regression: ride from the real temple/gate to an already active paired arena.
var failures := 0
var observations := {}

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
	var game := GameWorld.new()
	game.with_input = false
	game.with_art = false
	game.save_path = ""
	game.seed_offset = 101
	add_child(game)
	game.start_from({"version": GameState.VERSION, "defeated": GameState.ORDER.slice(0, 10).map(func(k: StringName) -> String: return String(k))})
	var bot := GameBot.new()
	add_child(bot)
	# A campaign return uses the standard temple/Agro state, with no initial soak
	# heading/wander randomization. Reproduce that actual subsequent-boss approach.
	bot.setup(game)
	var arrival_seen := false
	var previous_modes := ""
	var carried_outside_refuge := false
	observations.timeline = []
	for i in 60 * 900:
		await ticks(1)
		if not arrival_seen and bot.boss_bot is CelosiaCenobiaBot:
			arrival_seen = true
			observations.arrival = describe(game, bot.boss_bot as CelosiaCenobiaBot)
		if bot.boss_bot is CelosiaCenobiaBot:
			var pair := bot.boss_bot as CelosiaCenobiaBot
			if pair.boss.torch_carriers.has(pair.player) and not pair.player.actions.beam_held and not pair.boss.sheltered(pair.player):
				carried_outside_refuge = true
			var modes := "%d/%d/%d" % [pair.phase, pair.boss.guardians[0].mode, pair.boss.guardians[1].mode]
			if modes != previous_modes:
				observations.timeline.append(describe(game, pair))
				previous_modes = modes
		if not bot.stats.boss_results.is_empty() or bot.phase == GameBot.Phase.DONE:
			break
	observations.route = {"time": game.state.play_time, "phase": GameBot.Phase.keys()[bot.phase], "player_world": str(game.player().global_position), "events": bot.events.slice(-12)}
	check(arrival_seen, "GameBot did not ride to the paired encounter")
	var paired := bot.boss_bot as CelosiaCenobiaBot
	if paired:
		observations.final = describe(game, paired)
		observations.result = paired.result.duplicate(true)
	check(paired != null and bool(paired.result.get("won", false)), "Paired guardians could not be defeated after the real campaign arrival")
	if paired and bool(paired.result.get("won", false)):
		check(paired.encounter.resets == 0 and paired.stats.dodges > 0 and paired.stats.grabs >= 2 and paired.stats.weak_hits == 4 and paired.stats.both_open_before_hit, "Arrival fight skipped armour puzzles, independent sigils or reset during approach")
		check(carried_outside_refuge and paired.stats.fire_repositions > 0, "Arrival bot did not carry the acquired flame with the sword lowered to realign its retreat")
		game.set_physics_process(false)
		bot.set_physics_process(false)
		var encounter := paired.encounter
		var boss := paired.boss
		paired.free()
		bot.boss_bot = null
		# A deliberate restart follows the completed first fight, never the approach.
		encounter.reset_encounter()
		check(boss.torch_carriers.is_empty(), "Explicit restart retained the acquired flame")
		await ticks(3)
		var replay := CelosiaCenobiaBot.new()
		game.region.add_child(replay)
		replay.setup(game.player(), boss, encounter)
		for i in 60 * 245:
			await ticks(1)
			if not replay.result.is_empty(): break
		observations.restart = replay.result.duplicate(true)
		check(bool(replay.result.get("won", false)) and replay.stats.weak_hits == 4 and replay.stats.dodges > 0 and encounter.resets == 1, "Paired guardians could not replay the armour/sigil puzzles after an explicit restart")
		check(boss.guardians.all(func(g: PairedSentinel) -> bool: return g.is_defeated()), "Restart left one guardian alive")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/tests"))
	var file := FileAccess.open("res://data/tests/paired_arrival.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(observations, "  "))
	file.close()
	print("Paired arrival result: ", JSON.stringify(observations.get("result", {})))
	print("Paired restart result: ", JSON.stringify(observations.get("restart", {})))
	print("Detailed approach and state transitions saved locally to data/tests/paired_arrival.json")
	print("Paired arrival: %d failure(s); real temple ride, active pursuit before bot handoff, both armour puzzles and restart" % failures)
	get_tree().quit(1 if failures else 0)

func describe(game: GameWorld, paired: CelosiaCenobiaBot) -> Dictionary:
	var boss := paired.boss
	var guardians := []
	for g in boss.guardians:
		guardians.append({"mode": PairedSentinel.Mode.keys()[g.mode], "position": str(boss.to_local(g.global_position)), "distance": g.global_position.distance_to(paired.player.global_position), "cooldown": g.cooldown, "timer": g.timer, "armour_open": g.armour_open, "stats": g.stats.duplicate(true)})
	return {"game_time": game.state.play_time, "phase": CelosiaCenobiaBot.Phase.keys()[paired.phase], "player": str(boss.to_local(paired.player.global_position)), "state": paired.player.get_display_state(), "guardians": guardians, "torch_carriers": boss.torch_carriers.size(), "fire_faces": boss.fire_faces(boss.guardians[0]), "resets": paired.encounter.resets}
