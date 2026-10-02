extends Node
## Long regression run of the whole game: N new games played start to finish by GameBot
## (temple -> beam -> ride -> corridor -> Valus -> temple -> ... -> Hydrus -> the end).
## Each run uses other brain seeds in the arenas, another first guess of the way, Agro
## waiting somewhere else and a random first ride before the beam is checked again.
##
##   godot --headless --fixed-fps 60 res://tests/game_soak.tscn -- --runs=20 [--from=1]
## Writes tests/output/game_soak.json and prints a summary. Nothing is retried.

## Simulation limit per game (s).
const LIMIT := 60.0 * 45.0

var runs := 10
var first := 1
var results := []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--runs="):
			runs = int(a.trim_prefix("--runs="))
		elif a.begins_with("--from="):
			first = int(a.trim_prefix("--from="))
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	for i in range(first, first + runs):
		var r := await _run(i)
		results.append(r)
		print("game %3d: %s in %6.1f s  deaths %d  fights %s  valley %.0f s (ride %.0f)  beam sweeps %d locks %d unlit %d  detours %d  stalls %s" % [
			i, r.outcome, r.time, r.deaths, r.fights_line, r.valley_time, r.ride_time, r.beam_sweeps, r.beam_locks, r.beam_unlit, r.detours, str(r.stalls)])
	_summary()
	get_tree().quit(0)


func _run(i: int) -> Dictionary:
	var g := GameWorld.new()
	g.with_input = false
	g.with_art = false
	g.save_path = ""
	g.seed_offset = i * 101
	add_child(g)
	g.start(true)
	var bot := GameBot.new()
	bot.verbose = OS.get_environment("BOT_VERBOSE") != ""
	add_child(bot)
	var rng := RandomNumberGenerator.new()
	rng.seed = i
	# Another first guess of the way: the bot starts the sweep from a random heading.
	bot._heading = Basis(Vector3.UP, rng.randf() * TAU) * Vector3.FORWARD
	# Other ways through the valley: Agro somewhere else below the temple, and a ride off
	# in a random direction first, then the first look from the saddle.
	bot.wander = rng.randf_range(0.0, 15.0)
	bot.wander_dir = Basis(Vector3.UP, rng.randf() * TAU) * Vector3.FORWARD
	var h: Horse = g.refs.horse
	h.teleport(Valley.on_ground(Valley.HORSE_SPAWN + Vector3(rng.randf_range(-14.0, 14.0), 0, rng.randf_range(-12.0, 6.0))), rng.randf() * TAU)
	bot.setup(g)
	var t := 0
	while bot.phase != GameBot.Phase.DONE and t < LIMIT * 60.0:
		await get_tree().physics_frame
		t += 1
	var r := bot.result
	var st: Dictionary = bot.stats
	var line := []
	for f in st.boss_results:
		line.append("%s %s %.0fs" % [f.boss, "W" if f.won else "L", f.time])
	var out := {
		"run": i, "outcome": "WIN" if r.get("won", false) else "DEADLOCK", "why": r.get("why", "time limit"),
		"time": t / 60.0, "deaths": g.state.deaths, "defeated": g.state.to_dict().defeated,
		"fights": st.boss_results, "fights_line": " | ".join(line),
		"valley_time": st.valley_time, "ride_time": st.ride_time, "beam_sweeps": st.beam_sweeps,
		"beam_locks": st.beam_locks, "beam_unlit": st.beam_unlit, "detours": st.detours, "stalls": st.stalls,
		"transitions": g.transitions,
		"last_events": bot.events.slice(-14) if not r.get("won", false) else [],
	}
	bot.queue_free()
	g.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	return out


func _summary() -> void:
	var wins := 0
	var times: Array[float] = []
	var stalls := {}
	var fight_times := {}
	for r in results:
		if r.outcome == "WIN":
			wins += 1
			times.append(r.time)
		for s in r.stalls:
			stalls[s] = int(stalls.get(s, 0)) + 1
		for f in r.fights:
			if not fight_times.has(f.boss):
				fight_times[f.boss] = []
			fight_times[f.boss].append(snappedf(f.time, 0.1))
	times.sort()
	var summary := {"runs": results.size(), "wins": wins, "deadlocks": results.size() - wins, "stalls": stalls,
		"time_min": times[0] if times.size() > 0 else -1.0, "time_median": times[times.size() / 2] if times.size() > 0 else -1.0,
		"time_max": times[-1] if times.size() > 0 else -1.0, "fight_times": fight_times, "runs_detail": results}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	var f := FileAccess.open("res://tests/output/game_soak.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(summary, "  "))
	f.close()
	print("\n=== game soak: %d runs, %d complete, %d deadlocks ===" % [results.size(), wins, results.size() - wins])
	print("time to finish: min %.1f s, median %.1f s, max %.1f s" % [summary.time_min, summary.time_median, summary.time_max])
	print("stalls by phase: %s" % str(stalls))
	for r in results:
		if r.outcome != "WIN":
			print("DEADLOCK game %d (%s): %s" % [r.run, r.why, " | ".join(r.last_events)])
