extends Node
## Headless gameplay tests for Milestone 1 (climbing on a moving colossus).
##
## Run:  godot --headless --fixed-fps 60 res://tests/test_runner.tscn
## Optional: -- --only=<substring>  to run a subset.
## Exit code 0 = all passed. Tests drive the player through PlayerActions exactly like
## a human or AI companion would; they never poke at internals to fake progress.

const DT := 1.0 / 60.0

var _failures: Array[String] = []
var _current := ""
var _world: Node3D
var _log := PackedStringArray()
## Regression metrics: key -> {"value": float, "better": "lower"|"higher"|"info", "test": name}
var _metrics := {}
const BASELINE_PATH := "res://tests/baseline/etap2_baseline.json"


func _ready() -> void:
	InputSetup.ensure_defaults()
	var only := ""
	var save_baseline := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
		elif arg == "--save-baseline":
			save_baseline = true
	var tests: Array[Callable] = [
		test_rig_segments_follow_bones,
		test_physics_server_transform_matches_anchor,
		test_grab_and_hold_on_walking_leg,
		test_climb_leg_to_shoulders_frozen,
		test_climb_leg_to_shoulders_walking,
		test_traverse_around_limb,
		test_armor_blocks_climbing,
		test_exhaustion_drops_player,
		test_brain_shakes_and_rules_limit_it,
		test_shake_drains_more_than_hanging,
		test_release_inherits_surface_velocity,
		test_jump_off_and_regrab_midair,
		test_static_wall_climb_and_mantle,
		test_performance_budget,
		# --- ETAP 2 ---
		test_standing_on_still_colossus_is_stable,
		test_standing_on_walking_colossus_remains_controllable,
		test_standing_on_turning_colossus_is_carried,
		test_shake_destabilizes_standing_player,
		test_player_can_grab_during_slip,
		test_severe_shake_can_throw_ungripped_player,
		test_brain_shake_throws_idle_standing_player,
		test_gripping_player_resists_shake_using_stamina,
		test_small_fall_is_safe,
		test_medium_fall_has_consequence,
		test_large_fall_triggers_fall_consequence,
		test_lethal_fall_respawns,
		test_late_grab_catches_falling_player,
		test_grip_transfer_while_colossus_turns,
		test_camera_does_not_clip_into_colossus,
		test_camera_focus_frames_player_and_colossus,
		test_bone_local_grip_still_has_no_drift,
		probe_balance_disturbance,
	]
	for t in tests:
		var name := t.get_method()
		if only != "" and not name.contains(only):
			continue
		_current = name
		var fails_before := _failures.size()
		var t0 := Time.get_ticks_msec()
		await t.call()
		await _teardown()
		var ok := _failures.size() == fails_before
		print("%s %s (%d ms)" % ["PASS" if ok else "FAIL", name, Time.get_ticks_msec() - t0])
		for line in _log:
			print("    ", line)
		_log.clear()
	_report_metrics(save_baseline and only == "")
	print("\n%d failure(s)" % _failures.size())
	for f in _failures:
		print("  - ", f)
	get_tree().quit(1 if _failures.size() > 0 else 0)


# --- tests ----------------------------------------------------------------------------

func test_rig_segments_follow_bones() -> void:
	var w := await _setup(&"walk")
	var c: Colossus = w.colossus
	_check(c.segments.size() == 17, "expected 17 segments, got %d" % c.segments.size())
	await _ticks(120)
	var max_err := 0.0
	for s in c.segments:
		var expected := c.skeleton.global_transform * c.skeleton.get_bone_global_pose(s.bone_idx)
		max_err = maxf(max_err, expected.origin.distance_to(s.global_transform.origin))
	_check(max_err < 0.001, "segments deviate from bones by %.4f m" % max_err)
	_check(c.global_position.distance_to(Vector3.ZERO) > 0.3, "walking colossus did not move")


## Documents the physics-server behaviour SurfaceAnchor relies on.
func test_physics_server_transform_matches_anchor() -> void:
	var w := await _setup(&"walk")
	await _ticks(90)
	var seg: BodySegment = _segment(w.colossus, &"shin_l")
	var server := SurfaceAnchor.body_query_transform(seg)
	var lag := server.origin.distance_to(seg.global_transform.origin)
	_log.append("server vs node transform lag for kinematic segment: %.4f m" % lag)
	_check(lag < 0.2, "server transform lags too much: %.3f" % lag)


func test_grab_and_hold_on_walking_leg() -> void:
	var w := await _setup(&"walk")
	var p: PlayerCharacter = w.player
	await _ticks(30)
	await _grab_behind(w, &"shin_l", -1.8)
	_check(p.is_climbing(), "player did not grab the shin")
	if not p.is_climbing():
		return
	var start_local := p.grip.local_point
	var start_body := p.grip.body
	var max_surface_err := 0.0
	var max_speed := 0.0
	var dropped := false
	for i in 360:
		await _ticks(1)
		if not p.is_climbing():
			dropped = true
			break
		max_surface_err = maxf(max_surface_err, _surface_error(p))
		max_speed = maxf(max_speed, p.surface_velocity.length())
	_check(not dropped, "player lost grip while just holding (reason %s)" % p.last_release_reason)
	_check(p.grip == null or p.grip.body == start_body, "grip changed body without input")
	if p.grip:
		var drift := p.grip.local_point.distance_to(start_local)
		_log.append("local drift over 6 s: %.5f m, max anchor-to-surface error: %.4f m, max surface speed %.2f m/s" % [drift, max_surface_err, max_speed])
		_check(drift < 0.01, "anchor drifted %.4f m in segment space without input" % drift)
		_metric("grip_drift_walk_m", drift, "lower")
	_metric("grip_surface_err_walk_m", max_surface_err, "lower")
	_metric("grip_surface_speed_walk_mps", max_speed)
	_check(max_surface_err < 0.08, "anchor is %.3f m off the real collider" % max_surface_err)
	_check(max_speed > 0.3, "leg was not moving (%.2f m/s) - test is not testing anything" % max_speed)


func test_climb_leg_to_shoulders_frozen() -> void:
	await _climb_route(&"frozen")


