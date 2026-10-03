class_name AvionBot
extends Node
## Scripted player for the Avion fight (tests, soak, captures), through PlayerActions:
##
##   ENTER (off Agro, to the water) -> SWIM (to the nearest tower's creepers) -> TOWER
##   (climb to the top) -> WAIT (on top, facing the bird; when it passes low, hold the
##   grip and hop at the wing) -> HANG (round the wing's front edge onto its top) ->
##   ON_BACK (walk to the next weak point; hold on when it rolls) -> STRIKE -> ... DONE
##
## In the water again: SWIM. Every phase has a timeout, recorded as a stall.

signal finished(result: Dictionary)

enum Phase { ENTER, SWIM, TOWER, WAIT, HANG, ON_BACK, STRIKE, DONE }

const TIMEOUTS := {Phase.ENTER: 40.0, Phase.SWIM: 60.0, Phase.TOWER: 30.0, Phase.WAIT: 90.0, Phase.HANG: 30.0, Phase.ON_BACK: 60.0, Phase.STRIKE: 30.0}

var player: PlayerCharacter
var avion: Avion
var encounter: BossEncounter
var towers: Array = []
var verbose := false
var phase := Phase.ENTER
var phase_time := 0.0
var time := 0.0
var events: Array[String] = []
var stats := {"falls": 0, "grabs": 0, "strikes": 0, "weak_hits": 0, "rejected": 0, "stalls": [], "deaths": 0, "death_causes": [], "towers": 0, "missed_passes": 0}
var result := {}

var _last_damage := ""
var _off_body := 0.0
var _tower := -1
var _last_pos := Vector3.INF
var _stuck := 0.0
var _passing := false
var _seen_pass := false


func setup(p_player: PlayerCharacter, p_avion: Avion, p_encounter: BossEncounter, p_towers: Array) -> void:
	player = p_player
	avion = p_avion
	encounter = p_encounter
	towers = p_towers
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
	if avion.is_defeated():
		_finish(true, "defeated")
		return
	if TIMEOUTS.has(phase) and phase_time > TIMEOUTS[phase]:
		stats.stalls.append(Phase.keys()[phase])
		_log("STALL in %s at %s %s; avion %s %s" % [Phase.keys()[phase], str(player.global_position.snapped(Vector3.ONE * 0.1)), player.get_display_state(), avion.intent.kind, avion.swoop_name()])
		_enter(_fallback())
		return
	if player.dead:
		player.actions.clear()
		return
	_off_body = 0.0 if _on_body() or (player.is_climbing() and avion.owns_body(player.grip.body)) else _off_body + delta
	if phase in [Phase.HANG, Phase.ON_BACK, Phase.STRIKE] and _off_body > 0.5:
		stats.falls += 1
		_log("off the bird (%s) at %s" % [player.last_release_reason, str(player.global_position.snapped(Vector3.ONE * 0.1))])
		_enter(_fallback())
	match phase:
		Phase.ENTER:
			_enter_water()
		Phase.SWIM:
			_swim()
		Phase.TOWER:
			_climb_tower()
		Phase.WAIT:
			_wait()
		Phase.HANG:
			_hang()
		Phase.ON_BACK:
			_on_back()
		Phase.STRIKE:
			_strike()


func _fallback() -> Phase:
	if _on_body() or player.is_climbing() and avion.owns_body(player.grip.body):
		return Phase.ON_BACK
	if player.is_climbing():
		return Phase.TOWER
	if _on_tower_top():
		return Phase.WAIT
	return Phase.SWIM if player.is_swimming() else Phase.ENTER


func _on_body() -> bool:
	return avion.owns_body(player.get_support_body())


# --- to a tower and up --------------------------------------------------------------------

func _enter_water() -> void:
	var a := player.actions
	a.attack_held = false
	a.grab_held = false
	player.set_weapon(PlayerCharacter.Weapon.SWORD)
	if player.is_riding():
		a.grab_held = true
		if int(phase_time * 60.0) % 20 == 0:
			a.press_interact()
		return
	if player.is_swimming():
		_enter(Phase.SWIM)
		return
	if _on_tower_top():
		_enter(Phase.WAIT)
		return
	_tower = _nearest_tower()
	_go(_tower_base(_tower))


func _swim() -> void:
	var a := player.actions
	a.attack_held = false
	if player.is_climbing():
		if avion.owns_body(player.grip.body):
			_enter(Phase.HANG)
		else:
			_enter(Phase.TOWER)
		return
	if not player.is_swimming():
		if _on_tower_top():
			_enter(Phase.WAIT)
		else:
			_go(_tower_base(_nearest_tower()))
		return
	_tower = _nearest_tower()
	var spot := _tower_base(_tower)
	var d := _flat(spot - player.global_position)
	# Tired: tread water by the creepers until there is breath for the climb.
	if d.length() < 3.0 and player.stamina.ratio() < 0.7:
		a.grab_held = false
		a.move = Vector2.ZERO
		return
	a.grab_held = d.length() < 2.0
	_go(spot)


