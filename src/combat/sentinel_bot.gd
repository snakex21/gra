class_name SentinelBot
extends Node
## Scripted test driver for the Sentinel fight. It is not clever: it KNOWS the route and
## plays it through PlayerActions only (exactly like a human or a future AI companion):
##
##   enter the arena -> dodge telegraphed attacks -> run to the back of a calf -> grab
##   -> climb calf, thigh, hips, back -> pull up onto the shoulders -> rest (stamina)
##   -> walk beside the neck, grab the mane -> climb to the head top -> grip the fur there
##   -> charge the sword, strike the weak point -> hold on through the reaction -> repeat
##   -> COLOSSUS DEFEATED.
## Thrown off -> wait to stand up -> back to the leg. Dead -> wait for the encounter reset.
##
## Every phase has a timeout; a timeout is recorded as a stall (with the phase), never
## hidden. A run that does not finish is reported as a deadlock by the caller.

signal finished(result: Dictionary)

enum Phase { ENTER, APPROACH_LEG, GRAB_LEG, CLIMB_BODY, REST, TO_NECK, CLIMB_HEAD, ON_HEAD, STRIKE, FALLEN, DEAD, DONE }

const TIMEOUTS := {
	Phase.ENTER: 40.0, Phase.APPROACH_LEG: 45.0, Phase.GRAB_LEG: 6.0, Phase.CLIMB_BODY: 60.0,
	Phase.REST: 45.0, Phase.TO_NECK: 15.0, Phase.CLIMB_HEAD: 30.0, Phase.ON_HEAD: 25.0,
	Phase.STRIKE: 45.0, Phase.FALLEN: 20.0, Phase.DEAD: 30.0,
}

var player: PlayerCharacter
var sentinel: Sentinel
var encounter: SentinelEncounter
var phase := Phase.ENTER
var phase_time := 0.0
var time := 0.0
## Which calf to climb (&"shin_l" / &"shin_r"); picked per approach.
var leg: StringName = &"shin_l"
var stats := {"falls": 0, "grabs": 0, "strikes": 0, "weak_hits": 0, "rejected": 0, "evades": 0, "rests": 0, "stalls": [], "deaths": 0, "death_causes": [], "detours": 0, "max_height": 0.0}
var events := PackedStringArray()
var verbose := false
var result := {}

var _grab_release := 0
var _strike_hold := 0.0
var _evading := false
var _side := 1.0
var _last_hits := 0
var _approach_step := 0
var _last_damage := "none"
var _blocked := 0.0
var _detour := 0.0
var _detour_side := 1.0


func _ready() -> void:
	# After the colossus (-10) and the horse (-9), before the player (0).
	process_physics_priority = -5


func setup(p_player: PlayerCharacter, p_sentinel: Sentinel, p_encounter: SentinelEncounter) -> void:
	player = p_player
	sentinel = p_sentinel
	encounter = p_encounter
	player.sword.struck.connect(_on_struck)
	player.hit_taken.connect(func(dmg: float, source: StringName) -> void: _last_damage = "%s %.0f" % [source, dmg])
	player.landed.connect(func(speed: float, _tier: int, dmg: float) -> void:
		if dmg > 0.0:
			_last_damage = "fall %.1f m/s (%.0f, %s)" % [speed, dmg, Phase.keys()[phase]])
	# died fires before landed (fall damage): read the cause a moment later.
	player.died.connect(func() -> void: (func() -> void: stats.death_causes.append(_last_damage)).call_deferred())
	encounter.encounter_reset.connect(func(_n: int) -> void: _enter(Phase.ENTER))


