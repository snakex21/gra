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
## Pass/fail of every pre-Etap-4 test that ran (checked by existing_colossus_tests_still_pass).
var _legacy_results := {}
## Pass/fail of every test that ran before the Etap 5 (boss) tests.
var _pre_boss_results := {}
var _boss_started := false
## Results of every test before the Etap 6 ones (Valus is the regression boss).
var _pre_etap6_results := {}
var _etap6_started := false
var _pre_etap7_results := {}
var _etap7_started := false
var _pre_etap8_results := {}
var _etap8_started := false
const BASELINE_PATH := "res://tests/baseline/etap2_baseline.json"
## Agro metrics (horse_*) are frozen separately, so the stage 2/3 baseline stays untouched.
const HORSE_BASELINE_PATH := "res://tests/baseline/etap4_horse_baseline.json"
var _save_horse_baseline := false


func _ready() -> void:
	InputSetup.ensure_defaults()
	var only := ""
	var save_baseline := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
		elif arg == "--save-baseline":
			save_baseline = true
		elif arg == "--save-horse-baseline":
			_save_horse_baseline = true
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
		# --- ETAP 3 ---
		test_planted_foot_does_not_slide,
		test_walking_on_slope_places_feet_correctly,
		test_turning_uses_stable_steps,
		test_start_and_stop_are_smooth,
		test_walk_shake_walk_transition,
		test_pelvis_tracks_support_area,
		test_grip_does_not_drift_during_procedural_step,
		test_standing_player_remains_attached_during_step,
		test_standing_on_shoulder_during_start_stop,
		test_player_on_leg_survives_step_transition,
		test_grip_on_hips_during_turn,
		test_grip_on_back_during_sudden_direction_change,
		test_shake_behavior_unchanged_after_locomotion,
		test_locomotion_is_independent_of_render_fps,
		test_locomotion_cost_stays_within_reasonable_budget,
		ab_locomotion_comparison,
		probe_balance_disturbance,
		# --- ETAP 4: Agro ---
		test_horse_acceleration_is_smooth,
		test_horse_braking_is_smooth,
		test_horse_cannot_instant_turn_at_speed,
		test_horse_turn_radius_increases_with_speed,
		test_horse_feet_do_not_slide,
		test_horse_feet_follow_uneven_terrain,
		test_horse_body_lean_is_continuous,
		test_mounted_player_has_no_saddle_drift,
		test_mount_and_dismount_are_stable,
		test_dismount_refused_without_space,
		test_horse_avoids_small_obstacle,
		test_horse_keeps_heading_after_avoiding,
		test_horse_threads_narrow_passage,
		test_horse_steps_over_low_obstacle,
		test_horse_stops_before_large_obstacle,
		test_horse_stops_at_cliff_edge,
		test_horse_simulation_independent_of_render_fps,
		test_horse_camera_can_look_away_from_travel_direction,
		test_horse_comes_when_called,
		test_horse_follows_player,
		test_horse_cost_stays_within_budget,
		existing_colossus_tests_still_pass,
		# --- ETAP 5: Valus ---
		test_boss_enters_combat_when_player_enters_arena,
		test_boss_attack_has_telegraph,
		test_boss_attack_active_window_is_correct,
		test_boss_attack_has_recovery,
		test_boss_attack_can_damage_player,
		test_boss_cannot_spam_heavy_attack,
		test_boss_cannot_spam_shake,
		test_climb_route_is_reachable,
		test_weakpoint_moves_with_bone,
		test_weakpoint_rejects_invalid_hits,
		test_weakpoint_accepts_valid_sword_hit,
		test_weakpoint_damage_advances_progress,
		test_rest_surface_restores_stamina,
		test_boss_reacts_to_player_on_body,
		test_player_can_fall_and_reenter_climb_route,
		test_agro_avoids_colossus_legs,
		test_agro_reacts_to_stomp_danger,
		test_player_death_resets_encounter,
		test_boss_can_be_defeated,
		test_boss_stops_attacking_after_defeat,
		test_grip_survives_defeat_sequence,
		test_scripted_driver_can_complete_boss,
		test_boss_simulation_independent_of_render_fps,
		test_boss_cost_stays_within_budget,
		all_existing_tests_still_pass,
		# --- ETAP 6: Quadratus, bow ---
		test_quadratus_four_leg_locomotion_is_stable,
		test_quadratus_feet_do_not_slide,
		test_quadratus_handles_uneven_ground,
		test_quadratus_weight_shifts_between_legs,
		test_quadratus_foot_target_can_be_hit_with_arrow,
		test_quadratus_reacts_to_correct_foot_hit,
		test_quadratus_body_lowers_after_foot_hit,
		test_quadratus_climb_route_becomes_reachable,
		test_quadratus_grip_has_no_drift,
		test_quadratus_weakpoint_moves_with_body,
		test_quadratus_body_reaction_is_fair,
		test_quadratus_can_be_defeated,
		test_quadratus_scripted_driver_can_complete_fight,
		test_quadratus_simulation_independent_of_render_fps,
		test_quadratus_cost_stays_within_budget,
		test_valus_defeat_leaves_a_safe_way_down,
		test_bow_draw_strength_changes_arrow_velocity,
		test_bow_trajectory_is_repeatable,
		test_arrow_hits_expected_target,
		test_arrow_misses_when_aim_is_wrong,
		test_bow_is_independent_of_render_fps,
		test_player_can_aim_from_agro,
		test_horse_heading_is_not_changed_by_aim,
		test_arrow_hit_can_trigger_colossus_reaction,
		all_valus_and_earlier_tests_still_pass,
		# --- ETAP 7: Gaius, art, Quadratus loop, bow polish ---
		test_gaius_sword_follows_the_arm,
		test_gaius_slam_has_telegraph_and_stuck_window,
		test_gaius_slam_point_locks_for_a_late_dodge,
		test_gaius_blade_is_a_walkable_ramp,
		test_gaius_climb_route_blade_to_shoulders,
		test_gaius_grip_on_sword_arm_has_no_drift,
		test_gaius_helmet_breaks_after_charged_strikes,
		test_armor_plate_rejects_invalid_hits,
		test_gaius_can_be_defeated,
		test_gaius_scripted_driver_can_complete_fight,
		test_gaius_simulation_independent_of_render_fps,
		test_gaius_cost_stays_within_budget,
		test_attacks_respect_cooldowns_all_bosses,
		test_art_layer_does_not_change_gameplay,
		test_quadratus_lurch_unsettles_standing_player_fairly,
		test_quadratus_crown_needs_second_kneel,
		test_bow_aim_zooms_camera_over_shoulder,
		test_arrow_glances_off_stone,
		all_etap6_and_earlier_tests_still_pass,
		# --- ETAP 8: the valley, the beam, the whole game ---
		test_game_state_save_load_roundtrip,
		test_sword_beam_gathers_towards_target,
		test_sword_beam_works_from_agro,
		test_valley_ground_world_edge_and_closed_gates,
		test_open_gate_leads_to_next_colossus,
		test_leaving_arena_returns_to_its_gate,
		test_defeat_returns_to_temple_and_saves,
		test_no_mounting_while_knocked_down,
		test_game_bot_finds_way_with_beam,
		test_valley_simulation_independent_of_render_fps,
		test_valley_cost_stays_within_budget,
		test_gaius_head_phase_is_fair_and_smooth,
		test_sentinel_v2_dresses_valus,
		all_etap7_and_earlier_tests_still_pass,
	]
	for t in tests:
		var name := t.get_method()
		if only != "" and not Array(only.split(",")).any(func(o: String) -> bool: return name.contains(o)):
			continue
		_current = name
		var fails_before := _failures.size()
		var t0 := Time.get_ticks_msec()
		await t.call()
		await _teardown()
		var ok := _failures.size() == fails_before
		if not name.contains("horse") and not name.contains("mount") and name != "existing_colossus_tests_still_pass" and not _boss_started:
			_legacy_results[name] = ok
		if name == "test_boss_enters_combat_when_player_enters_arena":
			_boss_started = true
		if not _boss_started:
			_pre_boss_results[name] = ok
		if name == "test_quadratus_four_leg_locomotion_is_stable":
			_etap6_started = true
		if not _etap6_started:
			_pre_etap6_results[name] = ok
		if name == "test_gaius_sword_follows_the_arm":
			_etap7_started = true
		if not _etap7_started:
			_pre_etap7_results[name] = ok
		if name == "test_game_state_save_load_roundtrip":
			_etap8_started = true
		if not _etap8_started:
			_pre_etap8_results[name] = ok
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
	# Grab while the foot is planted; then hold on through the following steps (swings).
	await _wait_planted(w.colossus, 0)
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
		if OS.get_environment("TRACE") != "" and i % 60 == 0:
			_log.append("t=%d y=%.1f (y0 %.1f) st=%s sup=%s intent=%s" % [i / 60, p.global_position.y, y0, p.get_display_state(), (p.get_support_body() as Node).name if p.get_support_body() else "-", c.intent.kind])
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


# --- ETAP 3: locomotion, foot planting, IK, balance of the body ----------------------

func test_planted_foot_does_not_slide() -> void:
	var w := await _setup(&"frozen")
	var c: GreyboxHumanoid = w.colossus
	var t := _tracker(c)
	_drive(c, 1.4, 0.0)
	await _run_tracked(t, 60 * 6)
	_drive(c, 1.4, 0.2)
	await _run_tracked(t, 60 * 4)
	c.reset_foot_stats()
	_drive(c, 1.6, -0.15)
	await _run_tracked(t, 60 * 6)
	var st := c.foot_stats
	var avg: float = st.slip_sum / maxf(1.0, st.contact_ticks)
	_log.append("steps %d, stance slip max %.4f m/s avg %.4f m/s, IK reach error max %.3f m, speed %.2f" % [c.loco.step_count, st.slip_max, avg, st.reach_max, c.loco.speed])
	_metric("loco_slip_max_mps", st.slip_max, "lower")
	_metric("loco_reach_err_max_m", st.reach_max, "lower")
	_check(c.loco.step_count >= 8, "too few steps (%d)" % c.loco.step_count)
	_check(st.slip_max < 0.02, "planted feet slide (%.3f m/s)" % st.slip_max)
	_check(st.reach_max < 0.05, "IK could not reach the planned feet (%.3f m)" % st.reach_max)


func test_walking_on_slope_places_feet_correctly() -> void:
	var w := await _setup(&"frozen", false, true)
	var c: GreyboxHumanoid = w.colossus
	var t := _tracker(c)
	_drive(c, 1.4, 0.0)
	var y0 := c.global_position.y
	var max_h_err := 0.0
	var min_n_dot := 1.0
	var checked := 0
	var max_y := y0
	for i in 60 * 34:
		await _ticks(1)
		t.step(DT)
		max_y = maxf(max_y, c.global_position.y)
		if not t.touchdowns.is_empty() and t.touchdowns[-1][1] == t.ticks - 1:
			var leg: int = t.touchdowns[-1][0]
			var sole := c.sole_world(leg)
			var g := _ground_at(sole)
			if g.is_empty():
				continue
			checked += 1
			max_h_err = maxf(max_h_err, absf(sole.y - (g.position as Vector3).y))
			min_n_dot = minf(min_n_dot, c.loco.legs[leg].foot_normal.dot(g.normal))
	var st := c.foot_stats
	_log.append("course: %d touchdowns checked, max sole height error %.3f m, min normal match %.3f, rose %.2f m (max), slip max %.4f m/s, reach err %.3f, max shoulder accel %.1f m/s2" % [checked, max_h_err, min_n_dot, max_y - y0, st.slip_max, st.reach_max, t.max_shoulder_accel])
	_metric("slope_sole_height_err_m", max_h_err, "lower")
	_metric("slope_shoulder_accel_max", t.max_shoulder_accel, "lower")
	_check(checked >= 10, "too few touchdowns checked (%d)" % checked)
	_check(max_y - y0 > 3.0, "colossus did not climb the ramp (%.2f m)" % (max_y - y0))
	_check(max_h_err < 0.06, "feet not placed on the terrain (%.3f m off)" % max_h_err)
	_check(min_n_dot > 0.97, "feet not aligned to the ground normal (%.3f)" % min_n_dot)
	_check(st.slip_max < 0.02, "feet slide on uneven terrain (%.3f m/s)" % st.slip_max)
	_check(st.reach_max < 0.08, "IK could not reach terrain (%.3f m)" % st.reach_max)


func test_turning_uses_stable_steps() -> void:
	var w := await _setup(&"frozen")
	var c: GreyboxHumanoid = w.colossus
	var t := _tracker(c)
	var yaw0 := c.loco.yaw
	_drive(c, 0.0, 0.3)
	await _run_tracked(t, 60 * 9)
	var turned := absf(angle_difference(yaw0, c.loco.yaw))
	var st := c.foot_stats
	var left_steps := 0
	for td in t.touchdowns:
		if td[0] == 0:
			left_steps += 1
	_log.append("turn on the spot: turned %.2f rad, %d steps (%d left), max swinging %d, slip max %.4f m/s, yaw accel max %.3f rad/s2" % [turned, t.touchdowns.size(), left_steps, t.max_swinging, st.slip_max, t.max_yaw_accel])
	_check(turned > 1.5, "did not turn (%.2f rad)" % turned)
	_check(t.touchdowns.size() >= 4, "turning without stepping (%d steps): turntable" % t.touchdowns.size())
	_check(left_steps >= 1 and left_steps < t.touchdowns.size(), "only one leg stepped")
	_check(t.max_swinging <= 1, "both feet in the air at once")
	_check(st.slip_max < 0.02, "planted feet slide while turning (%.3f m/s)" % st.slip_max)
	_check(t.max_yaw_accel <= c.loco.max_turn_accel + 0.01, "turn rate changes abruptly")


func test_start_and_stop_are_smooth() -> void:
	var w := await _setup(&"frozen")
	var c: GreyboxHumanoid = w.colossus
	var t := _tracker(c)
	await _run_tracked(t, 60 * 2)              # idle
	_drive(c, 1.4, 0.0)
	await _run_tracked(t, 60 * 7)              # idle -> walk
	_drive(c, 2.2, 0.0)
	await _run_tracked(t, 60 * 5)              # walk -> faster walk
	_drive(c, 0.7, 0.3)
	await _run_tracked(t, 60 * 5)              # walk forward -> turn
	_drive(c, 1.4, 0.0)
	await _run_tracked(t, 60 * 5)              # turn -> walk
	_drive(c, 0.0, 0.0)
	await _run_tracked(t, 60 * 6)              # walk -> stop
	var steps_at_rest := c.loco.step_count
	await _run_tracked(t, 60 * 3)
	var st := c.foot_stats
	_log.append("max |accel| %.2f m/s2, max |jerk| %.2f m/s3, max shoulder accel %.2f m/s2, slip max %.4f m/s, steps %d (+%d after stopping), final speed %.3f" % [t.max_accel, t.max_jerk, t.max_shoulder_accel, st.slip_max, c.loco.step_count, c.loco.step_count - steps_at_rest, c.loco.speed])
	_metric("startstop_shoulder_accel_max", t.max_shoulder_accel, "lower")
	_check(t.max_accel <= c.loco.max_decel + 0.05, "speed changes faster than the body's mass allows")
	_check(t.max_jerk <= c.loco.max_jerk + 0.2, "acceleration changes abruptly (jerk %.2f)" % t.max_jerk)
	_check(t.max_shoulder_accel < 6.0, "shoulders jolt during start/stop/turn (%.1f m/s2)" % t.max_shoulder_accel)
	_check(st.slip_max < 0.02, "feet slide (%.3f m/s)" % st.slip_max)
	_check(c.loco.speed < 0.01, "did not stop")
	_check(c.loco.step_count == steps_at_rest, "keeps stepping in place after stopping")


func test_walk_shake_walk_transition() -> void:
	var w := await _setup(&"walk")
	var c: GreyboxHumanoid = w.colossus
	var t := _tracker(c)
	await _run_tracked(t, 60 * 5)
	var walking_speed := c.loco.speed
	c.debug_override = &"shake"
	c._think_left = 0.0
	await _run_tracked(t, 60 * 2)
	var steps_in_shake := c.loco.step_count
	await _run_tracked(t, 60 * 2)
	var speed_in_shake := c.loco.speed
	steps_in_shake = c.loco.step_count - steps_in_shake
	c.debug_override = &"walk"
	c._think_left = 0.0
	await _run_tracked(t, 60 * 6)
	_log.append("walk %.2f m/s -> shake %.2f m/s (%d steps during the last 2 s of shaking) -> walk %.2f m/s, max |accel| %.2f, slip max %.4f" % [walking_speed, speed_in_shake, steps_in_shake, c.loco.speed, t.max_accel, c.foot_stats.slip_max])
	_check(walking_speed > 1.0 and c.loco.speed > 1.0, "did not walk before/after the shake")
	_check(speed_in_shake < 0.1, "kept walking while shaking")
	_check(steps_in_shake <= 1, "feet kept stepping while braced for a shake")
	_check(t.max_accel <= c.loco.max_decel + 0.05, "abrupt speed change around the shake")
	_check(c.foot_stats.slip_max < 0.02, "feet slide during the shake")


func test_pelvis_tracks_support_area() -> void:
	var w := await _setup(&"frozen")
	var c: GreyboxHumanoid = w.colossus
	_drive(c, 1.4, 0.0)
	await _ticks(60 * 4)
	var side_sum := [0.0, 0.0]
	var side_n := [0, 0]
	var max_com_dist := 0.0
	var lift_loads := []
	var prev_phase := [LegState.Phase.STANCE, LegState.Phase.STANCE]
	for k in 60 * 10:
		await _ticks(1)
		var b := c.loco.body_basis()
		var lateral := (c.loco.pelvis - c.loco.position).dot(b.x)
		for i in 2:
			var leg := c.loco.legs[i]
			if leg.phase == LegState.Phase.SWING and prev_phase[i] == LegState.Phase.STANCE:
				lift_loads.append(leg.load)
			prev_phase[i] = leg.phase
		var swing := c.loco.swinging_count()
		if swing == 1:
			var stance := 0 if c.loco.legs[0].is_planted() else 1
			var side := 1.0 if stance == 0 else -1.0
			side_sum[stance] += lateral * side
			side_n[stance] += 1
		# Dynamic walking: the COM travels between the current support and the next
		# foothold, it is not held over the single stance foot.
		var com_g := Vector3(c.loco.com.x, 0, c.loco.com.z)
		var a: Vector3 = c.loco.legs[0].plant_pos if c.loco.legs[0].is_planted() else c.loco.legs[0].target_pos
		var bb: Vector3 = c.loco.legs[1].plant_pos if c.loco.legs[1].is_planted() else c.loco.legs[1].target_pos
		a.y = 0.0
		bb.y = 0.0
		max_com_dist = maxf(max_com_dist, com_g.distance_to(Geometry3D.get_closest_point_to_segment(com_g, a, bb)))
	var shift_l: float = side_sum[0] / maxf(1, side_n[0])
	var shift_r: float = side_sum[1] / maxf(1, side_n[1])
	var max_lift_load := 0.0
	for l in lift_loads:
		max_lift_load = maxf(max_lift_load, l)
	_log.append("pelvis shift towards stance foot: left %.2f m, right %.2f m; load on a foot when it lifts <= %.2f; COM distance from the support line (current to next foothold) max %.2f m" % [shift_l, shift_r, max_lift_load, max_com_dist])
	_check(shift_l > 0.1 and shift_r > 0.1, "pelvis does not move over the supporting foot")
	_check(max_lift_load < 0.15, "a foot lifts while still carrying weight (%.2f)" % max_lift_load)
	# Regression guard: in this dynamic walk the pelvis moves ~35% of the way over the
	# stance foot, so the COM stays within ~1.3 m of the support line.
	_metric("pelvis_com_support_dist_m", max_com_dist, "lower")
	_check(max_com_dist < 1.5, "centre of mass wanders away from the support line (%.2f m)" % max_com_dist)


func test_grip_does_not_drift_during_procedural_step() -> void:
	var w := await _setup(&"frozen")
	var p: PlayerCharacter = w.player
	var c: GreyboxHumanoid = w.colossus
	await _ticks(10)
	await _grab_behind(w, &"thigh_l", -2.4)
	_check(p.is_climbing(), "no grip")
	var start_local := p.grip.local_point
	_drive(c, 1.4, 0.0)
	var max_err := 0.0
	var max_speed := 0.0
	var swings := 0
	var was_swinging := false
	var max_jump := 0.0
	var prev := p.global_position
	var prev2 := p.global_position
	for i in 60 * 8:
		p.stamina.value = maxf(p.stamina.value, 50.0)  # isolate grip kinematics from stamina
		await _ticks(1)
		if not p.is_climbing():
			break
		var swinging := c.loco.legs[0].phase == LegState.Phase.SWING
		if swinging and not was_swinging:
			swings += 1
		was_swinging = swinging
		max_err = maxf(max_err, _surface_error(p))
		max_speed = maxf(max_speed, p.surface_velocity.length())
		# Teleport = velocity discontinuity: second difference of the position.
		if i > 1:
			max_jump = maxf(max_jump, (p.global_position - 2.0 * prev + prev2).length())
		prev2 = prev
		prev = p.global_position
	var drift := p.grip.local_point.distance_to(start_local) if p.grip else 99.0
	_log.append("thigh through %d swings: drift %.5f m, surface err %.4f, surface speed max %.2f m/s, max position 2nd difference %.4f m" % [swings, drift, max_err, max_speed, max_jump])
	_metric("grip_drift_procedural_step_m", drift, "lower")
	_check(p.is_climbing(), "lost grip (%s)" % p.last_release_reason)
	_check(swings >= 2, "leg did not swing (%d)" % swings)
	_check(drift < 0.01, "grip drifted %.4f m" % drift)
	_check(max_err < 0.08, "anchor left the collider")
	_check(max_jump < 0.01, "teleport while stepping (%.3f m)" % max_jump)


func test_standing_player_remains_attached_during_step() -> void:
	var w := await _setup(&"frozen")
	var p: PlayerCharacter = w.player
	var c: GreyboxHumanoid = w.colossus
	await _ticks(5)
	var foot := _segment(c, &"foot_l")
	# Stand on top of the left foot (the box top is 0.3 m above the ankle).
	p.global_position = foot.global_transform * Vector3(0, 0.35 + 1.0, -2.2)  # on the toes, clear of the shin
	p.velocity = Vector3.ZERO
	await _ticks(30)
	_check(p.get_support_body() == foot, "not standing on the foot")
	_drive(c, 1.0, 0.0)
	var lifted := false
	var landed_with_player := false
	var max_jump := 0.0
	var prev := p.global_position
	var prev2 := p.global_position
	var min_balance := 1.0
	for i in 60 * 6:
		await _ticks(1)
		var leg := c.loco.legs[0]
		if leg.phase == LegState.Phase.SWING and p.get_support_body() == foot:
			lifted = true
		if lifted and leg.is_planted() and p.get_support_body() == foot:
			landed_with_player = true
		if i > 1:
			max_jump = maxf(max_jump, (p.global_position - 2.0 * prev + prev2).length())
		prev2 = prev
		prev = p.global_position
		min_balance = minf(min_balance, p.balance.value)
		if landed_with_player:
			break
	_log.append("rode the foot through its swing: lifted %s, landed still on it %s, min balance %.2f, max jump %.4f m, state %s" % [lifted, landed_with_player, min_balance, max_jump, p.get_display_state()])
	_metric("ride_foot_min_balance", min_balance, "higher")
	_check(lifted, "foot never lifted with the player on it")
	_check(landed_with_player, "player was not carried through the step")
	_check(max_jump < 0.02, "teleport while riding the foot (%.3f m)" % max_jump)


func test_standing_on_shoulder_during_start_stop() -> void:
	var w := await _setup(&"frozen")
	var p: PlayerCharacter = w.player
	var c: GreyboxHumanoid = w.colossus
	await _stand_on_shoulder(w, Vector3(1.9, 0, 0))
	var chest := _segment(c, &"chest")
	var start := chest.global_transform.affine_inverse() * p.global_position
	var min_balance := 1.0
	for phase in [[1.4, 0.0, 6], [2.2, 0.0, 4], [0.0, 0.0, 5], [0.6, 0.3, 4], [0.0, -0.3, 4], [0.0, 0.0, 3]]:
		_drive(c, phase[0], phase[1])
		for i in 60 * int(phase[2]):
			await _ticks(1)
			min_balance = minf(min_balance, p.balance.value)
	var drift := (chest.global_transform.affine_inverse() * p.global_position).distance_to(start)
	_log.append("shoulder through start/fast/stop/turn/stop: min balance %.2f, drift %.3f m, still on chest %s" % [min_balance, drift, p.get_support_body() == chest])
	_metric("shoulder_startstop_min_balance", min_balance, "higher")
	_metric("shoulder_startstop_drift_m", drift, "lower")
	_check(p.get_support_body() == chest, "fell off the shoulder")
	_check(min_balance > 0.7, "start/stop destabilised a standing player (%.2f)" % min_balance)
	_check(drift < 0.3, "player drifted %.2f m on the shoulder" % drift)


func test_player_on_leg_survives_step_transition() -> void:
	var w := await _setup(&"frozen")
	var p: PlayerCharacter = w.player
	var c: GreyboxHumanoid = w.colossus
	await _ticks(10)
	await _grab_behind(w, &"shin_l", -1.5)
	_check(p.is_climbing(), "no grip")
	_drive(c, 1.4, 0.0)
	var transitions := 0
	var prev_phase := LegState.Phase.STANCE
	var max_jump := 0.0
	var prev := p.global_position
	var prev2 := p.global_position
	var max_shake := 0.0
	for i in 60 * 7:
		p.stamina.value = maxf(p.stamina.value, 50.0)
		await _ticks(1)
		if not p.is_climbing():
			break
		var ph := c.loco.legs[0].phase
		if ph != prev_phase:
			transitions += 1
		prev_phase = ph
		if i > 1:
			max_jump = maxf(max_jump, (p.global_position - 2.0 * prev + prev2).length())
		prev2 = prev
		prev = p.global_position
		max_shake = maxf(max_shake, p.shake_level)
	_log.append("shin through %d lift-off/touchdown transitions: still gripping %s, max jump %.4f m, max shake level %.2f" % [transitions, p.is_climbing(), max_jump, max_shake])
	_metric("shin_step_max_shake_level", max_shake)
	_check(p.is_climbing(), "fell off the leg at a step transition (%s)" % p.last_release_reason)
	_check(transitions >= 3, "too few step transitions (%d)" % transitions)
	_check(max_jump < 0.01, "teleport at a step transition (%.3f m)" % max_jump)


func test_grip_on_hips_during_turn() -> void:
	var w := await _setup(&"frozen")
	var p: PlayerCharacter = w.player
	var c: GreyboxHumanoid = w.colossus
	await _ticks(10)
	await _grab_behind(w, &"hips", 0.3, 1.75)
	_check(p.is_climbing() and p.grip.body == _segment(c, &"hips"), "no grip on the hips")
	var start_local := p.grip.local_point
	_drive(c, 0.2, 0.3)
	var max_shake := 0.0
	for i in 60 * 6:
		await _ticks(1)
		max_shake = maxf(max_shake, p.shake_level)
	var drift := p.grip.local_point.distance_to(start_local) if p.grip else 99.0
	_log.append("hips during a turn: drift %.5f m, max shake level %.2f, still gripping %s" % [drift, max_shake, p.is_climbing()])
	_check(p.is_climbing(), "fell off the hips while turning")
	_check(drift < 0.01, "grip drifted %.4f m" % drift)
	_check(max_shake < 0.3, "a calm turn feels like a shake (%.2f)" % max_shake)


func test_grip_on_back_during_sudden_direction_change() -> void:
	var w := await _setup(&"frozen")
	var p: PlayerCharacter = w.player
	var c: GreyboxHumanoid = w.colossus
	_drive(c, 2.0, 0.3)
	await _ticks(60 * 4)
	await _grab_back_patch(w)
	_check(p.is_climbing(), "no grip on the back")
	var start_local := p.grip.local_point
	_drive(c, 2.0, -0.3)            # the brain changes its mind at once
	var max_shake := 0.0
	var max_accel := 0.0
	for i in 60 * 5:
		await _ticks(1)
		max_shake = maxf(max_shake, p.shake_level)
		max_accel = maxf(max_accel, p.surface_accel.length())
	_drive(c, 0.0, 0.0)             # and stops
	for i in 60 * 4:
		await _ticks(1)
		max_shake = maxf(max_shake, p.shake_level)
		max_accel = maxf(max_accel, p.surface_accel.length())
	var drift := p.grip.local_point.distance_to(start_local) if p.grip else 99.0
	_log.append("back during turn reversal + stop: drift %.5f m, max surface accel %.2f m/s2, max shake level %.2f" % [drift, max_accel, max_shake])
	_metric("back_reversal_surface_accel_max", max_accel, "lower")
	_check(p.is_climbing(), "fell off during a direction change")
	_check(drift < 0.01, "grip drifted")
	_check(max_shake < 0.2, "a direction change shakes the climber off (%.2f)" % max_shake)