## Up the creepers to the top (a mantle at the edge).
func _climb_tower() -> void:
	var a := player.actions
	a.attack_held = false
	if not player.is_climbing():
		if _on_tower_top():
			stats.towers += 1
			_enter(Phase.WAIT)
		elif player.is_swimming():
			_enter(Phase.SWIM)
		elif phase_time > 1.0:
			_enter(Phase.ENTER)
		return
	if avion.owns_body(player.grip.body):
		_enter(Phase.HANG)
		return
	a.grab_held = true
	a.move = Vector2(0, 1)


# --- on top of a tower ------------------------------------------------------------------

func _wait() -> void:
	var a := player.actions
	a.attack_held = false
	if player.is_climbing():
		if avion.owns_body(player.grip.body):
			stats.grabs += 1
			_log("grabbed %s" % _grip_bone())
			_enter(Phase.HANG)
		else:
			a.grab_held = true
			a.move = Vector2(0, 1)
		return
	if player.is_swimming():
		_enter(Phase.SWIM)
		return
	# Stand in the middle of the top, facing the bird.
	var top: Vector3 = (towers[_tower].center as Vector3) if _tower >= 0 else player.global_position
	var off := _flat(top - player.global_position)
	_look(avion.global_position - player.global_position)
	a.move = Vector2.ZERO
	if off.length() > 0.8 and not _passing:
		_go(top, 0.4)
	# The pass: the wing over our head - hold the grip, hop up into it.
	var under := _wing_under()
	var low := avion.swoop in [Avion.Swoop.DIVE, Avion.Swoop.PASS]
	var d := under.distance_to(player.global_position + Vector3.UP * 0.9) if under != Vector3.INF else INF
	_passing = low and d < 4.0
	a.grab_held = low and d < 3.0
	if low and d < 2.4 and under.y > player.global_position.y + 0.6 and player.state == PlayerCharacter.State.GROUND:
		a.press_jump()
	# A pass gone by without us on it.
	if low:
		_seen_pass = true
	elif _seen_pass:
		_seen_pass = false
		stats.missed_passes += 1


## The point of a wing's underside nearest to our head (INF when far).
func _wing_under() -> Vector3:
	var head := player.global_position + Vector3.UP * 0.9
	var best := Vector3.INF
	for s in avion.segments:
		if not String(s.bone_name).begins_with("wing_"):
			continue
		var local := s.target_transform.affine_inverse() * head
		var left := String(s.bone_name).contains("_l_")
		var span := 7.0 if String(s.bone_name).ends_with("_in") else 6.0
		var q := Vector3(clampf(local.x, -span if left else 0.0, 0.0 if left else span), -0.22, clampf(local.z, -1.8, 1.8))
		var w := s.target_transform * q
		if best == Vector3.INF or w.distance_to(head) < best.distance_to(head):
			best = w
	return best


# --- on the bird ------------------------------------------------------------------------

## From under a wing (or its edge) onto its top: towards the front edge, round it, up.
func _hang() -> void:
	var a := player.actions
	a.attack_held = false
	if not player.is_climbing():
		if _on_body():
			_enter(Phase.ON_BACK)
		return
	a.grab_held = true
	if _hold_on():
		a.move = Vector2.ZERO
		return
	var n := player.grip.world_normal()
	if n.y > 0.72 and player.global_position.y > player.grip.world_point().y + 0.4 and _ground_under_feet() and not _too_steep():
		a.grab_held = false
		return
	var seg := player.grip.body as BodySegment
	var goal: Vector3
	if n.y < -0.4:
		# Underneath: to the front edge.
		goal = seg.target_transform * (player.grip.local_point + Vector3(0, 0, -3.0))
	else:
		# On the edge or on top: up and in towards the body.
		goal = avion.global_position + avion.global_basis.y * 2.0
	var dir := goal - player.grip.world_point()
	dir -= n * dir.dot(n)
	if dir.length() < 0.05:
		a.move = Vector2(0, 1)
		return
	dir = dir.normalized()
	# PlayerCharacter changes to camera-relative crawling on upward surfaces. Using
	# the wall frame here makes the same input walk away from the body after a turn.
	if n.y > 0.55:
		_look(dir)
		a.move = Vector2(0, 1)
	else:
		var right := player.climb_up.cross(n)
		a.move = Vector2(dir.dot(right), dir.dot(player.climb_up)).normalized()


