class_name HydrusBot
extends Node
## Scripted player for the Hydrus fight (tests, soak, captures). It plays only through
## PlayerActions, like a person:
##
##   ENTER -> SWIM (out into the lake, near its circle) -> WAIT (tread water; out of the
##   way of a ram; swim at the nearest side tuft when it comes close) -> CLIMB (up the
##   tuft, over the edge onto the back) -> ON_BACK (walk along the ridge to the next weak
##   point; hold on to the ridge when it rears up / dives / rolls) -> STRIKE -> ... DONE
##
## In the water again: back to WAIT. Every phase has a timeout, recorded as a stall.

signal finished(result: Dictionary)

enum Phase { ENTER, SWIM, WAIT, CLIMB, ON_BACK, STRIKE, DONE }

const TIMEOUTS := {Phase.ENTER: 30.0, Phase.SWIM: 40.0, Phase.WAIT: 90.0, Phase.CLIMB: 30.0, Phase.ON_BACK: 60.0, Phase.STRIKE: 30.0}

var player: PlayerCharacter
var hydrus: Hydrus
var encounter: BossEncounter
var verbose := false
var phase := Phase.ENTER
var phase_time := 0.0
var time := 0.0
var events: Array[String] = []
var stats := {"falls": 0, "grabs": 0, "strikes": 0, "weak_hits": 0, "rejected": 0, "stalls": [], "deaths": 0, "death_causes": [], "dodges": 0, "dives_held": 0, "underwater_s": 0.0}
var result := {}

var _last_damage := ""
var _off_body := 0.0
var _was_under := false


func setup(p_player: PlayerCharacter, p_hydrus: Hydrus, p_encounter: BossEncounter) -> void:
	player = p_player
	hydrus = p_hydrus
	encounter = p_encounter
	player.sword.struck.connect(_on_struck)
	player.hit_taken.connect(func(dmg: float, source: StringName) -> void: _last_damage = "%s %.0f" % [source, dmg])
	player.landed.connect(func(speed: float, _tier: int, dmg: float) -> void:
		if dmg > 0.0:
			_last_damage = "fall %.1f m/s (%.0f, %s)" % [speed, dmg, Phase.keys()[phase]])
	player.died.connect(func() -> void:
		stats.deaths += 1
		(func() -> void: stats.death_causes.append(_last_damage)).call_deferred())
	encounter.encounter_reset.connect(func(_n: int) -> void: _enter(Phase.ENTER))


func _ready() -> void:
	process_physics_priority = -5


func _physics_process(delta: float) -> void:
	if phase == Phase.DONE or player == null:
		return
	time += delta
	phase_time += delta
	if hydrus.is_defeated():
		_finish(true, "defeated")
		return
	if TIMEOUTS.has(phase) and phase_time > TIMEOUTS[phase]:
		stats.stalls.append(Phase.keys()[phase])
		_log("STALL in %s (%.0f s) at %s %s; hydrus %s dive %s speed %.1f head %s" % [Phase.keys()[phase], phase_time, str(player.global_position.snapped(Vector3.ONE * 0.1)), player.get_display_state(), hydrus.intent.kind, Hydrus.Dive.keys()[hydrus.dive], hydrus.speed, str(hydrus.head_point().snapped(Vector3.ONE * 0.1))])
		_enter(Phase.WAIT if player.is_swimming() else (Phase.ON_BACK if _on_body() else Phase.ENTER))
		return
	if player.dead:
		player.actions.clear()
		return
	var under := player.is_under_water()
	if under:
		stats.underwater_s += delta
	if under and not _was_under and player.is_climbing():
		stats.dives_held += 1
	_was_under = under
	_off_body = 0.0 if _on_body() or player.is_climbing() else _off_body + delta
	if phase in [Phase.CLIMB, Phase.ON_BACK, Phase.STRIKE] and _off_body > 0.4:
		stats.falls += 1
		_log("off the body (%s) at %s, intent %s" % [player.last_release_reason, str(player.global_position.snapped(Vector3.ONE * 0.1)), hydrus.intent.kind])
		_enter(Phase.WAIT if player.is_swimming() else Phase.ENTER)
	match phase:
		Phase.ENTER:
			_enter_lake()
		Phase.SWIM, Phase.WAIT:
			_wait()
		Phase.CLIMB:
			_climb()
		Phase.ON_BACK:
			_on_back()
		Phase.STRIKE:
			_strike()


func _on_body() -> bool:
	return hydrus.owns_body(player.get_support_body())


# --- in the water ------------------------------------------------------------------------

func _enter_lake() -> void:
	var a := player.actions
	a.grab_held = false
	a.attack_held = false
	player.set_weapon(PlayerCharacter.Weapon.SWORD)
	if player.is_riding():
		a.grab_held = true
		if int(phase_time * 60.0) % 20 == 0:
			a.press_interact()
		return
	if player.is_swimming():
		_enter(Phase.WAIT)
		return
	# Walk / wade towards the middle of the lake.
	_go(hydrus.arena_center)


