extends Node
## Long regression run for a boss fight (Valus, Quadratus or Gaius): N complete encounters, each
## with another brain seed and a slightly different start, played by the scripted bot.
## Nothing is retried: every run ends as WIN, or as a DEADLOCK (no result within the time
## limit). Quadratus runs alternate on foot / from Agro and vary the shooting distance.
##
##   godot --headless --fixed-fps 60 res://tests/boss_soak.tscn -- --runs=50 [--from=1] [--boss=quadratus]
## Writes tests/output/<boss>_soak.json (boss_soak.json for Valus) and prints a summary.
##
## Watched per run: wins, deaths (encounter resets), stalls per bot phase, attachment
## glitches (the climber moving > 0.5 m in one tick while gripping), wrong resets (state
## after a reset not as at the start), AI stuck (same non-idle intent > 25 s in combat with
## no attack), weak point unreachable (no strike landed for > 120 s of combat).
## Quadratus also: arrows (shots, sole hits, wrong side, into the body / ground, flying
## away), foot reactions that did not run REACT -> KNEEL -> RISE -> NONE with the leg's
## support back to 1, and buckles the bot could not use.

const LIMIT := 60.0 * 360.0

var runs := 50
var first := 1
var boss := "valus"
var results := []
var _prev_bone: StringName = &""
var _prev_hand := Vector3.ZERO
var _prev_local := Vector3.ZERO


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--runs="):
			runs = int(a.trim_prefix("--runs="))
		elif a.begins_with("--from="):
			first = int(a.trim_prefix("--from="))
		elif a.begins_with("--boss="):
			boss = a.trim_prefix("--boss=")
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	for i in range(first, first + runs):
		if boss == "quadratus":
			results.append(await _run_quadratus(i))
		else:
			results.append(await _run(i))
		var r: Dictionary = results[-1]
		print("run %3d seed %3d: %s in %6.1f s  deaths %d %s falls %d stalls %s glitches %d bad_resets %d ai_stuck %d no_strike %s%s" % [i, r.seed, r.outcome, r.time, r.deaths, str(r.death_causes), r.falls, str(r.stalls), r.glitches, r.bad_resets, r.ai_stuck, str(r.unreachable), r.get("extra_line", "")])
	_summary()
	get_tree().quit(0)


func _run(i: int) -> Dictionary:
	var world := Node3D.new()
	add_child(world)
	var w: Dictionary
	if boss == "gaius":
		w = GaiusArena.build_encounter(world, false, 3000 + i * 11)
		w.valus = w.gaius
	else:
		w = ValusArena.build_encounter(world, false, 1000 + i * 7)
	var p: PlayerCharacter = w.player
	# A slightly different start each run (still the arena entrance).
	var rng := RandomNumberGenerator.new()
	rng.seed = i
	p.global_position += Vector3(rng.randf_range(-6.0, 6.0), 0.0, rng.randf_range(-3.0, 3.0))
	p.spawn_transform = p.global_transform
	p.reset_physics_interpolation()
	var s: HumanoidBoss = w.valus
	var e: BossEncounter = w.encounter
	var bot: ValusBot = GaiusBot.new() if boss == "gaius" else ValusBot.new()
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
		var armour_ok := not (s is Gaius) or ((s as Gaius).helmet.hits == 0 and not (s as Gaius).helmet.is_broken and s.weak_point.state == WeakPoint.State.PROTECTED)
		if not armour_ok or s.encounter != HumanoidBoss.Encounter.DORMANT or s.weak_point.health != s.weak_point.max_health or p.dead or p.health < p.fall.max_health or s.attack != null and not s.attack.is_done():
			bad_resets += 1)
	var t := 0
	var dt := 1.0 / 60.0
	while bot.phase != ValusBot.Phase.DONE and t < LIMIT:
		await get_tree().physics_frame
		t += 1
		if p.is_climbing() and was_climbing and p.global_position.distance_to(prev) > 0.5:
			glitches += 1
			if OS.get_environment("TRACE") != "":
				print("  glitch t%.2f %.2f m grip %s n %s prev_bone %s phase %s | boss %s attack %s shake %.2f stagger %.2f anchor speed %.2f m/tick" % [t * dt, p.global_position.distance_to(prev), bot._grip_bone(), str(p.grip.world_normal().snapped(Vector3.ONE * 0.01)), _prev_bone, ValusBot.Phase.keys()[bot.phase], s.intent.kind, s.attack.describe() if s.attack and not s.attack.is_done() else "-", s._shake, s._stagger, p.grip.point_velocity(dt).length() * dt])
		if OS.get_environment("TRACE") != "" and p.is_climbing() and was_climbing and p.global_position.distance_to(prev) > 0.5:
			print("    hands moved %.2f m, local %s -> %s, normal %s, climb_up %s, mantle? state %s" % [p.grip.world_point().distance_to(_prev_hand), str(_prev_local), str(p.grip.local_point.snapped(Vector3.ONE * 0.01)), str(p.grip.world_normal().snapped(Vector3.ONE * 0.01)), str(p.climb_up.snapped(Vector3.ONE * 0.01)), p.state])
		if p.is_climbing():
			_prev_hand = p.grip.world_point()
			_prev_local = p.grip.local_point.snapped(Vector3.ONE * 0.01)
		_prev_bone = bot._grip_bone()
		was_climbing = p.is_climbing()
		prev = p.global_position
		if s.encounter == HumanoidBoss.Encounter.COMBAT:
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
		"run": i, "seed": (3000 + i * 11) if boss == "gaius" else (1000 + i * 7),
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