## Re-measures the shake behaviour and compares it with the frozen Etap 2 baseline.
func test_shake_behavior_unchanged_after_locomotion() -> void:
	if not FileAccess.file_exists(BASELINE_PATH):
		_check(false, "no baseline")
		return
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASELINE_PATH))
	# Grip: stamina cost of a full shake.
	var w := await _setup(&"frozen")
	var p: PlayerCharacter = w.player
	var c: Colossus = w.colossus
	await _ticks(10)
	await _grab_back_patch(w)
	c.debug_override = &"shake"
	c._think_left = 0.0
	var st0 := p.stamina.value
	await _ticks(150)
	var grip_cost := st0 - p.stamina.value
	await _teardown()
	# Standing: time to lose balance.
	w = await _setup(&"frozen")
	p = w.player
	c = w.colossus
	await _stand_on_shoulder(w, Vector3(1.25, 0, 0.1))
	c.debug_override = &"shake"
	c._think_left = 0.0
	var lost := -1
	for i in 240:
		await _ticks(1)
		if p.balance.state >= Balance.State.STUMBLE:
			lost = i
			break
	var b_cost: float = base["shake_full_grip_stamina_cost"].value
	var b_lost: float = base["shake_full_balance_loss_s"].value
	_log.append("grip stamina cost %.1f (baseline %.1f), balance lost after %.2f s (baseline %.2f)" % [grip_cost, b_cost, lost * DT, b_lost])
	_check(absf(grip_cost - b_cost) < b_cost * 0.25, "grip shake cost changed: %.1f vs %.1f" % [grip_cost, b_cost])
	_check(lost >= 0 and absf(lost * DT - b_lost) < 0.6, "standing balance loss time changed: %.2f vs %.2f s" % [lost * DT, b_lost])


## Runs the same deterministic scenario as separate processes at different render rates
## (physics stays at 60 Hz) and compares the simulation results.
func test_locomotion_is_independent_of_render_fps() -> void:
	var exe := OS.get_executable_path()
	var results := {}
	for fps in [30, 60, 144, 240]:
		var out_path := ProjectSettings.globalize_path("res://tests/output/fps_%d.json" % fps)
		var output := []
		var code := OS.execute(exe, ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--fixed-fps", str(fps), "--quit-after", "20000", "res://tests/fps_scenario.tscn", "--", "--out=" + out_path], output, true)
		if code != 0 or not FileAccess.file_exists(out_path):
			_check(false, "scenario at %d fps failed (code %d)" % [fps, code])
			return
		results[fps] = JSON.parse_string(FileAccess.get_file_as_string(out_path))
	var ref: Dictionary = results[60]
	var max_diff := 0.0
	for fps in results:
		var r: Dictionary = results[fps]
		for k in ref:
			if k == "frames":
				continue  # differs on purpose
			if ref[k] is Array:
				for j in (ref[k] as Array).size():
					max_diff = maxf(max_diff, absf(float(r[k][j]) - float(ref[k][j])))
			else:
				max_diff = maxf(max_diff, absf(float(r[k]) - float(ref[k])))
	_log.append("render 30/60/144/240 fps, physics 60 Hz: frames rendered %s, max difference of simulation state %.8f" % [str([results[30].frames, results[60].frames, results[144].frames, results[240].frames]), max_diff])
	_metric("fps_independence_max_diff", max_diff, "lower")
	_check(max_diff < 1e-4, "simulation depends on render fps (diff %.6f)" % max_diff)
	_check(int(results[240].frames) > int(results[30].frames) * 6, "render rate did not actually differ")


func test_locomotion_cost_stays_within_reasonable_budget() -> void:
	var w := await _setup(&"frozen", false, true)
	var c: GreyboxHumanoid = w.colossus
	_drive(c, 1.4, 0.1)
	await _ticks(60)
	var m := await _measure_loco(c, 600)
	_log.append("procedural locomotion on the course: colossus %.1f us/tick (locomotion %.1f, IK %.1f), ground probes %.3f/tick" % [m.colossus, m.locomotion, m.ik, m.rays])
	_metric("loco_colossus_us", m.colossus, "lower")
	_metric("loco_ik_us", m.ik, "lower")
	_metric("loco_probes_per_tick", m.rays, "lower")
	_check(m.colossus < 400.0, "colossus logic too expensive: %.0f us/tick" % m.colossus)
	_check(m.ik < 100.0, "IK too expensive: %.0f us/tick" % m.ik)
	_check(m.rays < 0.2, "too many ground probes: %.2f per tick" % m.rays)


func _measure_loco(c: GreyboxHumanoid, ticks: int) -> Dictionary:
	Perf.take()
	await _ticks(ticks)
	var pr := Perf.take()
	var us: Dictionary = pr.usec
	return {
		"colossus": us.get(&"colossus", 0) / float(ticks),
		"locomotion": us.get(&"locomotion", 0) / float(ticks),
		"ik": us.get(&"ik", 0) / float(ticks),
		"rays": pr.queries.get(&"climb_rays", 0) / float(ticks),
	}


## A/B: the same scripted walk over the course and the same climb in every leg mode.
func ab_locomotion_comparison() -> void:
	var rows := []
	for mode in [GreyboxHumanoid.LocomotionMode.PROCEDURAL, GreyboxHumanoid.LocomotionMode.ANIM_IK, GreyboxHumanoid.LocomotionMode.LEGACY_FK]:
		GreyboxHumanoid.default_mode = mode
		var w := await _setup(&"frozen", false, true)
		var c: GreyboxHumanoid = w.colossus
		var t := _tracker(c)
		_drive(c, 1.4, 0.0)
		await _run_tracked(t, 60 * 3)
		c.reset_foot_stats()
		Perf.take()
		var h_err := 0.0
		var samples := 0
		for i in 60 * 24:
			await _ticks(1)
			t.step(DT)
			if i % 6 == 0:
				for k in 2:
					if c.foot_in_contact(k):
						var sole := c.sole_world(k)
						var g := _ground_at(sole)
						if not g.is_empty():
							h_err = maxf(h_err, absf(sole.y - (g.position as Vector3).y))
							samples += 1
		var pr := Perf.take()
		var ticks := 60 * 24
		var st := c.foot_stats
		var row := {
			"mode": GreyboxHumanoid.MODE_NAMES[mode],
			"slip_avg": st.slip_sum / maxf(1.0, st.contact_ticks), "slip_max": st.slip_max,
			"ground_err": h_err, "shoulder_accel": t.max_shoulder_accel,
			"colossus_us": pr.usec.get(&"colossus", 0) / float(ticks), "ik_us": pr.usec.get(&"ik", 0) / float(ticks),
			"rays": pr.queries.get(&"climb_rays", 0) / float(ticks),
		}
		await _teardown()
		# Turn response: time to reach 90% of a commanded turn rate from a straight walk.
		w = await _setup(&"frozen")
		c = w.colossus
		_drive(c, 1.4, 0.0)
		await _ticks(60 * 4)
		_drive(c, 1.0, 0.3)
		var resp := -1
		var turn_slip := 0.0
		c.reset_foot_stats()
		for i in 60 * 6:
			await _ticks(1)
			if resp < 0 and c.loco.yaw_rate > 0.27:
				resp = i
		turn_slip = c.foot_stats.slip_max
		row["turn_response_s"] = resp * DT
		row["turn_slip_max"] = turn_slip
		await _teardown()
		# Climbing stability: the leg-to-shoulders route on a walking colossus.
		w = await _setup(&"walk")
		var p: PlayerCharacter = w.player
		await _ticks(20)
		await _wait_planted(w.colossus, 0)
		await _grab_behind(w, &"shin_l", -1.8)
		var mantled := [false]
		p.mantled.connect(func() -> void: mantled[0] = true)
		p.actions.move = Vector2(0, 1)
		var max_shake := 0.0
		for i in 60 * 20:
			_aim_view_at(p, w.colossus)
			await _ticks(1)
			max_shake = maxf(max_shake, p.shake_level)
			if mantled[0] or not p.is_climbing():
				break
		row["climb_ok"] = mantled[0]
		row["climb_stamina"] = p.stamina.value
		row["climb_max_shake"] = max_shake
		await _teardown()
		rows.append(row)
	GreyboxHumanoid.default_mode = GreyboxHumanoid.LocomotionMode.PROCEDURAL
	_log.append("%-20s %9s %9s %10s %10s %9s %7s %7s %9s %9s %9s %9s" % ["mode", "slip avg", "slip max", "ground err", "shoulder a", "colossus", "IK", "rays", "turn resp", "turn slip", "climb", "stamina"])
	for r in rows:
		_log.append("%-20s %9.4f %9.4f %10.3f %10.2f %7.0fus %5.0fus %7.3f %8.2fs %9.4f %9s %9.0f" % [r.mode, r.slip_avg, r.slip_max, r.ground_err, r.shoulder_accel, r.colossus_us, r.ik_us, r.rays, r.turn_response_s, r.turn_slip_max, "ok" if r.climb_ok else "FAILED", r.climb_stamina])
	var f := FileAccess.open("res://tests/output/ab_locomotion.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(rows, "  "))
	f.close()
	for r in rows:
		_metric("ab_%s_slip_max" % String(r.mode).split(" ")[0], r.slip_max)
		_metric("ab_%s_ground_err" % String(r.mode).split(" ")[0], r.ground_err)


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

func _setup(mode: StringName, with_wall := false, terrain := false) -> Dictionary:
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
	if terrain:
		TerrainKit.build_course(_world, Vector3(0, 0, -6))
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
	if _save_horse_baseline:
		var horse := {}
		for k in _metrics:
			if String(k).begins_with("horse_"):
				horse[k] = _metrics[k]
		var hb := FileAccess.open(HORSE_BASELINE_PATH, FileAccess.WRITE)
		hb.store_string(JSON.stringify(horse, "  ", true))
		hb.close()
		print("\nhorse baseline saved to %s (%d metrics)" % [HORSE_BASELINE_PATH, horse.size()])
	if not FileAccess.file_exists(BASELINE_PATH):
		return
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASELINE_PATH))
	if FileAccess.file_exists(HORSE_BASELINE_PATH):
		var hbase: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(HORSE_BASELINE_PATH))
		for k in hbase:
			if not base.has(k):
				base[k] = hbase[k]
	print("\n--- regression metrics vs frozen baselines (%s, %s) ---" % [BASELINE_PATH, HORSE_BASELINE_PATH])
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


# --- ETAP 3 helpers ---------------------------------------------------------------------

## Drives a GreyboxHumanoid through the "manual" override: desired forward speed and turn.
func _drive(c: GreyboxHumanoid, speed: float, turn: float) -> void:
	c.debug_override = &"manual"
	c.debug_desired_speed = speed
	c.debug_desired_turn = turn


## Tracks shoulder (chest top) acceleration, speed derivatives and touchdowns per tick.
class Tracker:
	var c: GreyboxHumanoid
	var chest: BodySegment
	var local := Vector3(1.9, 2.8, 0)
	var prev_v := Vector3.ZERO
	var prev_speed := 0.0
	var prev_rate := 0.0
	var prev_yaw_rate := 0.0
	var ticks := 0
	var max_shoulder_accel := 0.0
	var max_accel := 0.0
	var max_jerk := 0.0
	var max_yaw_accel := 0.0
	var max_swinging := 0
	var phases: Array = [LegState.Phase.STANCE, LegState.Phase.STANCE]
	var touchdowns := []  # [leg index, tick]

	func step(dt: float) -> void:
		var v := chest.local_point_velocity(local, dt)
		if ticks > 2:
			max_shoulder_accel = maxf(max_shoulder_accel, (v - prev_v).length() / dt)
			var rate := (c.loco.speed - prev_speed) / dt
			max_accel = maxf(max_accel, absf(rate))
			if ticks > 3:
				max_jerk = maxf(max_jerk, absf(rate - prev_rate) / dt)
			prev_rate = rate
			max_yaw_accel = maxf(max_yaw_accel, absf(c.loco.yaw_rate - prev_yaw_rate) / dt)
		prev_v = v
		prev_speed = c.loco.speed
		prev_yaw_rate = c.loco.yaw_rate
		max_swinging = maxi(max_swinging, c.loco.swinging_count())
		for i in 2:
			var ph: LegState.Phase = c.loco.legs[i].phase
			if phases[i] == LegState.Phase.SWING and ph == LegState.Phase.STANCE:
				touchdowns.append([i, ticks])
			phases[i] = ph
		ticks += 1


func _tracker(c: GreyboxHumanoid) -> Tracker:
	var t := Tracker.new()
	t.c = c
	t.chest = _segment(c, &"chest")
	return t


func _run_tracked(t: Tracker, ticks: int) -> void:
	for i in ticks:
		await _ticks(1)
		t.step(DT)


## Independent ground height under a point (straight ray, WORLD only).
func _ground_at(p: Vector3) -> Dictionary:
	var space := _world.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 10.0, p + Vector3.DOWN * 10.0, Layers.WORLD)
	return space.intersect_ray(q)


## Waits until leg i of a GreyboxHumanoid is in stance (procedural mode), max 4 s.
func _wait_planted(c: Colossus, i: int) -> void:
	var g := c as GreyboxHumanoid
	if g == null or g.locomotion_mode != GreyboxHumanoid.LocomotionMode.PROCEDURAL:
		return
	for k in 240:
		if g.loco.legs[i].is_planted() and g.loco.legs[1 - i].is_planted():
			return
		await _ticks(1)


## Puts the player right behind a limb segment (colossus back side) and holds grip.
func _grab_behind(w: Dictionary, bone: StringName, along: float, dist := 1.25) -> void:
	var c: Colossus = w.colossus
	var p: PlayerCharacter = w.player
	var seg := _segment(c, bone)
	var back := c.global_basis.z
	# Behind the limb in the segment's own frame (limbs are not vertical any more: knees bend).
	var target := seg.global_transform * Vector3(0, along, dist)
	p.global_position = target
	p.velocity = Vector3.ZERO
	p.facing = -back
	p.actions.view_basis = Basis.looking_at(-back)
	p.actions.grab_held = true
	p.reset_physics_interpolation()
	await _ticks(3)
	# A walking leg may have moved away in between: retry while it stands.
	for attempt in 3:
		if OS.get_environment("TRACE") != "":
			var g := c as GreyboxHumanoid
			_log.append("grab attempt %d: climbing %s, L %s R %s, p %s seg %s, state %s" % [attempt, p.is_climbing(), g.loco.legs[0].phase_name(), g.loco.legs[1].phase_name(), str(p.global_position.snapped(Vector3.ONE * 0.01)), str(seg.global_transform.origin.snapped(Vector3.ONE * 0.01)), p.get_display_state()])
		if p.is_climbing():
			return
		await _wait_planted(c, 0)
		target = seg.global_transform * Vector3(0, along, dist)
		p.global_position = target
		p.velocity = Vector3.ZERO
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


# --- ETAP 4: Agro --------------------------------------------------------------------------

## One tick of horse state for the smoothness checks.
func _horse_sample(h: Horse) -> Dictionary:
	var body := h.body_transform()
	var e := (h.global_basis.inverse() * body.basis).get_euler()
	return {"speed": h.controller.speed, "yaw": h.controller.yaw, "yaw_rate": h.controller.yaw_rate,
		"pos": h.global_position, "gait": int(h.controller.gait), "height": body.origin.y - h.global_position.y,
		"pitch": e.x, "roll": e.z, "body": body.origin,
		"collided": h.get_slide_collision_count() > 0, "obstacle": h.controller.obstacle}


## Runs n ticks recording a sample per tick (``each`` is called before the tick, with the tick index).
func _ride(h: Horse, n: int, each := Callable()) -> Array:
	var out := []
	for i in n:
		if each.is_valid():
			each.call(i)
		await _ticks(1)
		out.append(_horse_sample(h))
	return out


## Largest |d/dt| and |d2/dt2| of a sampled scalar.
func _rates(samples: Array, key: String, from := 0) -> Vector2:
	var d1 := 0.0
	var d2 := 0.0
	for i in range(maxi(from, 2), samples.size()):
		var a: float = samples[i - 2][key]
		var b: float = samples[i - 1][key]
		var c: float = samples[i][key]
		if key == "yaw":
			b = a + wrapf(b - a, -PI, PI)
			c = b + wrapf(c - (samples[i - 1][key] as float), -PI, PI)
		d1 = maxf(d1, absf(c - b) / DT)
		d2 = maxf(d2, absf(c - 2.0 * b + a) / (DT * DT))
	return Vector2(d1, d2)


func _setup_horse(start: String, with_player := false, with_camera := false) -> Dictionary:
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
	var points := AgroArena.build(_world)
	var h := Horse.new()
	h.name = "Agro"
	_world.add_child(h)
	var sp: Array = points[start]
	h.teleport(sp[0], sp[1])
	var d := ScriptedHorseDriver.new()
	d.name = "Driver"
	_world.add_child(d)
	var out := {"horse": h, "driver": d, "points": points}
	if with_player:
		var p := PlayerCharacter.new()
		p.name = "Player1"
		_world.add_child(p)
		p.global_position = (sp[0] as Vector3) + Vector3(-1.4, 0.95, 0.2)
		p.actions.view_basis = Basis.IDENTITY
		out.player = p
		if with_camera:
			var cam := PlayerCamera.new()
			cam.player = p
			_world.add_child(cam)
			out.camera = cam
	else:
		h.set_rider(d)
	await _ticks(2)
	h.reset_foot_stats()
	return out


## Player mounts the horse next to it through PlayerActions; waits until seated.
func _mount(p: PlayerCharacter) -> bool:
	p.actions.press_interact()
	for i in 90:
		await _ticks(1)
		if p.is_riding() and p.riding.phase == PlayerRiding.Phase.RIDING:
			return true
	return false


func _gait_sequence(samples: Array) -> Array:
	var seq := []
	for s in samples:
		if seq.is_empty() or seq[-1] != s.gait:
			seq.append(s.gait)
	return seq


func test_horse_acceleration_is_smooth() -> void:
	var w := await _setup_horse("flat")
	var h: Horse = w.horse
	var d: ScriptedHorseDriver = w.driver
	d.direction = Vector3.FORWARD
	d.drive = 1.0
	for i in 3:
		d.kick()
	var s := await _ride(h, 540)
	var r := _rates(s, "speed")
	var top: float = s[-1].speed
	var t_gallop := -1.0
	for i in s.size():
		if s[i].gait == HorseController.Gait.GALLOP:
			t_gallop = i * DT
			break
	# Real body speed (from positions), not only the controller's number.
	var body_v: Array = []
	for i in range(1, s.size()):
		body_v.append({"speed": ((s[i].pos as Vector3) - (s[i - 1].pos as Vector3)).length() / DT})
	var rb := _rates(body_v, "speed")
	_log.append("0 -> %.2f m/s, gaits %s, gallop after %.2f s; max accel %.2f m/s2 (body %.2f), max jerk %.2f m/s3" % [top, str(_gait_sequence(s)), t_gallop, r.x, rb.x, r.y])
	_metric("horse_accel_max", r.x, "lower")
	_metric("horse_jerk_max", r.y, "lower")
	_check(top > 9.0, "did not reach a gallop: %.2f m/s" % top)
	_check(_gait_sequence(s) == [0, 1, 2, 3], "gaits not in order: %s" % str(_gait_sequence(s)))
	_check(r.x <= h.controller.max_accel + 0.05, "acceleration too high: %.2f" % r.x)
	_check(rb.x <= h.controller.max_accel + 0.3, "body acceleration jumps: %.2f" % rb.x)
	_check(r.y <= h.controller.max_jerk + 0.5, "jerk too high: %.2f" % r.y)
	_check(t_gallop > 2.0, "reached a gallop instantly (%.2f s)" % t_gallop)


func test_horse_braking_is_smooth() -> void:
	var w := await _setup_horse("flat")
	var h: Horse = w.horse
	var d: ScriptedHorseDriver = w.driver
	d.direction = Vector3.FORWARD
	d.drive = 1.0
	for i in 3:
		d.kick()
	await _ticks(480)
	var v0 := h.get_speed()
	var p0 := h.global_position
	d.drive = 0.0
	d.direction = Vector3.ZERO
	d.rein = true
	var s := await _ride(h, 300)
	var stop_t := -1.0
	for i in s.size():
		if s[i].speed < 0.05:
			stop_t = i * DT
			break
	var r := _rates(s, "speed")
	var dist := Vector2(h.global_position.x - p0.x, h.global_position.z - p0.z).length()
	_log.append("rein from %.2f m/s: stopped after %.2f s / %.1f m, gaits %s, max decel %.2f m/s2, max jerk %.2f m/s3" % [v0, stop_t, dist, str(_gait_sequence(s)), r.x, r.y])
	_metric("horse_stop_distance", dist, "info")
	_check(v0 > 9.0, "not galloping before braking")
	_check(stop_t > 0.0 and stop_t < 4.5, "did not stop in time (%.2f s)" % stop_t)
	_check(stop_t > 1.2, "stopped like a car (%.2f s)" % stop_t)
	_check(r.x <= h.controller.rein_decel + 0.05, "deceleration too high: %.2f" % r.x)
	_check(r.y <= h.controller.max_jerk + 0.5, "jerk too high: %.2f" % r.y)
	_check(_gait_sequence(s) == [3, 2, 1, 0], "gaits not stepped down in order: %s" % str(_gait_sequence(s)))


func test_horse_cannot_instant_turn_at_speed() -> void:
	var w := await _setup_horse("flat")
	var h: Horse = w.horse
	var d: ScriptedHorseDriver = w.driver
	d.direction = Vector3.FORWARD
	d.drive = 1.0
	for i in 3:
		d.kick()
	await _ticks(480)
	var yaw0 := h.controller.yaw
	d.direction = Vector3.RIGHT   # a hard 90 deg request at a gallop
	var s := await _ride(h, 480)
	var over_limit := 0.0
	for e in s:
		over_limit = maxf(over_limit, absf(e.yaw_rate) - h.controller.max_turn_rate(e.speed))
	var after_quarter := absf(wrapf((s[14].yaw as float) - yaw0, -PI, PI))
	var done_t := -1.0
	for i in s.size():
		if absf(wrapf((s[i].yaw as float) - (-PI * 0.5), -PI, PI)) < 0.1:
			done_t = i * DT
			break
	var min_speed := 99.0
	for e in s:
		min_speed = minf(min_speed, e.speed)
	var r := _rates(s, "yaw_rate")
	_log.append("90 deg request at %.1f m/s: %.1f deg after 0.25 s, turn done after %.2f s, slowed to %.1f m/s, max yaw accel %.2f rad/s2" % [s[0].speed, rad_to_deg(after_quarter), done_t, min_speed, r.x])
	_check(after_quarter < 0.12, "turned %.2f rad in 0.25 s at a gallop" % after_quarter)
	_check(over_limit < 1e-3, "turn rate above the radius limit by %.3f" % over_limit)
	_check(r.x <= h.controller.max_yaw_accel + 0.01, "turn rate jumps: %.2f rad/s2" % r.x)
	_check(done_t > 1.0 and done_t < 7.5, "turn finished after %.2f s" % done_t)
	_check(min_speed < 7.0, "kept a full gallop through a hard turn (%.1f m/s)" % min_speed)


func test_horse_turn_radius_increases_with_speed() -> void:
	var w := await _setup_horse("flat")
	var h: Horse = w.horse
	var d: ScriptedHorseDriver = w.driver
	var radii: Array[float] = []
	for v in [1.7, 4.2, 9.5]:
		var sp: Array = w.points.flat
		h.teleport(sp[0], 0.0)
		d.hold_speed = v
		d.turn = 0.0
		await _ticks(300)
		d.turn = 0.4
		await _ticks(180)
		var s := await _ride(h, 180)
		var arc := 0.0
		for i in range(1, s.size()):
			arc += ((s[i].pos as Vector3) - (s[i - 1].pos as Vector3)).length()
		var turned := absf(wrapf((s[-1].yaw as float) - (s[0].yaw as float), -PI, PI))
		radii.append(arc / maxf(turned, 1e-4))
	_log.append("measured turn radius at 1.7 / 4.2 / 9.5 m/s: %.1f / %.1f / %.1f m" % [radii[0], radii[1], radii[2]])
	_metric("horse_radius_gallop", radii[2], "info")
	_check(radii[0] < radii[1] and radii[1] < radii[2], "radius does not grow with speed")
	_check(radii[2] > 12.0, "galloping turn too tight: %.1f m" % radii[2])
	_check(radii[0] < 4.0, "walking turn too wide: %.1f m" % radii[0])


func test_horse_feet_do_not_slide() -> void:
	var w := await _setup_horse("flat")
	var h: Horse = w.horse
	var d: ScriptedHorseDriver = w.driver
	d.direction = Vector3.ZERO
	var plan := func(i: int) -> void:
		match i:
			0:
				d.hold_speed = 1.7
			180:
				d.hold_speed = 4.2
			420:
				d.hold_speed = 9.5
			600:
				d.turn = 0.35
			780:
				d.turn = -0.35
			960:
				d.turn = 0.0
				d.hold_speed = 0.0
	await _ride(h, 1140, plan)
	var fs := h.foot_stats
	_log.append("walk/trot/gallop/turns/stop: foot slip max %.4f m/s, mean %.5f m/s over %d contacts; IK reach error max %.3f m; %d steps" % [fs.slip_max, fs.slip_sum / maxf(1.0, fs.contact_ticks), fs.contact_ticks, fs.reach_max, h.gait_planner.step_count])
	_metric("horse_foot_slip_max", fs.slip_max, "lower")
	_check(fs.slip_max < 0.05, "planted hoof slides: %.3f m/s" % fs.slip_max)
	_check(fs.reach_max < 0.03, "legs cannot reach the planned feet: %.3f m" % fs.reach_max)
	_check(h.gait_planner.step_count > 100, "too few steps: %d" % h.gait_planner.step_count)


func test_horse_feet_follow_uneven_terrain() -> void:
	var w := await _setup_horse("course")
	var h: Horse = w.horse
	var d: ScriptedHorseDriver = w.driver
	d.hold_speed = 4.2
	var worst := 0.0
	var samples := 0
	var max_y := 0.0
	# Across the ramp, the bumps and the 0.8 m step down (the course ends in a drop at z -60).
	for i in 1000:
		await _ticks(1)
		max_y = maxf(max_y, h.global_position.y)
		for k in 4:
			if not h.gait_planner.legs[k].is_planted():
				continue
			var sole := h.sole_world(k)
			var g := _ground_at(sole + Vector3.UP * 0.3)
			if g.is_empty():
				continue
			# The probe from 10 m above can land on a rock edge the hoof sits beside: only
			# compare where the ground is within reach.
			var err := absf(sole.y - (g.position as Vector3).y)
			if err < 0.6:
				worst = maxf(worst, err)
				samples += 1
	var fs := h.foot_stats
	_log.append("course (ramp 10 deg, bumps, 0.8 m step) at a trot: reached z %.1f, top %.2f m; planted hoof vs ground max %.3f m (%d samples); IK reach %.3f m; slip max %.4f m/s" % [h.global_position.z, max_y, worst, samples, fs.reach_max, fs.slip_max])
	_metric("horse_terrain_foot_error", worst, "lower")
	_check(h.global_position.z < -48.5, "did not cross the course (z %.1f)" % h.global_position.z)
	_check(max_y > 3.0, "never climbed the ramp")
	_check(worst < 0.05, "planted hooves not on the ground: %.3f m" % worst)
	_check(fs.reach_max < 0.05, "legs cannot reach the terrain: %.3f m" % fs.reach_max)
	_check(fs.slip_max < 0.05, "hooves slide on the course: %.3f m/s" % fs.slip_max)


func test_horse_body_lean_is_continuous() -> void:
	var w := await _setup_horse("flat")
	var h: Horse = w.horse
	var d: ScriptedHorseDriver = w.driver
	var plan := func(i: int) -> void:
		match i:
			0:
				d.hold_speed = 9.5
			300:
				d.turn = 0.5
			420:
				d.turn = -0.5
			540:
				d.turn = 0.0
				d.hold_speed = 0.0
				d.rein = true
	var s := await _ride(h, 780, plan)
	var roll := _rates(s, "roll", 3)
	var pitch := _rates(s, "pitch", 3)
	var height := _rates(s, "height", 3)
	var into := 0
	var turning := 0
	for e in s:
		if absf(e.yaw_rate) > 0.2:
			turning += 1
			if e.roll * e.yaw_rate > 0.0:
				into += 1
	_log.append("slalom at a gallop + rein stop: roll rate max %.2f rad/s (d2 %.1f), pitch rate %.2f (d2 %.1f), height rate %.2f m/s (d2 %.1f), hard height clamps %d; leaning into the turn %d/%d ticks" % [roll.x, roll.y, pitch.x, pitch.y, height.x, height.y, h.height_clamps, into, turning])
	_metric("horse_roll_d2", roll.y, "lower")
	_metric("horse_height_d2", height.y, "lower")
	_check(roll.x < 1.0 and pitch.x < 1.5, "body tilts too fast")
	_check(roll.y < 30.0 and pitch.y < 40.0 and height.y < 40.0, "body pose pops (second differences too large)")
	_check(turning > 30 and into > turning * 0.8, "does not lean into turns (%d/%d)" % [into, turning])