func _physics_process(delta: float) -> void:
	if player == null or phase == Phase.DONE:
		return
	time += delta
	phase_time += delta
	var a := player.actions
	a.move = Vector2.ZERO
	a.attack_held = a.attack_held and phase == Phase.STRIKE
	stats.max_height = maxf(stats.max_height, player.global_position.y)
	if sentinel.is_defeated() and phase != Phase.DONE:
		_finish(true, "defeated")
		return
	if player.dead and phase != Phase.DEAD:
		stats.deaths += 1
		_enter(Phase.DEAD)
	if phase_time > float(TIMEOUTS.get(phase, 999.0)):
		_stall()
		return
	var on_body := sentinel.owns_body(player.get_support_body())
	# Thrown off / fell while on the body route: start again from the leg.
	if phase in [Phase.CLIMB_BODY, Phase.REST, Phase.TO_NECK, Phase.CLIMB_HEAD, Phase.ON_HEAD, Phase.STRIKE] and not on_body and not player.is_climbing() and player.state != PlayerCharacter.State.AIR:
		stats.falls += 1
		_log("fell off (%s)" % player.last_release_reason)
		_enter(Phase.FALLEN)
	match phase:
		Phase.ENTER:
			a.grab_held = false
			if sentinel.encounter == Sentinel.Encounter.COMBAT or _dist_to(sentinel.global_position) < 30.0:
				_enter(Phase.APPROACH_LEG)
			else:
				_run_to(sentinel.global_position)
		Phase.APPROACH_LEG:
			a.grab_held = false
			_approach_leg()
		Phase.GRAB_LEG:
			_grab_leg()
		Phase.CLIMB_BODY:
			_climb_body()
		Phase.REST:
			_rest()
		Phase.TO_NECK:
			_to_neck()
		Phase.CLIMB_HEAD:
			_climb_head()
		Phase.ON_HEAD:
			_on_head()
		Phase.STRIKE:
			_strike(delta)
		Phase.FALLEN:
			a.grab_held = false
			var high := sentinel.region_of(player) in [&"shoulder", &"head"]
			if player.is_climbing() or (player.state == PlayerCharacter.State.GROUND and high):
				_reroute()
			elif player.state == PlayerCharacter.State.GROUND and player.balance.state != Balance.State.FALLEN and phase_time > 0.5:
				_enter(Phase.APPROACH_LEG)
		Phase.DEAD:
			a.grab_held = false


# --- ground ---------------------------------------------------------------------------

func _approach_leg() -> void:
	if _evade():
		return
	var seg := _seg(leg)
	var entry := seg.target_transform * Vector3(0, -1.6, 1.9)
	var ground_y := sentinel.global_position.y + 0.95
	entry.y = ground_y
	var inv := sentinel.global_transform.affine_inverse()
	var local := inv * player.global_position
	var entry_local := inv * entry
	# Waypoints: wide beside the leg -> straight behind it -> in to the calf.
	if local.z < entry_local.z - 1.0:
		_approach_step = 0
	var lateral_side := 1.0 if entry_local.x >= 0.0 else -1.0
	var w0 := Vector3(lateral_side * (absf(entry_local.x) + 4.5), 0, entry_local.z + 4.0)
	var w1 := Vector3(entry_local.x, 0, entry_local.z + 3.0)
	var goal := entry
	if _approach_step == 0:
		goal = sentinel.global_transform * w0
		if local.z > entry_local.z + 2.5 or _flat(goal - player.global_position).length() < 1.2:
			_approach_step = 1
	if _approach_step == 1:
		goal = sentinel.global_transform * w1
		if _flat(goal - player.global_position).length() < 1.0:
			_approach_step = 2
	if _approach_step == 2:
		goal = entry
	goal.y = ground_y
	if _flat(entry - player.global_position).length() < 0.9:
		# Tired (just fell off): catch breath on the ground before going up again.
		if player.stamina.ratio() < 0.9:
			return
		_enter(Phase.GRAB_LEG)
		return
	_run_to(goal)


func _grab_leg() -> void:
	var a := player.actions
	if _evade():
		a.grab_held = false
		_enter(Phase.APPROACH_LEG)
		return
	var seg := _seg(leg)
	var center := seg.target_transform * Vector3(0, -1.6, 0)
	a.grab_held = phase_time > 0.05
	_look(center - player.global_position)
	a.move = Vector2(0, 0.6)
	if player.is_climbing():
		stats.grabs += 1
		_log("grabbed %s" % _grip_bone())
		_enter(Phase.CLIMB_BODY)
	elif phase_time > 1.5:
		_enter(Phase.APPROACH_LEG)


# --- body ----------------------------------------------------------------------------

func _climb_body() -> void:
	var a := player.actions
	a.grab_held = true
	_aim_at_colossus()
	if not player.is_climbing():
		# Pulled up onto the shoulders (standing on the chest), or somewhere else.
		if player.state != PlayerCharacter.State.AIR and sentinel.region_of(player) != &"":
			_reroute()
		return
	if _grip_bone() in [&"neck", &"head"]:
		_enter(Phase.CLIMB_HEAD)
		return
	a.move = Vector2.ZERO if _hold_on() else Vector2(0, 1)


