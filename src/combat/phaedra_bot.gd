class_name PhaedraBot
extends Node
## Scripted player for the Phaedra fight (tests, soak, captures). It plays only through
## PlayerActions, like a person:
##
##   ENTER -> HIDE (run into the nearest tunnel) -> WAIT (just inside the mouth Phaedra
##   comes to look into) -> GRAB_HEAD (the fur cap of the lowered head, a hop if needed)
##   -> CLIMB (along the mane towards the next weak point; hold on in a shake) -> STRIKE
##   (charged) -> next weak point ... -> DONE
##
## Off the body: back to HIDE. Every phase has a timeout, recorded as a stall.

signal finished(result: Dictionary)

enum Phase { ENTER, HIDE, WAIT, GRAB_HEAD, CLIMB, STRIKE, FALLEN, DONE }

const TIMEOUTS := {Phase.ENTER: 20.0, Phase.HIDE: 40.0, Phase.WAIT: 120.0, Phase.GRAB_HEAD: 10.0, Phase.CLIMB: 45.0, Phase.STRIKE: 30.0, Phase.FALLEN: 15.0}

var player: PlayerCharacter
var phaedra: Phaedra
var encounter: BossEncounter
var verbose := false
var phase := Phase.ENTER
var phase_time := 0.0
var time := 0.0
var events: Array[String] = []
var stats := {"falls": 0, "grabs": 0, "strikes": 0, "weak_hits": 0, "rejected": 0, "stalls": [], "deaths": 0, "death_causes": [], "hides": 0, "head_grabs": 0, "evades": 0}
var result := {}

var _tunnel := -1
var _jumped := false
var _last_damage := ""
var _off_body := 0.0
var _blocked := 0.0
var _detour := 0.0
var _detour_side := 1.0


func setup(p_player: PlayerCharacter, p_phaedra: Phaedra, p_encounter: BossEncounter) -> void:
	player = p_player
	phaedra = p_phaedra
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
	if phaedra.is_defeated():
		_finish(true, "defeated")
		return
	if TIMEOUTS.has(phase) and phase_time > TIMEOUTS[phase]:
		stats.stalls.append(Phase.keys()[phase])
		_log("STALL in %s (%.0f s)" % [Phase.keys()[phase], phase_time])
		_reroute()
		return
	if player.dead:
		player.actions.clear()
		return
	var a := player.actions
	var on_body := phaedra.owns_body(player.get_support_body())
	# Off the body for a moment (contact lost for a tick on the moving neck) is not a fall.
	_off_body = 0.0 if on_body or player.is_climbing() else _off_body + delta
	if phase in [Phase.CLIMB, Phase.STRIKE] and _off_body > 0.4 and player.state == PlayerCharacter.State.GROUND:
		stats.falls += 1
		_log("fell off (%s) at %s, intent %s, peek %s" % [player.last_release_reason, str(player.global_position.snapped(Vector3.ONE * 0.1)), phaedra.intent.kind, phaedra.peek_name()])
		_enter(Phase.FALLEN)
	match phase:
		Phase.ENTER:
			a.clear()
			player.set_weapon(PlayerCharacter.Weapon.SWORD)
			_pick_tunnel()
			_enter(Phase.HIDE)
		Phase.HIDE:
			_hide()
		Phase.WAIT:
			_wait()
		Phase.GRAB_HEAD:
			_grab_head()
		Phase.CLIMB:
			_climb()
		Phase.STRIKE:
			_strike()
		Phase.FALLEN:
			a.grab_held = false
			a.attack_held = false
			a.move = Vector2.ZERO
			if player.state == PlayerCharacter.State.GROUND and phase_time > 0.8:
				_pick_tunnel()
				_enter(Phase.HIDE)


# --- on the ground ---------------------------------------------------------------------

func _pick_tunnel() -> void:
	var best := -1
	var best_d := INF
	for i in phaedra.tunnels.size():
		var d := _flat((phaedra.tunnels[i].center as Vector3) - player.global_position).length()
		if d < best_d:
			best_d = d
			best = i
	_tunnel = best


## The mouth of our tunnel Phaedra will look into: [pos, outward].
func _our_mouth() -> Array:
	if phaedra.peek != Phaedra.Peek.NONE and phaedra.tunnel_of_point(phaedra.peek_mouth) == _tunnel:
		return [phaedra.peek_mouth, phaedra.peek_out]
	return phaedra.near_mouth(_tunnel)