func test_climb_leg_to_shoulders_walking() -> void:
	await _climb_route(&"walk")


func _climb_route(mode: StringName) -> void:
	var w := await _setup(mode)
	var p: PlayerCharacter = w.player
	await _ticks(20)
	await _grab_behind(w, &"shin_l", -1.8)
	_check(p.is_climbing(), "player did not grab the shin")
	if not p.is_climbing():
		return
	var visited: Array[StringName] = []
	var mantled := [false]
	p.mantled.connect(func() -> void: mantled[0] = true)
	p.actions.move = Vector2(0, 1)
	var max_err := 0.0
	var start_y := p.global_position.y
	var trace := PackedStringArray()
	for i in 60 * 20:
		_aim_view_at(p, w.colossus)
		await _ticks(1)
		if p.is_climbing() and i % 30 == 0:
			trace.append("t=%.1f %s local=%s n=%s up=%s y=%.1f st=%.0f" % [i * DT, p.grip.body.name, str(p.grip.local_point.snapped(Vector3.ONE * 0.01)), str(p.grip.world_normal().snapped(Vector3.ONE * 0.01)), str(p.climb_up.snapped(Vector3.ONE * 0.01)), p.global_position.y, p.stamina.value])
		if p.is_climbing():
			max_err = maxf(max_err, _surface_error(p))
			var bone: StringName = (p.grip.body as BodySegment).bone_name if p.grip.body is BodySegment else &"?"
			if visited.is_empty() or visited[-1] != bone:
				visited.append(bone)
		elif mantled[0]:
			break
		else:
			break
	p.actions.move = Vector2.ZERO
	await _ticks(30)
	_log.append("[%s] route: %s" % [mode, " -> ".join(visited)])
	_log.append("[%s] rose %.1f m, state %s, stamina %.0f, max surface err %.3f, last release %s" % [mode, p.global_position.y - start_y, PlayerCharacter.State.keys()[p.state], p.stamina.value, max_err, p.last_release_reason])
	_metric("climb_route_%s_stamina_left" % mode, p.stamina.value, "higher")
	if OS.get_environment("TRACE") != "":
		_log.append_array(trace)
	_check(&"thigh_l" in visited, "never reached the thigh")
	_check(&"hips" in visited or &"spine" in visited, "never reached hips/spine")
	_check(&"chest" in visited, "never reached the chest")
	_check(mantled[0], "did not pull up onto the shoulders")
	_check(p.global_position.y - w.colossus.global_position.y > 13.0, "not standing on the shoulders (y=%.1f)" % p.global_position.y)
	_check(w.colossus.owns_body(p.get_support_body()), "support after mantle is not the colossus")
	_check(max_err < 0.08, "anchor left the collider surface by %.3f m" % max_err)


func test_traverse_around_limb() -> void:
	var w := await _setup(&"frozen")
	var p: PlayerCharacter = w.player
	await _ticks(10)
	await _grab_behind(w, &"thigh_l", -2.0)
	_check(p.is_climbing(), "player did not grab the thigh")
	if not p.is_climbing():
		return
	var n0 := p.grip.world_normal()
	p.actions.move = Vector2(1, 0)
	var min_dot := 1.0
	for i in 60 * 5:
		_aim_view_at(p, w.colossus)
		await _ticks(1)
		if not p.is_climbing():
			break
		min_dot = minf(min_dot, p.grip.world_normal().dot(n0))
	p.actions.move = Vector2.ZERO
	_log.append("sideways around thigh: min normal dot %.2f, still climbing %s" % [min_dot, p.is_climbing()])
	_check(p.is_climbing(), "fell off while traversing sideways (%s)" % p.last_release_reason)
	_check(min_dot < 0.0, "did not get around the limb (min dot %.2f)" % min_dot)


func test_armor_blocks_climbing() -> void:
	var w := await _setup(&"frozen")
	var p: PlayerCharacter = w.player
	await _ticks(10)
	# Start on the side of the shin and move towards the front armour plate.
	var seg := _segment(w.colossus, &"shin_l")
	var c: Colossus = w.colossus
	var side := c.global_basis.x
	p.global_position = seg.global_transform * Vector3(0, -2.2, 0) + side * 1.4 + Vector3.DOWN * 0.3
	p.facing = -side
	p.actions.grab_held = true
	await _ticks(2)
	_check(p.is_climbing(), "could not grab the side of the shin")
	if not p.is_climbing():
		return
	# Moving right while facing -X on the left leg means moving towards the front (-Z).
	p.actions.move = Vector2(1, 0)
	for i in 60 * 4:
		await _ticks(1)
	var local := seg.global_transform.affine_inverse() * p.grip.world_point() if p.grip else Vector3.ZERO
	_log.append("stopped at shin-local %s" % str(local.snapped(Vector3.ONE * 0.01)))
	_check(p.is_climbing(), "fell off at the armour edge")
	_check(p.grip != null and p.grip.shape is ClimbPatch, "ended on a non-climbable shape")
	_check(local.z > -0.8, "crawled onto/through the armour plate (z=%.2f)" % local.z)


func test_exhaustion_drops_player() -> void:
	var w := await _setup(&"frozen")
	var p: PlayerCharacter = w.player
	await _ticks(10)
	await _grab_behind(w, &"thigh_l", -2.0)
	_check(p.is_climbing(), "no grip")
	p.stamina.value = 4.0
	var released_at := -1
	for i in 60 * 4:
		await _ticks(1)
		if not p.is_climbing():
			released_at = i
			break
	_check(released_at >= 0, "player never let go at zero stamina")
	_check(p.last_release_reason == &"exhausted", "release reason %s" % p.last_release_reason)
	_check(p.stamina.exhausted, "stamina not flagged exhausted")
	# Still holding grab: must not re-grip while exhausted.
	var regripped := false
	var landed := false
	for i in 60 * 3:
		await _ticks(1)
		regripped = regripped or (p.is_climbing() and p.stamina.exhausted)
		landed = landed or p.state == PlayerCharacter.State.GROUND
	_check(landed, "player did not land")
	_check(not regripped, "player re-gripped while exhausted")
	for i in 60 * 2:
		await _ticks(1)
	_check(not p.stamina.exhausted, "stamina did not recover on the ground")