func _rest() -> void:
	var a := player.actions
	# Stand on the shoulder plateau; if it shakes, hold on to anything in reach.
	var shaking := _shaking()
	a.grab_held = shaking
	if player.is_climbing():
		# A rescue grab: hold on through the shake, then climb back up to the plateau (or,
		# if it was the mane and we are still tired, drop back onto the shoulders).
		a.grab_held = true
		if not shaking:
			if _grip_bone() in [&"neck", &"head"] and player.stamina.ratio() < 0.9:
				a.grab_held = false
			else:
				_reroute()
		return
	if sentinel.region_of(player) != &"shoulder" and player.state != PlayerCharacter.State.AIR:
		_reroute()
		return
	var chest := _seg(&"chest")
	var spot := chest.target_transform * Vector3(_side_of_neck() * 1.55, 2.8, 0.9)
	if _flat(spot - player.global_position).length() > 0.35:
		_run_to(spot, 0.5)
	# Plan the next climb: rested, and right after a shake (its cooldown keeps the next one
	# away for a while) - or if no shake came for a long time.
	var window := sentinel._shake_cooldown_left > 2.5 or phase_time > 10.0
	if player.stamina.ratio() >= 0.95 and not shaking and window and phase_time > 1.0:
		_enter(Phase.TO_NECK)


func _to_neck() -> void:
	var a := player.actions
	if player.is_climbing():
		if _grip_bone() in [&"neck", &"head"]:
			_log("grabbed the mane (stamina %.0f, shake cooldown %.1f)" % [player.stamina.value, sentinel._shake_cooldown_left])
			_enter(Phase.CLIMB_HEAD)
		else:
			a.grab_held = false
		return
	var chest := _seg(&"chest")
	var side := _side_of_neck()
	var spot := chest.target_transform * Vector3(side * 1.55, 2.8, 0.9)
	var neck := _seg(&"neck").target_transform * Vector3(0, 1.0, 0.9)
	if _flat(spot - player.global_position).length() > 0.4:
		_run_to(spot, 0.5)
		a.grab_held = _shaking()
		return
	# Face the mane and reach for it.
	_look(neck - player.global_position)
	a.move = Vector2(0, 0.3)
	_grab_release += 1
	a.grab_held = _grab_release % 20 > 3


func _climb_head() -> void:
	var a := player.actions
	a.grab_held = true
	if verbose and player.is_climbing() and int(phase_time * 60.0) % 30 == 0:
		_log("  head climb: %s local %s n %s up %s st %.0f" % [_grip_bone(), str(player.grip.local_point.snapped(Vector3.ONE * 0.01)), str(player.grip.world_normal().snapped(Vector3.ONE * 0.01)), str(player.climb_up.snapped(Vector3.ONE * 0.01)), player.stamina.value])
	_aim_at_colossus()
	if not player.is_climbing():
		if player.state != PlayerCharacter.State.AIR and sentinel.region_of(player) != &"":
			_reroute()
		return
	# Gripping the fur on top of the head: the weak point is right here.
	if _grip_bone() == &"head" and player.grip.world_normal().y > 0.7:
		_log("gripping the head top")
		_enter(Phase.STRIKE)
		return
	a.move = Vector2.ZERO if _hold_on() else Vector2(0, 1)


func _on_head() -> void:
	var a := player.actions
	var wp := sentinel.weak_point.world_point()
	if not player.is_climbing() and sentinel.region_of(player) != &"head" and player.state != PlayerCharacter.State.AIR:
		if verbose:
			var hs := _seg(&"head").target_transform
			_log("  left head: pos %s head-local %s support %s release %s" % [str(player.global_position.snapped(Vector3.ONE * 0.01)), str((hs.affine_inverse() * player.global_position).snapped(Vector3.ONE * 0.01)), str(player.get_support_body()), player.last_release_reason])
		_reroute()
		return
	if player.is_climbing() and _grip_bone() != &"head":
		_reroute()
		return
	if player.is_climbing():
		if _shaking() or player.stamina.ratio() >= 0.6:
			_enter(Phase.STRIKE)
		else:
			a.grab_held = false
		return
	var shaking := _shaking()
	var d := _flat(wp - player.global_position)
	if not shaking and d.length() > 0.6:
		_run_to(wp, 0.5)
		a.grab_held = false
		return
	if shaking or player.stamina.ratio() >= 0.9:
		# A shake is coming, or rested enough: crouch and hold on to the fur under the feet.
		_grab_release += 1
		a.grab_held = _grab_release % 10 > 2
	else:
		# Standing on the head between shakes: catch breath (stamina comes back).
		a.grab_held = false