func _wait() -> void:
	var a := player.actions
	a.attack_held = false
	if player.is_climbing():
		if not hydrus.owns_body(player.grip.body):
			# A pillar's creepers, not the serpent: let go again.
			a.grab_held = false
			return
		stats.grabs += 1
		_log("grabbed %s" % _grip_bone())
		_enter(Phase.CLIMB)
		return
	if not player.is_swimming():
		a.grab_held = false
		_go(hydrus.arena_center)
		return
	# A ram coming: out of its line, sideways.
	if hydrus.intent.kind == Hydrus.RAM and hydrus.rear_w > 0.05 or hydrus.intent.kind == Hydrus.RAM and hydrus.speed > 3.0:
		var head := hydrus.head_point()
		var line := hydrus.global_basis.z
		var dir := Basis(Vector3.UP, hydrus.yaw) * Vector3.FORWARD
		var off := _flat(player.global_position - head)
		var side := dir.cross(Vector3.UP).normalized()
		var s := 1.0 if off.dot(side) >= 0.0 else -1.0
		if absf(off.dot(side)) < 6.0 and off.dot(dir) > -4.0:
			if phase_time > 0.0 and int(phase_time * 60.0) % 60 == 0:
				stats.dodges += 1
			_look(side * s)
			a.move = Vector2(0, 1)
			a.grab_held = false
			return
	# The nearest fur within reach of a swim: go for it, grab when close.
	var tuft := _nearest_tuft()
	var d := _flat(tuft - player.global_position).length() if tuft != Vector3.INF else INF
	if d < 14.0 and hydrus.speed < 4.5:
		_look(tuft - player.global_position)
		a.move = Vector2(0, 1)
		a.grab_held = d < 3.0
		return
	# Otherwise wait near its circle, facing it.
	a.grab_held = false
	var spot := _wait_spot()
	if _flat(spot - player.global_position).length() > 2.0:
		_look(spot - player.global_position)
		a.move = Vector2(0, 1)
	else:
		a.move = Vector2.ZERO
		_look(hydrus.head_point() - player.global_position)


func _wait_spot() -> Vector3:
	# Just inside its cruising circle, ahead of the head.
	var c := hydrus.arena_center
	var off := hydrus.head_point() - c
	var a := atan2(off.z, off.x) + 0.9
	return c + Vector3(cos(a), 0, sin(a)) * (hydrus.cruise_radius - 7.0)


func _nearest_tuft() -> Vector3:
	var best := Vector3.INF
	for seg in hydrus.segments:
		for c in seg.get_children():
			if c is ClimbPatch and absf((c as ClimbPatch).position.x) > 1.5:
				var w := seg.target_transform * (c as ClimbPatch).position
				if best == Vector3.INF or _flat(w - player.global_position).length() < _flat(best - player.global_position).length():
					best = w
	return best


# --- on the body ----------------------------------------------------------------------

func _climb() -> void:
	var a := player.actions
	a.attack_held = false
	if not player.is_climbing():
		if _on_body():
			_enter(Phase.ON_BACK)
		return
	if not hydrus.owns_body(player.grip.body):
		# Crawled over onto a pillar's creepers: let go (into the water, try again).
		a.grab_held = false
		return
	a.grab_held = true
	if _hold_on():
		a.move = Vector2.ZERO
		return
	# Straight up the tuft and over the edge onto the back.
	a.move = Vector2(0, 1)
	if verbose and int(phase_time * 60.0) % 20 == 0:
		_log("  climb: %s local %s n %s up %s st %.0f state %s" % [_grip_bone(), str(player.grip.local_point.snapped(Vector3.ONE * 0.01)), str(player.grip.world_normal().snapped(Vector3.ONE * 0.01)), str(player.climb_up.snapped(Vector3.ONE * 0.01)), player.stamina.value, player.get_display_state()])
	var n := player.grip.world_normal()
	# Let go only on the ridge (a side tuft's top is too narrow to stand on: on up, over
	# the edge).
	if n.y > 0.72 and absf(player.grip.local_point.x) < 1.4 and player.global_position.y > player.grip.world_point().y + 0.4 and _ground_under_feet():
		a.grab_held = false


func _on_back() -> void:
	var a := player.actions
	a.attack_held = false
	if player.is_climbing():
		a.grab_held = true
		a.move = Vector2.ZERO
		if not _hold_on() and _ground_under_feet() and player.global_position.y > player.grip.world_point().y + 0.4 and phase_time > 0.3:
			a.grab_held = false
		return
	if not _on_body():
		return
	if verbose and int(phase_time * 60.0) % 15 == 0:
		_log("  back: %s bal %s ctrl %.2f acc %.1f angv %.2f slide %.2f pos %s seg %s" % [player.get_display_state(), Balance.State.keys()[player.balance.state], player.balance.control(), player.surface_accel.length(), player.surface_angular_velocity.length(), player._slide_velocity.length(), str(player.global_position.snapped(Vector3.ONE * 0.1)), (player.get_support_body() as BodySegment).bone_name])
	if _hold_on():
		# Down on the ridge and hold it (the rescue grip under the feet).
		a.move = Vector2.ZERO
		a.grab_held = true
		return
	a.grab_held = false
	var wp := hydrus.beam_weak_point()
	if wp == null:
		return
	if _blade_reach(wp) < wp.radius * 0.8:
		_enter(Phase.STRIKE)
		return
	_go(wp.world_point(), 0.5)