func test_brain_shakes_and_rules_limit_it() -> void:
	var w := await _setup(&"")
	var p: PlayerCharacter = w.player
	var c: Colossus = w.colossus
	await _ticks(10)
	await _grab_back_patch(w)
	_check(p.is_climbing(), "could not grab the back")
	var shake_ticks := 0
	var longest := 0
	var max_level := 0.0
	var first_shake := -1
	var stamina_start := p.stamina.value
	for i in 60 * 14:
		p.stamina.value = maxf(p.stamina.value, 60.0)  # isolate the rule check from falling
		await _ticks(1)
		if c.intent.kind == ColossusIntent.SHAKE_PLAYER:
			shake_ticks += 1
			longest = maxi(longest, shake_ticks)
			if first_shake < 0:
				first_shake = i
		else:
			shake_ticks = 0
		max_level = maxf(max_level, p.shake_level)
	_log.append("first shake after %.1f s, longest shake %.2f s, max shake level %.2f, still climbing %s" % [first_shake * DT, longest * DT, max_level, p.is_climbing()])
	_check(first_shake >= 0, "brain never tried to shake off a climber")
	_check(first_shake * DT > 1.5, "brain shook immediately, the climber gets no calm window")
	_check(longest * DT <= c.shake_max_duration + c.think_interval + 0.05, "shake exceeded the fairness limit: %.2f s" % (longest * DT))
	_check(max_level > 0.3, "shake too weak to be felt by the climber (%.2f)" % max_level)
	_check(stamina_start > 0.0, "")


func test_shake_drains_more_than_hanging() -> void:
	var w := await _setup(&"frozen")
	var p: PlayerCharacter = w.player
	await _ticks(10)
	await _grab_back_patch(w)
	_check(p.is_climbing(), "could not grab the back")
	p.stamina.refill()
	await _ticks(60)
	var hang_drain := 100.0 - p.stamina.value
	p.stamina.refill()
	w.colossus.debug_override = &"shake"
	w.colossus._think_left = 0.0
	await _ticks(30)  # ramp up
	var before := p.stamina.value
	await _ticks(60)
	var shake_drain := before - p.stamina.value
	_log.append("stamina/s hanging %.1f, shaking %.1f" % [hang_drain, shake_drain])
	_metric("shake_grip_stamina_drain_per_s", shake_drain)
	_check(shake_drain > hang_drain * 2.5, "shaking is not noticeably harder than hanging")


func test_release_inherits_surface_velocity() -> void:
	var w := await _setup(&"shake")
	var p: PlayerCharacter = w.player
	await _ticks(10)
	await _grab_back_patch(w)
	_check(p.is_climbing(), "could not grab the back")
	p.stamina.value = 100.0
	await _ticks(50)
	var sv := p.surface_velocity
	p.actions.grab_held = false
	await _ticks(1)
	var inherited := p.velocity
	_log.append("surface velocity %.2f m/s, velocity after release %.2f m/s" % [sv.length(), inherited.length()])
	_metric("release_inherit_error_mps", Vector2(inherited.x, inherited.z).distance_to(Vector2(sv.x, sv.z)), "lower")
	_check(not p.is_climbing(), "did not let go")
	_check(sv.length() > 0.2, "surface was not moving")
	# One tick of gravity/air control is applied after the release.
	_check(Vector2(inherited.x, inherited.z).distance_to(Vector2(sv.x, sv.z)) < 0.5, "horizontal velocity not inherited")


func test_jump_off_and_regrab_midair() -> void:
	var w := await _setup(&"frozen")
	var p: PlayerCharacter = w.player
	await _ticks(10)
	await _grab_behind(w, &"thigh_l", -2.0)
	_check(p.is_climbing(), "no grip")
	var y0 := p.global_position.y
	p.actions.move = Vector2(0, 1)
	p.actions.press_jump()
	await _ticks(1)
	_check(not p.is_climbing(), "jump did not release")
	_check(p.last_release_reason == &"jump", "release reason %s" % p.last_release_reason)
	var regrabbed_at := -1
	for i in 90:
		await _ticks(1)
		if p.is_climbing():
			regrabbed_at = i
			break
	p.actions.move = Vector2.ZERO
	_log.append("re-grabbed after %d ticks at dy %.2f" % [regrabbed_at, p.global_position.y - y0])
	_metric("leap_regrab_gain_m", p.global_position.y - y0, "higher")
	_check(regrabbed_at >= int(p.regrab_delay / DT) - 1, "re-grabbed before the regrab delay")
	_check(regrabbed_at >= 0, "holding grip in the air did not catch the surface again")
	_check(p.global_position.y > y0 + 0.5, "leap along the surface did not gain height")


func test_static_wall_climb_and_mantle() -> void:
	var w := await _setup(&"frozen", true)
	var p: PlayerCharacter = w.player
	await _ticks(5)
	p.global_position = Vector3(40, 0.95, 1.9)
	p.facing = Vector3.FORWARD
	p.actions.view_basis = Basis.IDENTITY
	await _ticks(10)
	p.actions.grab_held = true
	await _ticks(2)
	_check(p.is_climbing(), "could not grab the vines")
	var mantled := [false]
	p.mantled.connect(func() -> void: mantled[0] = true)
	p.actions.move = Vector2(0, 1)
	for i in 60 * 8:
		await _ticks(1)
		if mantled[0]:
			break
	p.actions.move = Vector2.ZERO
	await _ticks(20)
	_log.append("static wall: mantled %s, y %.2f, state %s" % [mantled[0], p.global_position.y, PlayerCharacter.State.keys()[p.state]])
	_check(mantled[0], "did not mantle onto the wall top")
	_check(p.global_position.y > 7.5 and p.state == PlayerCharacter.State.GROUND, "not standing on the wall")