func _strike(delta: float) -> void:
	var a := player.actions
	a.grab_held = true
	if not player.is_climbing():
		a.attack_held = false
		_reroute()
		return
	var sw := player.sword
	var wp := sentinel.weak_point
	if verbose and int(phase_time * 60.0) % 30 == 0:
		_log("  strike: grip %s d %.2f sword %s %.2f wp %s hold %s shake_lvl %.2f st %.0f intent %s" % [_grip_bone(), player.grip.world_point().distance_to(wp.world_point()), sw.state_name(), sw.charge, wp.state_name(), _hold_on(), player.shake_level, player.stamina.value, sentinel.intent.kind])
	# Tired and it is calm: let go and stand on the head to recover.
	if not _hold_on() and player.stamina.ratio() < 0.45 and sw.state == PlayerSword.State.READY and _over_head_top():
		if verbose:
			var hs := _seg(&"head").target_transform.affine_inverse()
			_log("  tired, letting go: hands %s body %s n %s" % [str((hs * player.grip.world_point()).snapped(Vector3.ONE * 0.01)), str((hs * player.global_position).snapped(Vector3.ONE * 0.01)), str(player.grip.world_normal().snapped(Vector3.ONE * 0.01))])
		a.grab_held = false
		_enter(Phase.ON_HEAD)
		return
	# Move the grip onto the weak point first.
	var hand := player.grip.world_point()
	var to := wp.world_point() - hand
	to -= player.grip.world_normal() * to.dot(player.grip.world_normal())
	var tired := player.stamina.ratio() < 0.45
	if (to.length() > 0.6 or (tired and not _over_head_top())) and sw.state == PlayerSword.State.READY and not _hold_on():
		_look(to)
		a.move = Vector2(0, 0.7)
		a.attack_held = false
		return
	if wp.state == WeakPoint.State.PROTECTED or _hold_on():
		# Closed, or a violent shake: just hold on (the charge is kept while it shakes).
		if sw.state != PlayerSword.State.CHARGE:
			a.attack_held = false
			return
	match sw.state:
		PlayerSword.State.READY:
			a.attack_held = true
		PlayerSword.State.CHARGE:
			a.attack_held = sw.charge < 1.0
		_:
			a.attack_held = false


# --- helpers -----------------------------------------------------------------------------

## Picks the phase that fits where the player actually is on the body (after a slide, a
## rescue grab on an arm, a drop from the head onto the shoulders...).
func _reroute() -> void:
	if player.is_climbing():
		var bone := _grip_bone()
		if bone == &"head" and player.grip.world_normal().y > 0.7:
			_enter(Phase.STRIKE)
		elif bone == &"head" or bone == &"neck":
			_enter(Phase.CLIMB_HEAD)
		else:
			_enter(Phase.CLIMB_BODY)
		return
	match sentinel.region_of(player):
		&"shoulder":
			_enter(Phase.REST)
		&"head":
			_enter(Phase.ON_HEAD)
		_:
			# On the ground, or standing on a foot: back to the start of the route.
			if phase != Phase.FALLEN:
				stats.falls += 1
				_log("off the route (%s)" % player.last_release_reason)
			_enter(Phase.APPROACH_LEG if player.state == PlayerCharacter.State.GROUND else Phase.FALLEN)


## Telegraphed danger close by: run out of it. Returns true while evading.
func _evade() -> bool:
	for z in sentinel.get_danger_zones():
		var c: Vector3 = z[0]
		var r: float = float(z[1]) + 1.5
		var off := _flat(player.global_position - c)
		if off.length() < r:
			if not _evading:
				stats.evades += 1
				_log("evade %s" % sentinel.attack.kind)
			_evading = true
			var away := off.normalized() if off.length() > 0.2 else _flat(player.global_position - sentinel.global_position).normalized()
			_run_to(player.global_position + away * 5.0)
			return true
	_evading = false
	return false


## Is the body above the head top (letting go leaves the player standing on the head)?
func _over_head_top() -> bool:
	if not player.is_climbing():
		return false
	var local := _seg(&"head").target_transform.affine_inverse() * player.grip.world_point()
	return absf(local.x) < 0.6 and local.z > -0.6 and local.z < 0.9 and local.y > 2.4