func test_mounted_player_has_no_saddle_drift() -> void:
	var w := await _setup_horse("flat", true)
	var h: Horse = w.horse
	var p: PlayerCharacter = w.player
	_check(await _mount(p), "could not mount")
	p.actions.move = Vector2(0, 1)
	var worst := 0.0
	var top := 0.0
	for i in 900:
		match i:
			30, 60, 90:
				p.actions.press_jump()
			400:
				p.actions.move = Vector2(0.7, 0.7)
			560:
				p.actions.move = Vector2(-0.7, 0.7)
			720:
				p.actions.move = Vector2.ZERO
				p.actions.grab_held = true
		await _ticks(1)
		var seat := h.saddle_transform()
		worst = maxf(worst, p.global_position.distance_to(seat.origin))
		top = maxf(top, h.get_speed())
	_log.append("ride 15 s (gallop, turns, rein stop): rider vs saddle max %.6f m; top speed %.1f m/s" % [worst, top])
	_metric("horse_saddle_drift", worst, "lower")
	_check(worst < 1e-4, "rider drifts in the saddle: %.5f m" % worst)
	_check(p.is_riding(), "fell off")
	_check(top > 9.0, "never galloped")


func test_mount_and_dismount_are_stable() -> void:
	var w := await _setup_horse("flat", true)
	var h: Horse = w.horse
	var p: PlayerCharacter = w.player
	var states := []
	var m := {"max_step": 0.0, "prev": p.global_position, "where": ""}
	var track := func() -> void:
		var st := p.get_display_state()
		if states.is_empty() or states[-1] != st:
			states.append(st)
		var step: float = p.global_position.distance_to(m.prev)
		if step > m.max_step:
			m.max_step = step
			m.where = st
		m.prev = p.global_position
	await _ticks(10)
	track.call()
	p.actions.press_interact()
	for i in 60:
		await _ticks(1)
		track.call()
	var mounted := p.is_riding() and p.riding.phase == PlayerRiding.Phase.RIDING
	# Walk a bit, stop, get off.
	p.actions.move = Vector2(0, 1)
	for i in 180:
		await _ticks(1)
		track.call()
	p.actions.move = Vector2.ZERO
	p.actions.grab_held = true
	for i in 120:
		await _ticks(1)
		track.call()
	p.actions.grab_held = false
	p.actions.press_interact()
	for i in 90:
		await _ticks(1)
		track.call()
	var off := not p.is_riding()
	var max_step: float = m.max_step
	var hd := Vector2(p.global_position.x - h.global_position.x, p.global_position.z - h.global_position.z).length()
	var g := _ground_at(p.global_position)
	var above: float = p.global_position.y - (g.position as Vector3).y if not g.is_empty() else 99.0
	_log.append("states %s; max per-tick move %.3f m (%s); on foot %.2f m from the horse, %.2f m above ground, on floor %s" % [" -> ".join(states), max_step, m.where, hd, above, str(p.is_on_floor())])
	_check(mounted, "did not reach RIDE")
	_check(off, "did not get off")
	_check(states.has("APPROACH HORSE") and states.has("MOUNT") and states.has("RIDE") and states.has("DISMOUNT"), "missing states: %s" % str(states))
	_check(max_step < 0.12, "teleport-like jump of %.3f m in one tick" % max_step)
	_check(hd > 0.8, "player ends inside the horse (%.2f m)" % hd)
	_check(above < 1.1 and p.is_on_floor(), "player not standing on the ground after dismount")
	# Riding again works (state machine closed the loop).
	_check(await _mount(p), "could not mount again")


func test_dismount_refused_without_space() -> void:
	var w := await _setup_horse("flat", true)
	var h: Horse = w.horse
	var p: PlayerCharacter = w.player
	_check(await _mount(p), "could not mount")
	# Rocks close on every side: no free, flat spot to step off to.
	var c := h.global_position
	var mat := StandardMaterial3D.new()
	TerrainKit.box(_world, c + Vector3(-1.6, 1.0, 0), Vector3(1.3, 2.0, 3.0), mat)
	TerrainKit.box(_world, c + Vector3(1.6, 1.0, 0), Vector3(1.3, 2.0, 3.0), mat)
	TerrainKit.box(_world, c + Vector3(0, 1.0, -2.4), Vector3(4.5, 2.0, 1.0), mat)
	TerrainKit.box(_world, c + Vector3(0, 1.0, 2.4), Vector3(4.5, 2.0, 1.0), mat)
	await _ticks(10)
	p.actions.press_interact()
	await _ticks(10)
	_log.append("boxed in: still riding %s, reason '%s'" % [str(p.riding.phase == PlayerRiding.Phase.RIDING), p.riding.last_refusal])
	_check(p.is_riding() and p.riding.phase == PlayerRiding.Phase.RIDING, "dismounted into a rock")
	_check(p.riding.last_refusal != "", "no reason given")


func test_horse_avoids_small_obstacle() -> void:
	var w := await _setup_horse("rocks")
	var h: Horse = w.horse
	var d: ScriptedHorseDriver = w.driver
	d.direction = Vector3.FORWARD
	d.hold_speed = 4.2
	var s := await _ride(h, 900)
	var hits := 0
	var max_dev := 0.0
	var max_avoid := 0.0
	for e in s:
		hits += 1 if e.collided else 0
		max_dev = maxf(max_dev, absf((e.pos as Vector3).x))
	var r := _rates(s, "yaw")
	_log.append("rock field at a trot: reached z %.1f, %d ticks touching a rock, max sideways %.2f m, max turn rate %.2f rad/s (d2 %.1f)" % [h.global_position.z, hits, max_dev, r.x, r.y])
	_metric("horse_rock_contacts", hits, "lower")
	_check(h.global_position.z < -42.0, "did not get through the rocks (z %.1f)" % h.global_position.z)
	_check(hits == 0, "ran into rocks (%d ticks)" % hits)
	_check(max_dev < 4.5, "wandered off the line (%.1f m)" % max_dev)


## Horse-relative steering (no stick direction, no turn): after going round a rock the
## horse comes back to the heading it was given instead of following its own nose.
func test_horse_keeps_heading_after_avoiding() -> void:
	var w := await _setup_horse("rocks")
	var h: Horse = w.horse
	var d: ScriptedHorseDriver = w.driver
	d.drive = 1.0
	d.hold_speed = 4.2
	var s := await _ride(h, 900)
	var hits := 0
	var max_yaw := 0.0
	for e in s:
		hits += 1 if e.collided else 0
		max_yaw = maxf(max_yaw, absf(e.yaw))
	_log.append("rocks, horse-relative steering: reached z %.1f, final heading %.1f deg (max %.0f deg while going round), %d contacts" % [h.global_position.z, rad_to_deg(h.controller.yaw), rad_to_deg(max_yaw), hits])
	_check(h.global_position.z < -42.0, "did not get through (z %.1f)" % h.global_position.z)
	_check(absf(h.controller.yaw) < 0.1, "lost its heading (%.2f rad)" % h.controller.yaw)
	_check(hits == 0, "ran into rocks")


func test_horse_threads_narrow_passage() -> void:
	var w := await _setup_horse("passage")
	var h: Horse = w.horse
	var d: ScriptedHorseDriver = w.driver
	d.direction = Vector3.FORWARD
	d.hold_speed = 4.2
	var s := await _ride(h, 540)
	var hits := 0
	for e in s:
		hits += 1 if e.collided else 0
	_log.append("3 m gap at a trot: reached z %.1f, %d ticks touching a wall" % [h.global_position.z, hits])
	_check(h.global_position.z < -22.0, "did not get through the passage (z %.1f)" % h.global_position.z)
	_check(hits == 0, "scraped the walls (%d ticks)" % hits)


func test_horse_steps_over_low_obstacle() -> void:
	var w := await _setup_horse("log")
	var h: Horse = w.horse
	var d: ScriptedHorseDriver = w.driver
	d.direction = Vector3.FORWARD
	d.hold_speed = 4.2
	var s := await _ride(h, 360)
	var max_dev := 0.0
	var saw_step := false
	for e in s:
		max_dev = maxf(max_dev, absf((e.pos as Vector3).x - 18.0))
		saw_step = saw_step or e.obstacle == "step"
	var fs := h.foot_stats
	_log.append("0.3 m log at a trot: reached z %.1f, max sideways %.2f m, classified as step %s; IK reach %.3f m, slip %.4f m/s" % [h.global_position.z, max_dev, str(saw_step), fs.reach_max, fs.slip_max])
	_check(h.global_position.z < -8.0, "did not cross the log")
	_check(saw_step, "log not recognised as something to step over")
	_check(max_dev < 0.5, "went around the log instead of over it (%.2f m)" % max_dev)
	_check(fs.reach_max < 0.05 and fs.slip_max < 0.05, "feet failed on the log")


func test_horse_stops_before_large_obstacle() -> void:
	var w := await _setup_horse("wall")
	var h: Horse = w.horse
	var d: ScriptedHorseDriver = w.driver
	d.direction = Vector3.FORWARD
	d.drive = 1.0
	for i in 3:
		d.kick()
	var s := await _ride(h, 720)
	var hits := 0
	var near_speed := 0.0
	var top := 0.0
	var min_gap := 99.0
	for e in s:
		hits += 1 if e.collided else 0
		top = maxf(top, e.speed)
		var gap: float = (e.pos as Vector3).z - (-59.5) - 1.15
		min_gap = minf(min_gap, gap)
		if gap < 3.0:
			near_speed = maxf(near_speed, e.speed)
	_log.append("gallop at a 5 m wall, rider keeps pushing: top %.1f m/s, max speed within 3 m %.2f m/s, closest nose gap %.2f m, final speed %.2f, %d contact ticks" % [top, near_speed, min_gap, h.get_speed(), hits])
	_check(top > 8.0, "never galloped")
	_check(hits == 0, "ran into the wall")
	_check(min_gap > 0.2, "nose in the wall (gap %.2f m)" % min_gap)
	_check(near_speed < 4.0, "still fast next to the wall: %.1f m/s" % near_speed)
	_check(h.get_speed() < 0.3, "not standing at the wall")


func test_horse_stops_at_cliff_edge() -> void:
	var w := await _setup_horse("cliff")
	var h: Horse = w.horse
	var d: ScriptedHorseDriver = w.driver
	d.direction = Vector3.FORWARD
	d.drive = 1.0
	for i in 3:
		d.kick()
	var s := await _ride(h, 600)
	var min_y := 99.0
	var top := 0.0
	for e in s:
		min_y = minf(min_y, (e.pos as Vector3).y)
		top = maxf(top, e.speed)
	var edge := -72.7
	_log.append("galloping at a 4 m drop: top %.1f m/s, stopped %.2f m before the edge, lowest %.2f m, final speed %.2f" % [top, h.global_position.z - edge, min_y, h.get_speed()])
	_check(min_y > 3.5, "went over the edge")
	_check(h.global_position.z - edge > 1.2, "stopped with the front hooves over the edge")
	_check(h.get_speed() < 0.3, "not standing at the edge")
	_check(top > 6.0, "never got going")