func test_performance_budget() -> void:
	var w := await _setup(&"walk")
	var p: PlayerCharacter = w.player
	var c: Colossus = w.colossus
	await _ticks(10)
	# A0: same scenario as the Milestone 1 benchmark (no camera): climbing a walking colossus.
	await _grab_behind(w, &"shin_l", -1.8)
	p.actions.move = Vector2(0, 1)
	var a0 := await _measure(300)
	var cam := PlayerCamera.new()
	cam.player = p
	cam.focus_target = c
	_world.add_child(cam)
	# A: the same with the camera.
	var a := await _measure(120)
	# B: standing on the shoulders during a full shake (balance + Coulomb slide).
	p.actions.move = Vector2.ZERO
	p.actions.grab_held = false
	await _ticks(2)
	await _stand_on_shoulder(w, Vector3(1.9, 0, 0))
	c.debug_override = &"shake"
	c._think_left = 0.0
	var b := await _measure(120)
	# C: falling while holding grip (grab search every tick).
	c.debug_override = &"frozen"
	p.global_position = Vector3(30, 40, 30)
	p.actions.grab_held = true
	var d := await _measure(60)
	var objects_before := Performance.get_monitor(Performance.OBJECT_COUNT)
	await _ticks(300)
	var objects_growth := Performance.get_monitor(Performance.OBJECT_COUNT) - objects_before
	for r in [["climb (M1)", a0], ["climb+cam", a], ["stand+shake", b], ["fall+grab", d]]:
		var m: Dictionary = r[1]
		_log.append("%-12s frame %.3f ms | logic/tick: colossus %.1f us, player %.1f us, camera %.1f us | queries/tick: climb rays %.1f, grab %.1f, camera %.1f" % [r[0], m.frame_ms, m.colossus, m.player, m.camera, m.climb_rays, m.grab, m.cam_q])
	_log.append("object count growth over 300 ticks: %d" % objects_growth)
	for r in [["climb", a0], ["climb_cam", a], ["stand_shake", b], ["fall_grab", d]]:
		var m: Dictionary = r[1]
		_metric("perf_%s_frame_ms" % r[0], m.frame_ms, "lower")
		_metric("perf_%s_colossus_us" % r[0], m.colossus, "lower")
		_metric("perf_%s_player_us" % r[0], m.player, "lower")
		_metric("perf_%s_camera_us" % r[0], m.camera, "lower")
		_metric("perf_%s_climb_rays" % r[0], m.climb_rays, "lower")
		_metric("perf_%s_grab_queries" % r[0], m.grab, "lower")
		_metric("perf_%s_camera_queries" % r[0], m.cam_q, "lower")
	_check(a0.frame_ms < 0.6, "regression vs Milestone 1 benchmark (~0.25 ms): %.3f ms" % a0.frame_ms)
	_check(a.climb_rays < 8.0, "too many climb rays per tick: %.1f" % a.climb_rays)
	_check(d.grab <= 2.0, "grab search too expensive: %.1f shape queries per tick" % d.grab)
	_check(a.cam_q <= 10.0, "camera too expensive: %.1f queries per tick" % a.cam_q)
	_check(objects_growth < 20, "objects leak every frame (+%d)" % objects_growth)


func _measure(ticks: int) -> Dictionary:
	Perf.take()
	var t0 := Time.get_ticks_usec()
	await _ticks(ticks)
	var total := Time.get_ticks_usec() - t0
	var pr := Perf.take()
	var us: Dictionary = pr.usec
	var q: Dictionary = pr.queries
	return {
		"frame_ms": total / 1000.0 / ticks,
		"colossus": us.get(&"colossus", 0) / float(ticks),
		"player": us.get(&"player", 0) / float(ticks),
		"camera": us.get(&"camera", 0) / float(ticks),
		"climb_rays": q.get(&"climb_rays", 0) / float(ticks),
		"grab": q.get(&"grab_queries", 0) / float(ticks),
		"cam_q": q.get(&"camera_queries", 0) / float(ticks),
	}


# --- ETAP 2: balance, falls, camera ----------------------------------------------------

func test_standing_on_still_colossus_is_stable() -> void:
	var w := await _setup(&"frozen")
	var p: PlayerCharacter = w.player
	var c: Colossus = w.colossus
	await _stand_on_shoulder(w, Vector3(1.9, 0, 0))
	var chest := _segment(c, &"chest")
	var start := chest.global_transform.affine_inverse() * p.global_position
	var min_balance := 1.0
	for i in 180:
		await _ticks(1)
		min_balance = minf(min_balance, p.balance.value)
	var drift := (chest.global_transform.affine_inverse() * p.global_position).distance_to(start)
	_log.append("min balance %.3f, drift on chest %.3f m, state %s" % [min_balance, drift, p.get_display_state()])
	_metric("standing_drift_still_m", drift, "lower")
	_check(c.owns_body(p.get_support_body()), "not standing on the colossus")
	_check(p.get_display_state() == "STAND", "display state is %s" % p.get_display_state())
	_check(min_balance > 0.95, "balance dropped on a still colossus (%.2f)" % min_balance)
	_check(drift < 0.05, "player drifted %.3f m on a still colossus" % drift)


func test_standing_on_walking_colossus_remains_controllable() -> void:
	var w := await _setup(&"walk")
	var p: PlayerCharacter = w.player
	var c: Colossus = w.colossus
	await _ticks(200)  # let it reach walking speed
	await _stand_on_shoulder(w, Vector3(1.9, 0, 0.6))
	var chest := _segment(c, &"chest")
	var min_balance := 1.0
	for i in 120:
		await _ticks(1)
		min_balance = minf(min_balance, p.balance.value)
	# Walk towards the colossus' front edge for 0.3 s (relative to the moving body).
	var before := chest.global_transform.affine_inverse() * p.global_position
	for i in 18:
		p.actions.view_basis = Basis.looking_at(-c.global_basis.z)
		p.actions.move = Vector2(0, 1)
		await _ticks(1)
		min_balance = minf(min_balance, p.balance.value)
	p.actions.move = Vector2.ZERO
	await _ticks(20)
	var after := chest.global_transform.affine_inverse() * p.global_position
	var moved := before.z - after.z  # chest-local -Z is the colossus front
	_log.append("colossus speed %.2f m/s, min balance %.2f, moved %.2f m forward on the body, state %s" % [(c as GreyboxHumanoid).get_speed(), min_balance, moved, p.get_display_state()])
	_metric("standing_walk_min_balance", min_balance, "higher")
	_metric("standing_walk_moved_m", moved, "higher")
	_check((c as GreyboxHumanoid).get_speed() > 1.0, "colossus was not walking")
	_check(min_balance > 0.7, "walking colossus destabilised a standing player (%.2f)" % min_balance)
	_check(moved > 0.8, "player input did not move him on the walking body (%.2f m)" % moved)
	_check(c.owns_body(p.get_support_body()), "player is no longer on the colossus")


