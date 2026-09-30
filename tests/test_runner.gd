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


func _ready() -> void:
	InputSetup.ensure_defaults()
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
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
	await _ticks(10)
	await _grab_behind(w, &"shin_l", -1.8)
	p.actions.move = Vector2(0, 1)
	var t0 := Time.get_ticks_usec()
	await _ticks(600)
	var per_tick := (Time.get_ticks_usec() - t0) / 600.0
	_log.append("avg frame (headless, colossus + climbing player + physics): %.3f ms" % (per_tick / 1000.0))
	_check(per_tick < 4000.0, "frame too slow: %.2f ms" % (per_tick / 1000.0))


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
	var target := seg.global_transform * Vector3(0, along, 0) + back * 1.6
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