func _run_quadratus(i: int) -> Dictionary:
	var world := Node3D.new()
	add_child(world)
	var w := QuadratusArena.build_encounter(world, false, 2000 + i * 13)
	var p: PlayerCharacter = w.player
	var rng := RandomNumberGenerator.new()
	rng.seed = i
	p.global_position += Vector3(rng.randf_range(-8.0, 8.0), 0.0, rng.randf_range(-4.0, 4.0))
	p.spawn_transform = p.global_transform
	p.reset_physics_interpolation()
	var q: Quadratus = w.quadratus
	var e: BossEncounter = w.encounter
	var bot := QuadratusBot.new()
	bot.verbose = OS.get_environment("BOT_VERBOSE") != ""
	bot.use_horse = i % 2 == 0
	bot.shoot_distance = rng.randf_range(10.0, 17.0)
	world.add_child(bot)
	bot.setup(p, q, e, w.horse)
	var m := {"glitches": 0, "bad_resets": 0, "ai_stuck": 0, "bad_buckles": 0, "buckles": 0}
	e.encounter_reset.connect(func(_n: int) -> void:
		var supports_ok := true
		for leg in q.loco.legs:
			supports_ok = supports_ok and leg.support >= 1.0 and not leg.scripted
		if q.encounter != Quadratus.Encounter.DORMANT or q.weak_points_left() != 2 or q.rump.health != q.rump.max_health or q.crown.health != q.crown.max_health or q.buckle != Quadratus.Buckle.NONE or not supports_ok or p.dead or p.health < p.fall.max_health or ArrowSystem.of(p).arrows.size() > 0:
			m.bad_resets += 1)
	# Foot reactions must run their whole course.
	var seq := []
	q.buckle_changed.connect(func(b: Quadratus.Buckle) -> void:
		seq.append(b)
		if b == Quadratus.Buckle.REACT:
			m.buckles += 1
		if b == Quadratus.Buckle.NONE:
			if seq.size() < 4 or seq.slice(-4) != [Quadratus.Buckle.REACT, Quadratus.Buckle.KNEEL, Quadratus.Buckle.RISE, Quadratus.Buckle.NONE]:
				m.bad_buckles += 1
			for leg in q.loco.legs:
				if leg.support < 0.99:
					m.bad_buckles += 1
			seq.clear())
	var t := 0
	var dt := 1.0 / 60.0
	var prev := p.global_position
	var was_climbing := false
	var same_intent := 0.0
	var last_kind := &""
	var since_strike := 0.0
	var unreachable := false
	var lost_grips := 0
	var last_hits := 0
	var long_buckle := 0
	while bot.phase != QuadratusBot.Phase.DONE and t < LIMIT:
		await get_tree().physics_frame
		t += 1
		if p.is_climbing() and was_climbing and p.global_position.distance_to(prev) > 0.5:
			m.glitches += 1
		if was_climbing and not p.is_climbing() and p.last_release_reason == &"invalid":
			lost_grips += 1
		was_climbing = p.is_climbing()
		prev = p.global_position
		if q.encounter == Quadratus.Encounter.COMBAT:
			var kind := q.intent.kind
			var attacking := q.attack != null and not q.attack.is_done()
			if kind == last_kind and kind != ColossusIntent.IDLE and not attacking:
				same_intent += dt
				if same_intent > 25.0 and same_intent - dt <= 25.0:
					m.ai_stuck += 1
			else:
				same_intent = 0.0
			last_kind = kind
			since_strike += dt
			if since_strike > 150.0:
				unreachable = true
			if q.buckle != Quadratus.Buckle.NONE and q.buckle_t > maxf(q.kneel_time, q.kneel_time_crown) + q.rise_time + 5.0:
				long_buckle += 1
		if bot.stats.weak_hits != last_hits:
			last_hits = bot.stats.weak_hits
			since_strike = 0.0
	var r := bot.result
	var st: Dictionary = bot.stats
	var arrows := {"shots": int(st.shots), "sole_hits": int(st.arrow_hits), "wrong_side": int(st.arrow_wrong_side), "disabled": int(st.arrow_disabled), "surface": int(st.arrow_surface), "from_horse": int(st.shots_from_horse)}
	var out := {
		"run": i, "seed": 2000 + i * 13, "variant": "horse" if bot.use_horse else "foot", "shoot_distance": bot.shoot_distance,
		"outcome": "WIN" if r.get("won", false) else "DEADLOCK",
		"time": float(r.get("time", t * dt)),
		"deaths": int(st.deaths), "death_causes": st.death_causes.duplicate(), "falls": int(st.falls), "stalls": st.stalls.duplicate(),
		"strikes": int(st.strikes), "weak_hits": int(st.weak_hits), "evades": int(st.evades),
		"hits_taken": int(q.stats.hits_on_player), "resets": e.resets, "glitches": m.glitches + lost_grips,
		"bad_resets": m.bad_resets, "ai_stuck": m.ai_stuck + long_buckle, "unreachable": unreachable,
		"arrows": arrows, "buckles": m.buckles, "bad_buckles": m.bad_buckles, "buckles_missed": int(st.buckles_missed),
		"last_events": bot.events.slice(-12) if not r.get("won", false) else [],
		"extra_line": "  [%s %.0fm] arrows %d -> sole %d (wrong side %d, body/ground %d) buckles %d (bad %d, unused %d)" % ["horse" if bot.use_horse else "foot", bot.shoot_distance, arrows.shots, arrows.sole_hits, arrows.wrong_side, arrows.surface, m.buckles, m.bad_buckles, int(st.buckles_missed)],
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
	if boss == "quadratus":
		var arrows := {"shots": 0, "sole_hits": 0, "wrong_side": 0, "disabled": 0, "surface": 0, "from_horse": 0}
		var q := {"buckles": 0, "bad_buckles": 0, "buckles_missed": 0, "foot_wins": 0, "horse_wins": 0}
		for r in results:
			for k in arrows:
				arrows[k] += int(r.arrows[k])
			for k in ["buckles", "bad_buckles", "buckles_missed"]:
				q[k] += int(r[k])
			if r.outcome == "WIN":
				q[r.variant + "_wins"] += 1
		summary.arrows = arrows
		summary.quadratus = q
	var f := FileAccess.open("res://tests/output/%s.json" % ("boss_soak" if boss == "valus" else boss + "_soak"), FileAccess.WRITE)
	f.store_string(JSON.stringify(summary, "  "))
	f.close()
	print("\n=== %s soak: %d runs, %d wins, %d deadlocks ===" % [boss, results.size(), wins, results.size() - wins])
	print("time to win: min %.1f s, median %.1f s, max %.1f s" % [summary.time_min, summary.time_median, summary.time_max])
	print("totals: %s" % str(totals))
	print("stalls by phase: %s" % str(stalls))
	print("death causes: %s" % str(causes))
	if summary.has("arrows"):
		print("arrows: %s" % str(summary.arrows))
		print("foot reactions: %s" % str(summary.quadratus))
	for r in results:
		if r.outcome != "WIN":
			print("DEADLOCK run %d seed %d: %s" % [r.run, r.seed, " | ".join(r.last_events)])