func test_standing_on_turning_colossus_is_carried() -> void:
	var w := await _setup(&"turn")
	var p: PlayerCharacter = w.player
	var c: Colossus = w.colossus
	await _ticks(120)
	await _stand_on_shoulder(w, Vector3(1.9, 0, 0))
	var chest := _segment(c, &"chest")
	var start := chest.global_transform.affine_inverse() * p.global_position
	var yaw0 := c.rotation.y
	var min_balance := 1.0
	for i in 240:
		await _ticks(1)
		min_balance = minf(min_balance, p.balance.value)
	var drift := (chest.global_transform.affine_inverse() * p.global_position).distance_to(start)
	_log.append("turned %.2f rad, drift on chest %.3f m, min balance %.2f" % [absf(angle_difference(yaw0, c.rotation.y)), drift, min_balance])
	_metric("standing_drift_turning_m", drift, "lower")
	_check(absf(angle_difference(yaw0, c.rotation.y)) > 0.2, "colossus did not turn")
	_check(drift < 0.25, "player was not carried by the rotating body (drift %.2f m)" % drift)
	_check(min_balance > 0.7, "slow turn destabilised the player")


func test_shake_destabilizes_standing_player() -> void:
	var w := await _setup(&"frozen")
	var p: PlayerCharacter = w.player
	var c: Colossus = w.colossus
	await _stand_on_shoulder(w, Vector3(1.9, 0, 0))
	c.debug_shake_strength = 0.5
	c.debug_override = &"shake"
	c._think_left = 0.0
	var min_balance := 1.0
	var states := {}
	var slid := 0.0
	for i in 180:
		await _ticks(1)
		min_balance = minf(min_balance, p.balance.value)
		states[Balance.State.keys()[p.balance.state]] = true
		slid = maxf(slid, p._slide_velocity.length())
	_log.append("half-strength shake: min balance %.2f, states %s, max slide speed %.2f m/s" % [min_balance, str(states.keys()), slid])
	_metric("shake_half_min_balance", min_balance)
	_check(min_balance < 0.5, "shake did not destabilise a standing player (%.2f)" % min_balance)
	_check(states.has("UNSTABLE"), "no gradual UNSTABLE phase (not continuous)")
	_check(slid > 0.05, "losing balance did not make the player slide at all")


func test_player_can_grab_during_slip() -> void:
	var w := await _setup(&"frozen")
	var p: PlayerCharacter = w.player
	var c: Colossus = w.colossus
	# Stand next to the neck (fur) and keep grip released until balance is lost.
	await _stand_on_shoulder(w, Vector3(1.25, 0, 0.1))
	c.debug_override = &"shake"
	c._think_left = 0.0
	var lost_at := -1
	var grabbed_at := -1
	for i in 240:
		await _ticks(1)
		if lost_at < 0 and p.balance.state >= Balance.State.STUMBLE:
			lost_at = i
			p.actions.grab_held = true
		if lost_at >= 0 and p.is_climbing():
			grabbed_at = i
			break
	_log.append("lost balance after %.2f s, saved by grab after %d ticks on %s" % [lost_at * DT, grabbed_at - lost_at, p.grip.body.name if p.grip else "-"])
	_metric("shake_full_balance_loss_s", lost_at * DT)
	_metric("rescue_grab_ticks", grabbed_at - lost_at, "lower")
	_check(lost_at >= 0, "never lost balance")
	_check(grabbed_at >= 0, "could not grab while slipping")
	_check(p.grip != null and c.owns_body(p.grip.body), "rescue grab did not hold onto the colossus")
	await _ticks(60)
	_check(p.is_climbing(), "rescue grip did not hold during the shake")


func test_severe_shake_can_throw_ungripped_player() -> void:
	var w := await _setup(&"frozen")
	var p: PlayerCharacter = w.player
	var c: Colossus = w.colossus
	await _stand_on_shoulder(w, Vector3(1.9, 0, 0))
	var y0 := p.global_position.y
	var chest := _segment(c, &"chest")
	c.debug_override = &"shake"
	c._think_left = 0.0
	var fallen_at := -1
	var off_at := -1
	for i in 60 * 6:
		await _ticks(1)
		if fallen_at < 0 and p.balance.state == Balance.State.FALLEN:
			fallen_at = i
		# Off the shoulders and dropped (may land on an arm, a leg or the ground).
		if off_at < 0 and p.get_support_body() != chest and p.global_position.y < y0 - 3.0:
			off_at = i
	for i in 120:
		await _ticks(1)
	_log.append("knocked down after %.2f s, thrown off after %.2f s, impact %.1f m/s (%s), health %.0f" % [fallen_at * DT, off_at * DT, p.last_impact_speed, FallImpact.Tier.keys()[p.last_impact_tier], p.health])
	_metric("shake_full_thrown_off_s", off_at * DT)
	_check(fallen_at >= 0, "full shake never knocked the standing player down")
	_check(off_at >= 0, "full shake never threw the ungripped player off")
	_check(p.last_impact_tier != FallImpact.Tier.NONE or p.get_support_body() is BodySegment, "being thrown off had no landing consequence")


## Same as above, but with the real brain and fairness rules (shake <= 3 s, then cooldown):
## a player who just stands on the shoulders and ignores the shaking must still get thrown.
func test_brain_shake_throws_idle_standing_player() -> void:
	var w := await _setup(&"frozen")
	var p: PlayerCharacter = w.player
	var c: Colossus = w.colossus
	await _stand_on_shoulder(w, Vector3(1.9, 0, 0))
	var y0 := p.global_position.y
	var chest := _segment(c, &"chest")
	c.debug_override = &""
	c._think_left = 0.0
	var first_shake := -1
	var off_at := -1
	for i in 60 * 15:
		await _ticks(1)
		if first_shake < 0 and c.intent.kind == ColossusIntent.SHAKE_PLAYER:
			first_shake = i
		if p.get_support_body() != chest and p.global_position.y < y0 - 3.0:
			off_at = i
			break
	_log.append("brain: first shake at %.1f s, idle player thrown off at %.1f s" % [first_shake * DT, off_at * DT])
	_metric("brain_idle_player_thrown_s", off_at * DT)
	_check(first_shake >= 0, "brain never shook the standing player")
	_check(off_at >= 0, "a standing player who does nothing survives the brain's shakes")


