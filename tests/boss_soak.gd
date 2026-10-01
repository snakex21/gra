extends Node
## Long regression run for the Valus fight: N complete encounters, each with another
## brain seed and a slightly different start, played by the scripted bot. Nothing is
## retried: every run ends as WIN, or as a DEADLOCK (no result within the time limit).
##
##   godot --headless --fixed-fps 60 res://tests/boss_soak.tscn -- --runs=50 [--from=1]
## Writes tests/output/boss_soak.json and prints a summary.
##
## Watched per run: wins, deaths (encounter resets), stalls per bot phase, attachment
## glitches (the climber moving > 0.5 m in one tick while gripping), wrong resets (state
## after a reset not as at the start), AI stuck (same non-idle intent > 25 s in combat with
## no attack), weak point unreachable (no strike landed for > 120 s of combat).

const LIMIT := 60.0 * 360.0

var runs := 50
var first := 1
var results := []
var _prev_bone: StringName = &""


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
		results.append(await _run(i))
		var r: Dictionary = results[-1]
		print("run %3d seed %3d: %s in %6.1f s  deaths %d %s falls %d stalls %s glitches %d bad_resets %d ai_stuck %d no_strike %s" % [i, r.seed, r.outcome, r.time, r.deaths, str(r.death_causes), r.falls, str(r.stalls), r.glitches, r.bad_resets, r.ai_stuck, str(r.unreachable)])
	_summary()
	get_tree().quit(0)


func _run(i: int) -> Dictionary:
	var world := Node3D.new()
	add_child(world)
	var w := ValusArena.build_encounter(world, false, 1000 + i * 7)
	var p: PlayerCharacter = w.player
	# A slightly different start each run (still the arena entrance).
	var rng := RandomNumberGenerator.new()
	rng.seed = i
	p.global_position += Vector3(rng.randf_range(-6.0, 6.0), 0.0, rng.randf_range(-3.0, 3.0))
	p.spawn_transform = p.global_transform
	p.reset_physics_interpolation()
	var s: Valus = w.valus
	var e: BossEncounter = w.encounter
	var bot := ValusBot.new()
	bot.verbose = OS.get_environment("BOT_VERBOSE") != ""
	world.add_child(bot)
	bot.setup(p, s, e)
	var glitches := 0
	var bad_resets := 0
	var ai_stuck := 0
	var same_intent := 0.0
	var last_kind := &""
	var since_strike := 0.0
	var unreachable := false
	var prev := p.global_position
	var was_climbing := false
	e.encounter_reset.connect(func(_n: int) -> void:
		# Right after a reset everything must be as at the start.
		if s.encounter != Valus.Encounter.DORMANT or s.weak_point.health != s.weak_point.max_health or p.dead or p.health < p.fall.max_health or s.attack != null and not s.attack.is_done():
			bad_resets += 1)
	var t := 0
	var dt := 1.0 / 60.0
	while bot.phase != ValusBot.Phase.DONE and t < LIMIT:
		await get_tree().physics_frame
		t += 1
		if p.is_climbing() and was_climbing and p.global_position.distance_to(prev) > 0.5:
			glitches += 1
			if OS.get_environment("TRACE") != "":
				print("  glitch t%.2f %.2f m grip %s n %s prev_bone %s phase %s" % [t * dt, p.global_position.distance_to(prev), bot._grip_bone(), str(p.grip.world_normal().snapped(Vector3.ONE * 0.01)), _prev_bone, ValusBot.Phase.keys()[bot.phase]])
		_prev_bone = bot._grip_bone()
		was_climbing = p.is_climbing()
		prev = p.global_position
		if s.encounter == Valus.Encounter.COMBAT:
			var kind := s.intent.kind
			var attacking := s.attack != null and not s.attack.is_done()
			if kind == last_kind and kind != ColossusIntent.IDLE and not attacking:
				same_intent += dt
				if same_intent > 25.0 and same_intent - dt <= 25.0:
					ai_stuck += 1
			else:
				same_intent = 0.0
			last_kind = kind
			since_strike += dt
			if since_strike > 120.0:
				unreachable = true
		if bot.stats.weak_hits > 0 and since_strike > 0.0 and s.weak_point.since_hit < dt * 1.5:
			since_strike = 0.0
	var r := bot.result
	var out := {
		"run": i, "seed": 1000 + i * 7,
		"outcome": "WIN" if r.get("won", false) else "DEADLOCK",
		"time": float(r.get("time", t * dt)),
		"deaths": int(bot.stats.deaths), "death_causes": bot.stats.death_causes.duplicate(), "falls": int(bot.stats.falls), "stalls": bot.stats.stalls.duplicate(),
		"strikes": int(bot.stats.strikes), "weak_hits": int(bot.stats.weak_hits), "evades": int(bot.stats.evades),
		"hits_taken": int(s.stats.hits_on_player), "resets": e.resets, "glitches": glitches,
		"bad_resets": bad_resets, "ai_stuck": ai_stuck, "unreachable": unreachable,
		"last_events": bot.events.slice(-12) if not r.get("won", false) else [],
	}
	world.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	return out


func _summary() -> void:
	var wins := 0
	var times: Array[float] = []
	var totals := {"deaths": 0, "falls": 0, "glitches": 0, "bad_resets": 0, "ai_stuck": 0, "unreachable": 0, "hits_taken": 0, "evades": 0}
	var stalls := {}
	var causes := {}
	for r in results:
		for c in r.death_causes:
			var key: String = String(c).split(" ")[0]
			causes[key] = int(causes.get(key, 0)) + 1
		if r.outcome == "WIN":
			wins += 1
			times.append(r.time)
		for k in ["deaths", "falls", "glitches", "bad_resets", "ai_stuck", "hits_taken", "evades"]:
			totals[k] += int(r[k])
		totals.unreachable += 1 if r.unreachable else 0
		for st in r.stalls:
			stalls[st] = int(stalls.get(st, 0)) + 1
	times.sort()
	var summary := {"runs": results.size(), "wins": wins, "deadlocks": results.size() - wins, "totals": totals, "stalls": stalls,
		"time_min": times[0] if times.size() > 0 else -1.0, "time_median": times[times.size() / 2] if times.size() > 0 else -1.0,
		"time_max": times[-1] if times.size() > 0 else -1.0, "death_causes": causes, "runs_detail": results}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	var f := FileAccess.open("res://tests/output/boss_soak.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(summary, "  "))
	f.close()
	print("\n=== boss soak: %d runs, %d wins, %d deadlocks ===" % [results.size(), wins, results.size() - wins])
	print("time to win: min %.1f s, median %.1f s, max %.1f s" % [summary.time_min, summary.time_median, summary.time_max])
	print("totals: %s" % str(totals))
	print("stalls by phase: %s" % str(stalls))
	print("death causes: %s" % str(causes))
	for r in results:
		if r.outcome != "WIN":
			print("DEADLOCK run %d seed %d: %s" % [r.run, r.seed, " | ".join(r.last_events)])