func _hide() -> void:
	var a := player.actions
	a.grab_held = false
	a.attack_held = false
	if phaedra.tunnel_of(player) == _tunnel:
		stats.hides += 1
		_enter(Phase.WAIT)
		return
	if _evade():
		return
	# Into the tunnel through the mouth nearer to us (from outside, straight in).
	var t: Dictionary = phaedra.tunnels[_tunnel]
	var best: Array = t.mouths[0]
	for m in t.mouths:
		if _flat((m[0] as Vector3) - player.global_position).length() < _flat((best[0] as Vector3) - player.global_position).length():
			best = m
	var outside: Vector3 = (best[0] as Vector3) + (best[1] as Vector3) * 2.5
	var inside: Vector3 = (best[0] as Vector3) - (best[1] as Vector3) * 2.0
	var off := _flat(player.global_position - (best[0] as Vector3))
	var target := inside if off.dot(best[1]) < 3.0 and absf(off.dot((best[1] as Vector3).cross(Vector3.UP))) < 2.2 else outside
	if player.global_position.y - phaedra.arena_center.y > 2.5:
		# On a roof (fell there from the head): off its end first.
		target = outside + (best[1] as Vector3) * 2.0
	if verbose and int(phase_time * 60.0) % 120 == 0:
		_log("  hide: tunnel %d pos %s target %s vel %s" % [_tunnel, str(player.global_position.snapped(Vector3.ONE * 0.1)), str(target.snapped(Vector3.ONE * 0.1)), str(player.velocity.snapped(Vector3.ONE * 0.1))])
	_run_to(target)


func _wait() -> void:
	var a := player.actions
	a.grab_held = false
	a.attack_held = false
	if phaedra.tunnel_of(player) != _tunnel:
		_enter(Phase.HIDE)
		return
	var m := _our_mouth()
	var mouth: Vector3 = m[0]
	var out: Vector3 = m[1]
	# Inside, a little behind the mouth (the snout comes ~1 m in), facing out.
	var spot := mouth - out * 1.7
	if _flat(spot - player.global_position).length() > 0.3:
		_run_to(spot, 0.6)
	else:
		a.move = Vector2.ZERO
		_look(out)
	if phaedra.peek in [Phaedra.Peek.LOWER, Phaedra.Peek.HOLD] and phaedra.peek_w > 0.6 and phaedra.peek_mouth.distance_to(mouth) < 0.5:
		_enter(Phase.GRAB_HEAD)


func _grab_head() -> void:
	var a := player.actions
	if player.is_climbing():
		stats.grabs += 1
		stats.head_grabs += 1
		_log("grabbed %s" % _grip_bone())
		_enter(Phase.CLIMB)
		return
	a.grab_held = true
	var head := phaedra.head_point()
	_look(head - player.global_position)
	var d := _flat(head - player.global_position).length()
	a.move = Vector2(0, 0.5) if d > 1.6 else Vector2.ZERO
	if not _jumped and phase_time > 0.5 and player.state == PlayerCharacter.State.GROUND:
		_jumped = true
		a.press_jump()
	if phaedra.peek in [Phaedra.Peek.NONE, Phaedra.Peek.APPROACH]:
		_enter(Phase.WAIT)


# --- on the body ----------------------------------------------------------------------

func _climb() -> void:
	var a := player.actions
	var wp := phaedra.beam_weak_point()
	if wp == null:
		return
	a.attack_held = false
	if not player.is_climbing():
		if phaedra.owns_body(player.get_support_body()):
			# Standing on the mane / withers: walk to the weak point and strike there;
			# crouch and hold the fur when it shakes, catch breath when tired.
			a.grab_held = _hold_on()
			if _hold_on() or (player.stamina.ratio() < 0.6 and phase_time < 6.0):
				a.move = Vector2.ZERO
				return
			if _blade_reach(wp) < wp.radius * 0.8:
				_enter(Phase.STRIKE)
				return
			_run_to(wp.world_point(), 0.45)
			return
		a.grab_held = true
		return
	a.grab_held = true
	var hand := player.grip.world_point()
	var to := wp.world_point() - hand
	if _blade_reach(wp) < wp.radius * 0.8:
		_enter(Phase.STRIKE)
		return
	if _hold_on() or phaedra.peek_w > 0.05:
		# Hold on while it shakes, and while the head is still coming up out of the mouth
		# (crawling up there would pull us onto the tunnel roof).
		a.move = Vector2.ZERO
		return
	# Crawl towards it: on the mane (a top surface) the stick is view-relative.
	var n := player.grip.world_normal()
	if n.y > 0.72 and player.global_position.y > hand.y + 0.4 and _ground_under_feet():
		# On top of the mane, which is gentle enough to stand on: let go, walk and strike
		# standing (stamina comes back standing, never while hanging).
		a.grab_held = false
		a.move = Vector2.ZERO
		_log("  stand up on %s (y %.1f)" % [_grip_bone(), player.global_position.y])
		return
	to -= n * to.dot(n)
	_look(to)
	a.move = Vector2(0, 1)
	if n.y < 0.55:
		# On a side of the neck / head the stick is relative to the climb frame: up onto
		# the mane first, drifting towards the weak point (not straight "up" the slope,
		# which leads to the head).
		var dir := to.normalized()
		var right := player.climb_up.cross(n)
		a.move = Vector2(dir.dot(right), maxf(dir.dot(player.climb_up), 0.6)).normalized()