func test_gripping_player_resists_shake_using_stamina() -> void:
	var w := await _setup(&"frozen")
	var p: PlayerCharacter = w.player
	var c: Colossus = w.colossus
	await _ticks(10)
	await _grab_back_patch(w)
	c.debug_override = &"shake"
	c._think_left = 0.0
	var st0 := p.stamina.value
	var held := true
	for i in 150:
		await _ticks(1)
		held = held and p.is_climbing()
	_log.append("2.5 s full shake: still gripping %s, stamina %.0f -> %.0f" % [held, st0, p.stamina.value])
	_metric("shake_full_grip_stamina_cost", st0 - p.stamina.value)
	_check(held, "gripping player was thrown off with stamina left")
	_check(st0 - p.stamina.value > 25.0, "shake cost too little stamina (%.0f)" % (st0 - p.stamina.value))


func test_small_fall_is_safe() -> void:
	var r := await _drop_from(1.5)
	_check(r.tier == FallImpact.Tier.NONE and r.damage == 0.0, "1.5 m fall had consequences: %s" % str(r))
	_check(not r.knocked, "1.5 m fall knocked the player down")


func test_medium_fall_has_consequence() -> void:
	var r := await _drop_from(5.0)
	_check(r.tier == FallImpact.Tier.HARD, "5 m fall tier %s" % FallImpact.Tier.keys()[r.tier])
	_check(r.damage > 5.0 and r.damage < 50.0, "5 m fall damage %.1f not moderate" % r.damage)
	_check(not r.knocked and r.min_balance < 0.6, "5 m fall should stagger, not knock down")


func test_large_fall_triggers_fall_consequence() -> void:
	var r := await _drop_from(12.0)
	_check(r.tier == FallImpact.Tier.SEVERE, "12 m fall tier %s" % FallImpact.Tier.keys()[r.tier])
	_check(r.damage >= 50.0, "12 m fall damage only %.1f" % r.damage)
	_check(r.knocked, "12 m fall did not knock the player down")
	_check(not r.dead, "12 m fall should hurt badly, not kill")
	_check(r.got_up, "player never got up after the fall")


func test_lethal_fall_respawns() -> void:
	var r := await _drop_from(18.0)
	_check(r.dead, "18 m fall was survivable (damage %.1f)" % r.damage)
	_check(r.respawned, "dead player did not respawn")


func _drop_from(height: float) -> Dictionary:
	var w := await _setup(&"frozen")
	var p: PlayerCharacter = w.player
	p.global_position = Vector3(30, 0.9 + height, 30)
	p.velocity = Vector3.ZERO
	await _ticks(2)
	var r := {"tier": -1, "damage": 0.0, "speed": 0.0, "knocked": false, "min_balance": 1.0, "dead": false, "got_up": false, "respawned": false}
	p.landed.connect(func(speed: float, tier: int, dmg: float) -> void:
		if r.tier == -1:
			r.tier = tier
			r.damage = dmg
			r.speed = speed)
	var died := [false]
	p.died.connect(func() -> void: died[0] = true)
	for i in 60 * 6:
		await _ticks(1)
		if r.tier != -1:
			r.min_balance = minf(r.min_balance, p.balance.value)
			r.knocked = r.knocked or p.balance.state == Balance.State.FALLEN
			if r.knocked and p.balance.state != Balance.State.FALLEN and not p.dead:
				r.got_up = true
		r.dead = r.dead or died[0]
		if died[0] and not p.dead:
			r.respawned = true
			break
		if r.tier != -1 and i > 60 * 3 and not died[0]:
			break
	_metric("fall_%dm_damage" % int(height), r.damage)
	_log.append("drop %.1f m: impact %.1f m/s, tier %s, damage %.1f, min balance %.2f, knocked %s, dead %s" % [height, r.speed, FallImpact.Tier.keys()[maxi(r.tier, 0)], r.damage, r.min_balance, r.knocked, r.dead])
	return r


func test_late_grab_catches_falling_player() -> void:
	var w := await _setup(&"frozen")
	var p: PlayerCharacter = w.player
	await _ticks(10)
	await _grab_behind(w, &"thigh_l", -2.6)
	_check(p.is_climbing(), "no grip")
	var y0 := p.global_position.y
	p.actions.grab_held = false
	await _ticks(1)
	_check(not p.is_climbing(), "did not let go")
	# Fall along the leg, grab again just before reaching the ground.
	while p.global_position.y > 2.2 and p.state == PlayerCharacter.State.AIR:
		await _ticks(1)
	var vy := p.velocity.y
	p.actions.grab_held = true
	await _ticks(3)
	_log.append("falling at %.1f m/s; let go at %.1f m, caught at %.1f m on %s" % [vy, y0, p.global_position.y, p.grip.body.name if p.grip else "-"])
	_metric("late_grab_caught_height_m", p.global_position.y)
	_check(p.is_climbing(), "late grab did not catch the falling player")


func test_grip_transfer_while_colossus_turns() -> void:
	var w := await _setup(&"turn")
	var p: PlayerCharacter = w.player
	var c: Colossus = w.colossus
	await _ticks(120)
	await _grab_behind(w, &"shin_l", -1.8)
	_check(p.is_climbing(), "no grip")
	p.actions.move = Vector2(0, 1)
	var visited: Array[StringName] = []
	var dropped := false
	var max_err := 0.0
	for i in 60 * 6:
		_aim_view_at(p, c)
		await _ticks(1)
		if not p.is_climbing():
			dropped = p.last_release_reason != &""
			break
		max_err = maxf(max_err, _surface_error(p))
		var bone: StringName = (p.grip.body as BodySegment).bone_name
		if visited.is_empty() or visited[-1] != bone:
			visited.append(bone)
	p.actions.move = Vector2.ZERO
	_log.append("turning colossus route: %s, max surface err %.3f" % [" -> ".join(visited), max_err])
	_metric("turn_transfer_surface_err_m", max_err, "lower")
	_check(not dropped, "dropped during segment transfer on a turning colossus (%s)" % p.last_release_reason)
	_check(&"thigh_l" in visited and &"hips" in visited, "did not transfer leg -> hip")
	_check(max_err < 0.08, "anchor left the surface during transfer")


