class_name MalusBot
extends Node
signal finished(result: Dictionary)
enum Phase { SIEGE, CLIMB_BASE, PRESSURE, TO_HAND, WRIST, LIFT, CLIMB_UPPER, CROWN, STRIKE, DONE }
var player: PlayerCharacter
var malus: Malus
var encounter: BossEncounter
var phase := Phase.SIEGE
var phase_time := 0.0
var time := 0.0
var verbose := false
var result := {}
var stats := {"cover_visits": 0, "cover_order": [], "grabs": 0, "pressure_strikes": 0, "wrist_shots": 0, "hand_rides": 0, "crown_strikes": 0, "stalls": []}
var _route_index := 0
var _cover_wait := 0.0
var _route: Array[Vector3] = []
var _cover_stops := {}
func _ready() -> void:
	process_physics_priority = -5
func setup(p: PlayerCharacter, c: Malus, e: BossEncounter) -> void:
	player = p
	malus = c
	encounter = e
	_route.clear()
	_cover_stops.clear()
	for i in MalusArena.ROUTE.size():
		var at: Vector3 = MalusArena.ROUTE[i]
		if i < 5:
			# Approach the open +Z side on its centre line. A diagonal straight
			# to the shelter's centre can hit the support at x +/-4, z +3.5.
			_route.append(at + Vector3(0, 0, 7))
			_cover_stops[_route.size()] = i
			_route.append(at)
			var side := -1.0 if i % 2 == 0 else 1.0
			_route.append(at + Vector3(side * 5.8, 0, 0))
			_route.append(at + Vector3(side * 5.8, 0, -6))
		else:
			# ROUTE[5] is inside the final covered gallery; ROUTE[6] reaches
			# the exposed rear service seam and is not a cover visit.
			if i == 5: _cover_stops[_route.size()] = i
			_route.append(at)
	p.bow.shot.connect(func(_a: Dictionary) -> void: stats.wrist_shots += 1)
	c.weak_point.struck.connect(func(_d: float, _h: float) -> void: stats.crown_strikes += 1)
	e.encounter_reset.connect(func(_n: int) -> void:
		_route_index = 0
		_cover_wait = 0.0
		_enter(Phase.SIEGE))