func _strike() -> void:
	var a := player.actions
	var wp := hydrus.beam_weak_point()
	if wp == null:
		return
	var sw := player.sword
	a.move = Vector2.ZERO
	if _hold_on() and sw.state != PlayerSword.State.CHARGE:
		a.grab_held = true
		a.attack_held = false
		return
	a.grab_held = player.is_climbing()
	if not player.is_climbing():
		_look(wp.world_point() - player.global_position)
	if _blade_reach(wp) > wp.radius and sw.state == PlayerSword.State.READY:
		_enter(Phase.ON_BACK)
		return
	if verbose and int(phase_time * 60.0) % 20 == 0:
		_log("  strike: sword %s charge %.2f reach %.2f wp %s hold %s %s" % [sw.state_name(), sw.charge, _blade_reach(wp), wp.state_name(), str(_hold_on()), player.get_display_state()])
	match sw.state:
		PlayerSword.State.READY:
			a.attack_held = phase_time > 0.2
		PlayerSword.State.CHARGE:
			a.attack_held = sw.charge < 1.0 and not _hold_on()
		_:
			a.attack_held = false


## It rears up (a dive coming) or dives, we are losing our footing, or under water: hold
## on. A roll alone is ridden out standing (holding on costs stamina, standing gives it).
func _hold_on() -> bool:
	if player.balance.state >= Balance.State.STUMBLE or player.is_under_water():
		return true
	if hydrus.dive == Hydrus.Dive.NONE:
		return false
	# The dip runs back along the body: hold on once it reaches our part (this segment or
	# the one in front of it going down), not for the whole dive.
	var seg := player.get_support_body() as BodySegment
	if player.is_climbing() and player.grip.body is BodySegment:
		seg = player.grip.body as BodySegment
	if seg == null or not hydrus.owns_body(seg):
		return true
	var i := hydrus.segments.find(seg)
	var level := hydrus.water_level - hydrus.swim_depth - 0.2
	for k in [i, i - 1, i - 2]:
		if k >= 0 and hydrus.segments[k].target_transform.origin.y < level:
			return true
	return hydrus.dive == Hydrus.Dive.REAR and i <= 1


func _ground_under_feet() -> bool:
	var from := player.global_position
	var hit := ClimbQuery.ray(player.get_world_3d().direct_space_state, from, from + Vector3.DOWN * 1.5, [player.get_rid()], Layers.COLOSSUS)
	return not hit.is_empty() and hydrus.owns_body(hit.collider) and (hit.normal as Vector3).y > 0.72


func _blade_reach(wp: WeakPoint) -> float:
	var d := INF
	for q in player.sword.strike_points(player):
		d = minf(d, q.distance_to(wp.world_point()))
	return d


func _on_struck(r: Dictionary) -> void:
	stats.strikes += 1
	if r.get("accepted", false) and r.get("reason", &"") == &"hit":
		stats.weak_hits += 1
		_log("weak point hit %.0f" % float(r.get("damage", 0.0)))
	elif not r.get("accepted", false):
		stats.rejected += 1


# --- helpers --------------------------------------------------------------------------

func _go(target: Vector3, speed := 1.0) -> void:
	var d := _flat(target - player.global_position)
	if d.length() < 0.05:
		player.actions.move = Vector2.ZERO
		return
	_look(d)
	player.actions.move = Vector2(0, speed)


func _look(dir: Vector3) -> void:
	var d := _flat(dir)
	if d.length() > 0.01:
		player.actions.view_basis = Basis.looking_at(d.normalized())


func _grip_bone() -> StringName:
	if player.grip and player.grip.body is BodySegment:
		return (player.grip.body as BodySegment).bone_name
	return &""


func _enter(p: Phase) -> void:
	if p != phase:
		_log("%s -> %s" % [Phase.keys()[phase], Phase.keys()[p]])
	phase = p
	phase_time = 0.0


func _finish(won: bool, why: String) -> void:
	result = {"won": won, "why": why, "time": time, "stats": stats.duplicate(true), "boss": hydrus.stats.duplicate(true), "resets": encounter.resets}
	_log("FINISHED %s (%s) after %.1f s" % ["WIN" if won else "LOSS", why, time])
	phase = Phase.DONE
	player.actions.move = Vector2.ZERO
	player.actions.attack_held = false
	finished.emit(result)


func _log(s: String) -> void:
	var line := "[%6.1f] %s" % [time, s]
	events.append(line)
	if verbose:
		print(line)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