func test_camera_does_not_clip_into_colossus() -> void:
	var w := await _setup(&"walk")
	var p: PlayerCharacter = w.player
	var c: Colossus = w.colossus
	var cam := PlayerCamera.new()
	cam.player = p
	cam.focus_target = c
	_world.add_child(cam)
	await _ticks(10)
	await _grab_behind(w, &"shin_l", -1.8)
	cam.snap_behind_player()
	var space := p.get_world_3d().direct_space_state
	var probe := SphereShape3D.new()
	probe.radius = 0.12  # ~ near plane footprint
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = probe
	q.collision_mask = Layers.COLOSSUS
	var inside := 0
	var frames := 0
	var min_dist := 99.0
	var occlusion_clamps := 0
	p.actions.move = Vector2(0, 1)
	for i in 60 * 14:
		# A player who keeps spinning the camera around, through the body.
		p.actions.look_delta += Vector2(0.045, 0.02 * sin(i * 0.05))
		_aim_view_at(p, c)
		if i == 60 * 8:
			c.debug_override = &"shake"
			c._think_left = 0.0
		await _ticks(1)
		q.transform = Transform3D(Basis.IDENTITY, cam.global_position)
		frames += 1
		if not space.intersect_shape(q, 1).is_empty():
			inside += 1
			if OS.get_environment("TRACE") != "":
				_log.append("inside at %d: dist %.2f clamp '%s' state %s pivot-in %s" % [i, cam.get_distance(), cam.last_clamp, p.get_display_state(), str(cam._inside(space, cam._pivot, Layers.COLOSSUS, 0.15))])
		min_dist = minf(min_dist, cam.get_distance())
		if cam.last_clamp.begins_with("colossus"):
			occlusion_clamps += 1
	_log.append("camera frames %d, inside colossus %d, min distance %.2f, colossus clamps %d, player %s" % [frames, inside, min_dist, occlusion_clamps, p.get_display_state()])
	_metric("camera_inside_colossus_frames", inside, "lower")
	_check(inside == 0, "camera was inside the colossus in %d frames" % inside)
	_check(occlusion_clamps > 0, "test never put the colossus between camera and player")


## Standing right under the colossus and holding focus: the camera must stay at a usable
## distance and show both the player and the colossus (not end up behind the player's head).
func test_camera_focus_frames_player_and_colossus() -> void:
	var w := await _setup(&"frozen")
	var p: PlayerCharacter = w.player
	var c: Colossus = w.colossus
	var cam := PlayerCamera.new()
	cam.player = p
	cam.focus_target = c
	_world.add_child(cam)
	p.global_position = c.global_position + c.global_basis.z * 6.0 + Vector3(0, 0.95, 0)
	p.facing = -c.global_basis.z
	cam.snap_behind_player()
	await _ticks(30)
	p.actions.focus_held = true
	await _ticks(120)
	var player_visible := cam.is_position_in_frustum(p.global_position)
	var colossus_visible := cam.is_position_in_frustum(c.get_focus_point())
	_log.append("focus under the colossus: distance %.1f m, pitch %.2f, player in view %s, colossus in view %s" % [cam.get_distance(), cam.pitch, player_visible, colossus_visible])
	_check(cam.get_distance() > 3.0, "camera collapsed to %.1f m while focusing" % cam.get_distance())
	_check(player_visible and colossus_visible, "focus does not frame both player and colossus")


func test_bone_local_grip_still_has_no_drift() -> void:
	var w := await _setup(&"walk")
	var p: PlayerCharacter = w.player
	var c: Colossus = w.colossus
	await _ticks(120)
	await _grab_back_patch(w)
	_check(p.is_climbing(), "no grip")
	var start_local := p.grip.local_point
	var start_body := p.grip.body
	c.debug_override = &"shake"
	c._think_left = 0.0
	var max_err := 0.0
	var max_speed := 0.0
	for i in 150:
		await _ticks(1)
		if not p.is_climbing():
			break
		max_err = maxf(max_err, _surface_error(p))
		max_speed = maxf(max_speed, p.surface_velocity.length())
	var drift := p.grip.local_point.distance_to(start_local) if p.grip and p.grip.body == start_body else 99.0
	_log.append("walk+shake 2.5 s: drift %.5f m, max surface err %.4f, surface speed up to %.1f m/s, stamina %.0f" % [drift, max_err, max_speed, p.stamina.value])
	_metric("grip_drift_walk_shake_m", drift, "lower")
	_metric("grip_surface_speed_walk_shake_mps", max_speed)
	_check(p.is_climbing(), "lost grip")
	_check(drift < 0.01, "grip drifted %.4f m in bone space" % drift)
	_check(max_err < 0.08, "anchor left the collider surface")


## Not a pass/fail test: prints what a standing player feels in each colossus mode.
## Run with --only=probe when re-tuning Balance.
func probe_balance_disturbance() -> void:
	if OS.get_environment("PROBE") == "":
		return
	for mode in [&"frozen", &"walk", &"turn", &"shake_half", &"shake"]:
		var w := await _setup(&"shake" if String(mode).begins_with("shake") else mode)
		var c: Colossus = w.colossus
		c.debug_shake_strength = 0.5 if mode == &"shake_half" else 1.0
		var p: PlayerCharacter = w.player
		p.balance.capacity = 1000.0  # measure only
		await _stand_on_shoulder(w, Vector3(1.9, 0, 0))
		var mx := 0.0
		var avg := 0.0
		var acc := 0.0
		for i in 180:
			await _ticks(1)
			mx = maxf(mx, p.balance.disturbance)
			avg += p.balance.disturbance / 180.0
			acc = maxf(acc, p.surface_accel.length())
		_log.append("%s: disturbance avg %.1f max %.1f, |a| max %.1f, |w| %.2f, on body %s" % [mode, avg, mx, acc, p.surface_angular_velocity.length(), c.owns_body(p.get_support_body())])
		await _teardown()