## Same scripted ride as separate processes at 30..240 render FPS (physics 60 Hz).
func test_horse_simulation_independent_of_render_fps() -> void:
	var exe := OS.get_executable_path()
	var results := {}
	var rates := [30, 60, 90, 120, 144, 240]
	for fps in rates:
		var out_path := ProjectSettings.globalize_path("res://tests/output/horse_fps_%d.json" % fps)
		var output := []
		var code := OS.execute(exe, ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--fixed-fps", str(fps), "--quit-after", "20000", "res://tests/fps_scenario.tscn", "--", "--scenario=horse", "--out=" + out_path], output, true)
		if code != 0 or not FileAccess.file_exists(out_path):
			_check(false, "horse scenario at %d fps failed (code %d)" % [fps, code])
			return
		results[fps] = JSON.parse_string(FileAccess.get_file_as_string(out_path))
	var ref: Dictionary = results[60]
	var max_diff := 0.0
	var frames := []
	for fps in rates:
		var r: Dictionary = results[fps]
		frames.append(int(r.frames))
		for k in ref:
			if k == "frames":
				continue
			if ref[k] is Array:
				for j in (ref[k] as Array).size():
					max_diff = maxf(max_diff, absf(float(r[k][j]) - float(ref[k][j])))
			else:
				max_diff = maxf(max_diff, absf(float(r[k]) - float(ref[k])))
	_log.append("mount, ride, turn, rein, dismount at render %s fps: frames %s, max state difference %.8f (steps %d)" % [str(rates), str(frames), max_diff, int(ref.steps)])
	_metric("horse_fps_max_diff", max_diff, "lower")
	_check(max_diff < 1e-4, "horse simulation depends on render fps (diff %.6f)" % max_diff)
	_check(frames[-1] > frames[0] * 6, "render rate did not actually differ")


func test_horse_camera_can_look_away_from_travel_direction() -> void:
	var w := await _setup_horse("flat", true, true)
	var h: Horse = w.horse
	var p: PlayerCharacter = w.player
	var cam: PlayerCamera = w.camera
	_check(await _mount(p), "could not mount")
	p.actions.view_basis = cam.global_basis
	p.actions.move = Vector2(0, 1)
	p.actions.press_jump()
	await _ticks(240)
	p.actions.move = Vector2(0, 1)
	var yaw0 := h.controller.yaw
	# Let go of the stick and look 90 degrees to the side.
	p.actions.move = Vector2.ZERO
	var cam_yaw0 := cam.yaw
	p.actions.look_delta = Vector2(PI * 0.5, 0.0)
	await _ticks(30)
	p.actions.view_basis = cam.global_basis
	await _ticks(150)
	var drift_free := absf(wrapf(h.controller.yaw - yaw0, -PI, PI))
	var cam_turn := absf(wrapf(cam.yaw - cam_yaw0, -PI, PI))
	var v_free := h.get_speed()
	# Horse-relative steering while still looking sideways (prep for riding + aiming).
	p.riding.steer_relative = true
	p.actions.move = Vector2(0, 1)
	await _ticks(180)
	var drift_rel := absf(wrapf(h.controller.yaw - yaw0, -PI, PI))
	var cam_vs_travel := absf(wrapf(cam.yaw - h.controller.yaw, -PI, PI))
	_log.append("camera turned %.0f deg away; horse heading change %.1f deg (no stick), %.1f deg (horse-relative stick); speed %.1f m/s; camera vs travel %.0f deg" % [rad_to_deg(cam_turn), rad_to_deg(drift_free), rad_to_deg(drift_rel), v_free, rad_to_deg(cam_vs_travel)])
	_check(cam_turn > 1.4, "camera did not turn")
	_check(drift_free < 0.03, "camera steered the horse (%.3f rad)" % drift_free)
	_check(drift_rel < 0.03, "horse-relative stick followed the camera (%.3f rad)" % drift_rel)
	_check(v_free > 3.0, "horse stopped when the camera turned")
	_check(cam_vs_travel > 1.3, "camera snapped back to the travel direction")


func test_horse_comes_when_called() -> void:
	var w := await _setup_horse("rocks", true)
	var h: Horse = w.horse
	var p: PlayerCharacter = w.player
	# The horse waits on the far side of the rock field.
	h.teleport(Vector3(1, 0, -46), PI)
	await _ticks(5)
	p.actions.press_call()
	var s := await _ride(h, 1500)
	var hits := 0
	for e in s:
		hits += 1 if e.collided else 0
	var dist := Vector2(h.global_position.x - p.global_position.x, h.global_position.z - p.global_position.z).length()
	_log.append("called from 56 m through the rocks: arrived %.2f m from the player, speed %.2f, command %s, %d rock contacts" % [dist, h.get_speed(), Horse.Command.keys()[h.command], hits])
	_check(dist < 4.5 and dist > 1.5, "did not stop next to the player (%.1f m)" % dist)
	_check(h.get_speed() < 0.2, "still moving")
	_check(hits == 0, "ran into rocks")


func test_horse_follows_player() -> void:
	var w := await _setup_horse("flat", true)
	var h: Horse = w.horse
	var p: PlayerCharacter = w.player
	h.command_follow(p)
	p.actions.move = Vector2(0, 1)
	var max_d := 0.0
	var min_d := 99.0
	var run_end := 0.0
	for i in 600:
		await _ticks(1)
		var dd := Vector2(h.global_position.x - p.global_position.x, h.global_position.z - p.global_position.z).length()
		if i > 240:
			max_d = maxf(max_d, dd)
		if i > 60:
			min_d = minf(min_d, dd)
		run_end = dd
	p.actions.move = Vector2.ZERO
	await _ticks(300)
	var end_d := Vector2(h.global_position.x - p.global_position.x, h.global_position.z - p.global_position.z).length()
	_log.append("follow a running player (5.5 m/s) 10 s: distance %.1f..%.1f m (%.1f m at the end of the run), after the player stops %.1f m, speed %.2f" % [min_d, max_d, run_end, end_d, h.get_speed()])
	_check(max_d < 16.0, "fell behind (%.1f m)" % max_d)
	_check(run_end < 10.0, "did not catch up (%.1f m)" % run_end)
	_check(min_d > 1.5, "ran over the player (%.1f m)" % min_d)
	_check(h.get_speed() < 0.2 and end_d < 8.0, "did not settle near the player")


func test_horse_cost_stays_within_budget() -> void:
	var w := await _setup_horse("course", true, true)
	var h: Horse = w.horse
	var p: PlayerCharacter = w.player
	_check(await _mount(p), "could not mount")
	p.actions.view_basis = Basis.IDENTITY
	p.actions.move = Vector2(0, 1)
	p.actions.press_jump()
	await _ticks(60)
	Perf.take()
	await _ticks(600)
	var m := Perf.take()
	var u: Dictionary = m.usec
	var q: Dictionary = m.queries
	var per := func(k: StringName) -> float: return float(u.get(k, 0)) / 600.0
	var horse_total: float = per.call(&"horse")
	var rays := float(q.get(&"horse_rays", 0)) / 600.0
	_log.append("ridden on the course: horse %.1f us/tick (controller %.1f of which obstacle probes %.1f, step planner %.1f, IK+body %.1f), mount %.1f, camera %.1f us/frame; horse queries %.1f/tick" % [horse_total, per.call(&"horse_controller"), per.call(&"horse_probes"), per.call(&"horse_steps"), per.call(&"horse_ik"), per.call(&"mount"), per.call(&"camera"), rays])
	_metric("horse_probes_us", per.call(&"horse_probes"), "lower")
	_metric("horse_us", horse_total, "lower")
	_metric("horse_controller_us", per.call(&"horse_controller"), "lower")
	_metric("horse_steps_us", per.call(&"horse_steps"), "lower")
	_metric("horse_ik_us", per.call(&"horse_ik"), "lower")
	_metric("horse_rays_per_tick", rays, "lower")
	_check(horse_total < 400.0, "horse logic too expensive: %.0f us/tick" % horse_total)
	_check(rays < 14.0, "too many horse rays: %.1f/tick" % rays)


## All tests from Milestone 1 and stages 2-3 ran in this process before the horse tests.
func existing_colossus_tests_still_pass() -> void:
	var ran := 0
	var failed := PackedStringArray()
	for n in _legacy_results:
		ran += 1
		if not _legacy_results[n]:
			failed.append(n)
	_log.append("%d earlier tests ran in this run, %d failed %s" % [ran, failed.size(), str(failed) if failed.size() > 0 else ""])
	_check(failed.is_empty(), "earlier tests failed: %s" % str(failed))


# --- ETAP 5: Valus (first complete boss) ---------------------------------------------

## A brain that always proposes the same intent (to prove the fairness rules hold anyway).
class SpamBrain:
	extends ColossusBrain
	var kind: StringName
	var strength := 1.0

	func _init(p_kind: StringName) -> void:
		kind = p_kind

	func decide(obs: ColossusObservation) -> ColossusIntent:
		var i := ColossusIntent.make(kind, strength)
		var best: ColossusObservation.PlayerInfo = null
		for p in obs.players:
			if best == null or p.distance < best.distance:
				best = p
		if best:
			i.target_player = best.player
			i.target_position = best.position
		i.score = 1.0
		return i


func _setup_valus(seed_value := 7, frozen := false) -> Dictionary:
	Sfx.enabled = false
	Fx.enabled = false
	_world = Node3D.new()
	_world.name = "World_" + _current
	add_child(_world)
	var w := ValusArena.build_encounter(_world, false, seed_value)
	if frozen:
		(w.valus as Valus).debug_override = &"frozen"
	await _ticks(2)
	return w


## Puts the player on the ground next to foot ``i`` (outside it).
func _stand_by_foot(w: Dictionary, i: int, off := Vector3(2.6, 0, 1.0)) -> void:
	var s: Valus = w.valus
	var p: PlayerCharacter = w.player
	var foot := s.loco.legs[i].plant_pos
	var side := s.global_basis.x * (1.0 if i == 0 else -1.0)
	p.global_position = foot + side * off.x + s.global_basis.z * off.z + Vector3.UP * 0.95
	p.velocity = Vector3.ZERO
	p.reset_physics_interpolation()


func _start_combat(s: Valus) -> void:
	s._set_encounter(Valus.Encounter.COMBAT)


## Drops the player onto the head top above the weak point (frozen boss).
func _stand_on_head(w: Dictionary) -> void:
	var s: Valus = w.valus
	var p: PlayerCharacter = w.player
	# Let the pose settle first (no head bowed from the dormant pose).
	await _ticks(90)
	var head := s._seg_by_bone[&"head"] as BodySegment
	p.global_position = head.target_transform * (Valus.WEAK_POINT_LOCAL + Vector3(0, 1.1, 0.15))
	p.velocity = Vector3.ZERO
	p.facing = s.global_basis.z
	p.actions.view_basis = Basis.looking_at(s.global_basis.z)
	p.reset_physics_interpolation()
	await _ticks(20)


## Holds the attack action for ``charge`` seconds and releases it; returns the strike result.
func _sword_strike(p: PlayerCharacter, charge: float) -> Dictionary:
	p.sword.last_result = {}
	p.actions.attack_held = true
	await _ticks(int(round(charge * 60.0)) + 1)
	p.actions.attack_held = false
	for i in 20:
		await _ticks(1)
		if not p.sword.last_result.is_empty():
			break
	return p.sword.last_result


func test_boss_enters_combat_when_player_enters_arena() -> void:
	var w := await _setup_valus()
	var s: Valus = w.valus
	var p: PlayerCharacter = w.player
	var states := []
	var attacks_before_combat := [0]
	s.encounter_changed.connect(func(e: Valus.Encounter) -> void: states.append([Valus.Encounter.keys()[e], _tick_now()]))
	s.attack_started.connect(func(_a: ColossusAttack) -> void:
		if s.encounter != Valus.Encounter.COMBAT:
			attacks_before_combat[0] += 1)
	await _ticks(180)
	var dormant_far: bool = s.encounter == Valus.Encounter.DORMANT
	# Walk into the arena (as a player would: through PlayerActions).
	p.actions.view_basis = Basis.looking_at(Vector3.FORWARD)
	var entered := -1
	for i in 60 * 12:
		p.actions.move = Vector2(0, 1)
		await _ticks(1)
		if entered < 0 and _flat_dist(p.global_position, s.global_position) < s.notice_radius:
			entered = _tick_now()
		if s.encounter == Valus.Encounter.COMBAT:
			break
	p.actions.move = Vector2.ZERO
	var combat_at := _tick_now()
	var lag := (combat_at - entered) / 60.0
	_log.append("dormant while far: %s; entered at 42 m, states %s, combat %.2f s after entering (notice %.1f + engage %.1f)" % [str(dormant_far), str(states), lag, s.notice_time, s.engage_time])
	_check(dormant_far, "not dormant at the entrance")
	_check(s.encounter == Valus.Encounter.COMBAT, "never reached COMBAT")
	_check(states.size() >= 3 and states[0][0] == "NOTICE" and states[1][0] == "ENGAGED" and states[2][0] == "COMBAT", "wrong sequence %s" % str(states))
	_check(lag < s.notice_time + s.engage_time + 0.3, "too slow to engage (%.2f s)" % lag)
	_check(attacks_before_combat[0] == 0, "attacked before COMBAT")


func _tick_now() -> int:
	return Engine.get_physics_frames()


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Records every attack's phase changes and the ticks with active hit volumes.
func _record_attacks(s: Valus) -> Dictionary:
	var rec := {"phases": [], "active_ticks": [], "hits": []}
	s.attack_phase_changed.connect(func(a: ColossusAttack) -> void: rec.phases.append([a.kind, a.phase_name(), _tick_now(), a.telegraph_time, a.active_time, a.recovery_time]))
	s.player_hit.connect(func(_p: Node3D, k: StringName, d: float) -> void: rec.hits.append([k, _tick_now(), d]))
	return rec


## Plays: the player stands by a foot (stomp) and later in front (sweep), invulnerable.
func _provoke_attacks(w: Dictionary, seconds: float, rec: Dictionary) -> void:
	var s: Valus = w.valus
	var p: PlayerCharacter = w.player
	_start_combat(s)
	for i in int(seconds * 60.0):
		if i % 600 < 300:
			if i % 20 == 0:
				_stand_by_foot(w, 0)
		elif i % 20 == 0:
			p.global_position = s.global_transform * Vector3(-1.5, 0.95, -5.5)
			p.velocity = Vector3.ZERO
		p.health = 100.0
		p.dead = false
		await _ticks(1)
		for v in s.hit_volumes.values():
			if (v as HitVolume).active:
				rec.active_ticks.append(_tick_now())
				break


func test_boss_attack_has_telegraph() -> void:
	var w := await _setup_valus()
	var s: Valus = w.valus
	var rec := _record_attacks(s)
	await _provoke_attacks(w, 25.0, rec)
	var telegraphs := []
	var start := {}
	for ph in rec.phases:
		if ph[1] == "TELEGRAPH":
			start[ph[0]] = ph[2]
		elif ph[1] == "ACTIVE" and start.has(ph[0]):
			telegraphs.append([ph[0], (ph[2] - start[ph[0]]) / 60.0])
	var kinds := {}
	var min_t := 99.0
	for t in telegraphs:
		kinds[t[0]] = true
		min_t = minf(min_t, t[1])
	# The rules clamp any attack definition to the minimum telegraph.
	var a := ColossusAttack.make(&"test", 0.05, 0.2, 0.1, true)
	s.rules.clamp_attack(a)
	_log.append("telegraphs (kind, seconds): %s; rules clamp 0.05 s -> %.2f s, recovery 0.1 -> %.2f s" % [str(telegraphs), a.telegraph_time, a.recovery_time])
	_metric("boss_min_telegraph", min_t, "higher")
	_check(kinds.has(Valus.STOMP) and kinds.has(Valus.ARM_SWEEP), "did not see both attacks: %s" % str(kinds.keys()))
	_check(min_t >= s.rules.min_telegraph - 1e-3, "telegraph shorter than the rule (%.2f s)" % min_t)
	_check(a.telegraph_time >= s.rules.min_telegraph and a.recovery_time >= s.rules.heavy_recovery_min, "rules did not clamp the attack")


func test_boss_attack_active_window_is_correct() -> void:
	var w := await _setup_valus()
	var s: Valus = w.valus
	var rec := _record_attacks(s)
	await _provoke_attacks(w, 25.0, rec)
	var windows := []
	var open_at := -1
	var kind := &""
	for ph in rec.phases:
		if ph[1] == "ACTIVE":
			open_at = ph[2]
			kind = ph[0]
		elif ph[1] == "RECOVERY" and open_at >= 0:
			windows.append([kind, open_at, ph[2], ph[4]])
			open_at = -1
	var outside := 0
	for t in rec.active_ticks:
		var inside := false
		for win in windows:
			# Hit volumes are tested after the colossus' own tick of the phase change.
			if t >= int(win[1]) and t <= int(win[2]) + 1:
				inside = true
		if not inside:
			outside += 1
	var hits_outside := 0
	for h in rec.hits:
		var inside := false
		for win in windows:
			if int(h[1]) >= int(win[1]) and int(h[1]) <= int(win[2]) + 1:
				inside = true
		if not inside:
			hits_outside += 1
	var lengths := []
	var wrong_len := 0
	for win in windows:
		var secs: float = (win[2] - win[1]) / 60.0
		lengths.append("%s %.2f/%.2f" % [win[0], secs, win[3]])
		if absf(secs - float(win[3])) > 1.5 / 60.0:
			wrong_len += 1
	_log.append("active windows: %s; hit-volume ticks %d (outside a window: %d); hits %d (outside: %d)" % [", ".join(PackedStringArray(lengths)), rec.active_ticks.size(), outside, rec.hits.size(), hits_outside])
	_check(windows.size() >= 2, "too few attacks")
	_check(rec.active_ticks.size() > 0, "hit volumes never active")
	_check(outside == 0, "hit volumes active outside ACTIVE (%d ticks)" % outside)
	_check(hits_outside == 0, "damage outside ACTIVE")
	_check(wrong_len == 0, "active window length differs from the definition")


func test_boss_attack_has_recovery() -> void:
	var w := await _setup_valus()
	var s: Valus = w.valus
	var rec := _record_attacks(s)
	await _provoke_attacks(w, 30.0, rec)
	var recov := []
	var r_at := -1
	var gaps := []
	var last_done := -1
	for ph in rec.phases:
		if ph[1] == "RECOVERY":
			r_at = ph[2]
		elif ph[1] == "DONE" and r_at >= 0:
			recov.append((ph[2] - r_at) / 60.0)
			r_at = -1
			last_done = ph[2]
		elif ph[1] == "TELEGRAPH" and last_done >= 0:
			gaps.append((ph[2] - last_done) / 60.0)
	var min_r := 99.0
	for r in recov:
		min_r = minf(min_r, r)
	var min_gap := 99.0
	for g in gaps:
		min_gap = minf(min_gap, g)
	_log.append("recoveries %s s (min %.2f, rule %.2f); gaps before the next wind-up %s s (rule %.1f)" % [str(recov), min_r, s.rules.heavy_recovery_min, str(gaps), s.rules.attack_gap])
	_check(recov.size() >= 2, "too few attacks")
	_check(min_r >= s.rules.heavy_recovery_min - 1e-3, "recovery shorter than the rule")
	_check(gaps.is_empty() or min_gap >= s.rules.attack_gap - 0.02, "next attack came too soon (%.2f s)" % min_gap)


func test_boss_attack_can_damage_player() -> void:
	var w := await _setup_valus()
	var s: Valus = w.valus
	var p: PlayerCharacter = w.player
	var rec := _record_attacks(s)
	_start_combat(s)
	_stand_by_foot(w, 0)
	var hp_before := p.health
	var fallen := false
	for i in 60 * 6:
		await _ticks(1)
		fallen = fallen or p.balance.state == Balance.State.FALLEN
		if not rec.hits.is_empty():
			break
	var stomp_hp := p.health
	await _ticks(60 * 4)
	# Sweep: stand in front of the boss.
	p.respawn()
	p.global_position = s.global_transform * Vector3(-1.5, 0.95, -5.5)
	p.reset_physics_interpolation()
	var sweep_hit := false
	for i in 60 * 14:
		await _ticks(1)
		for h in rec.hits:
			if h[0] == Valus.ARM_SWEEP:
				sweep_hit = true
		if sweep_hit:
			break
	_log.append("hits %s; HP after the stomp %.0f (from %.0f), knocked down %s; sweep hit %s" % [str(rec.hits), stomp_hp, hp_before, str(fallen), str(sweep_hit)])
	_check(stomp_hp < hp_before, "stomp did no damage")
	_check(fallen, "stomp did not knock the player down")
	_check(sweep_hit, "sweep never hit a player standing in front")


func test_boss_cannot_spam_heavy_attack() -> void:
	var w := await _setup_valus()
	var s: Valus = w.valus
	var p: PlayerCharacter = w.player
	s.brain = SpamBrain.new(Valus.STOMP)   # a brain that wants nothing but stomps
	var starts := []
	s.attack_started.connect(func(_a: ColossusAttack) -> void: starts.append(_tick_now()))
	_start_combat(s)
	for i in 60 * 60:
		if i % 15 == 0:
			_stand_by_foot(w, 0)
		p.health = 100.0
		p.balance.reset()
		await _ticks(1)
	var min_gap := 999.0
	for i in range(1, starts.size()):
		min_gap = minf(min_gap, (starts[i] - starts[i - 1]) / 60.0)
	var max_in_20 := 0
	for i in starts.size():
		var n := 0
		for j in range(i, starts.size()):
			if starts[j] - starts[i] < 20 * 60:
				n += 1
		max_in_20 = maxi(max_in_20, n)
	_log.append("stomp-only brain, player always at the foot, 60 s: %d stomps, min gap %.1f s, max %d within 20 s; rule interventions %d" % [starts.size(), min_gap, max_in_20, s.rules.interventions])
	_metric("boss_spam_stomps_per_minute", starts.size(), "lower")
	_check(starts.size() >= 2, "no stomps at all")
	_check(min_gap >= s.rules.cooldowns[Valus.STOMP], "stomps closer than the cooldown (%.1f s)" % min_gap)
	_check(max_in_20 <= s.rules.max_repeat, "more than %d stomps in a row (%d)" % [s.rules.max_repeat, max_in_20])


func test_boss_cannot_spam_shake() -> void:
	var w := await _setup_valus()
	var s: Valus = w.valus
	var p: PlayerCharacter = w.player
	s.brain = SpamBrain.new(ColossusIntent.SHAKE_PLAYER)   # wants to shake all the time
	_start_combat(s)
	await _grab_valus(w, &"thigh_l", -2.0)
	_check(p.is_climbing(), "no grip on the thigh")
	var spans := []
	var start := -1
	var shaking_ticks := 0
	for i in 60 * 40:
		p.stamina.value = 100.0   # keep him on so the rule (not exhaustion) ends the shakes
		await _ticks(1)
		var sh := s.intent.kind == ColossusIntent.SHAKE_PLAYER
		if sh:
			shaking_ticks += 1
		if sh and start < 0:
			start = _tick_now()
		elif not sh and start >= 0:
			spans.append([start, _tick_now()])
			start = -1
	var max_len := 0.0
	var min_gap := 999.0
	for i in spans.size():
		max_len = maxf(max_len, (spans[i][1] - spans[i][0]) / 60.0)
		if i > 0:
			min_gap = minf(min_gap, (spans[i][0] - spans[i - 1][1]) / 60.0)
	var share := shaking_ticks / (60.0 * 40.0)
	_log.append("shake-only brain, 40 s on the thigh: %d shakes, longest %.2f s (rule %.1f incl. %.1f s brace), shortest pause %.2f s (rule %.1f), shaking %.0f%% of the time" % [spans.size(), max_len, s.shake_max_duration, s.shake_telegraph, min_gap, s.shake_cooldown, share * 100.0])
	_metric("boss_spam_shake_share", share, "lower")
	_check(spans.size() >= 3, "too few shakes")
	_check(max_len <= s.shake_max_duration + 0.05, "a shake lasted %.2f s" % max_len)
	_check(min_gap >= s.shake_cooldown - 0.05, "shake chained after %.2f s" % min_gap)
	_check(share < 0.45, "shaking %.0f%% of the time" % (share * 100.0))


## Grabs a Valus segment from behind (like _grab_behind, for the Valus world).
func _grab_valus(w: Dictionary, bone: StringName, along: float, dist := 1.25) -> void:
	var s: Valus = w.valus
	var p: PlayerCharacter = w.player
	var seg := s._seg_by_bone[bone] as BodySegment
	for attempt in 4:
		p.global_position = seg.global_transform * Vector3(0, along, dist)
		p.velocity = Vector3.ZERO
		p.facing = -s.global_basis.z
		p.actions.view_basis = Basis.looking_at(-s.global_basis.z)
		p.actions.grab_held = true
		p.reset_physics_interpolation()
		await _ticks(3)
		if p.is_climbing():
			return
		await _wait_planted(s, 0)


func test_climb_route_is_reachable() -> void:
	var w := await _setup_valus(7, true)
	var s: Valus = w.valus
	var p: PlayerCharacter = w.player
	var bot := ValusBot.new()
	_world.add_child(bot)
	bot.setup(p, s, w.encounter)
	var regions: Array[StringName] = []
	var reached := false
	for i in 60 * 90:
		await _ticks(1)
		var r := s.region_of(p)
		if r != &"" and (regions.is_empty() or regions[-1] != r):
			regions.append(r)
		if bot.phase == ValusBot.Phase.STRIKE and p.is_climbing() and p.grip.world_point().distance_to(s.weak_point.world_point()) < s.weak_point.radius:
			reached = true
			break
	var t := bot.time
	_log.append("frozen Valus, route %s; weak point in reach after %.1f s, stamina %.0f" % [" -> ".join(PackedStringArray(regions)), t, p.stamina.value])
	_metric("boss_route_time", t, "lower")
	_check(reached, "did not get the weak point within reach")
	for r in [&"calf", &"thigh", &"shoulder", &"head"]:
		_check(r in regions, "route missed %s" % r)
	_check(&"pelvis" in regions or &"back" in regions, "route missed the hips / back")


func test_weakpoint_moves_with_bone() -> void:
	var w := await _setup_valus()
	var s: Valus = w.valus
	s.debug_override = &"manual"
	s.debug_desired_speed = 1.4
	s.debug_desired_turn = 0.2
	var wp := s.weak_point
	var head := s._seg_by_bone[&"head"] as BodySegment
	var start := wp.world_point()
	var max_err := 0.0
	var node_err := 0.0
	for i in 60 * 8:
		await _ticks(1)
		max_err = maxf(max_err, wp.world_point().distance_to(head.target_transform * Valus.WEAK_POINT_LOCAL))
		# The visual node is a child of the segment: it follows the same bone.
		node_err = maxf(node_err, (head.global_transform * wp.position).distance_to(wp.global_position))
	var moved := wp.world_point().distance_to(start)
	_log.append("boss walked and turned 8 s: weak point moved %.1f m, error vs head bone %.6f m, visual node vs its segment %.6f m" % [moved, max_err, node_err])
	_check(moved > 3.0, "weak point did not move with the boss")
	_check(max_err < 1e-4, "weak point drifts from the bone")
	_check(node_err < 1e-3, "weak point visual not attached to the segment")


func test_weakpoint_rejects_invalid_hits() -> void:
	var w := await _setup_valus(7, true)
	var s: Valus = w.valus
	var p: PlayerCharacter = w.player
	var wp := s.weak_point
	var at := wp.world_point()
	var r1 := wp.try_hit(at, 1.0, &"stomp")
	var r2 := wp.try_hit(at + Vector3(0, 0, 3.0), 1.0, &"sword")
	wp.set_protected(true)
	var r3 := wp.try_hit(at, 1.0, &"sword")
	wp.set_protected(false)
	# A real swing from the ground, far below.
	_start_combat(s)
	p.global_position = s.global_transform * Vector3(0, 0.95, 8.0)
	p.reset_physics_interpolation()
	await _ticks(10)
	var r4 := await _sword_strike(p, 1.2)
	var hp := wp.health
	_log.append("stomp on it: %s; 3 m off: %s; protected: %s; sword from the ground: %s; health %.0f" % [r1.reason, r2.reason, r3.reason, r4.get("reason", "?"), hp])
	_check(not r1.accepted and r1.reason == &"not_a_sword", "accepted a non-sword hit")
	_check(not r2.accepted and r2.reason == &"out_of_range", "accepted a hit out of range")
	_check(not r3.accepted and r3.reason == &"protected", "accepted a hit while protected")
	_check(not r4.get("accepted", false), "a swing from the ground counted")
	_check(hp == wp.max_health, "health changed by invalid hits (%.0f)" % hp)


func test_weakpoint_accepts_valid_sword_hit() -> void:
	var w := await _setup_valus(7, true)
	var s: Valus = w.valus
	var p: PlayerCharacter = w.player
	_start_combat(s)
	await _stand_on_head(w)
	# Crouch and hold on to the fur on the head (grab while standing on it).
	p.actions.grab_held = true
	await _ticks(5)
	var gripping := p.is_climbing()
	var r := await _sword_strike(p, 1.25)
	_log.append("standing on the head: %s, grip on fur under the feet %s; full charge strike: %s, damage %.0f, weak point %.0f/%.0f" % [s.region_of(p), str(gripping), r.get("reason", "?"), r.get("damage", 0.0), s.weak_point.health, s.weak_point.max_health])
	_check(gripping, "could not grip the fur on the head")
	_check(r.get("accepted", false), "valid strike rejected (%s)" % r.get("reason", "none"))
	_check(absf(float(r.get("damage", 0.0)) - s.weak_point.damage_max) < 0.01, "full charge did not do full damage")


func test_weakpoint_damage_advances_progress() -> void:
	var w := await _setup_valus(7, true)
	var s: Valus = w.valus
	var p: PlayerCharacter = w.player
	_start_combat(s)
	await _stand_on_head(w)
	p.actions.grab_held = true
	await _ticks(5)
	var progress := [s.weak_point.progress()]
	var jab := await _sword_strike(p, 0.0)
	progress.append(s.weak_point.progress())
	await _ticks(40)
	for i in 3:
		p.stamina.value = 100.0
		await _sword_strike(p, 1.25)
		progress.append(snappedf(s.weak_point.progress(), 0.001))
		await _ticks(40)
	_log.append("progress after jab (%.0f dmg) and full strikes: %s; state %s, encounter %s" % [jab.get("damage", 0.0), str(progress), s.weak_point.state_name(), s.encounter_name()])
	_check(progress[1] > progress[0], "a jab did not count")
	_check(progress[2] > progress[1] and progress[3] > progress[2], "strikes did not advance progress")
	_check(s.weak_point.state == WeakPoint.State.DESTROYED and progress[-1] >= 1.0, "weak point not destroyed")
	_check(s.encounter == Valus.Encounter.DEFEATED, "boss not defeated by its weak point")


func test_rest_surface_restores_stamina() -> void:
	var w := await _setup_valus(7, true)
	var s: Valus = w.valus
	var p: PlayerCharacter = w.player
	var chest := s._seg_by_bone[&"chest"] as BodySegment
	p.global_position = chest.target_transform * Vector3(1.5, 2.8 + 1.0, 0.6)
	p.reset_physics_interpolation()
	await _ticks(20)
	var support: Object = p.get_support_body()
	var tag := &""
	var hit := ClimbQuery.ray(p.get_world_3d().direct_space_state, p.global_position, p.global_position + Vector3.DOWN * 2.0, [p.get_rid()])
	if not hit.is_empty():
		var owner_id: int = (hit.collider as CollisionObject3D).shape_find_owner(int(hit.get("shape", 0)))
		var shape_node := (hit.collider as CollisionObject3D).shape_owner_get_owner(owner_id)
		if shape_node and shape_node.has_meta(&"surface"):
			tag = shape_node.get_meta(&"surface")
	p.stamina.value = 15.0
	p.stamina.drain(0.01)
	var t := 0
	while p.stamina.value < 90.0 and t < 600:
		await _ticks(1)
		t += 1
	_log.append("standing on %s (%s, surface tag '%s'), no grip: stamina 15 -> 90 in %.1f s; region %s" % [_segment_name(support), p.get_display_state(), tag, t / 60.0, s.region_of(p)])
	_check(s.owns_body(support) and s.region_of(p) == &"shoulder", "not standing on the shoulders")
	_check(tag == &"rest", "surface not tagged as a rest surface")
	_check(t < 240, "stamina did not come back while resting (%.1f s)" % (t / 60.0))
	_check(not p.is_climbing(), "had to hold on to rest")


func _segment_name(o: Object) -> String:
	return String((o as BodySegment).bone_name) if o is BodySegment else str(o)


func test_boss_reacts_to_player_on_body() -> void:
	var w := await _setup_valus()
	var s: Valus = w.valus
	var p: PlayerCharacter = w.player
	_start_combat(s)
	var seen := {}
	var cases := [[&"shin_l", -1.8, &"calf", 1.25], [&"spine", 1.0, &"back", 1.7]]
	for c in cases:
		p.respawn()
		await _ticks(5)
		await _grab_valus(w, c[0], c[1], c[3])
		var kinds := {}
		for i in 60 * 12:
			p.stamina.value = 100.0
			await _ticks(1)
			if p.is_climbing():
				kinds[s.intent.kind] = true
		seen[c[2]] = kinds.keys()
	# On the head: shake / protect.
	p.respawn()
	await _ticks(5)
	s.debug_override = &"frozen"
	await _stand_on_head(w)
	p.actions.grab_held = true
	await _ticks(5)
	s.debug_override = &""
	var head_kinds := {}
	var protected := false
	for i in 60 * 12:
		p.stamina.value = 100.0
		await _ticks(1)
		head_kinds[s.intent.kind] = true
		protected = protected or s.weak_point.state == WeakPoint.State.PROTECTED
	seen[&"head"] = head_kinds.keys()
	_log.append("intents while the player was on: %s; weak point closed while on the head: %s" % [str(seen), str(protected)])
	_check(ColossusIntent.REPOSITION in seen[&"calf"], "no leg movement while on the calf")
	_check(ColossusIntent.SHAKE_PLAYER in seen[&"back"], "no shake while on the back")
	_check(ColossusIntent.SHAKE_PLAYER in seen[&"head"] or Valus.PROTECT in seen[&"head"], "no reaction to the player on the head")
	_check(protected, "weak point never protected with the player on it")


func test_player_can_fall_and_reenter_climb_route() -> void:
	var w := await _setup_valus(7, true)
	var s: Valus = w.valus
	var p: PlayerCharacter = w.player
	var bot := ValusBot.new()
	_world.add_child(bot)
	bot.setup(p, s, w.encounter)
	var dropped := false
	var regrabbed := false
	var max_h := 0.0
	for i in 60 * 120:
		await _ticks(1)
		if not dropped and bot.phase == ValusBot.Phase.CLIMB_BODY and p.global_position.y - s.global_position.y > 6.0:
			p.stamina.value = 0.0   # exhausted: the grip goes
			p.stamina.drain(1.0)
			dropped = true
		if dropped and bot.stats.falls > 0 and bot.stats.grabs >= 2 and p.is_climbing():
			max_h = maxf(max_h, p.global_position.y - s.global_position.y)
			regrabbed = true
			if max_h > 8.0:
				break
	_log.append("dropped from the thigh/hips (exhausted): falls %d, grabs %d, climbing again %s up to %.1f m; events: %s" % [bot.stats.falls, bot.stats.grabs, str(regrabbed), max_h, " | ".join(bot.events.slice(-6))])
	_check(dropped, "never got high enough to drop")
	_check(bot.stats.falls >= 1, "fall not detected")
	_check(regrabbed and max_h > 8.0, "could not get back onto the route")


func test_agro_avoids_colossus_legs() -> void:
	var w := await _setup_valus()
	var s: Valus = w.valus
	var h: Horse = w.horse
	s.debug_override = &"walk"
	_start_combat(s)
	var d := ScriptedHorseDriver.new()
	_world.add_child(d)
	h.set_rider(d)
	var hits := 0
	var min_d := 99.0
	# Ride straight at the Valus and through where it stands, several passes.
	for pass_i in 3:
		var from := s.global_position + Vector3(0, 0, 32.0).rotated(Vector3.UP, pass_i * 2.0)
		h.teleport(Vector3(from.x, 0, from.z), atan2(-(s.global_position.x - from.x), -(s.global_position.z - from.z)))
		d.direction = PlayerCharacter._flat_dir(s.global_position - from, Vector3.FORWARD)
		d.hold_speed = 6.0
		for i in 60 * 10:
			await _ticks(1)
			for k in h.get_slide_collision_count():
				if h.get_slide_collision(k).get_collider() is BodySegment:
					hits += 1
			for leg in s.loco.legs:
				min_d = minf(min_d, _flat_dist(h.global_position, leg.foot_pos))
	_log.append("3 passes at 6 m/s straight at the walking Valus: %d body contacts, closest to a foot %.1f m" % [hits, min_d])
	_check(hits == 0, "rode into the colossus (%d ticks)" % hits)
	_check(min_d > 1.0, "went under a foot (%.1f m)" % min_d)


func test_agro_reacts_to_stomp_danger() -> void:
	var w := await _setup_valus()
	var s: Valus = w.valus
	var p: PlayerCharacter = w.player
	var h: Horse = w.horse
	_start_combat(s)
	s.brain = SpamBrain.new(Valus.STOMP)
	_stand_by_foot(w, 0)
	var foot := s.loco.legs[0].plant_pos
	# Close to the foot (inside the danger zone, which is the shockwave plus a margin).
	h.teleport(foot + s.global_basis.x * 6.5 + s.global_basis.z * 1.5, 0.0)
	var responses := {}
	var impact := [false, -1.0]
	var at_start := [-1.0]
	s.attack_started.connect(func(_a: ColossusAttack) -> void:
		if at_start[0] < 0.0:
			at_start[0] = _flat_dist(h.global_position, _stomp_point_of(s)))
	s.attack_phase_changed.connect(func(a: ColossusAttack) -> void:
		if a.kind == Valus.STOMP and a.phase == ColossusAttack.Phase.RECOVERY and not impact[0]:
			impact[0] = true
			impact[1] = _flat_dist(h.global_position, s._slam_point))
	for i in 60 * 6:
		p.health = 100.0
		await _ticks(1)
		responses[h.controller.danger_response] = true
		if impact[0]:
			break
	var at_impact: float = impact[1]
	# Ridden: a rider steering straight into a winding-up stomp is refused.
	await _ticks(60 * 8)
	var d := ScriptedHorseDriver.new()
	_world.add_child(d)
	h.set_rider(d)
	h.teleport(s.global_position + s.global_basis.x * 22.0, 0.0)
	var refused := false
	var min_d := 99.0
	var started := false
	for i in 60 * 14:
		p.health = 100.0
		if i % 20 == 0:
			_stand_by_foot(w, 0)
		var zones := s.get_danger_zones()
		if not zones.is_empty():
			var c: Vector3 = zones[0][0]
			if not started:
				# The rider points Agro straight at the coming stomp from just outside it.
				started = true
				var out := PlayerCharacter._flat_dir(h.global_position - c, s.global_basis.x)
				var from := c + out * (float(zones[0][1]) + h.controller.danger_margin + 3.0)
				h.teleport(Vector3(from.x, 0, from.z), atan2(out.x, out.z))
			d.direction = PlayerCharacter._flat_dir(c - h.global_position, Vector3.FORWARD)
			d.hold_speed = 6.0
			min_d = minf(min_d, _flat_dist(h.global_position, c) - float(zones[0][1]))
		elif started:
			break
		await _ticks(1)
		refused = refused or h.controller.danger_response == "refuse"
	_log.append("riderless Agro beside a stomp: responses %s, %.1f m from the stomp when it was decided -> %.1f m at impact (shockwave %.0f m); ridden into a wind-up: refused %s, closest to the zone edge %.1f m" % [str(responses.keys()), at_start[0], at_impact, s.shockwave_radius, str(refused), min_d])
	_check(responses.has("flee"), "did not flee the stomp")
	_check(at_impact > at_start[0] + 1.0, "did not get away from the stomp (%.1f -> %.1f m)" % [at_start[0], at_impact])
	_check(at_impact > 3.0, "under the foot at impact (%.1f m)" % at_impact)
	_check(refused and min_d > -1.0, "rider could steer into the stomp (%.1f m)" % min_d)


func _stomp_point_of(s: Valus) -> Vector3:
	var z := s.get_danger_zones()
	return z[0][0] if not z.is_empty() else s.loco.legs[0].plant_pos


func test_player_death_resets_encounter() -> void:
	var w := await _setup_valus()
	var s: Valus = w.valus
	var p: PlayerCharacter = w.player
	var h: Horse = w.horse
	var e: BossEncounter = w.encounter
	_start_combat(s)
	s.weak_point.try_hit(s.weak_point.world_point(), 1.0, &"sword")
	h.teleport(Vector3(20, 0, 10), 1.0)
	p.global_position = Vector3(5, 0.95, 5)
	p.stamina.value = 30.0
	await _ticks(10)
	p.apply_hit(500.0, Vector3.ZERO, 0.0, &"test")
	var dead := p.dead
	var banner := ""
	for i in int(e.death_pause * 60.0) - 10:
		await _ticks(1)
		if e.banner != "":
			banner = e.banner
	var still_dead := p.dead
	await _ticks(30)
	var hpos := _flat_dist(h.global_position, ValusArena.HORSE_START)
	_log.append("dead %s, banner '%s', still dead before the pause ends %s; after reset: resets %d, player HP %.0f stamina %.0f at %.1f m from spawn, boss %s, weak point %.0f/%.0f, horse %.1f m from its start" % [str(dead), banner, str(still_dead), e.resets, p.health, p.stamina.value, p.global_position.distance_to(ValusArena.PLAYER_START), s.encounter_name(), s.weak_point.health, s.weak_point.max_health, hpos])
	_check(dead and banner == "YOU DIED" and still_dead, "no death pause")
	_check(e.resets == 1, "encounter not reset")
	_check(not p.dead and p.health == p.fall.max_health and p.stamina.value == p.stamina.max_value, "player not restored")
	_check(p.global_position.distance_to(ValusArena.PLAYER_START) < 1.5, "player not back at the spawn")
	_check(s.encounter == Valus.Encounter.DORMANT and s.weak_point.health == s.weak_point.max_health, "boss not reset")
	_check(hpos < 0.5, "Agro not back at its start")


func test_boss_can_be_defeated() -> void:
	var w := await _setup_valus(7, true)
	var s: Valus = w.valus
	var p: PlayerCharacter = w.player
	var e: BossEncounter = w.encounter
	_start_combat(s)
	await _stand_on_head(w)
	p.actions.grab_held = true
	await _ticks(5)
	var n := 0
	while s.encounter != Valus.Encounter.DEFEATED and n < 6:
		p.stamina.value = 100.0
		await _sword_strike(p, 1.25)
		await _ticks(30)
		n += 1
	await _ticks(5)
	_log.append("%d full strikes: encounter %s, banner '%s', weak point %s" % [n, s.encounter_name(), e.banner, s.weak_point.state_name()])
	_check(s.encounter == Valus.Encounter.DEFEATED, "not defeated")
	_check(e.banner == "COLOSSUS DEFEATED", "no defeat banner")
	_check(n == 3, "expected 3 full strikes, took %d" % n)


func test_boss_stops_attacking_after_defeat() -> void:
	var w := await _setup_valus()
	var s: Valus = w.valus
	var p: PlayerCharacter = w.player
	var rec := _record_attacks(s)
	_start_combat(s)
	_stand_by_foot(w, 0)
	# Defeat it in the middle of a stomp wind-up.
	for i in 60 * 6:
		await _ticks(1)
		if s.attack != null and s.attack.phase == ColossusAttack.Phase.TELEGRAPH:
			break
	var mid_attack := s.attack != null and not s.attack.is_done()
	for k in 3:
		s.weak_point.try_hit(s.weak_point.world_point(), 1.0, &"sword")
	var starts := [0]
	s.attack_started.connect(func(_a: ColossusAttack) -> void: starts[0] += 1)
	var hits_before: int = rec.hits.size()
	var hp := p.health
	var aggressive := {}
	for i in 60 * 20:
		if i % 30 == 0:
			_stand_by_foot(w, 0)
		await _ticks(1)
		aggressive[s.intent.kind] = true
		for v in s.hit_volumes.values():
			_check(not (v as HitVolume).active, "hit volume active after defeat")
	var still := s.loco.speed
	_log.append("defeated mid wind-up (%s): new attacks %d, hits after %d, HP %.0f -> %.0f, intents %s, speed %.2f, pelvis drop %.1f m" % [str(mid_attack), starts[0], rec.hits.size() - hits_before, hp, p.health, str(aggressive.keys()), still, s.extra_pelvis_drop])
	_check(mid_attack, "test did not catch an attack in progress")
	_check(starts[0] == 0, "attacked after defeat")
	_check(rec.hits.size() == hits_before and p.health >= hp, "damaged the player after defeat")
	_check(aggressive.keys() == [ColossusIntent.IDLE], "non-idle intents after defeat: %s" % str(aggressive.keys()))
	_check(s.extra_pelvis_drop > 2.0, "no kneeling sequence")


func test_grip_survives_defeat_sequence() -> void:
	var w := await _setup_valus(7, true)
	var s: Valus = w.valus
	var p: PlayerCharacter = w.player
	_start_combat(s)
	await _stand_on_head(w)
	p.actions.grab_held = true
	await _ticks(5)
	s.weak_point.try_hit(s.weak_point.world_point(), 1.0, &"sword")
	s.weak_point.try_hit(s.weak_point.world_point(), 1.0, &"sword")
	var r := await _sword_strike(p, 1.25)
	var defeated := s.encounter == Valus.Encounter.DEFEATED
	var max_err := 0.0
	var max_step := 0.0
	var prev := p.global_position
	var y0 := p.global_position.y
	for i in 60 * 9:
		await _ticks(1)
		if not p.is_climbing():
			break
		max_err = maxf(max_err, _surface_error(p))
		var stepd := p.global_position.distance_to(prev)
		if stepd > 0.1 and OS.get_environment("TRACE") != "":
			_log.append("  jump %.3f at %d: %s -> %s, grip %s n %s up %s, boss %s pelvis %.2f" % [stepd, i, str(prev), str(p.global_position), _segment_name(p.grip.body), str(p.grip.world_normal()), str(p.climb_up), s.encounter_name(), s.extra_pelvis_drop])
		max_step = maxf(max_step, stepd)
		prev = p.global_position
	var lowered := y0 - p.global_position.y
	# After the kneel the body is still: let go and step off safely.
	var settled := s.loco.speed < 0.01
	p.actions.grab_held = false
	await _ticks(120)
	_log.append("final strike %s, defeated %s; through 9 s of kneeling: still gripping %s, carried down %.1f m, max step %.3f m/tick, anchor error %.6f m; body settled %s; after letting go: %s, HP %.0f" % [r.get("reason", "?"), str(defeated), str(p.is_climbing() or p.state != PlayerCharacter.State.AIR), lowered, max_step, max_err, str(settled), p.get_display_state(), p.health])
	_check(defeated, "not defeated by the final strike")
	_check(lowered > 1.5, "the kneel did not carry the player down")
	_check(max_step < 0.1, "player jumped during the defeat sequence")
	_check(max_err < 0.08, "anchor left the surface during the defeat sequence (%.3f m)" % max_err)
	_check(not p.dead, "player died after the defeat")


func test_scripted_driver_can_complete_boss() -> void:
	var w := await _setup_valus()
	var bot := ValusBot.new()
	_world.add_child(bot)
	bot.setup(w.player, w.valus, w.encounter)
	var cam: PlayerCamera = w.camera
	var cam_inside := 0
	for i in 60 * 300:
		await _ticks(1)
		if cam._inside(cam.get_world_3d().direct_space_state, cam.global_position, Layers.COLOSSUS, 0.05):
			cam_inside += 1
		if bot.phase == ValusBot.Phase.DONE:
			break
	var r := bot.result
	_log.append("bot result: %s in %.1f s; %s; boss %s; camera inside the colossus %d frames" % ["WIN" if r.get("won", false) else "NO WIN", r.get("time", -1.0), str(r.get("stats", {})), str(r.get("boss", {})), cam_inside])
	_metric("boss_scripted_win_time", r.get("time", 999.0), "lower")
	_check(r.get("won", false), "the scripted driver did not beat the Valus: %s" % " | ".join(bot.events.slice(-8)))
	_check(cam_inside == 0, "camera inside the colossus (%d frames)" % cam_inside)


func test_boss_simulation_independent_of_render_fps() -> void:
	var exe := OS.get_executable_path()
	var results := {}
	var rates := [30, 60, 90, 120, 144, 240]
	for fps in rates:
		var out_path := ProjectSettings.globalize_path("res://tests/output/boss_fps_%d.json" % fps)
		var output := []
		var code := OS.execute(exe, ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--fixed-fps", str(fps), "--quit-after", "400000", "res://tests/fps_scenario.tscn", "--", "--scenario=boss", "--out=" + out_path], output, true)
		if code != 0 or not FileAccess.file_exists(out_path):
			_check(false, "boss scenario at %d fps failed (code %d)" % [fps, code])
			return
		results[fps] = JSON.parse_string(FileAccess.get_file_as_string(out_path))
	var ref: Dictionary = results[60]
	var max_diff := 0.0
	var frames := []
	for fps in rates:
		var r: Dictionary = results[fps]
		frames.append(int(r.frames))
		for k in ref:
			if k == "frames":
				continue
			if ref[k] is Array:
				for j in (ref[k] as Array).size():
					max_diff = maxf(max_diff, absf(float(r[k][j]) - float(ref[k][j])))
			else:
				max_diff = maxf(max_diff, absf(float(r[k]) - float(ref[k])))
	_log.append("whole fight (bot) at render %s fps: won %s at tick %d, frames %s, max state difference %.8f" % [str(rates), str(ref.won), int(ref.tick), str(frames), max_diff])
	_metric("boss_fps_max_diff", max_diff, "lower")
	_check(int(ref.won) == 1, "the reference run did not win")
	_check(max_diff < 1e-4, "boss fight depends on the render rate (diff %.6f)" % max_diff)


func test_boss_cost_stays_within_budget() -> void:
	Fx.enabled = true
	var w := await _setup_valus()
	Fx.enabled = true
	var bot := ValusBot.new()
	_world.add_child(bot)
	bot.setup(w.player, w.valus, w.encounter)
	await _ticks(60 * 12)   # approaching and dodging in combat
	Perf.take()
	var fx0 := Fx.spawned
	var ticks := 60 * 25
	var physics_ms := 0.0
	var physics_max := 0.0
	for i in ticks:
		await _ticks(1)
		var pm := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		physics_ms += pm
		physics_max = maxf(physics_max, pm)
	var m := Perf.take()
	var u: Dictionary = m.usec
	var q: Dictionary = m.queries
	var per := func(k: StringName) -> float: return float(u.get(k, 0)) / ticks
	var qp := func(k: StringName) -> float: return float(q.get(k, 0)) / ticks
	var colossus: float = per.call(&"colossus")
	var total := 0.0
	for k in [&"colossus", &"player", &"horse", &"encounter"]:
		total += per.call(k)
	_log.append("Valus fight (bot climbing, 25 s): colossus %.1f us/tick = brain %.1f + combat %.1f + hits %.1f + attack pose %.1f + locomotion %.1f + IK %.1f; player %.1f; Agro %.1f; camera %.1f us/frame; vfx %.1f (%d effects); queries/tick: climb %.2f, horse %.2f, camera %.2f, boss hit tests %.2f, sword %.3f" % [colossus, per.call(&"brain"), per.call(&"boss_combat"), per.call(&"boss_hits"), per.call(&"boss_pose"), per.call(&"locomotion"), per.call(&"ik"), per.call(&"player"), per.call(&"horse"), per.call(&"camera"), per.call(&"vfx"), Fx.spawned - fx0, qp.call(&"climb_rays"), qp.call(&"horse_rays"), qp.call(&"camera_queries"), qp.call(&"boss_hit_tests"), qp.call(&"sword_checks")])
	_log.append("whole physics tick (engine monitor, incl. physics server): mean %.3f ms, max %.3f ms" % [physics_ms / ticks, physics_max])
	_metric("boss_physics_tick_ms", physics_ms / ticks, "lower")
	_metric("boss_colossus_us", colossus, "lower")
	_metric("boss_brain_us", per.call(&"brain"), "lower")
	_metric("boss_hits_us", per.call(&"boss_hits"), "lower")
	_check(colossus < 500.0, "Valus logic too expensive: %.0f us/tick" % colossus)
	Fx.enabled = false


## Everything that ran before the Etap 5 tests in this process passed.
func all_existing_tests_still_pass() -> void:
	var ran := 0
	var failed := PackedStringArray()
	for n in _pre_boss_results:
		ran += 1
		if not _pre_boss_results[n]:
			failed.append(n)
	_log.append("%d earlier tests (Milestone 1, Etap 2-4) ran in this run, %d failed %s" % [ran, failed.size(), str(failed) if failed.size() > 0 else ""])
	_check(failed.is_empty(), "earlier tests failed: %s" % str(failed))


# --- ETAP 6: Quadratus, bow and arrows ------------------------------------------------------

func _setup_quadratus(seed_value := 11, frozen := false) -> Dictionary:
	Sfx.enabled = false
	Fx.enabled = false
	_world = Node3D.new()
	_world.name = "World_" + _current
	add_child(_world)
	var w := QuadratusArena.build_encounter(_world, false, seed_value)
	if frozen:
		(w.quadratus as Quadratus).debug_override = &"frozen"
	await _ticks(2)
	return w


## Bare Quadratus (manual movement) on flat ground or the test course.
func _setup_quad_walk(terrain := false) -> Quadratus:
	Sfx.enabled = false
	Fx.enabled = false
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
	if terrain:
		TerrainKit.build_course(_world, Vector3(0, 0, -6))
	var q := Quadratus.new()
	q.debug_override = &"manual"
	q.effects_enabled = false
	_world.add_child(q)
	await _ticks(2)
	return q


## Player behind Quadratus (``dist`` m behind the hind legs, on the side of leg ``leg``).
func _stand_behind(w: Dictionary, leg := 2, dist := 13.0) -> void:
	var q: Quadratus = w.quadratus
	var p: PlayerCharacter = w.player
	var side := -1.0 if leg == 2 else 1.0
	var pos := q.global_transform * Vector3(side * 3.2, 0, 5.0 + dist)
	p.global_position = Vector3(pos.x, q.global_position.y + 0.95, pos.z)
	p.velocity = Vector3.ZERO
	p.reset_physics_interpolation()
	p.set_weapon(PlayerCharacter.Weapon.BOW)


## Aims the bow along ``dir`` from the bow itself (what is computed is what is shot).
func _aim_bow(p: PlayerCharacter, dir: Vector3) -> void:
	p.actions.view_basis = Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.98 else Vector3.FORWARD)
	p.actions.aim_origin = p.bow.bow_point(p)


## Lead direction at an ArrowTarget for a full-draw arrow (the bot's solver).
func _lead_dir(p: PlayerCharacter, t: ArrowTarget) -> Vector3:
	var from := p.bow.bow_point(p)
	var speed := p.bow.speed_for(1.0)
	var pt := t.world_point()
	var v := (pt - t.previous_frame() * t.local_point) / DT
	var flight := from.distance_to(pt) / speed
	var aim := pt
	for k in 3:
		aim = pt + v * flight
		flight = from.distance_to(aim) / (speed * 0.98)
	return PlayerBow.launch_direction(from, aim, speed)


## Draws to full, waits for an exposed hind sole and shoots it. Returns the impact info
## of that arrow ({} if no shot within ``seconds``).
func _shoot_exposed_sole(w: Dictionary, seconds := 30.0) -> Dictionary:
	var q: Quadratus = w.quadratus
	var p: PlayerCharacter = w.player
	var impacts := []
	var sys := ArrowSystem.of(p)
	var cb := func(info: Dictionary) -> void: impacts.append(info)
	sys.impact.connect(cb)
	p.actions.attack_held = true
	var shot := false
	for i in int(seconds * 60.0):
		await _ticks(1)
		if not shot:
			var best: ArrowTarget = null
			for t in q.arrow_targets:
				var leg := q.loco.legs[int(t.tag)]
				if t.enabled and leg.swing_t < 0.55:
					best = t
			if best:
				var d := _lead_dir(p, best)
				if d != Vector3.ZERO:
					_aim_bow(p, d)
					if p.bow.state == PlayerBow.State.AIM:
						p.actions.attack_held = false
						shot = true
			else:
				_aim_bow(p, (q.global_transform * Vector3(0, 1.5, 5.0) - p.bow.bow_point(p)).normalized())
		elif not impacts.is_empty():
			break
	sys.impact.disconnect(cb)
	p.actions.attack_held = false
	return impacts[0] if not impacts.is_empty() else {}


func _hip_height(q: Quadratus, i: int) -> float:
	return q.loco.hip_world(q.loco.legs[i]).y - q.loco.legs[i].plant_pos.y


func test_quadratus_four_leg_locomotion_is_stable() -> void:
	var q := await _setup_quad_walk()
	var start := q.global_position
	var order: Array[int] = []
	var last_steps := q.loco.step_count
	var max_swing := 0
	var min_planted := 4
	var max_tilt := 0.0
	var h_min := 99.0
	var h_max := 0.0
	var steps_after_stop := 0
	var stop_steps := 0
	for i in 60 * 36:
		if i == 30:
			q.debug_desired_speed = 1.3
		if i == 60 * 18:
			q.debug_desired_turn = 0.12
		if i == 60 * 24:
			q.debug_desired_speed = 0.0
			q.debug_desired_turn = 0.0
		await _ticks(1)
		if q.loco.step_count != last_steps:
			last_steps = q.loco.step_count
			if i < 60 * 18:
				order.append(q.loco.last_step_leg)
		var sw := q.loco.swinging_count()
		max_swing = maxi(max_swing, sw)
		min_planted = mini(min_planted, 4 - sw)
		if i > 60 * 2:
			max_tilt = maxf(max_tilt, maxf(absf(q.loco.body_pitch), absf(q.loco.body_roll)))
			var h := q.loco.pelvis.y - q.global_position.y
			h_min = minf(h_min, h)
			h_max = maxf(h_max, h)
		if i == 60 * 32:
			stop_steps = q.loco.step_count
	steps_after_stop = q.loco.step_count - stop_steps
	var seq := [2, 0, 3, 1]
	var in_order := 0
	for k in range(1, order.size()):
		if seq[(seq.find(order[k - 1]) + 1) % 4] == order[k]:
			in_order += 1
	var ratio := float(in_order) / maxf(1.0, order.size() - 1)
	var walked := _flatv(q.global_position - start).length()
	_log.append("36 s walk/turn/stop: walked %.1f m, %d steps, gait order RL-FL-RR-FR %.0f%%, max swinging %d, min planted %d, max tilt %.3f rad, hip height %.2f..%.2f m, reach error %.4f m, steps in the last 4 s still %d" % [walked, q.loco.step_count, ratio * 100.0, max_swing, min_planted, max_tilt, h_min, h_max, q.foot_stats.reach_max, steps_after_stop])
	_metric("quad_gait_order_ratio", ratio, "higher")
	_check(walked > 25.0, "did not walk (%.1f m)" % walked)
	_check(ratio > 0.9, "steps not in the four-beat order (%.0f%%)" % (ratio * 100.0))
	_check(max_swing <= 2 and min_planted >= 2, "too many legs in the air at once")
	_check(max_tilt < 0.15, "body tilts on flat ground (%.3f)" % max_tilt)
	_check(h_max - h_min < 0.5, "body bobs too much (%.2f m)" % (h_max - h_min))
	_check(q.foot_stats.reach_max < 0.05, "IK out of reach (%.3f m)" % q.foot_stats.reach_max)
	_check(steps_after_stop == 0, "keeps stepping after it stopped")


func _flatv(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func test_quadratus_feet_do_not_slide() -> void:
	var q := await _setup_quad_walk()
	q.reset_foot_stats()
	for i in 60 * 30:
		q.debug_desired_speed = 1.3 if i > 30 and i < 60 * 24 else 0.0
		q.debug_desired_turn = 0.15 if i > 60 * 10 and i < 60 * 18 else 0.0
		await _ticks(1)
	var mean: float = q.foot_stats.slip_sum / maxf(1.0, q.foot_stats.contact_ticks)
	_log.append("30 s walking + turning: planted-foot slip max %.4f m/s, mean %.5f m/s over %d foot-ticks" % [q.foot_stats.slip_max, mean, q.foot_stats.contact_ticks])
	_metric("quad_slip_max", q.foot_stats.slip_max, "lower")
	_check(q.foot_stats.slip_max < 0.02, "planted feet slide (%.4f m/s)" % q.foot_stats.slip_max)


func test_quadratus_handles_uneven_ground() -> void:
	var q := await _setup_quad_walk(true)
	q.reset_foot_stats()
	var max_pitch := 0.0
	var sole_err := 0.0
	var max_reach := 0.0
	for i in 60 * 40:
		q.debug_desired_speed = 1.3 if i > 30 and i < 60 * 34 else 0.0
		await _ticks(1)
		max_pitch = maxf(max_pitch, q.loco.body_pitch)
		if i % 10 == 0:
			for leg in q.loco.legs:
				if leg.is_planted():
					var g := _ground_at(leg.plant_pos)
					if not g.is_empty():
						sole_err = maxf(sole_err, absf((g.position as Vector3).y - leg.plant_pos.y))
			max_reach = maxf(max_reach, q.foot_stats.reach_max)
	var climbed := q.global_position.y
	_log.append("course (10 deg ramp, bumps, 0.8 m step down): reached z %.1f, height %.2f m, max body pitch %.3f rad (ramp %.3f), planted sole vs ground max %.3f m, slip max %.4f m/s, reach error %.3f m" % [q.global_position.z, climbed, max_pitch, deg_to_rad(10.0), sole_err, q.foot_stats.slip_max, max_reach])
	_metric("quad_terrain_sole_err", sole_err, "lower")
	_check(q.global_position.z < -30.0, "did not get over the course")
	_check(max_pitch > 0.12, "body does not pitch with the slope (%.3f)" % max_pitch)
	_check(sole_err < 0.05, "planted feet not on the ground (%.3f m)" % sole_err)
	_check(max_reach < 0.1, "legs could not reach the ground (%.3f m)" % max_reach)
	_check(q.foot_stats.slip_max < 0.03, "feet slide on uneven ground")


func test_quadratus_weight_shifts_between_legs() -> void:
	var q := await _setup_quad_walk()
	var lo := [9.0, 9.0, 9.0, 9.0]
	var hi := [0.0, 0.0, 0.0, 0.0]
	var sum_err := 0.0
	var swing_load := 0.0
	var lateral := []
	for i in 60 * 20:
		q.debug_desired_speed = 1.3 if i > 30 else 0.0
		await _ticks(1)
		if i < 60 * 4:
			continue
		var sum := 0.0
		for k in 4:
			var leg := q.loco.legs[k]
			lo[k] = minf(lo[k], leg.load)
			hi[k] = maxf(hi[k], leg.load)
			sum += leg.load
			if leg.phase == LegState.Phase.SWING and leg.swing_t > 0.3:
				swing_load = maxf(swing_load, leg.load)
		sum_err = maxf(sum_err, absf(sum - 1.0))
		lateral.append((q.global_transform.affine_inverse() * q.loco.support_center).x)
	var lat_min: float = lateral.min()
	var lat_max: float = lateral.max()
	_log.append("walking 16 s: load per leg min %s max %s, swinging leg load max %.3f, |sum-1| max %.3f, support centre sideways %.2f..%.2f m" % [str(lo.map(func(v: float) -> String: return "%.2f" % v)), str(hi.map(func(v: float) -> String: return "%.2f" % v)), swing_load, sum_err, lat_min, lat_max])
	for k in 4:
		_check(lo[k] < 0.05 and hi[k] > 0.3, "leg %d does not take and give up weight (%.2f..%.2f)" % [k, lo[k], hi[k]])
	_check(swing_load < 0.05, "a swinging leg still carries weight (%.3f)" % swing_load)
	_check(sum_err < 0.05, "loads do not add up to the body weight (%.3f)" % sum_err)
	_check(lat_max - lat_min > 0.4, "weight does not move from side to side")


func test_quadratus_foot_target_can_be_hit_with_arrow() -> void:
	var w := await _setup_quadratus()
	var q: Quadratus = w.quadratus
	var p: PlayerCharacter = w.player
	q.debug_override = &"manual"
	q._set_encounter(Quadratus.Encounter.COMBAT)
	await _ticks(30)
	_stand_behind(w, 2)
	# Standing: hooves planted, the soles are not targets.
	var planted_enabled := 0
	for i in 60:
		await _ticks(1)
		for t in q.arrow_targets:
			if t.enabled:
				planted_enabled += 1
	q.debug_desired_speed = 0.9
	var info := await _shoot_exposed_sole(w, 25.0)
	_log.append("standing: sole targets enabled %d ticks; walking: shot -> %s (leg %s, flight %.2f s, point %s)" % [planted_enabled, info.get("reason", "no shot"), str(info.get("tag", "-")), info.get("flight_time", -1.0), str(info.get("point", Vector3.ZERO))])
	_check(planted_enabled == 0, "a planted sole counted as a target")
	_check(info.get("accepted", false), "the arrow did not hit the lifted sole: %s" % str(info.get("reason", "no shot")))


func test_quadratus_reacts_to_correct_foot_hit() -> void:
	var w := await _setup_quadratus()
	var q: Quadratus = w.quadratus
	var p: PlayerCharacter = w.player
	q._set_encounter(Quadratus.Encounter.COMBAT)
	await _ticks(10)
	# 1) An arrow into the stone of a planted front hoof: nothing.
	p.global_position = q.global_transform * Vector3(-12, 0.95, -5)
	p.reset_physics_interpolation()
	p.set_weapon(PlayerCharacter.Weapon.BOW)
	q.debug_override = &"frozen"
	await _ticks(5)
	var hoof := (q._seg_by_bone[&"fl_foot"] as BodySegment).target_transform * Vector3(0, -0.3, 0)
	_aim_bow(p, PlayerBow.launch_direction(p.bow.bow_point(p), hoof, p.bow.speed_for(1.0)))
	p.actions.attack_held = true
	await _ticks(60)
	p.actions.attack_held = false
	await _ticks(40)
	var stone: Dictionary = ArrowSystem.of(p).last_impact
	var buckle_after_stone := q.buckle
	# 2) The lifted hind sole, from behind (brain running: it turns, stepping).
	q.debug_override = &""
	_stand_behind(w, 2)
	var phases := []
	q.buckle_changed.connect(func(b: Quadratus.Buckle) -> void: phases.append(Quadratus.Buckle.keys()[b]))
	var attacks := [0]
	q.attack_started.connect(func(_a: ColossusAttack) -> void: attacks[0] += 1)
	var info := await _shoot_exposed_sole(w, 30.0)
	var leg_i := int(info.get("tag", 2))
	var intents := {}
	var min_support := 1.0
	for i in 60 * 6:
		await _ticks(1)
		intents[q.intent.kind] = true
		min_support = minf(min_support, q.loco.legs[leg_i].support)
	_log.append("stone hoof hit: %s -> buckle %s; sole hit: %s (leg %d) -> phases %s, intents %s, hit leg support min %.2f, attacks started %d" % [stone.get("reason", "-"), Quadratus.Buckle.keys()[buckle_after_stone], info.get("reason", "no shot"), leg_i, str(phases), str(intents.keys()), min_support, attacks[0]])
	_check(stone.get("reason", &"") == &"surface" and buckle_after_stone == Quadratus.Buckle.NONE, "a hit on the stone hoof caused a reaction")
	_check(info.get("accepted", false), "sole not hit")
	_check(phases.size() >= 2 and phases[0] == "REACT" and phases[1] == "KNEEL", "no react -> kneel sequence: %s" % str(phases))
	_check(Quadratus.REACT_FOOT in intents or Quadratus.LOWER_BODY in intents, "brain did not switch to the foot-hit intents")
	_check(min_support < 0.05, "the hit leg did not give way")
	_check(attacks[0] == 0, "attacked while reacting / kneeling")


func test_quadratus_body_lowers_after_foot_hit() -> void:
	var w := await _setup_quadratus()
	var q: Quadratus = w.quadratus
	q.debug_override = &"frozen"
	q._set_encounter(Quadratus.Encounter.COMBAT)
	await _ticks(60)
	var i := 2
	var corner0 := _hip_height(q, i)
	var centre0 := q.loco.pelvis.y
	var body := q._seg_by_bone[&"body"] as BodySegment
	var thigh := q._seg_by_bone[&"rl_up"] as BodySegment
	var fur0 := (thigh.target_transform * Vector3(0, -2.7, 0)).y
	q._on_sole_hit({"tag": i, "point": q.sole_world(i)})
	var max_step := 0.0
	var prev := body.target_transform.origin
	var steps0 := q.loco.step_count
	var max_swing := 0
	for k in 60 * 5:
		await _ticks(1)
		max_step = maxf(max_step, body.target_transform.origin.distance_to(prev))
		prev = body.target_transform.origin
		max_swing = maxi(max_swing, q.loco.swinging_count())
	var kneel_steps := q.loco.step_count - steps0
	var corner := _hip_height(q, i)
	var centre := q.loco.pelvis.y
	var fur := (thigh.target_transform * Vector3(0, -2.7, 0)).y
	var loads := q.leg_loads()
	var others := loads[0] + loads[1] + loads[3]
	var pitch := q.loco.body_pitch
	var roll := q.loco.body_roll
	# Rises again after the kneel.
	for k in int((q.kneel_time + q.rise_time + 2.0) * 60.0):
		await _ticks(1)
	var corner_back := _hip_height(q, i)
	_log.append("hind-left hit: hip there %.2f -> %.2f m, body centre %.2f -> %.2f m, pitch %.3f roll %.3f rad, lowest thigh fur %.2f -> %.2f m, loads %s (others %.2f), body max %.3f m/tick, steps while going down %d (max %d legs up); after the kneel: buckle %s, support %.2f, hip %.2f m" % [corner0, corner, centre0, centre, pitch, roll, fur0, fur, str(loads.map(func(v: float) -> String: return "%.2f" % v)), others, max_step, kneel_steps, max_swing, q.buckle_name(), q.loco.legs[i].support, corner_back])
	_metric("quad_kneel_corner_drop", corner0 - corner, "info")
	_check(corner0 - corner > 2.5, "the corner did not come down (%.2f m)" % (corner0 - corner))
	_check(centre0 - centre > 0.8, "the body did not lower")
	_check(pitch > 0.05 and roll > 0.1, "the body does not tilt towards the hind-left corner (pitch %.3f roll %.3f)" % [pitch, roll])
	_check(loads[i] < 0.05 and others > 0.95, "the other legs do not take over the weight")
	_check(fur < 3.2, "thigh fur still out of reach (%.2f m)" % fur)
	_check(max_step < 0.06, "the body dropped abruptly (%.3f m/tick)" % max_step)
	_check(max_swing <= 1, "two legs stepped at once while one was weakened")
	_check(q.buckle == Quadratus.Buckle.NONE and q.loco.legs[i].support > 0.99 and absf(corner_back - corner0) < 0.3, "did not rise again")


## Jump-grab from the ground at the hind-left thigh: true if it holds.
func _try_thigh_grab(w: Dictionary) -> bool:
	var q: Quadratus = w.quadratus
	var p: PlayerCharacter = w.player
	var seg: BodySegment = q._seg_by_bone[&"rl_up"]
	var entry := seg.target_transform * Vector3(0, -2.4, 0) - q.global_basis.x * 1.6 + q.global_basis.z * 0.8
	p.global_position = Vector3(entry.x, q.loco.legs[2].plant_pos.y + 0.95, entry.z)
	p.velocity = Vector3.ZERO
	p.reset_physics_interpolation()
	p.set_weapon(PlayerCharacter.Weapon.SWORD)
	await _ticks(10)
	for k in 90:
		var look := seg.target_transform * Vector3(0, -1.6, 0) - p.global_position
		look.y = 0.0
		p.actions.view_basis = Basis.looking_at(look.normalized())
		p.actions.move = Vector2(0, 0.5)
		p.actions.grab_held = k > 2
		if k == 8:
			p.actions.press_jump()
		await _ticks(1)
		if p.is_climbing():
			return true
	p.actions.move = Vector2.ZERO
	p.actions.grab_held = false
	return false


func test_quadratus_climb_route_becomes_reachable() -> void:
	var w := await _setup_quadratus()
	var q: Quadratus = w.quadratus
	var p: PlayerCharacter = w.player
	q.debug_override = &"frozen"
	q._set_encounter(Quadratus.Encounter.COMBAT)
	await _ticks(60)
	var before := await _try_thigh_grab(w)
	await _ticks(60)
	q._on_sole_hit({"tag": 2, "point": q.sole_world(2)})
	await _ticks(90)
	var after := await _try_thigh_grab(w)
	# Climb: up the thigh and the haunch onto the back, then crawl to the rump.
	var reached := false
	var t := 0.0
	for k in 60 * 12:
		var a := p.actions
		a.grab_held = true
		if p.is_climbing() and p.grip.world_normal().y > 0.7:
			a.view_basis = Basis.looking_at(_flatv(q.rump.world_point() - p.global_position).normalized())
		else:
			a.view_basis = Basis.looking_at(_flatv(q.get_focus_point() - p.global_position).normalized())
		a.move = Vector2(0, 1)
		await _ticks(1)
		t += DT
		if p.is_climbing() and p.grip.world_point().distance_to(q.rump.world_point()) < 1.4:
			reached = true
			break
	_log.append("thigh grab before the foot hit: %s; while kneeling: %s; reached the rump weak point by climbing: %s after %.1f s (buckle %s, stamina %.0f)" % [str(before), str(after), str(reached), t, q.buckle_name(), p.stamina.value])
	_check(not before, "the thigh fur is reachable without bringing it down")
	_check(after, "could not grab the lowered thigh")
	_check(reached and q.buckle != Quadratus.Buckle.NONE, "the climb to the rump did not work within the kneel")


func test_quadratus_grip_has_no_drift() -> void:
	var w := await _setup_quadratus()
	var q: Quadratus = w.quadratus
	var p: PlayerCharacter = w.player
	q.debug_override = &"frozen"
	q._set_encounter(Quadratus.Encounter.COMBAT)
	await _ticks(30)
	q._on_sole_hit({"tag": 2, "point": q.sole_world(2)})
	await _ticks(90)
	var grabbed := await _try_thigh_grab(w)
	p.actions.move = Vector2.ZERO
	p.actions.grab_held = true
	p.stamina.value = 100.0
	var local0: Vector3 = p.grip.local_point if grabbed else Vector3.ZERO
	var max_err := 0.0
	var max_local := 0.0
	var moved := 0.0
	var prev := p.global_position
	# Kneel, rise, then walk away with the player holding on.
	for k in int((q.kneel_time + q.rise_time + 6.0) * 60.0):
		if k == int((q.kneel_time + q.rise_time) * 60.0):
			q.debug_override = &"manual"
			q.debug_desired_speed = 1.0
			q.debug_desired_turn = 0.08
		p.stamina.value = 100.0
		await _ticks(1)
		if not p.is_climbing():
			break
		max_err = maxf(max_err, _surface_error(p))
		max_local = maxf(max_local, p.grip.local_point.distance_to(local0))
		moved += p.global_position.distance_to(prev)
		prev = p.global_position
	_log.append("gripping the hind thigh through kneel, rise and walk: still holding %s, carried %.1f m, anchor vs surface max %.6f m, anchor local drift %.6f m" % [str(p.is_climbing()), moved, max_err, max_local])
	_check(grabbed and p.is_climbing(), "lost the grip")
	_check(moved > 3.0, "the player was not carried")
	_check(max_err < 0.02, "anchor left the surface (%.4f m)" % max_err)
	_check(max_local < 1e-4, "anchor drifted on the bone (%.6f m)" % max_local)


func test_quadratus_weakpoint_moves_with_body() -> void:
	var q := await _setup_quad_walk()
	var body := q._seg_by_bone[&"body"] as BodySegment
	var head := q._seg_by_bone[&"head"] as BodySegment
	var r0 := q.rump.world_point()
	var max_err := 0.0
	var node_err := 0.0
	q._set_encounter(Quadratus.Encounter.COMBAT)
	for i in 60 * 14:
		q.debug_desired_speed = 1.3 if i < 60 * 6 else 0.0
		q.debug_desired_turn = 0.15 if i < 60 * 6 else 0.0
		if i == 60 * 7:
			q._on_sole_hit({"tag": 3, "point": q.sole_world(3)})
		await _ticks(1)
		max_err = maxf(max_err, q.rump.world_point().distance_to(body.target_transform * Quadratus.RUMP_LOCAL))
		max_err = maxf(max_err, q.crown.world_point().distance_to(head.target_transform * Quadratus.CROWN_LOCAL))
		node_err = maxf(node_err, (body.global_transform * q.rump.position).distance_to(q.rump.global_position))
	var moved := q.rump.world_point().distance_to(r0)
	_log.append("walk, turn, kneel: rump weak point moved %.1f m (tilt pitch %.2f roll %.2f), error vs bone %.6f m, visual vs segment %.6f m" % [moved, q.loco.body_pitch, q.loco.body_roll, max_err, node_err])
	_check(moved > 3.0, "weak point did not move with the body")
	_check(max_err < 1e-4, "weak point drifts from its bone")
	_check(node_err < 1e-3, "weak point visual not attached")


func test_quadratus_body_reaction_is_fair() -> void:
	var w := await _setup_quadratus()
	var q: Quadratus = w.quadratus
	var p: PlayerCharacter = w.player
	q._set_encounter(Quadratus.Encounter.COMBAT)
	await _ticks(30)
	# A player standing on the back for 60 s (keeps holding on through shakes).
	var body := q._seg_by_bone[&"body"] as BodySegment
	var shakes := []         # [start, brace seconds, shake seconds]
	var cur := {}
	var kneel_shake := 0
	var attacks := []
	q.attack_phase_changed.connect(func(a: ColossusAttack) -> void:
		if a.phase == ColossusAttack.Phase.ACTIVE:
			attacks.append([a.kind, a.telegraph_time, a.recovery_time]))
	var t := 0.0
	for k in 60 * 60:
		if p.get_support_body() == null or not q.owns_body(p.get_support_body()):
			if p.state == PlayerCharacter.State.GROUND or k == 0:
				p.global_position = body.target_transform * Vector3(0, 3.2, 1.5)
				p.velocity = Vector3.ZERO
				p.reset_physics_interpolation()
		p.stamina.value = 100.0
		p.actions.grab_held = q._shake > 0.05 or q.intent.kind == Quadratus.SHAKE_BODY
		if k == 60 * 40:
			q._on_sole_hit({"tag": 2, "point": q.sole_world(2)})
		await _ticks(1)
		t += DT
		# Body reactions: the torso shake and the lurch step share the rules.
		var shaking: bool = q.intent.kind in q._shake_kinds()
		if shaking and cur.is_empty():
			cur = {"start": t, "first_motion": -1.0, "kind": q.intent.kind}
		var moving := q._shake > 0.05 or (q.intent.kind == Quadratus.LURCH and q.loco.speed > 0.3)
		if shaking and moving and cur.first_motion < 0.0:
			cur.first_motion = t
		if not shaking and not cur.is_empty():
			shakes.append([cur.start, (cur.first_motion - cur.start) if cur.first_motion > 0.0 else -1.0, t - cur.start, cur.kind])
			cur = {}
		if shaking and q.buckle != Quadratus.Buckle.NONE:
			kneel_shake += 1
	var min_brace := 99.0
	var max_len := 0.0
	var min_gap := 99.0
	for i in shakes.size():
		if shakes[i][1] >= 0.0:
			min_brace = minf(min_brace, shakes[i][1])
		max_len = maxf(max_len, shakes[i][2])
		if i > 0:
			min_gap = minf(min_gap, shakes[i][0] - (shakes[i - 1][0] + shakes[i - 1][2]))
	var kinds := {}
	for sh in shakes:
		kinds[sh[3]] = int(kinds.get(sh[3], 0)) + 1
	_log.append("player on the back 60 s: %d body reactions %s, brace before motion min %.2f s, longest %.2f s, shortest gap %.2f s, shakes while kneeling %d ticks; ground attacks %s" % [shakes.size(), str(kinds), min_brace, max_len, min_gap, kneel_shake, str(attacks)])
	_check(shakes.size() >= 2, "it never tried to shake the player off")
	_check(min_brace >= minf(q.shake_telegraph, q.lurch_telegraph) - 0.05, "body reaction without a telegraph (%.2f s)" % min_brace)
	_check(max_len <= q.shake_max_duration + 0.3, "shake too long (%.2f s)" % max_len)
	_check(min_gap >= q.shake_cooldown * 0.3 - 0.05, "shakes back to back (%.2f s)" % min_gap)
	_check(kneel_shake == 0, "shook while kneeling (the climb window)")
	for a in attacks:
		_check(a[1] >= q.rules.min_telegraph and a[2] >= q.rules.heavy_recovery_min, "attack %s without a fair telegraph / recovery" % a[0])


func test_quadratus_can_be_defeated() -> void:
	var w := await _setup_quadratus(11, true)
	var q: Quadratus = w.quadratus
	var p: PlayerCharacter = w.player
	var e: BossEncounter = w.encounter
	q._set_encounter(Quadratus.Encounter.COMBAT)
	await _ticks(60)
	p.set_weapon(PlayerCharacter.Weapon.SWORD)
	var strikes := 0
	var crown_closed_standing := false
	for wp in [q.rump, q.crown]:
		if wp == q.crown:
			# The crown is shut while it stands; it opens only when it kneels again.
			crown_closed_standing = q.crown.state == WeakPoint.State.PROTECTED
			q._on_sole_hit({"tag": 2, "point": q.sole_world(2)})
			await _ticks(150)
		var seg: BodySegment = wp.segment
		p.actions.grab_held = false
		await _ticks(5)
		p._carry_body = null   # standing on the body: do not carry back to the old spot
		p.global_position = wp.world_point() + seg.target_transform.basis.y.normalized() * 1.0
		p.velocity = Vector3.ZERO
		p.reset_physics_interpolation()
		await _ticks(20)
		p.actions.grab_held = true
		await _ticks(10)
		var n := 0
		while wp.state != WeakPoint.State.DESTROYED and n < 6:
			p.stamina.value = 100.0
			var res := await _sword_strike(p, 1.25)
			await _ticks(30)
			n += 1
			_log.append("  strike on %s: %s %.0f (player %s, %s, %.2f m from it)" % [wp.segment.bone_name, res.get("reason", "?"), res.get("damage", 0.0), p.get_display_state(), _segment_name(p.get_support_body()), p.global_position.distance_to(wp.world_point())])
		strikes += n
	var y_grip := p.global_position.y
	for k in 60 * 8:
		await _ticks(1)
	var y_low := p.global_position.y
	var top := (q._seg_by_bone[&"body"] as BodySegment).target_transform * Vector3(0, 1.9, 4.0)
	p.actions.grab_held = false
	var tiers := []
	p.landed.connect(func(_s: float, tier: int, _d: float) -> void: tiers.append(tier))
	await _ticks(120)
	_log.append("%d full strikes: %s, banner '%s'; lying down: player %.1f -> %.1f m, rump top %.1f m; let go -> %s, landing tiers %s, HP %.0f" % [strikes, q.encounter_name(), e.banner, y_grip, y_low, top.y, p.get_display_state(), str(tiers), p.health])
	_check(crown_closed_standing, "the crown was open while it stood (the loop must repeat)")
	_check(q.encounter == Quadratus.Encounter.DEFEATED, "not defeated")
	_check(e.banner == "COLOSSUS DEFEATED", "no defeat banner")
	_check(strikes >= 4 and strikes <= 6, "expected 2-3 full strikes per weak point, took %d" % strikes)
	_check(top.y < 7.0, "it did not lie down (%.1f m)" % top.y)
	_check(not p.dead and not (FallImpact.Tier.SEVERE in tiers), "getting off the defeated colossus was not safe")


func test_quadratus_scripted_driver_can_complete_fight() -> void:
	for variant in ["foot", "horse"]:
		var w := await _setup_quadratus()
		var bot := QuadratusBot.new()
		bot.use_horse = variant == "horse"
		_world.add_child(bot)
		bot.setup(w.player, w.quadratus, w.encounter, w.horse)
		for i in 60 * 300:
			await _ticks(1)
			if bot.phase == QuadratusBot.Phase.DONE:
				break
		var r := bot.result
		_log.append("%s: %s in %.1f s; %s; boss %s" % [variant, "WIN" if r.get("won", false) else "NO WIN", r.get("time", -1.0), str(r.get("stats", {})), str(r.get("boss", {}))])
		_metric("quad_bot_%s_time" % variant, r.get("time", 999.0), "lower")
		_check(r.get("won", false), "%s: the scripted driver did not beat Quadratus: %s" % [variant, " | ".join(bot.events.slice(-8))])
		if variant == "horse":
			_check(int(r.get("stats", {}).get("shots_from_horse", 0)) > 0, "no arrow was shot from the horse")
		await _teardown()


func test_quadratus_simulation_independent_of_render_fps() -> void:
	var exe := OS.get_executable_path()
	var rates := [30, 60, 90, 120, 144, 240]
	for scenario in ["quadratus", "quadratus_horse"]:
		var results := {}
		for fps in rates:
			var out_path := ProjectSettings.globalize_path("res://tests/output/%s_fps_%d.json" % [scenario, fps])
			var output := []
			var code := OS.execute(exe, ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--fixed-fps", str(fps), "--quit-after", "400000", "res://tests/fps_scenario.tscn", "--", "--scenario=" + scenario, "--out=" + out_path], output, true)
			if code != 0 or not FileAccess.file_exists(out_path):
				_check(false, "%s at %d fps failed (code %d)" % [scenario, fps, code])
				return
			results[fps] = JSON.parse_string(FileAccess.get_file_as_string(out_path))
		var diff := _max_json_diff(results, rates)
		var ref: Dictionary = results[60]
		_log.append("%s (bot) at %s fps: won %s at tick %d, arrows %d, max state difference %.8f" % [scenario, str(rates), str(ref.won), int(ref.tick), int(ref.shots), diff])
		_metric("%s_fps_max_diff" % scenario, diff, "lower")
		_check(int(ref.won) == 1, "%s reference run did not win" % scenario)
		_check(diff < 1e-4, "%s depends on the render rate (diff %.6f)" % [scenario, diff])


func _max_json_diff(results: Dictionary, rates: Array) -> float:
	var ref: Dictionary = results[60]
	var max_diff := 0.0
	for fps in rates:
		var r: Dictionary = results[fps]
		for k in ref:
			if k == "frames":
				continue
			if ref[k] is Array:
				if (r[k] as Array).size() != (ref[k] as Array).size():
					return INF
				for j in (ref[k] as Array).size():
					max_diff = maxf(max_diff, absf(float(r[k][j]) - float(ref[k][j])))
			else:
				max_diff = maxf(max_diff, absf(float(r[k]) - float(ref[k])))
	return max_diff


func test_quadratus_cost_stays_within_budget() -> void:
	Fx.enabled = true
	var w := await _setup_quadratus()
	Fx.enabled = true
	var q: Quadratus = w.quadratus
	q.effects_enabled = true
	var bot := QuadratusBot.new()
	bot.use_horse = true
	_world.add_child(bot)
	bot.setup(w.player, w.quadratus, w.encounter, w.horse)
	await _ticks(60 * 20)   # riding in, combat, aiming from the saddle
	Perf.take()
	var ticks := 60 * 30
	var physics_ms := 0.0
	var physics_max := 0.0
	var arrows_max := 0
	for i in ticks:
		await _ticks(1)
		var pm := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		physics_ms += pm
		physics_max = maxf(physics_max, pm)
		arrows_max = maxi(arrows_max, ArrowSystem.of(w.player).arrows.size())
	var m := Perf.take()
	var u: Dictionary = m.usec
	var qq: Dictionary = m.queries
	var per := func(k: StringName) -> float: return float(u.get(k, 0)) / ticks
	var qp := func(k: StringName) -> float: return float(qq.get(k, 0)) / ticks
	var colossus: float = per.call(&"colossus")
	_log.append("Quadratus fight (bot from Agro, then climbing, 30 s; phases seen up to %s): colossus %.1f us/tick = brain %.1f + combat %.1f + hits %.1f + pose %.1f + quadruped locomotion %.1f (of it balance / weight transfer %.1f) + four-leg IK %.1f; arrows %.1f (max %d alive); player %.1f (of it bow %.1f, climbing %.1f); Agro %.1f; camera %.1f us/frame; queries/tick: arrow rays %.2f, arrow target tests %.2f, bow aim rays %.3f, climb %.2f, horse %.2f, camera %.2f, colossus ground probes %d total" % [QuadratusBot.Phase.keys()[bot.phase], colossus, per.call(&"brain"), per.call(&"boss_combat"), per.call(&"boss_hits"), per.call(&"boss_pose"), per.call(&"locomotion"), per.call(&"loco_balance"), per.call(&"ik"), per.call(&"arrows"), arrows_max, per.call(&"player"), per.call(&"bow"), per.call(&"climb"), per.call(&"horse"), per.call(&"camera"), qp.call(&"arrow_rays"), qp.call(&"arrow_target_tests"), qp.call(&"bow_aim_rays"), qp.call(&"climb_rays"), qp.call(&"horse_rays"), qp.call(&"camera_queries"), q.loco.step_count])
	_log.append("whole physics tick (engine monitor, incl. physics server): mean %.3f ms, max %.3f ms" % [physics_ms / ticks, physics_max])
	_metric("quad_physics_tick_ms", physics_ms / ticks, "lower")
	_metric("quad_colossus_us", colossus, "lower")
	_metric("quad_locomotion_us", per.call(&"locomotion"), "lower")
	_metric("quad_ik_us", per.call(&"ik"), "lower")
	_metric("quad_arrows_us", per.call(&"arrows"), "lower")
	_check(colossus < 500.0, "Quadratus logic too expensive: %.0f us/tick" % colossus)
	_check(per.call(&"arrows") < 100.0, "arrow simulation too expensive")
	Fx.enabled = false


func test_valus_defeat_leaves_a_safe_way_down() -> void:
	var w := await _setup_valus(7, true)
	var s: Valus = w.valus
	var p: PlayerCharacter = w.player
	_start_combat(s)
	await _stand_on_head(w)
	p.actions.grab_held = true
	await _ticks(5)
	var y0 := p.global_position.y
	for k in 3:
		s.weak_point.try_hit(s.weak_point.world_point(), 1.0, &"sword")
	var max_err := 0.0
	for i in 60 * 9:
		await _ticks(1)
		if p.is_climbing():
			max_err = maxf(max_err, _surface_error(p))
	var held := p.is_climbing()
	var y1 := p.global_position.y
	var head := (s._seg_by_bone[&"head"] as BodySegment).target_transform * Valus.WEAK_POINT_LOCAL
	var tiers := []
	p.landed.connect(func(_s: float, tier: int, _d: float) -> void: tiers.append(tier))
	var hp := p.health
	p.actions.grab_held = false
	await _ticks(150)
	_log.append("gripping the head through the defeat: held %s, carried from %.1f m down to %.1f m (head top %.1f m), anchor error %.5f m; let go -> %s, landing tiers %s, HP %.0f -> %.0f" % [str(held), y0, y1, head.y, max_err, p.get_display_state(), str(tiers), hp, p.health])
	_metric("valus_defeat_head_height", head.y, "lower")
	_check(held, "lost the grip during the defeat")
	_check(head.y < 4.0, "the head stays too high to get down (%.1f m)" % head.y)
	_check(max_err < 0.08, "anchor left the surface")
	_check(not p.dead and not (FallImpact.Tier.SEVERE in tiers), "getting down was not safe")


# --- bow ---------------------------------------------------------------------------------

func _setup_range() -> PlayerCharacter:
	Sfx.enabled = false
	Fx.enabled = false
	_world = Node3D.new()
	_world.name = "World_" + _current
	add_child(_world)
	var ground := StaticBody3D.new()
	ground.collision_layer = Layers.WORLD
	var gs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(600, 2, 600)
	gs.shape = box
	gs.position = Vector3(0, -1, 0)
	ground.add_child(gs)
	_world.add_child(ground)
	var p := PlayerCharacter.new()
	p.name = "Archer"
	_world.add_child(p)
	p.global_position = Vector3(0, 0.95, 0)
	p.set_weapon(PlayerCharacter.Weapon.BOW)
	await _ticks(10)
	return p


## A post with a round mark (ArrowTarget facing the archer) at ``pos``.
func _range_target(pos: Vector3, facing: Vector3) -> ArrowTarget:
	var post := TerrainKit.box(_world, pos, Vector3(1.4, 1.4, 0.3), StandardMaterial3D.new(), Basis.looking_at(-facing))
	return ArrowTarget.create(post, Vector3(0, 0, 0.16), Vector3(0, 0, 1), 0.5)


## Holds the attack for ``hold`` s, releases; returns the arrow.
func _shoot(p: PlayerCharacter, hold: float) -> Dictionary:
	p.actions.attack_held = true
	await _ticks(int(round(hold * 60.0)))
	p.actions.attack_held = false
	await _ticks(1)
	return p.bow.last_shot.get("arrow", {})


func _wait_arrow(a: Dictionary, seconds := 6.0) -> void:
	for i in int(seconds * 60.0):
		if a.state != &"flying":
			return
		await _ticks(1)


func test_bow_draw_strength_changes_arrow_velocity() -> void:
	var p := await _setup_range()
	p.actions.view_basis = Basis.looking_at(Vector3(0, 0.1, -1).normalized())
	var rows := []
	for hold in [0.1, 0.3, 0.6, 1.2]:
		p.bow.last_shot = {}
		var a := await _shoot(p, hold)
		var shot := not p.bow.last_shot.is_empty()
		var v := (a.vel as Vector3).length() if shot else 0.0
		var range_m := 0.0
		if shot:
			await _wait_arrow(a)
			range_m = _flatv((a.pos as Vector3) - p.global_position).length()
		rows.append([hold, p.bow.last_shot.get("draw", 0.0), v, range_m])
		await _ticks(40)
	_log.append("hold s / draw / speed m/s / range m: %s" % str(rows.map(func(r: Array) -> String: return "%.1f/%.2f/%.1f/%.0f" % r)))
	_check(rows[0][2] == 0.0, "a 0.1 s tug shot an arrow")
	_check(rows[1][2] < rows[2][2] and rows[2][2] < rows[3][2], "speed does not grow with the draw")
	_check(rows[1][3] < rows[2][3] and rows[2][3] < rows[3][3], "range does not grow with the draw")
	_check(absf(rows[3][2] - p.bow.max_speed) < 0.6, "full draw is not max speed")


func test_bow_trajectory_is_repeatable() -> void:
	var p := await _setup_range()
	var paths := []
	for k in 2:
		p.global_position = Vector3(0, 0.95, 0)
		p.velocity = Vector3.ZERO
		p.reset_physics_interpolation()
		await _ticks(20)
		p.actions.view_basis = Basis.looking_at(Vector3(0.2, 0.15, -1).normalized())
		p.actions.aim_origin = Vector3(0, 2.0, 3.0)
		var a := await _shoot(p, 1.0)
		await _wait_arrow(a)
		paths.append([a.path, a.pos])
		await _ticks(30)
	var pa: PackedVector3Array = paths[0][0]
	var pb: PackedVector3Array = paths[1][0]
	var diff := 0.0
	for i in mini(pa.size(), pb.size()):
		diff = maxf(diff, pa[i].distance_to(pb[i]))
	# Matches the closed-form ballistic curve too.
	var shot: Dictionary = p.bow.last_shot
	var v0: Vector3 = (shot.dir as Vector3) * float(shot.speed)
	var curve := 0.0
	for i in pa.size():
		curve = maxf(curve, pa[i].distance_to(ArrowSystem.predict(pa[0], v0, i * DT)))
	_log.append("two identical shots: %d / %d path points, max difference %.8f m, landing %s vs %s; deviation from the analytic parabola %.6f m" % [pa.size(), pb.size(), diff, str(paths[0][1]), str(paths[1][1]), curve])
	_check(pa.size() == pb.size() and diff < 1e-5, "trajectory not repeatable")
	_check(curve < 1e-3, "trajectory is not the ballistic curve")


func test_arrow_hits_expected_target() -> void:
	var p := await _setup_range()
	var rows := []
	for d in [15.0, 30.0, 60.0]:
		var pos := Vector3(d * 0.3, 1.8, -d)
		var t := _range_target(pos, _flatv(p.global_position - pos).normalized())
		await _ticks(2)
		var hits := []
		t.hit.connect(func(info: Dictionary) -> void: hits.append(info))
		var dir := PlayerBow.launch_direction(p.bow.bow_point(p), t.world_point(), p.bow.speed_for(1.0))
		_aim_bow(p, dir)
		var a := await _shoot(p, 1.2)
		await _wait_arrow(a)
		var err := (a.pos as Vector3).distance_to(t.world_point())
		var predicted := _flatv(t.world_point() - p.bow.bow_point(p)).length() / (p.bow.speed_for(1.0) * _flatv(dir).length())
		rows.append([d, hits.size(), err, float(a.get("flight", -1.0)), predicted])
		t.get_parent().queue_free()
		await _ticks(20)
	_log.append("distance / hits / impact error m / flight s / predicted s: %s" % str(rows.map(func(r: Array) -> String: return "%.0f/%d/%.3f/%.3f/%.3f" % r)))
	for r in rows:
		_check(r[1] == 1, "missed the target at %.0f m" % r[0])
		_check(r[2] < 0.5, "impact off the mark at %.0f m" % r[0])
		_check(absf(r[3] - r[4]) < 2.0 * DT, "flight time off the prediction at %.0f m" % r[0])


func test_arrow_misses_when_aim_is_wrong() -> void:
	var p := await _setup_range()
	var pos := Vector3(0, 1.8, -30)
	var t := _range_target(pos, Vector3(0, 0, 1))
	await _ticks(2)
	var hits := []
	t.hit.connect(func(info: Dictionary) -> void: hits.append(info))
	var dir := PlayerBow.launch_direction(p.bow.bow_point(p), t.world_point(), p.bow.speed_for(1.0))
	var rows := []
	# 1.5 degrees off to the side, a gravity-blind straight aim, and a weak draw.
	for case in [["side", dir.rotated(Vector3.UP, deg_to_rad(1.5)), 1.2], ["no drop", (t.world_point() - p.bow.bow_point(p)).normalized(), 1.2], ["weak draw", dir, 0.35]]:
		_aim_bow(p, case[1])
		var a := await _shoot(p, case[2])
		await _wait_arrow(a)
		rows.append("%s: %s at %s" % [case[0], "HIT" if hits.size() > 0 else "miss", str((a.pos as Vector3).snapped(Vector3.ONE * 0.01))])
		_check(hits.is_empty(), "%s still hit the mark" % case[0])
		hits.clear()
		await _ticks(30)
	# From behind the post (wrong side of the mark): no hit even dead centre.
	p.global_position = Vector3(0, 0.95, -60)
	p.reset_physics_interpolation()
	await _ticks(20)
	var back := PlayerBow.launch_direction(p.bow.bow_point(p), t.world_point(), p.bow.speed_for(1.0))
	_aim_bow(p, back)
	var a2 := await _shoot(p, 1.2)
	await _wait_arrow(a2)
	rows.append("from behind: %s (%s)" % ["HIT" if hits.size() > 0 else "miss", t.last_reason])
	_log.append(", ".join(rows))
	_check(hits.is_empty(), "hit the mark from behind")


func test_bow_is_independent_of_render_fps() -> void:
	var exe := OS.get_executable_path()
	var rates := [30, 60, 90, 120, 144, 240]
	var results := {}
	for fps in rates:
		var out_path := ProjectSettings.globalize_path("res://tests/output/bow_fps_%d.json" % fps)
		var output := []
		var code := OS.execute(exe, ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--fixed-fps", str(fps), "--quit-after", "400000", "res://tests/fps_scenario.tscn", "--", "--scenario=bow", "--out=" + out_path], output, true)
		if code != 0 or not FileAccess.file_exists(out_path):
			_check(false, "bow scenario at %d fps failed (code %d)" % [fps, code])
			return
		results[fps] = JSON.parse_string(FileAccess.get_file_as_string(out_path))
	var diff := _max_json_diff(results, rates)
	var ref: Dictionary = results[60]
	_log.append("3 shots on foot + 1 from a galloping Agro at %s fps: %d impacts, max difference %.8f (impact points and flight times)" % [str(rates), (ref.impacts as Array).size() / 4, diff])
	_metric("bow_fps_max_diff", diff, "lower")
	_check((ref.impacts as Array).size() == 16, "expected 4 arrows to land")
	_check(diff < 1e-4, "arrows depend on the render rate (diff %.6f)" % diff)


## Player on Agro at a gallop on open ground.
func _setup_riding_archer() -> Dictionary:
	var p := await _setup_range()
	var h := Horse.new()
	_world.add_child(h)
	h.teleport(Vector3(0, 0, 0), 0.0)
	p.global_position = Vector3(-1.4, 0.95, 0.2)
	p.reset_physics_interpolation()
	await _ticks(5)
	p.actions.press_interact()
	await _ticks(60)
	p.actions.view_basis = Basis.IDENTITY
	p.actions.move = Vector2(0, 1)
	p.actions.press_jump()
	await _ticks(40)
	p.actions.press_jump()
	await _ticks(100)
	p.actions.move = Vector2.ZERO
	return {"player": p, "horse": h}


func test_player_can_aim_from_agro() -> void:
	var r := await _setup_riding_archer()
	var p: PlayerCharacter = r.player
	var h: Horse = r.horse
	var speed := h.controller.speed
	# A mark out to the right of the ride, ~25 m away.
	var ahead := h.global_position + h.controller.forward() * (speed * 1.6)
	var pos := ahead + h.controller.forward().cross(Vector3.UP) * 25.0 + Vector3.UP * 1.5
	var t := _range_target(pos, -h.controller.forward().cross(Vector3.UP))
	await _ticks(2)
	var hits := []
	t.hit.connect(func(info: Dictionary) -> void: hits.append(info))
	p.actions.attack_held = true
	var aimed := false
	for i in 90:
		# Lead for the horse's own motion (the arrow inherits it).
		var from := p.bow.bow_point(p)
		var v := p.bow.speed_for(maxf(p.bow.draw, 0.2))
		var dir := PlayerBow.launch_direction(from, t.world_point(), p.bow.speed_for(1.0))
		var rel := (dir * p.bow.speed_for(1.0) - p.velocity).normalized()
		_aim_bow(p, rel)
		await _ticks(1)
		aimed = aimed or p.bow.is_aiming()
		if p.bow.state == PlayerBow.State.AIM:
			break
	var state := p.bow.state_name()
	p.actions.attack_held = false
	await _ticks(2)
	var a: Dictionary = p.bow.last_shot.get("arrow", {})
	if not a.is_empty():
		await _wait_arrow(a)
	_log.append("riding at %.1f m/s: bow %s while riding (%s), shot %s, arrow %s at %s, mark hits %d" % [speed, state, p.get_display_state(), str(not a.is_empty()), a.get("state", "-"), str((a.get("pos", Vector3.ZERO) as Vector3).snapped(Vector3.ONE * 0.01)), hits.size()])
	_check(speed > 4.5, "not riding fast")
	_check(aimed and p.is_riding(), "could not draw the bow on horseback")
	_check(not a.is_empty(), "no arrow from the saddle")
	_check(hits.size() == 1, "missed the mark from the galloping horse")


func test_horse_heading_is_not_changed_by_aim() -> void:
	var r := await _setup_riding_archer()
	var p: PlayerCharacter = r.player
	var h: Horse = r.horse
	var yaw0 := h.controller.yaw
	p.actions.attack_held = true
	var max_dev := 0.0
	# Sweep the aim all around (look left, back, right) for 3 s, no stick input.
	for i in 180:
		var ang := TAU * i / 180.0
		_aim_bow(p, Vector3(sin(ang), 0.1, cos(ang)).normalized())
		await _ticks(1)
		max_dev = maxf(max_dev, absf(angle_difference(yaw0, h.controller.yaw)))
	var while_aiming := p.bow.is_aiming()
	# While aiming the stick steers relative to the horse: right turns right, wherever
	# the camera looks.
	p.actions.move = Vector2(0.8, 0.0)
	_aim_bow(p, -h.controller.forward().cross(Vector3.UP))   # looking to the left
	var yaw1 := h.controller.yaw
	await _ticks(60)
	var turned := angle_difference(yaw1, h.controller.yaw)
	p.actions.attack_held = false
	p.actions.move = Vector2.ZERO
	_log.append("aiming around 360 deg for 3 s: horse heading deviation %.4f rad (still aiming %s); stick right while looking left: horse turned %.3f rad (right = negative yaw)" % [max_dev, str(while_aiming), turned])
	_check(while_aiming, "lost the draw while riding")
	_check(max_dev < 0.02, "aiming turned the horse (%.3f rad)" % max_dev)
	_check(turned < -0.05, "stick did not steer the horse relative to itself while aiming")


func test_arrow_hit_can_trigger_colossus_reaction() -> void:
	var w := await _setup_quadratus()
	var q: Quadratus = w.quadratus
	q._set_encounter(Quadratus.Encounter.COMBAT)
	await _ticks(10)
	_stand_behind(w, 3, 12.0)
	var reactions := []
	q.foot_hit.connect(func(leg: int) -> void: reactions.append(leg))
	var info := await _shoot_exposed_sole(w, 30.0)
	await _ticks(30)
	_log.append("arrow: %s (target leg %s, colossus %s) -> foot_hit %s, buckle %s, intent %s" % [info.get("reason", "no shot"), str(info.get("tag", "-")), str(info.get("colossus", null)), str(reactions), q.buckle_name(), q.intent.kind])
	_check(info.get("accepted", false) and info.get("colossus", null) == q, "the arrow did not register on Quadratus")
	_check(reactions.size() == 1 and q.buckle != Quadratus.Buckle.NONE, "no reaction to the arrow")


## Everything that ran before the Etap 6 tests (Milestone 1 .. Etap 5 incl. Valus) passed.
func all_valus_and_earlier_tests_still_pass() -> void:
	var ran := 0
	var failed := PackedStringArray()
	for n in _pre_etap6_results:
		ran += 1
		if not _pre_etap6_results[n]:
			failed.append(n)
	_log.append("%d earlier tests (Milestone 1, Etap 2-5) ran in this run, %d failed %s" % [ran, failed.size(), str(failed) if failed.size() > 0 else ""])
	_check(failed.is_empty(), "earlier tests failed: %s" % str(failed))


# --- ETAP 7: Gaius, art layer, Quadratus loop and lurch, bow polish -----------------------

func _setup_gaius(seed_value := 13, frozen := false) -> Dictionary:
	Sfx.enabled = false
	Fx.enabled = false
	_world = Node3D.new()
	_world.name = "World_" + _current
	add_child(_world)
	var w := GaiusArena.build_encounter(_world, false, seed_value)
	if frozen:
		(w.gaius as Gaius).debug_override = &"frozen"
	await _ticks(2)
	return w


## Starts a slam at a point in front of Gaius (the player stands there, then steps out).
func _provoke_slam(w: Dictionary) -> void:
	var g: Gaius = w.gaius
	var p: PlayerCharacter = w.player
	g._set_encounter(Gaius.Encounter.COMBAT)
	p.global_position = g.global_transform * Vector3(-2.5, 0.95, -15.0)
	p.velocity = Vector3.ZERO
	p.reset_physics_interpolation()
	for i in 60 * 8:
		await _ticks(1)
		if g.attack != null and not g.attack.is_done() and g.attack.kind == Gaius.SWORD_SLAM and g.attack.phase == ColossusAttack.Phase.TELEGRAPH and g.attack.phase_t() > 0.7:
			break
	# Out of the shockwave, to the side.
	p.global_position = g.global_transform * Vector3(12.0, 0.95, -12.0)
	p.velocity = Vector3.ZERO
	p.reset_physics_interpolation()


func test_gaius_sword_follows_the_arm() -> void:
	var w := await _setup_gaius()
	var g: Gaius = w.gaius
	var sword := g._seg_by_bone[&"sword"] as BodySegment
	var hand := g._seg_by_bone[&"hand_r"] as BodySegment
	var max_err := 0.0
	var phases := {}
	await _provoke_slam(w)
	var tip_err := 99.0
	var face := 0.0
	var slope := 0.0
	var max_step := 0.0
	var prev := g.blade_tip()
	for i in 60 * 12:
		await _ticks(1)
		# The sword segment is rigidly held: its origin stays at the grip in the hand.
		max_err = maxf(max_err, sword.target_transform.origin.distance_to(hand.target_transform * Gaius.SWORD_GRIP))
		var tip := g.blade_tip()
		max_step = maxf(max_step, tip.distance_to(prev))
		prev = tip
		if g.sword_stuck():
			phases["stuck"] = true
			tip_err = minf(tip_err, _flatv(tip - g.slam_point).length() + absf(tip.y - g.slam_point.y))
			face = sword.target_transform.basis.z.normalized().y
			var h := hand.target_transform.origin
			slope = rad_to_deg(asin(clampf((h.y - tip.y) / h.distance_to(tip), -1.0, 1.0)))
	_log.append("sword grip vs hand max %.6f m; stuck: tip vs slam point %.3f m, flat face up %.2f, blade slope %.1f deg; tip max %.2f m/tick" % [max_err, tip_err, face, slope, max_step])
	_check(phases.has("stuck"), "the sword never got stuck in the ground")
	_check(max_err < 1e-4, "the sword is not held by the hand")
	_check(tip_err < 0.4, "the blade tip is not at the slam point (%.2f m)" % tip_err)
	_check(face > 0.85, "the blade's flat face does not face up (%.2f)" % face)
	_check(slope > 12.0 and slope < 40.0, "the stuck blade is no walkable ramp (%.1f deg)" % slope)


func test_gaius_slam_has_telegraph_and_stuck_window() -> void:
	var w := await _setup_gaius()
	var g: Gaius = w.gaius
	var rec := {"phases": [], "zones_in_telegraph": 0, "intents_stuck": {}}
	g.attack_phase_changed.connect(func(a: ColossusAttack) -> void:
		if a.kind == Gaius.SWORD_SLAM:
			rec.phases.append([ColossusAttack.Phase.keys()[a.phase], g._time]))
	await _provoke_slam(w)
	var t_stuck := 0.0
	for i in 60 * 14:
		await _ticks(1)
		if g.attack != null and g.attack.kind == Gaius.SWORD_SLAM and g.attack.phase == ColossusAttack.Phase.TELEGRAPH and not g.get_danger_zones().is_empty():
			rec.zones_in_telegraph += 1
		if g.sword_stuck():
			t_stuck += DT
			rec.intents_stuck[g.intent.kind] = true
	var times := {}
	for k in range(1, rec.phases.size()):
		times[rec.phases[k - 1][0]] = float(rec.phases[k][1]) - float(rec.phases[k - 1][1])
	_log.append("slam phases %s; durations %s; stuck %.1f s, intents while stuck %s, danger zone ticks in the wind-up %d" % [str(rec.phases.map(func(x: Array) -> String: return x[0])), str(times), t_stuck, str(rec.intents_stuck.keys()), rec.zones_in_telegraph])
	_check(float(times.get("TELEGRAPH", 0.0)) >= 1.4, "slam telegraph too short")
	_check(t_stuck >= g.stuck_time - 0.1, "the blade does not stay stuck for the climb window (%.1f s)" % t_stuck)
	_check(not ColossusIntent.SHAKE_PLAYER in rec.intents_stuck, "it shook while the sword was stuck")
	# Counted from 70 % of the wind-up on (the setup waits for the slam to be sure).
	_check(rec.zones_in_telegraph > 20, "no danger zone during the wind-up (Agro / AI)")


func test_gaius_slam_point_locks_for_a_late_dodge() -> void:
	var w := await _setup_gaius()
	var g: Gaius = w.gaius
	var p: PlayerCharacter = w.player
	g._set_encounter(Gaius.Encounter.COMBAT)
	p.global_position = g.global_transform * Vector3(-2.5, 0.95, -15.0)
	p.reset_physics_interpolation()
	var locked_at := Vector3.ZERO
	var moved_after := 0.0
	var hp0 := p.health
	for i in 60 * 10:
		await _ticks(1)
		var a := g.attack
		if a != null and not a.is_done() and a.kind == Gaius.SWORD_SLAM and a.phase == ColossusAttack.Phase.TELEGRAPH:
			if a.phase_t() > 0.55 and locked_at == Vector3.ZERO:
				locked_at = g.slam_point
				# Late dodge: sideways, 9 m.
				p.global_position = g.global_transform * Vector3(7.0, 0.95, -15.0)
				p.reset_physics_interpolation()
			if locked_at != Vector3.ZERO:
				moved_after = maxf(moved_after, g.slam_point.distance_to(locked_at))
		if g.sword_stuck():
			break
	_log.append("slam point after 55%% of the wind-up moved %.3f m; late dodge: HP %.0f -> %.0f" % [moved_after, hp0, p.health])
	_check(locked_at != Vector3.ZERO, "no slam observed")
	_check(moved_after < 0.01, "the slam point kept following after it locked")
	_check(p.health >= hp0, "a late dodge out of the shockwave still got hit")


## Puts the player on the stuck blade near its tip.
func _onto_blade(w: Dictionary) -> void:
	var g: Gaius = w.gaius
	var p: PlayerCharacter = w.player
	var tip := g.blade_tip()
	var hand := (g._seg_by_bone[&"hand_r"] as BodySegment).target_transform.origin
	p.global_position = tip.lerp(hand, 0.15) + Vector3.UP * 1.3
	p.velocity = Vector3.ZERO
	p.reset_physics_interpolation()
	p.set_weapon(PlayerCharacter.Weapon.SWORD)
	await _ticks(20)


func test_gaius_blade_is_a_walkable_ramp() -> void:
	var w := await _setup_gaius()
	var g: Gaius = w.gaius
	var p: PlayerCharacter = w.player
	await _provoke_slam(w)
	for i in 120:
		await _ticks(1)
		if g.sword_stuck():
			break
	await _onto_blade(w)
	var start_y := p.global_position.y
	var on_blade_ticks := 0
	var fist := (g._seg_by_bone[&"hand_r"] as BodySegment).target_transform * Vector3(0, -0.9, 0)
	var closest := 99.0
	for i in 60 * 5:
		var to := fist - p.global_position
		p.actions.view_basis = Basis.looking_at(_flatv(to).normalized())
		p.actions.move = Vector2(0, 1)
		await _ticks(1)
		var s: Object = p.get_support_body()
		if s is BodySegment and (s as BodySegment).bone_name == &"sword":
			on_blade_ticks += 1
		closest = minf(closest, p.global_position.distance_to(fist))
	p.actions.move = Vector2.ZERO
	_log.append("walking up the stuck blade: %d ticks standing on it, climbed %.1f m, closest to the fist %.2f m, state %s" % [on_blade_ticks, p.global_position.y - start_y, closest, p.get_display_state()])
	_check(on_blade_ticks > 60, "could not stand on the blade")
	_check(p.global_position.y - start_y > 2.0, "could not walk up the blade")
	_check(closest < 2.6, "did not reach the fist")


func test_gaius_climb_route_blade_to_shoulders() -> void:
	var w := await _setup_gaius()
	var g: Gaius = w.gaius
	var p: PlayerCharacter = w.player
	g.debug_override = &""
	var bot := GaiusBot.new()
	_world.add_child(bot)
	bot.setup(p, g, w.encounter)
	var reached := -1.0
	var grabbed := -1.0
	for i in 60 * 120:
		await _ticks(1)
		if grabbed < 0.0 and p.is_climbing() and bot._grip_bone() == &"hand_r":
			grabbed = i * DT
		if g.region_of(p) == &"shoulder":
			reached = i * DT
			break
	_log.append("bot: grabbed the fist at %.1f s, standing on the shoulders at %.1f s (slams %d)" % [grabbed, reached, int(g.stats.attacks.get(Gaius.SWORD_SLAM, 0))])
	_check(grabbed > 0.0, "never got from the blade to the fist")
	_check(reached > 0.0, "never reached the shoulders over the sword arm")


func test_gaius_grip_on_sword_arm_has_no_drift() -> void:
	var w := await _setup_gaius()
	var g: Gaius = w.gaius
	var p: PlayerCharacter = w.player
	await _provoke_slam(w)
	for i in 120:
		await _ticks(1)
		if g.sword_stuck():
			break
	# Grip the forearm fur and hold on through the pull-out and the swing back.
	var fore := g._seg_by_bone[&"forearm_r"] as BodySegment
	var c := fore.target_transform * Vector3(0, -2.0, 0)
	var n := fore.target_transform.basis.z.normalized()
	p.global_position = c + Vector3.UP * 1.6
	p.reset_physics_interpolation()
	p.actions.grab_held = true
	for i in 40:
		await _ticks(1)
		if p.is_climbing():
			break
	var held := p.is_climbing()
	var local0: Vector3 = p.grip.local_point if held else Vector3.ZERO
	var max_err := 0.0
	var max_local := 0.0
	var moved := 0.0
	var prev := p.global_position
	for i in 60 * 12:
		p.stamina.value = 100.0
		await _ticks(1)
		if not p.is_climbing():
			break
		max_err = maxf(max_err, _surface_error(p))
		max_local = maxf(max_local, p.grip.local_point.distance_to(local0))
		moved += p.global_position.distance_to(prev)
		prev = p.global_position
	_log.append("gripping the sword arm through the pull-out (12 s): held %s / still %s, carried %.1f m, anchor vs surface %.6f m, local drift %.6f m" % [str(held), str(p.is_climbing()), moved, max_err, max_local])
	_check(held and p.is_climbing(), "lost the grip on the sword arm")
	_check(moved > 2.0, "the arm did not carry the player")
	_check(max_err < 0.02, "anchor left the surface")
	_check(max_local < 1e-4, "anchor drifted on the bone")


func test_gaius_helmet_breaks_after_charged_strikes() -> void:
	var w := await _setup_gaius(13, true)
	var g: Gaius = w.gaius
	var p: PlayerCharacter = w.player
	g._set_encounter(Gaius.Encounter.COMBAT)
	await _ticks(90)
	var head := g._seg_by_bone[&"head"] as BodySegment
	p.set_weapon(PlayerCharacter.Weapon.SWORD)
	p.global_position = head.target_transform * Vector3(0, 3.0 + 1.0, 0.1)
	p.velocity = Vector3.ZERO
	p.facing = g.global_basis.z
	p.reset_physics_interpolation()
	await _ticks(40)
	var wp_before := g.weak_point.state_name()
	var weak := await _sword_strike(p, 0.2)
	await _ticks(40)
	var results := [weak.get("reason", "-")]
	var n := 0
	while not g.helmet.is_broken and n < 6:
		p.stamina.value = 100.0
		var r := await _sword_strike(p, 1.25)
		results.append(r.get("reason", "-"))
		await _ticks(40)
		n += 1
	var shape_off := g.helmet.shape.disabled
	_log.append("on the helmet: weak point %s; strikes %s; helmet broken %s after %d charged strikes, its collision off %s, weak point now %s" % [wp_before, str(results), str(g.helmet.is_broken), n, str(shape_off), g.weak_point.state_name()])
	_check(wp_before == "PROTECTED", "the weak point was open under the helmet")
	_check(results[0] == &"too_weak", "a weak strike cracked the helmet")
	_check(g.helmet.is_broken and n == g.helmet_hits, "helmet did not break after %d charged strikes" % g.helmet_hits)
	_check(shape_off, "the broken helmet still collides")
	_check(g.weak_point.state == WeakPoint.State.OPEN, "the weak point did not open")


func test_armor_plate_rejects_invalid_hits() -> void:
	var w := await _setup_gaius(13, true)
	var g: Gaius = w.gaius
	var plate := g.helmet
	var at := plate.world_point()
	var rows := []
	rows.append(plate.try_hit(at, 1.0, &"arrow").reason)
	rows.append(plate.try_hit(at + Vector3.UP * 3.0, 1.0, &"sword").reason)
	rows.append(plate.try_hit(at, 0.3, &"sword").reason)
	rows.append(plate.try_hit(at, 0.9, &"sword").reason)
	_log.append("arrow / out of range / weak / charged: %s, hits %d" % [str(rows), plate.hits])
	_check(rows == [&"not_a_sword", &"out_of_range", &"too_weak", &"armor_cracked"], "armour plate rules wrong: %s" % str(rows))


func test_gaius_can_be_defeated() -> void:
	var w := await _setup_gaius(13, true)
	var g: Gaius = w.gaius
	var p: PlayerCharacter = w.player
	var e: BossEncounter = w.encounter
	g._set_encounter(Gaius.Encounter.COMBAT)
	await _ticks(90)
	for k in g.helmet_hits:
		g.helmet.try_hit(g.helmet.world_point(), 1.0, &"sword")
	await _ticks(60)
	var head := g._seg_by_bone[&"head"] as BodySegment
	p.global_position = head.target_transform * (Gaius.WEAK_POINT_LOCAL + Vector3(0, 1.1, 0.15))
	p.velocity = Vector3.ZERO
	p.facing = g.global_basis.z
	p.reset_physics_interpolation()
	await _ticks(30)
	p.actions.grab_held = true
	await _ticks(5)
	var n := 0
	while g.encounter != Gaius.Encounter.DEFEATED and n < 6:
		p.stamina.value = 100.0
		await _sword_strike(p, 1.25)
		await _ticks(30)
		n += 1
	for i in 60 * 9:
		await _ticks(1)
	var head_y := (head.target_transform * Gaius.WEAK_POINT_LOCAL).y
	_log.append("helmet broken, %d full strikes: %s, banner '%s', head top after the kneel %.1f m" % [n, g.encounter_name(), e.banner, head_y])
	_check(g.encounter == Gaius.Encounter.DEFEATED, "not defeated")
	_check(e.banner == "COLOSSUS DEFEATED", "no defeat banner")
	_check(n <= 4, "too many strikes (%d)" % n)
	_check(head_y < 4.5, "the defeated Gaius leaves the head too high (%.1f m)" % head_y)


func test_gaius_scripted_driver_can_complete_fight() -> void:
	var w := await _setup_gaius()
	var bot := GaiusBot.new()
	_world.add_child(bot)
	bot.setup(w.player, w.gaius, w.encounter)
	for i in 60 * 360:
		await _ticks(1)
		if bot.phase == ValusBot.Phase.DONE:
			break
	var r := bot.result
	_log.append("%s in %.1f s; %s; boss %s" % ["WIN" if r.get("won", false) else "NO WIN", r.get("time", -1.0), str(r.get("stats", {})), str(r.get("boss", {}))])
	_metric("gaius_bot_time", r.get("time", 999.0), "lower")
	_check(r.get("won", false), "the scripted driver did not beat Gaius: %s" % " | ".join(bot.events.slice(-8)))


func test_gaius_simulation_independent_of_render_fps() -> void:
	var exe := OS.get_executable_path()
	var rates := [30, 60, 90, 120, 144, 240]
	var results := {}
	for fps in rates:
		var out_path := ProjectSettings.globalize_path("res://tests/output/gaius_fps_%d.json" % fps)
		var output := []
		var code := OS.execute(exe, ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--fixed-fps", str(fps), "--quit-after", "400000", "res://tests/fps_scenario.tscn", "--", "--scenario=gaius", "--out=" + out_path], output, true)
		if code != 0 or not FileAccess.file_exists(out_path):
			_check(false, "gaius scenario at %d fps failed (code %d)" % [fps, code])
			return
		results[fps] = JSON.parse_string(FileAccess.get_file_as_string(out_path))
	var diff := _max_json_diff(results, rates)
	var ref: Dictionary = results[60]
	_log.append("Gaius fight (bot) at %s fps: won %s at tick %d, slams %d, max state difference %.8f" % [str(rates), str(ref.won), int(ref.tick), int(ref.slams), diff])
	_metric("gaius_fps_max_diff", diff, "lower")
	_check(int(ref.won) == 1, "reference run did not win")
	_check(diff < 1e-4, "the Gaius fight depends on the render rate (diff %.6f)" % diff)


func test_gaius_cost_stays_within_budget() -> void:
	Fx.enabled = true
	var w := await _setup_gaius()
	Fx.enabled = true
	var g: Gaius = w.gaius
	var bot := GaiusBot.new()
	_world.add_child(bot)
	bot.setup(w.player, g, w.encounter)
	await _ticks(60 * 10)
	Perf.take()
	var ticks := 60 * 25
	var physics_ms := 0.0
	for i in ticks:
		await _ticks(1)
		physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var m := Perf.take()
	var u: Dictionary = m.usec
	var per := func(k: StringName) -> float: return float(u.get(k, 0)) / ticks
	var colossus: float = per.call(&"colossus")
	_log.append("Gaius fight (bot, 25 s: slams, blade, arm): colossus %.1f us/tick = brain %.1f + combat %.1f + hits %.1f + pose (sword arm IK incl.) %.1f + locomotion %.1f + IK %.1f; player %.1f (climb %.1f); physics tick %.3f ms" % [colossus, per.call(&"brain"), per.call(&"boss_combat"), per.call(&"boss_hits"), per.call(&"boss_pose"), per.call(&"locomotion"), per.call(&"ik"), per.call(&"player"), per.call(&"climb"), physics_ms / ticks])
	_metric("gaius_colossus_us", colossus, "lower")
	_check(colossus < 500.0, "Gaius logic too expensive: %.0f us/tick" % colossus)
	Fx.enabled = false


func test_attacks_respect_cooldowns_all_bosses() -> void:
	# Regression: an attack that ran to DONE must start its cooldown (FairnessRules).
	var rows := []
	for which in ["quadratus", "gaius"]:
		var w: Dictionary
		if which == "quadratus":
			w = await _setup_quadratus()
		else:
			w = await _setup_gaius()
		var c: Colossus = w.quadratus if which == "quadratus" else w.gaius
		var p: PlayerCharacter = w.player
		c.call(&"_set_encounter", 3)  # COMBAT
		var starts := {}
		# Attacks that really happened (wound up); one given up before its telegraph is not.
		c.attack_phase_changed.connect(func(a: ColossusAttack) -> void:
			if a.phase != ColossusAttack.Phase.TELEGRAPH:
				return
			if not starts.has(a.kind):
				starts[a.kind] = []
			starts[a.kind].append(c._time))
		for i in 60 * 50:
			# Keep standing in its attack range (and out of the way after each hit).
			if i % 120 == 0:
				var local := Vector3(-2.5, 0.95, -15.0) if which == "gaius" else Vector3(-4.0, 0.95, -11.0)
				p.global_position = c.global_transform * local
				p.velocity = Vector3.ZERO
				p.health = 100.0
				p.reset_physics_interpolation()
			await _ticks(1)
		var rules: FairnessRules = c.get(&"rules")
		var min_gap := 99.0
		var worst := ""
		for kind in starts:
			var ts: Array = starts[kind]
			for k in range(1, ts.size()):
				var gap: float = ts[k] - ts[k - 1]
				if gap < min_gap:
					min_gap = gap
					worst = kind
		rows.append("%s: starts %s, shortest same-kind gap %.1f s (%s)" % [which, str(starts.keys().map(func(k: StringName) -> String: return "%s x%d" % [k, (starts[k] as Array).size()])), min_gap, worst])
		for kind in starts:
			var ts: Array = starts[kind]
			for k in range(1, ts.size()):
				_check(float(ts[k]) - float(ts[k - 1]) >= float(rules.cooldowns.get(kind, 0.0)), "%s: %s again after %.1f s (cooldown %.1f)" % [which, kind, float(ts[k]) - float(ts[k - 1]), float(rules.cooldowns.get(kind, 0.0))])
		_check(starts.size() > 0, "%s never attacked" % which)
		await _teardown()
	_log.append("; ".join(rows))


func test_art_layer_does_not_change_gameplay() -> void:
	# 1) The same 8 s of Valus walking with and without art, each in its own process.
	var exe := OS.get_executable_path()
	var runs := {}
	for art in [false, true]:
		var out_path := ProjectSettings.globalize_path("res://tests/output/art_check_%s.json" % str(art))
		var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--fixed-fps", "60", "--quit-after", "100000", "res://tests/fps_scenario.tscn", "--", "--scenario=art", "--out=" + out_path]
		if art:
			args.append("--art")
		var output := []
		var code := OS.execute(exe, args, output, true)
		if code != 0 or not FileAccess.file_exists(out_path):
			_check(false, "art scenario failed (code %d)" % code)
			return
		runs[art] = JSON.parse_string(FileAccess.get_file_as_string(out_path))
	var diff := _max_json_diff({60: runs[false], 61: runs[true]}, [60, 61])
	# 2) Collision and climb surfaces of the colossus, and what is drawn.
	var facts := []
	for art in [false, true]:
		Sfx.enabled = false
		Fx.enabled = false
		_world = Node3D.new()
		_world.name = "World_%s_%s" % [_current, str(art)]
		add_child(_world)
		var w := ValusArena.build_encounter(_world, false, 7, art)
		var v: Valus = w.valus
		await _ticks(5)
		var shapes := 0
		var patches := 0
		var art_nodes := 0
		var visible_greybox := 0
		for sg in v.segments:
			for c in sg.get_children():
				if c is CollisionShape3D:
					shapes += 1
					if c is ClimbPatch:
						patches += 1
				elif c.name == "ArtVisual":
					art_nodes += 1
				elif c is MeshInstance3D and (c as MeshInstance3D).visible:
					visible_greybox += 1
		# New collision from art props stays outside the fight (radius 55 m).
		var near_new := 0
		var terrain := false
		for c in _world.get_children():
			if c.get_script() == ArenaArt.Asset and (c as Node3D).collidable and _flatv((c as Node3D).global_position).length() < 55.0:
				near_new += 1
			if c.name == "Ground":
				for m in c.get_children():
					if m is MeshInstance3D and (m as MeshInstance3D).material_override == ArenaArt.TERRAIN:
						terrain = true
		facts.append({"shapes": shapes, "patches": patches, "art": art_nodes, "greybox_visible": visible_greybox, "art_collision_in_fight": near_new, "terrain": terrain})
		await _teardown()
	_log.append("8 s of walking, art off / on in separate processes: max state difference %.8f; colossus off %s / on %s" % [diff, str(facts[0]), str(facts[1])])
	_check(diff < 1e-6, "the art layer changed the simulation (%.6f)" % diff)
	_check(facts[0].shapes == facts[1].shapes and facts[0].patches == facts[1].patches, "the art layer changed collision / climb surfaces")
	_check(int(facts[1].art) == 17 and bool(facts[1].terrain), "the art was not attached")
	_check(int(facts[1].greybox_visible) < int(facts[0].greybox_visible), "greybox parts still drawn under the art")
	_check(int(facts[1].art_collision_in_fight) == 0, "art props with collision inside the fight area")


func test_quadratus_lurch_unsettles_standing_player_fairly() -> void:
	var w := await _setup_quadratus()
	var q: Quadratus = w.quadratus
	var p: PlayerCharacter = w.player
	q._set_encounter(Quadratus.Encounter.COMBAT)
	await _ticks(30)
	var body := q._seg_by_bone[&"body"] as BodySegment
	var lurches := []
	var cur := {}
	var falls := 0
	for i in 60 * 40:
		if p.state == PlayerCharacter.State.GROUND and not q.owns_body(p.get_support_body()) or i == 0:
			p.global_position = body.target_transform * Vector3(0, 3.3, 1.5)
			p.velocity = Vector3.ZERO
			p.reset_physics_interpolation()
			if i > 0:
				falls += 1
		p.stamina.value = 100.0
		await _ticks(1)
		if q.intent.kind == Quadratus.LURCH:
			if cur.is_empty():
				cur = {"t0": i * DT, "move": -1.0, "min_bal": 1.0, "peak_speed": 0.0}
			if q.loco.speed > 0.3 and cur.move < 0.0:
				cur.move = i * DT
			cur.min_bal = minf(cur.min_bal, p.balance.value)
			cur.peak_speed = maxf(cur.peak_speed, q.loco.speed)
		elif not cur.is_empty():
			lurches.append(cur)
			cur = {}
	var briefs := lurches.map(func(l: Dictionary) -> String: return "brace %.2f s, peak %.1f m/s, balance min %.2f" % [l.move - l.t0 if l.move > 0.0 else -1.0, l.peak_speed, l.min_bal])
	_log.append("40 s standing on the back: %d lurches [%s], thrown off %d times" % [lurches.size(), "; ".join(briefs), falls])
	_check(lurches.size() >= 2, "it never lurched against a standing player")
	for l in lurches:
		_check(l.move < 0.0 or l.move - l.t0 >= q.lurch_telegraph - 0.05, "lurch without a telegraph")
		_check(l.min_bal < 0.8, "a lurch did not unsettle the standing player")


func test_quadratus_crown_needs_second_kneel() -> void:
	var w := await _setup_quadratus(11, true)
	var q: Quadratus = w.quadratus
	q._set_encounter(Quadratus.Encounter.COMBAT)
	await _ticks(30)
	var states := ["start " + q.crown.state_name()]
	q._on_sole_hit({"tag": 2, "point": q.sole_world(2)})
	await _ticks(120)
	states.append("kneel, rump intact " + q.crown.state_name())
	for k in 3:
		q.rump.try_hit(q.rump.world_point(), 1.0, &"sword")
	await _ticks(5)
	var rising := q.buckle_name()
	states.append("rump destroyed (%s) %s" % [rising, q.crown.state_name()])
	for i in 60 * 6:
		await _ticks(1)
	states.append("standing again " + q.crown.state_name())
	q._buckle_cooldown_left = 0.0
	q._on_sole_hit({"tag": 3, "point": q.sole_world(3)})
	await _ticks(120)
	states.append("second kneel " + q.crown.state_name())
	var t := 0.0
	while q.buckle != Quadratus.Buckle.RISE and t < 30.0:
		await _ticks(1)
		t += DT
	states.append("it rises after %.1f s: %s" % [t, q.crown.state_name()])
	_log.append(" -> ".join(states))
	_check(states[0].ends_with("PROTECTED") and states[1].ends_with("PROTECTED"), "the crown was open before the rump was destroyed")
	_check(rising == "RISE", "it did not get up when the rump was destroyed")
	_check(states[3].ends_with("PROTECTED"), "the crown open while it stands")
	_check(states[4].ends_with("OPEN"), "the crown did not open on the second kneel")
	# t counts from 2 s after the hit; the kneel starts after the reaction.
	_check(t + 2.0 - q.react_time >= q.kneel_time_crown - 0.05, "the second kneel was not the long one")


func test_bow_aim_zooms_camera_over_shoulder() -> void:
	var w := await _setup_quadratus()
	var p: PlayerCharacter = w.player
	var cam: PlayerCamera = w.camera
	p.set_weapon(PlayerCharacter.Weapon.BOW)
	await _ticks(60)
	var d0 := cam.get_distance()
	var fov0 := cam.fov
	p.actions.attack_held = true
	var d1 := 99.0
	for i in 60:
		await _process_frames(1)
		d1 = minf(d1, cam.get_distance())
	var fov1 := cam.fov
	var side := (cam.global_position - p.global_position).dot(cam.global_basis.x)
	p.actions.attack_held = false
	await _process_frames(90)
	_log.append("camera: %.1f m / fov %.0f -> drawing %.1f m / fov %.0f, %.2f m to the right of the archer -> after the shot %.1f m / fov %.0f" % [d0, fov0, d1, fov1, side, cam.get_distance(), cam.fov])
	_check(d1 < d0 - 1.0 and fov1 < fov0 - 10.0, "no aiming view while drawing")
	_check(side > 0.3, "the aiming view is not over the right shoulder")
	_check(absf(cam.fov - fov0) < 1.0, "the view did not return after the shot")


func _process_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func test_arrow_glances_off_stone() -> void:
	var w := await _setup_quadratus(11, true)
	var q: Quadratus = w.quadratus
	var p: PlayerCharacter = w.player
	await _ticks(30)
	p.global_position = q.global_transform * Vector3(-12, 0.95, -5)
	p.reset_physics_interpolation()
	p.set_weapon(PlayerCharacter.Weapon.BOW)
	await _ticks(10)
	var reasons := []
	var sys := ArrowSystem.of(p)
	sys.impact.connect(func(info: Dictionary) -> void: reasons.append([info.reason, (info.segment as BodySegment).bone_name if info.segment else &"ground"]))
	# Stone: the front hoof. Fur: the thigh.
	for target in [(q._seg_by_bone[&"fl_low"] as BodySegment).target_transform * Vector3(0, -1.8, 0), (q._seg_by_bone[&"body"] as BodySegment).target_transform * Vector3(-3.2, 0.0, -1.0)]:
		_aim_bow(p, PlayerBow.launch_direction(p.bow.bow_point(p), target, p.bow.speed_for(1.0)))
		var a := await _shoot(p, 1.2)
		await _wait_arrow(a)
		await _ticks(10)
		reasons.append(["--", a.state, str(a.segment.bone_name) if a.segment else "-"])
	_log.append("impacts: %s" % str(reasons))
	_check(reasons[0][0] == &"bounce" and reasons[0][1] == &"fl_low", "the arrow did not glance off the stone shin")
	var last_fur: Array = reasons[-1]
	_check(last_fur[1] == &"stuck" and last_fur[2] == "body", "the arrow did not stick in the fur")


## Everything that ran before the Etap 7 tests passed.
func all_etap6_and_earlier_tests_still_pass() -> void:
	var ran := 0
	var failed := PackedStringArray()
	for n in _pre_etap7_results:
		ran += 1
		if not _pre_etap7_results[n]:
			failed.append(n)
	_log.append("%d earlier tests (Milestone 1, Etap 2-6) ran in this run, %d failed %s" % [ran, failed.size(), str(failed) if failed.size() > 0 else ""])
	_check(failed.is_empty(), "earlier tests failed: %s" % str(failed))


# --- ETAP 8: the valley, the sword's beam, the whole game -----------------------------

## A GameWorld under the test world (no art, no input). ``save`` = save file ("" = none).
func _setup_game(save := "") -> GameWorld:
	Sfx.enabled = false
	Fx.enabled = false
	_world = Node3D.new()
	_world.name = "World_" + _current
	add_child(_world)
	var g := GameWorld.new()
	g.with_input = false
	g.with_art = false
	g.save_path = save
	_world.add_child(g)
	g.start(save == "")
	await _ticks(2)
	return g


## The Valus arena with a frozen Valus: flat open ground, the player and Agro.
func _setup_plain_arena() -> Dictionary:
	Sfx.enabled = false
	Fx.enabled = false
	_world = Node3D.new()
	_world.name = "World_" + _current
	add_child(_world)
	var w := ValusArena.build_encounter(_world, false, 7)
	(w.valus as Valus).debug_override = &"frozen"
	await _ticks(2)
	return w


func _wait_region(g: GameWorld, kind: StringName, max_ticks: int) -> bool:
	for i in max_ticks:
		if g.region_kind == kind and g.phase == GameWorld.Phase.PLAYING:
			return true
		await _ticks(1)
	return g.region_kind == kind and g.phase == GameWorld.Phase.PLAYING


func test_game_state_save_load_roundtrip() -> void:
	var path := "user://test_etap8_state.json"
	var s := GameState.new()
	_check(s.next_colossus() == &"valus", "a new game does not lead to Valus")
	s.mark_defeated(&"valus")
	s.mark_defeated(&"valus")
	s.mark_defeated(&"nobody")
	s.play_time = 123.5
	s.deaths = 2
	_check(s.defeated.size() == 1 and s.next_colossus() == &"quadratus", "progress after Valus is wrong: %s" % str(s.defeated))
	_check(s.save(path), "saving failed")
	var l := GameState.new()
	var ok := l.load_from(path)
	_check(ok and l.defeated == s.defeated and is_equal_approx(l.play_time, 123.5) and l.deaths == 2, "the loaded state differs: %s" % str(l.to_dict()))
	# Out of order or unknown names in a file never skip a colossus.
	var gap := GameState.new()
	gap.from_dict({"version": GameState.VERSION, "defeated": ["quadratus", "gaius", "x"]})
	_check(gap.defeated.is_empty() and gap.next_colossus() == &"valus", "a save with a gap skipped a colossus: %s" % str(gap.defeated))
	# A broken or foreign file is a new game, not a crash.
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	var b := GameState.new()
	_check(not b.load_from(path) and b.defeated.is_empty(), "a broken save was not treated as a new game")
	_check(not GameState.new().load_from("user://does_not_exist.json"), "a missing save was not a new game")
	var all := GameState.new()
	for c in GameState.ORDER:
		all.mark_defeated(c)
	_check(all.is_complete() and all.next_colossus() == &"", "three defeats do not complete the game")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_log.append("save: %s" % JSON.stringify(s.to_dict()))


func test_sword_beam_gathers_towards_target() -> void:
	var w := await _setup_plain_arena()
	var p: PlayerCharacter = w.player
	var a := p.actions
	var target := Vector3(0, 0, 0)    # straight ahead (-Z) of the arena entrance
	p.beam.target = target
	a.view_basis = Basis.IDENTITY
	a.beam_held = true
	await _ticks(60)
	_check(p.beam.raised and p.beam.raise >= 1.0 and p.beam.lit, "the sword was not raised to the sun (raise %.2f lit %s)" % [p.beam.raise, p.beam.lit])
	_check(p.beam.locked and p.beam.direction.dot((target - p.global_position).normalized()) > 0.95, "looking at the target, the beam did not gather (focus %.2f)" % p.beam.focus)
	var locked_focus := p.beam.focus
	# Looking 30 degrees off: partly gathered; 90 degrees off: scattered.
	a.view_basis = Basis(Vector3.UP, 0.52)
	await _ticks(40)
	var partial := p.beam.focus
	a.view_basis = Basis(Vector3.UP, PI * 0.5)
	await _ticks(40)
	var off := p.beam.focus
	_check(partial > 0.05 and partial < 0.9, "30 degrees off the beam should be partly gathered (%.2f)" % partial)
	_check(off < 0.01 and not p.beam.locked, "90 degrees off the beam still gathered (%.2f)" % off)
	# Moving with the sword up is a slow walk.
	a.move = Vector2(0, 1)
	await _ticks(60)
	var speed := Vector2(p.velocity.x, p.velocity.z).length()
	_check(speed < p.run_speed * 0.4, "walking with the sword raised is not slow (%.2f m/s)" % speed)
	a.move = Vector2.ZERO
	# In shadow (a roof between the blade and the sun) the beam does not gather.
	a.view_basis = Basis.IDENTITY
	var roof := TerrainKit.box(_world, p.global_position + Valley.SUN_DIRECTION.normalized() * 6.0, Vector3(8, 1, 8), StandardMaterial3D.new())
	await _ticks(40)
	_check(not p.beam.lit and p.beam.focus < 0.01, "in shadow the beam still shone (lit %s focus %.2f)" % [p.beam.lit, p.beam.focus])
	roof.queue_free()
	await _ticks(40)
	_check(p.beam.lit and p.beam.focus > 0.9, "back in the sun the beam did not return (%.2f)" % p.beam.focus)
	# Only with the sword in hand.
	p.set_weapon(PlayerCharacter.Weapon.BOW)
	await _ticks(20)
	_check(not p.beam.raised and p.beam.focus < 0.01, "the beam works with the bow in hand")
	_log.append("focus: locked %.2f, 30 deg %.2f, 90 deg %.2f; walk with sword up %.2f m/s; sun rays %d" % [locked_focus, partial, off, speed, p.beam.sun_rays])


func test_sword_beam_works_from_agro() -> void:
	var w := await _setup_plain_arena()
	var p: PlayerCharacter = w.player
	var h: Horse = w.horse
	p.riding.mount_now(h)
	await _ticks(10)
	_check(p.is_riding(), "not in the saddle")
	p.beam.target = Vector3(0, 0, 0)
	var yaw0 := h.controller.yaw
	p.actions.beam_held = true
	# Sweep the view round with the sword up: only the view turns, not the horse.
	for i in 90:
		p.actions.view_basis = Basis(Vector3.UP, sin(i * 0.07) * 1.2)
		await _ticks(1)
	p.actions.view_basis = Basis.IDENTITY
	await _ticks(40)
	_check(p.beam.raised and p.beam.locked, "from the saddle the beam did not gather (focus %.2f)" % p.beam.focus)
	_check(absf(wrapf(h.controller.yaw - yaw0, -PI, PI)) < 0.02, "raising the sword turned Agro (%.3f rad)" % (h.controller.yaw - yaw0))


func test_valley_ground_world_edge_and_closed_gates() -> void:
	var t0 := Time.get_ticks_msec()
	var g := await _setup_game()
	var build_ms := Time.get_ticks_msec() - t0
	var p := g.player()
	await _ticks(60)
	var ground := Valley.ground_height(p.global_position.x, p.global_position.z)
	_check(p.state == PlayerCharacter.State.GROUND and absf(p.global_position.y - (ground + 0.95)) < 0.25, "the player does not stand in the temple (y %.2f, ground %.2f, state %d)" % [p.global_position.y, ground, p.state])
	var h: Horse = g.refs.horse
	_check(absf(h.global_position.y - Valley.ground_height(h.global_position.x, h.global_position.z)) < 0.6, "Agro does not stand on the valley floor")
	var gates: Dictionary = g.refs.gates
	_check(gates[&"valus"].open and not gates[&"quadratus"].open and not gates[&"gaius"].open, "a new game should open only the way to Valus")
	# The world's edge holds.
	p.global_position = Valley.on_ground(Vector3(-160, 0, -120), 1.2)
	p.reset_physics_interpolation()
	p.actions.view_basis = Basis(Vector3.UP, PI * 0.5)   # looking -X
	p.actions.move = Vector2(0, 1)
	await _ticks(60 * 5)
	var edge_x := p.global_position.x
	_check(edge_x > -Valley.EDGE - 0.5 and edge_x < -160.0, "walked off the world's edge (x %.1f)" % edge_x)
	# A closed gate is a wall of mist.
	var q: Dictionary = gates[&"quadratus"]
	p.global_position = Valley.on_ground((q.pos as Vector3) - (q.out as Vector3) * 8.0, 1.2)
	p.reset_physics_interpolation()
	p.actions.view_basis = Basis.looking_at(q.out)
	await _ticks(60 * 4)
	var through := (p.global_position - (q.pos as Vector3)).dot(q.out)
	_check(through < 0.0 and g.region_kind == GameWorld.VALLEY, "walked through a closed gate (%.2f m past it, region %s)" % [through, g.region_kind])
	p.actions.move = Vector2.ZERO
	_log.append("valley built in %d ms (no grass); temple floor %.2f m; edge stop x %.1f; closed gate stop %.2f m before" % [build_ms, ground, edge_x, -through])
	_metric("valley_build_ms", build_ms, "info")


func test_open_gate_leads_to_next_colossus() -> void:
	var g := await _setup_game()
	var p := g.player()
	var gate: Dictionary = g.refs.gates[&"valus"]
	var out: Vector3 = gate.out
	# On horseback through the open gate: arrive in the Valus arena, still in the saddle.
	var h: Horse = g.refs.horse
	h.teleport(Valley.on_ground((gate.pos as Vector3) - out * 12.0), atan2(-out.x, -out.z))
	await _ticks(2)
	p.riding.mount_now(h)
	p.actions.view_basis = Basis.looking_at(out)
	p.actions.move = Vector2(0, 1)
	var arrived := await _wait_region(g, &"valus", 60 * 20)
	await _ticks(2)
	p = g.player()
	_check(arrived and g.colossus() is Valus, "riding through the gate did not lead to Valus (region %s)" % g.region_kind)
	_check(p.is_riding() and p.riding.horse == g.refs.horse, "arrived on foot although we rode through the gate")
	_check(p.beam.target.distance_to(g.colossus().beam_target()) < 0.01 and g.colossus().beam_weak_point() != null, "in the arena the beam does not lead to the weak point")
	# Raise the sword towards the weak point: it lights up.
	p.actions.move = Vector2.ZERO
	var wp := g.colossus().beam_weak_point()
	for i in 90:
		var to := wp.world_point() - p.global_position
		p.actions.view_basis = Basis.looking_at(Vector3(to.x, 0, to.z).normalized())
		p.actions.beam_held = true
		await _ticks(1)
	_check(p.beam.locked and wp.revealed > 0.5, "the beam did not reveal the weak point (focus %.2f, revealed %.2f)" % [p.beam.focus, wp.revealed])
	_log.append("through the gate after %d transitions, riding %s" % [g.transitions, str(p.is_riding())])


func test_leaving_arena_returns_to_its_gate() -> void:
	var g := await _setup_game()
	var p := g.player()
	var gate: Dictionary = g.refs.gates[&"valus"]
	p.global_position = Valley.on_ground((gate.pos as Vector3) - (gate.out as Vector3) * 2.0, 1.0)
	p.reset_physics_interpolation()
	p.actions.view_basis = Basis.looking_at(gate.out)
	p.actions.move = Vector2(0, 1)
	_check(await _wait_region(g, &"valus", 60 * 10), "did not reach the arena")
	p = g.player()
	await _ticks(10)
	# Turn round and walk back out through the entrance.
	p.actions.view_basis = Basis(Vector3.UP, PI)
	p.actions.move = Vector2(0, 1)
	_check(await _wait_region(g, GameWorld.VALLEY, 60 * 15), "walking out of the arena did not lead back to the valley")
	p = g.player()
	var d := Vector2(p.global_position.x - gate.pos.x, p.global_position.z - gate.pos.z).length()
	_check(d < 20.0, "back in the valley %.1f m from the Valus gate (expected next to it)" % d)
	_check(g.state.defeated.is_empty() and g.refs.gates[&"valus"].open, "leaving the fight changed the progress")


func test_defeat_returns_to_temple_and_saves() -> void:
	var path := "user://test_etap8_save.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var g := await _setup_game(path)
	var p := g.player()
	var gate: Dictionary = g.refs.gates[&"valus"]
	p.global_position = Valley.on_ground((gate.pos as Vector3) - (gate.out as Vector3) * 2.0, 1.0)
	p.reset_physics_interpolation()
	p.actions.view_basis = Basis.looking_at(gate.out)
	p.actions.move = Vector2(0, 1)
	_check(await _wait_region(g, &"valus", 60 * 10), "did not reach the arena")
	var bot := ValusBot.new()
	g.region.add_child(bot)
	bot.setup(g.player(), g.colossus(), g.refs.encounter)
	var fight := {}
	bot.finished.connect(func(r: Dictionary) -> void: fight.merge(r))
	var back := await _wait_region(g, GameWorld.VALLEY, 60 * 240)
	_check(back and fight.get("won", false), "the fight was not won and followed by the temple")
	await _ticks(2)
	p = g.player()
	_check(p.global_position.distance_to(Valley.on_ground(Valley.TEMPLE_SPAWN, 0.95)) < 1.5, "after the victory the player is not in the temple (%s)" % str(p.global_position))
	_check(g.state.defeated == [&"valus"] and g.state.next_colossus() == &"quadratus", "progress after Valus is wrong: %s" % str(g.state.defeated))
	var gates: Dictionary = g.refs.gates
	_check(gates[&"quadratus"].open and not gates[&"valus"].open, "the way should now lead to Quadratus only")
	var saved := GameState.new()
	_check(saved.load_from(path) and saved.defeated == [&"valus"], "the victory was not saved")
	_check(g.player().beam.target.distance_to(gates[&"quadratus"].trigger) < 0.01, "the beam does not lead to the next gate")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_log.append("won in %.1f s, saved %s" % [float(fight.get("time", 0.0)), JSON.stringify(saved.to_dict())])


func test_no_mounting_while_knocked_down() -> void:
	var w := await _setup_plain_arena()
	var p: PlayerCharacter = w.player
	var h: Horse = w.horse
	p.global_position = h.saddle_transform().origin + h.global_basis.x * -1.4
	p.global_position.y = 0.95
	p.reset_physics_interpolation()
	await _ticks(20)
	p.balance.knock_down(1.5)
	for i in 30:
		if i % 5 == 0:
			p.actions.press_interact()
		await _ticks(1)
	_check(not p.is_riding(), "mounted Agro while lying on the ground")
	var waited := 0
	while p.balance.state == Balance.State.FALLEN and waited < 60 * 5:
		await _ticks(1)
		waited += 1
	p.actions.press_interact()
	await _ticks(60)
	_check(p.is_riding(), "could not mount after getting up")
	# Knocked over in the saddle (e.g. right after a hit): the rider recovers there.
	p.balance.knock_down(1.0)
	await _ticks(60 * 3)
	_check(p.balance.state != Balance.State.FALLEN and PlayerBow.can_use(p), "in the saddle the rider never recovered (bow unusable)")


func test_game_bot_finds_way_with_beam() -> void:
	var g := await _setup_game()
	var bot := GameBot.new()
	_world.add_child(bot)
	bot._heading = Vector3.BACK   # first guess: the wrong way
	bot.setup(g)
	var arrived := await _wait_region(g, &"valus", 60 * 120)
	_check(arrived, "the bot did not find the way to Valus (phase %s, events %s)" % [GameBot.Phase.keys()[bot.phase], str(bot.events.slice(-6))])
	_check(int(bot.stats.beam_locks) >= 1, "the bot found the way without the beam")
	_check(bot.stats.stalls.is_empty(), "stalls on the way: %s" % str(bot.stats.stalls))
	_log.append("temple -> Valus gate: %.1f s (riding %.1f s), beam sweeps %d, locks %d, detours %d" % [bot.time, float(bot.stats.ride_time), int(bot.stats.beam_sweeps), int(bot.stats.beam_locks), int(bot.stats.detours)])
	_metric("game_temple_to_valus_s", bot.time, "lower")


func test_valley_simulation_independent_of_render_fps() -> void:
	var exe := OS.get_executable_path()
	var rates := [30, 60, 144, 240]
	var results := {}
	for fps in rates:
		var out_path := ProjectSettings.globalize_path("res://tests/output/valley_fps_%d.json" % fps)
		var output := []
		var code := OS.execute(exe, ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--fixed-fps", str(fps), "--quit-after", "400000", "res://tests/fps_scenario.tscn", "--", "--scenario=valley", "--out=" + out_path], output, true)
		if code != 0 or not FileAccess.file_exists(out_path):
			_check(false, "valley scenario at %d fps failed (code %d)" % [fps, code])
			return
		results[fps] = JSON.parse_string(FileAccess.get_file_as_string(out_path))
	var diff := _max_json_diff(results, rates)
	var ref: Dictionary = results[60]
	_log.append("temple -> Valus gate (bot, beam, Agro) at %s fps: arrived at tick %d, max state difference %.8f" % [str(rates), int(ref.tick), diff])
	_metric("valley_fps_max_diff", diff, "lower")
	_check(int(ref.arrived) == 1, "reference run did not reach the gate")
	_check(diff < 1e-4, "the valley ride depends on the render rate (diff %.6f)" % diff)


func test_valley_cost_stays_within_budget() -> void:
	var g := await _setup_game()
	var bot := GameBot.new()
	_world.add_child(bot)
	bot._heading = Vector3.FORWARD
	bot.setup(g)
	# Wait until it rides, then measure 15 s of riding (with beam checks from the saddle).
	var waited := 0
	while bot.phase != GameBot.Phase.RIDE and waited < 60 * 30:
		await _ticks(1)
		waited += 1
	Perf.take()
	var ticks := 60 * 15
	# Wall clock per tick (the engine's physics monitor is not reliable with --fixed-fps
	# headless): everything the engine does in a tick, physics server included.
	var t0 := Time.get_ticks_usec()
	await _ticks(ticks)
	var physics_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var m := Perf.take()
	var u: Dictionary = m.usec
	var q: Dictionary = m.queries
	var per := func(k: StringName) -> float: return float(u.get(k, 0)) / ticks
	_log.append("valley ride (bot, 15 s): player %.1f us/tick (beam %.1f, mount %.1f), Agro %.1f us (controller %.1f, probes %.1f, steps %.1f), camera %.1f us; beam rays %.2f/tick, horse rays %.1f/tick; whole tick (wall clock) %.3f ms" % [
		per.call(&"player"), per.call(&"beam"), per.call(&"mount"), per.call(&"horse"), per.call(&"horse_controller"), per.call(&"horse_probes"), per.call(&"horse_steps"), per.call(&"camera"),
		float(q.get(&"beam_rays", 0)) / ticks, float(q.get(&"horse_rays", 0)) / ticks, physics_ms / ticks])
	_metric("valley_player_us", per.call(&"player"), "lower")
	_metric("valley_horse_us", per.call(&"horse"), "lower")
	_check(float(q.get(&"beam_rays", 0)) / ticks <= 0.25, "the beam casts too many rays")
	_check(per.call(&"beam") < 40.0, "the beam costs too much (%.1f us/tick)" % per.call(&"beam"))
	_check(physics_ms / ticks < 4.0, "a valley tick takes %.2f ms" % (physics_ms / ticks))


func test_gaius_head_phase_is_fair_and_smooth() -> void:
	var w := await _setup_gaius()
	var g: Gaius = w.gaius
	var p: PlayerCharacter = w.player
	var bot := GaiusBot.new()
	_world.add_child(bot)
	bot.setup(p, g, w.encounter)
	var hits: Array[float] = []
	var shakes: Array[float] = []
	var t := 0.0
	# Lambdas copy locals: they read the clock from the colossus instead.
	g.weak_point.struck.connect(func(_d: float, _h: float) -> void: hits.append(g._time))
	g.intent_changed.connect(func(i: ColossusIntent) -> void:
		if i.kind in g._shake_kinds():
			shakes.append(g._time))
	var max_jump := 0.0
	var max_body := 0.0
	var prev := p.visual.global_position
	var prev_body := p.global_position
	var was := false
	for i in 60 * 200:
		await _ticks(1)
		t += DT
		if p.is_climbing() and was:
			# What is drawn (the gameplay capsule may step at an edge wrap; the visual eases it).
			max_jump = maxf(max_jump, p.visual.global_position.distance_to(prev) - p.surface_velocity.length() * DT)
			max_body = maxf(max_body, p.global_position.distance_to(prev_body))
		was = p.is_climbing()
		prev = p.visual.global_position
		prev_body = p.global_position
		if bot.phase == ValusBot.Phase.DONE:
			break
	var calm := g.recover_time + g.shake_after_flinch - 2.0 * DT
	var too_soon := 0
	for h in hits:
		for s in shakes:
			if s > h and s - h < calm:
				too_soon += 1
	_log.append("won %s in %.1f s, deaths %d; weak point hits at %s, shakes %d (%d within %.1f s after a hit); largest drawn body step while gripping %.3f m (gameplay capsule %.3f m)" % [str(bot.result.get("won", false)), t, int(bot.stats.deaths), str(hits.map(func(x: float) -> String: return "%.1f" % x)), shakes.size(), too_soon, calm, max_jump, max_body])
	_metric("gaius_max_grip_body_step", max_jump, "lower")
	# Deaths are counted by the soak (a few in 100 fights); here: the fight is won, and the
	# two properties of the head phase hold over all of it.
	_metric("gaius_head_test_deaths", int(bot.stats.deaths), "info")
	_check(bot.result.get("won", false), "Gaius was not beaten")
	_check(too_soon == 0, "%d shakes started right after a flinch" % too_soon)
	_check(max_jump < 0.3, "the drawn body jumped %.2f m in one tick while gripping" % max_jump)


func test_sentinel_v2_dresses_valus() -> void:
	Sfx.enabled = false
	_world = Node3D.new()
	_world.name = "World_" + _current
	add_child(_world)
	var w := ValusArena.build_encounter(_world, false, 7, true)
	await _ticks(2)
	var v: Valus = w.valus
	var visuals := 0
	var v2_meshes := 0
	var extended := 0
	var cues_visible := 0
	for seg in v.segments:
		for c in seg.get_children():
			if c.name == "ArtVisual":
				visuals += 1
				for m in c.get_children():
					var path := (m as MeshInstance3D).mesh.resource_path if (m as MeshInstance3D).mesh else ""
					if path.contains("sentinel_v2") or (m as MeshInstance3D).mesh != null:
						v2_meshes += 1
				if seg.bone_name in [&"foot_l", &"foot_r"]:
					extended += 1
			elif c is MeshInstance3D and c.visible and c.has_meta(&"kind"):
				cues_visible += 1
	_check(visuals == 17 and v2_meshes == 51, "Sentinel v2: %d of 17 segments dressed, %d of 51 LOD meshes" % [visuals, v2_meshes])
	_check(ArenaArt._extended_feet() and extended == 2, "the 3.6 m feet did not get the extended kit feet")
	_check(cues_visible > 0, "Valus' climbing cues (mane, fur cap, armour) are hidden")
	_log.append("Sentinel v2: %d segments, %d LOD meshes, extended feet %s, %d greybox climbing cues still visible" % [visuals, v2_meshes, str(ArenaArt._extended_feet()), cues_visible])


## Everything that ran before the Etap 8 tests passed.
func all_etap7_and_earlier_tests_still_pass() -> void:
	var ran := 0
	var failed := PackedStringArray()
	for n in _pre_etap8_results:
		ran += 1
		if not _pre_etap8_results[n]:
			failed.append(n)
	_log.append("%d earlier tests (Milestone 1, Etap 2-7) ran in this run, %d failed %s" % [ran, failed.size(), str(failed) if failed.size() > 0 else ""])
	_check(failed.is_empty(), "earlier tests failed: %s" % str(failed))