func _hold_on() -> bool:
	return _shaking() or player.shake_level > 0.35 or player.stamina.ratio() < 0.12 and player.shake_level > 0.1


func _shaking() -> bool:
	var k := sentinel.intent.kind
	return k == ColossusIntent.SHAKE_PLAYER or k == Sentinel.RECOVER or sentinel._stagger > 0.2


func _side_of_neck() -> float:
	var local := _seg(&"chest").target_transform.affine_inverse() * player.global_position
	return 1.0 if local.x >= 0.0 else -1.0


func _grip_bone() -> StringName:
	if player.grip and player.grip.body is BodySegment:
		return (player.grip.body as BodySegment).bone_name
	return &""


func _run_to(target: Vector3, speed := 1.0) -> void:
	var d := _flat(target - player.global_position)
	if d.length() < 0.05:
		return
	# Blocked (a horse, a rock, a foot in the way)? Step round it for a moment.
	var dt := get_physics_process_delta_time()
	var moving := _flat(player.velocity).length() > 0.6
	if player.state == PlayerCharacter.State.GROUND and not moving and _detour <= 0.0:
		_blocked += dt
		if _blocked > 0.6:
			_detour = 1.0
			_detour_side = -_detour_side
			_blocked = 0.0
			stats.detours += 1
	else:
		_blocked = 0.0
	if _detour > 0.0:
		_detour -= dt
		d = d.rotated(Vector3.UP, _detour_side * PI * 0.5)
	_look(d)
	player.actions.move = Vector2(0, clampf(speed * d.length() / 0.6, 0.25, 1.0) if speed < 1.0 else 1.0)


func _look(dir: Vector3) -> void:
	var d := _flat(dir)
	if d.length() > 0.01:
		player.actions.view_basis = Basis.looking_at(d.normalized())


func _aim_at_colossus() -> void:
	_look(sentinel.global_position - player.global_position)


func _seg(bone: StringName) -> BodySegment:
	return sentinel._seg_by_bone[bone]


func _dist_to(p: Vector3) -> float:
	return _flat(p - player.global_position).length()


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _enter(p: Phase) -> void:
	if p == phase:
		return
	_log("%s -> %s" % [Phase.keys()[phase], Phase.keys()[p]])
	phase = p
	phase_time = 0.0
	_grab_release = 0
	player.actions.attack_held = false
	if p == Phase.REST:
		stats.rests += 1
	if p == Phase.APPROACH_LEG:
		_approach_step = 0
		# The calf nearer to the player.
		var dl := _flat(_seg(&"shin_l").target_transform.origin - player.global_position).length()
		var dr := _flat(_seg(&"shin_r").target_transform.origin - player.global_position).length()
		leg = &"shin_l" if dl <= dr else &"shin_r"


func _stall() -> void:
	var what: String = Phase.keys()[phase]
	stats.stalls.append(what)
	_log("STALL in %s (%.0f s)" % [what, phase_time])
	match phase:
		Phase.DEAD:
			_finish(false, "dead, no reset")
		Phase.CLIMB_BODY, Phase.CLIMB_HEAD, Phase.STRIKE, Phase.TO_NECK, Phase.ON_HEAD, Phase.REST:
			phase_time = 0.0
			_reroute()
		_:
			phase_time = 0.0
			_enter(Phase.APPROACH_LEG)


func _on_struck(r: Dictionary) -> void:
	stats.strikes += 1
	if r.get("accepted", false):
		stats.weak_hits += 1
		_log("weak point hit %.0f (charge %.2f)" % [r.damage, r.power])
	else:
		stats.rejected += 1
		_log("strike rejected: %s" % r.reason)


func _finish(won: bool, why: String) -> void:
	result = {"won": won, "why": why, "time": time, "stats": stats.duplicate(true), "boss": sentinel.stats.duplicate(true), "resets": encounter.resets}
	_log("FINISHED %s (%s) after %.1f s" % ["WIN" if won else "LOSS", why, time])
	phase = Phase.DONE
	# Stop moving and swinging, but keep holding on: the colossus is still going down.
	player.actions.move = Vector2.ZERO
	player.actions.attack_held = false
	finished.emit(result)


func _log(s: String) -> void:
	var line := "[%6.1f] %s" % [time, s]
	events.append(line)
	if verbose:
		print(line)