# --- helpers --------------------------------------------------------------------------

func _setup(mode: StringName, with_wall := false) -> Dictionary:
	_world = Node3D.new()
	_world.name = "World_" + _current
	add_child(_world)
	var ground := StaticBody3D.new()
	ground.collision_layer = Layers.WORLD
	var gs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 2, 400)
	gs.shape = box
	gs.position = Vector3(0, -1, 0)
	ground.add_child(gs)
	_world.add_child(ground)
	if with_wall:
		var wall := StaticBody3D.new()
		wall.collision_layer = Layers.WORLD
		wall.position = Vector3(40, 3.5, 0)
		var ws := CollisionShape3D.new()
		var wb := BoxShape3D.new()
		wb.size = Vector3(10, 7, 2)
		ws.shape = wb
		wall.add_child(ws)
		var vines := ClimbPatch.new()
		var vb := BoxShape3D.new()
		vb.size = Vector3(4, 6.6, 0.3)
		vines.shape = vb
		vines.position = Vector3(0, -0.2, 1.1)
		wall.add_child(vines)
		_world.add_child(wall)
	var c := GreyboxHumanoid.new()
	c.name = "Colossus"
	c.debug_override = mode
	_world.add_child(c)
	var p := PlayerCharacter.new()
	p.name = "Player1"
	_world.add_child(p)
	p.global_position = Vector3(0, 0.95, 20)
	return {"colossus": c, "player": p}


func _teardown() -> void:
	if _world:
		_world.queue_free()
		_world = null
	await _ticks(2)


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## Records a regression metric (compared against the frozen baseline at the end of the run).
func _metric(key: String, value: float, better := "info") -> void:
	_metrics[key] = {"value": value, "better": better, "test": _current}


func _report_metrics(save: bool) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	var f := FileAccess.open("res://tests/output/metrics.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(_metrics, "  ", true))
	f.close()
	if save:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/baseline"))
		var b := FileAccess.open(BASELINE_PATH, FileAccess.WRITE)
		b.store_string(JSON.stringify(_metrics, "  ", true))
		b.close()
		print("\nbaseline saved to %s (%d metrics)" % [BASELINE_PATH, _metrics.size()])
		return
	if not FileAccess.file_exists(BASELINE_PATH):
		return
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASELINE_PATH))
	print("\n--- regression metrics vs frozen baseline (%s) ---" % BASELINE_PATH)
	var keys := _metrics.keys()
	keys.sort()
	var flagged := 0
	for k in keys:
		var cur: float = _metrics[k].value
		var better: String = _metrics[k].better
		if not base.has(k):
			print("  %-44s %10.4f   (new)" % [k, cur])
			continue
		var old: float = base[k].value
		var mark := ""
		# Generous tolerance: these are smoke alarms, the tests hold the hard limits.
		if better == "lower" and cur > old * 1.5 + 0.02:
			mark = "  <-- WORSE"
		elif better == "higher" and cur < old * 0.67 - 0.02:
			mark = "  <-- WORSE"
		if mark != "":
			flagged += 1
		print("  %-44s %10.4f   baseline %10.4f%s" % [k, cur, old, mark])
	print("  %d metric(s) flagged" % flagged)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append("%s: %s" % [_current, msg])


func _segment(c: Colossus, bone: StringName) -> BodySegment:
	for s in c.segments:
		if s.bone_name == bone:
			return s
	return null


## Puts the player right behind a limb segment (colossus back side) and holds grip.
func _grab_behind(w: Dictionary, bone: StringName, along: float) -> void:
	var c: Colossus = w.colossus
	var p: PlayerCharacter = w.player
	var seg := _segment(c, bone)
	var back := c.global_basis.z
	var target := seg.global_transform * Vector3(0, along, 0) + back * 1.45
	p.global_position = target
	p.velocity = Vector3.ZERO
	p.facing = -back
	p.actions.view_basis = Basis.looking_at(-back)
	p.actions.grab_held = true
	p.reset_physics_interpolation()
	await _ticks(3)


func _grab_back_patch(w: Dictionary) -> void:
	var c: Colossus = w.colossus
	var p: PlayerCharacter = w.player
	var seg := _segment(c, &"chest")
	var back := c.global_basis.z
	p.global_position = seg.global_transform * Vector3(0, 1.0, 2.3)
	p.velocity = Vector3.ZERO
	p.facing = -back
	p.actions.view_basis = Basis.looking_at(-back)
	p.actions.grab_held = true
	await _ticks(3)


## Drops the player onto the top of the chest ("shoulders"), chest-local offset from centre.
func _stand_on_shoulder(w: Dictionary, local_offset: Vector3) -> void:
	var c: Colossus = w.colossus
	var p: PlayerCharacter = w.player
	await _ticks(2)
	var seg := _segment(c, &"chest")
	p.global_position = seg.global_transform * (Vector3(0, 2.8 + 1.0, 0) + local_offset)
	p.velocity = Vector3.ZERO
	p.facing = -c.global_basis.z
	p.actions.view_basis = Basis.looking_at(-c.global_basis.z)
	p.reset_physics_interpolation()
	await _ticks(20)


## Keeps the "camera" behind the player looking at the colossus, like a human would.
func _aim_view_at(p: PlayerCharacter, c: Colossus) -> void:
	var d := PlayerCharacter._flat_dir(c.global_position - p.global_position, Vector3.FORWARD)
	p.actions.view_basis = Basis.looking_at(d)


## Distance between the anchor and the actual collider surface, measured independently.
func _surface_error(p: PlayerCharacter) -> float:
	var pt := p.grip.query_point()
	var n := p.grip.query_normal()
	var hit := ClimbQuery.ray(p.get_world_3d().direct_space_state, pt + n * 0.5, pt - n * 0.5, [p.get_rid()])
	if hit.is_empty():
		return 1.0
	return (hit.position as Vector3).distance_to(pt)