func _physics_process(delta: float) -> void:
	if player == null or phase == Phase.DONE: return
	time += delta
	phase_time += delta
	var a := player.actions
	a.move = Vector2.ZERO
	if malus.is_defeated():
		phase = Phase.DONE
		result = {"won": true, "time": time, "stats": stats.duplicate(true), "boss": malus.stats.duplicate(true)}
		a.attack_held = false
		finished.emit(result)
		return
	if player.dead:
		a.clear()
		return
	if phase_time > 75.0:
		stats.stalls.append(Phase.keys()[phase])
		if verbose: print("Malus STALL %s p %s %s boss %s" % [Phase.keys()[phase], player.global_position, player.get_display_state(), malus.debug_text()])
		phase_time = 0.0
	match phase:
		Phase.SIEGE:
			a.grab_held = false
			a.attack_held = false
			if _route_index >= _route.size():
				_enter(Phase.CLIMB_BASE)
				return
			var root := malus.start_transform * Transform3D(Basis(Vector3.UP, -MalusArena.MALUS_YAW), Vector3.ZERO)
			var goal: Vector3 = root * _route[_route_index]
			if _flat(goal - player.global_position).length() < 0.6:
				if _cover_stops.has(_route_index):
					if player.state != PlayerCharacter.State.GROUND or player.global_position.y > root.origin.y + 3.0: return
					_cover_wait += delta
					if _cover_wait < (1.5 if _cover_stops[_route_index] == 0 else 0.25): return
					stats.cover_visits += 1
					stats.cover_order.append(_cover_stops[_route_index])
				_route_index += 1
				_cover_wait = 0.0
			else:
				_cover_wait = 0.0
				_go(goal)
		Phase.CLIMB_BASE:
			var entry := malus.global_transform * Vector3(0, 0.95, 7.0)
			_go(entry)
			a.grab_held = _flat(entry - player.global_position).length() < 2.0 and int(time * 60) % 25 > 3
			if player.is_climbing():
				stats.grabs += 1
				_enter(Phase.PRESSURE)
		Phase.PRESSURE:
			a.grab_held = true
			_weapon(PlayerCharacter.Weapon.SWORD)
			if malus.hand_phase != Malus.Hand.SEALED:
				stats.pressure_strikes += 1
				_enter(Phase.TO_HAND)
				return
			if _reach(malus.pressure_mark) < 0.85:
				_strike()
			else:
				a.move = Vector2(0, 1)
		Phase.TO_HAND:
			a.attack_held = false
			a.grab_held = true
			if malus.hand_phase != Malus.Hand.BOARD: return
			if player.is_climbing():
				a.move = Vector2(0, 1)
				_look(malus.global_transform * Malus.HAND_LOW - player.global_position)
				if player.grip.world_normal().y > 0.8 and absf(player.grip.local_point.z) < 1.8:
					a.grab_held = false
			elif player.get_support_body() == malus._seg_by_bone[&"hand"]:
				stats.hand_rides += 1
				_enter(Phase.WRIST)
		Phase.WRIST:
			a.grab_held = false
			_weapon(PlayerCharacter.Weapon.BOW)
			if malus.hand_phase != Malus.Hand.BOARD:
				a.attack_held = false
				_enter(Phase.LIFT)
				return
			var from := player.bow.bow_point(player)
			var dir := PlayerBow.launch_direction(from, malus.wrist.world_point(), player.bow.max_speed)
			if dir != Vector3.ZERO:
				a.view_basis = Basis.looking_at(dir, Vector3.UP)
				a.aim_origin = from
				a.attack_held = player.bow.state in [PlayerBow.State.IDLE, PlayerBow.State.DRAW]
		Phase.LIFT:
			a.attack_held = false
			a.grab_held = false
			_weapon(PlayerCharacter.Weapon.SWORD)
			if malus.hand_phase == Malus.Hand.DOCKED: _enter(Phase.CLIMB_UPPER)
		Phase.CLIMB_UPPER:
			a.grab_held = true
			a.attack_held = false
			_look(malus.global_position - player.global_position)
			if player.is_climbing():
				a.move = Vector2(0, 1)
				if (player.grip.body as BodySegment).bone_name == &"head" and player.grip.world_normal().y > 0.8:
					_enter(Phase.CROWN)
			else:
				_go(malus.global_transform * Vector3(0, 19.6, 2.9), 0.45)
		Phase.CROWN:
			a.grab_held = true
			var to := malus.weak_point.world_point() - player.grip.world_point() if player.grip else Vector3.ZERO
			_look(to)
			if _reach(malus.weak_point) < 0.8:
				_enter(Phase.STRIKE)
			else:
				a.move = Vector2(0, 0.6)
		Phase.STRIKE:
			a.grab_held = true
			_strike()

func _strike() -> void:
	match player.sword.state:
		PlayerSword.State.READY: player.actions.attack_held = true
		PlayerSword.State.CHARGE: player.actions.attack_held = player.sword.charge < 1.0
		_: player.actions.attack_held = false
func _weapon(w: PlayerCharacter.Weapon) -> void:
	if player.weapon != w: player.actions.press_switch_weapon()
func _go(target: Vector3, speed := 1.0) -> void:
	var d := _flat(target - player.global_position)
	if d.length() > 0.1:
		_look(d)
		player.actions.move = Vector2(0, speed)
func _look(dir: Vector3) -> void:
	var d := _flat(dir)
	if d.length() > 0.01: player.actions.view_basis = Basis.looking_at(d.normalized())
	player.actions.aim_origin = Vector3.INF
func _reach(w: WeakPoint) -> float:
	var d := INF
	for p in player.sword.strike_points(player): d = minf(d, p.distance_to(w.world_point()))
	return d
func _enter(p: Phase) -> void:
	if verbose and p != phase: print("Malus %.1f %s -> %s" % [time, Phase.keys()[phase], Phase.keys()[p]])
	phase = p
	phase_time = 0.0
	player.actions.attack_held = false
static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)