func _strike() -> void:
	var a := player.actions
	var wp := phaedra.beam_weak_point()
	if wp == null:
		return
	var sw := player.sword
	var climbing := player.is_climbing()
	a.grab_held = climbing or _hold_on()
	a.move = Vector2.ZERO
	if not climbing:
		_look(wp.world_point() - player.global_position)
	if _blade_reach(wp) > wp.radius and sw.state == PlayerSword.State.READY:
		_enter(Phase.CLIMB)
		return
	match sw.state:
		PlayerSword.State.READY:
			a.attack_held = not _hold_on() and phase_time > 0.2
		PlayerSword.State.CHARGE:
			# Keep the charge through a shake, release when calm and full.
			a.attack_held = sw.charge < 1.0 or _hold_on()
		_:
			a.attack_held = false


## Something of Phaedra right under the feet (letting go there means standing, not falling).
func _ground_under_feet() -> bool:
	var from := player.global_position
	var hit := ClimbQuery.ray(player.get_world_3d().direct_space_state, from, from + Vector3.DOWN * 1.5, [player.get_rid()], Layers.COLOSSUS)
	return not hit.is_empty() and phaedra.owns_body(hit.collider) and (hit.normal as Vector3).y > 0.72 and not _hold_on() and phaedra.peek == Phaedra.Peek.NONE


## How far the blade's strike points are from the weak point (as the sword tests it).
func _blade_reach(wp: WeakPoint) -> float:
	var d := INF
	for q in player.sword.strike_points(player):
		d = minf(d, q.distance_to(wp.world_point()))
	return d


func _hold_on() -> bool:
	var k := phaedra.intent.kind
	return k in phaedra._shake_kinds() or k == Quadratus.RECOVER or phaedra._stagger > 0.2 or phaedra._shake > 0.1 or player.shake_level > 0.35


func _on_struck(r: Dictionary) -> void:
	stats.strikes += 1
	if r.get("accepted", false) and r.get("reason", &"") == &"hit":
		stats.weak_hits += 1
		_log("weak point hit %.0f" % float(r.get("damage", 0.0)))
	elif not r.get("accepted", false):
		stats.rejected += 1


# --- helpers --------------------------------------------------------------------------

func _evade() -> bool:
	for z in phaedra.get_danger_zones():
		var c: Vector3 = z[0]
		var r: float = z[1]
		var off := _flat(player.global_position - c)
		if off.length() < r + 1.5:
			var away := off.normalized() if off.length() > 0.1 else Vector3.RIGHT
			_run_to(player.global_position + away * 6.0)
			stats.evades += 1
			return true
	return false


func _run_to(target: Vector3, speed := 1.0) -> void:
	var d := _flat(target - player.global_position)
	if d.length() < 0.05:
		player.actions.move = Vector2.ZERO
		return
	# Blocked (a pillar, a wall end): step round it to one side for a moment.
	var dt := get_physics_process_delta_time()
	if player.state == PlayerCharacter.State.GROUND and _flat(player.velocity).length() < 0.4 * speed and _detour <= 0.0:
		_blocked += dt
		if _blocked > 0.5:
			_detour = 1.0
			_detour_side = -_detour_side
			_blocked = 0.0
			stats.detours = int(stats.get("detours", 0)) + 1
	else:
		_blocked = 0.0
	if _detour > 0.0:
		_detour -= dt
		d = d.rotated(Vector3.UP, 1.3 * _detour_side)
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


func _reroute() -> void:
	if player.is_climbing() or phaedra.owns_body(player.get_support_body()):
		_enter(Phase.CLIMB)
	else:
		_pick_tunnel()
		_enter(Phase.HIDE)


func _enter(p: Phase) -> void:
	if p != phase:
		_log("%s -> %s" % [Phase.keys()[phase], Phase.keys()[p]])
	phase = p
	phase_time = 0.0
	_jumped = false


func _finish(won: bool, why: String) -> void:
	result = {"won": won, "why": why, "time": time, "stats": stats.duplicate(true), "boss": phaedra.stats.duplicate(true), "resets": encounter.resets}
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