func _on_back() -> void:
	var a := player.actions
	a.attack_held = false
	if player.is_climbing():
		a.grab_held = true
		a.move = Vector2.ZERO
		if not _hold_on() and not _too_steep() and _ground_under_feet() and player.global_position.y > player.grip.world_point().y + 0.4 and phase_time > 0.3:
			a.grab_held = false
		elif not _hold_on() and phase_time > 1.0:
			_enter(Phase.HANG)
		return
	if not _on_body():
		return
	if _hold_on() or _too_steep():
		a.move = Vector2.ZERO
		a.grab_held = true
		return
	a.grab_held = false
	var wp := avion.beam_weak_point()
	if wp == null:
		return
	if _blade_reach(wp) < wp.radius * 0.8:
		_enter(Phase.STRIKE)
		return
	_go(wp.world_point(), 0.45)


func _strike() -> void:
	var a := player.actions
	var wp := avion.beam_weak_point()
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
	match sw.state:
		PlayerSword.State.READY:
			a.attack_held = phase_time > 0.2
		PlayerSword.State.CHARGE:
			a.attack_held = sw.charge < 1.0 and not _hold_on()
		_:
			a.attack_held = false


## Hold the grip: it shakes, we stumble, or it banks too steeply.
func _hold_on() -> bool:
	# The carrying turn converges to 0.3 rad from above. A threshold at that exact
	# limit keeps the bot gripping forever until its stamina expires.
	return avion.intent.kind == Avion.SHAKE_BODY or player.balance.state >= Balance.State.STUMBLE or absf(avion.roll) > 0.35


## Too steep to let go and stand: it climbs or dives (a swoop).
func _too_steep() -> bool:
	return absf(avion.pitch) > 0.3 or avion.swoop in [Avion.Swoop.DIVE, Avion.Swoop.PASS]


func _ground_under_feet() -> bool:
	var from := player.global_position
	var hit := ClimbQuery.ray(player.get_world_3d().direct_space_state, from, from + Vector3.DOWN * 1.5, [player.get_rid()], Layers.COLOSSUS)
	return not hit.is_empty() and avion.owns_body(hit.collider) and (hit.normal as Vector3).y > 0.72


# --- helpers --------------------------------------------------------------------------

func _nearest_tower() -> int:
	var best := 0
	for i in towers.size():
		if _flat((towers[i].center as Vector3) - player.global_position).length() < _flat((towers[best].center as Vector3) - player.global_position).length():
			best = i
	return best


## The water at the foot of a tower's creeper facing us.
func _tower_base(i: int) -> Vector3:
	var t: Dictionary = towers[i]
	var c: Vector3 = t.center
	var best := Vector3.INF
	for dir: Vector3 in t.creepers:
		var p := c + dir * (float(t.radius) + 0.9)
		if best == Vector3.INF or _flat(p - player.global_position).length() < _flat(best - player.global_position).length():
			best = p
	return Vector3(best.x, player.global_position.y, best.z)


func _on_tower_top() -> bool:
	for i in towers.size():
		var c: Vector3 = towers[i].center
		if _flat(c - player.global_position).length() < float(towers[i].radius) + 0.3 and absf(player.global_position.y - 0.9 - c.y) < 0.6:
			_tower = i
			return true
	return false


func _blade_reach(wp: WeakPoint) -> float:
	var d := INF
	for q in player.sword.strike_points(player):
		d = minf(d, q.distance_to(wp.world_point()))
	return d


func _go(target: Vector3, speed := 1.0) -> void:
	var d := _flat(target - player.global_position)
	if d.length() < 0.05:
		player.actions.move = Vector2.ZERO
		return
	var dt := get_physics_process_delta_time()
	if player.global_position.distance_to(_last_pos) > 0.2:
		_last_pos = player.global_position
		_stuck = 0.0
	else:
		_stuck += dt
	if _stuck > 1.0 and not _on_body():
		d = d.rotated(Vector3.UP, 1.2 * (1.0 if int(_stuck) % 2 == 0 else -1.0))
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


func _on_struck(r: Dictionary) -> void:
	stats.strikes += 1
	if r.get("accepted", false) and r.get("reason", &"") == &"hit":
		stats.weak_hits += 1
		_log("weak point hit %.0f" % float(r.get("damage", 0.0)))
	elif not r.get("accepted", false):
		stats.rejected += 1


func _enter(p: Phase) -> void:
	_seen_pass = false
	if p != phase:
		_log("%s -> %s" % [Phase.keys()[phase], Phase.keys()[p]])
	phase = p
	phase_time = 0.0


func _finish(won: bool, why: String) -> void:
	result = {"won": won, "why": why, "time": time, "stats": stats.duplicate(true), "boss": avion.stats.duplicate(true), "resets": encounter.resets}
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
