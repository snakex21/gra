class_name WormBot
extends Node
signal finished(result: Dictionary)
enum Phase { APPROACH, RHYTHM, WAIT, SHOOT, MINERAL, CLIMB, CROWN, STRIKE, EXIT, DONE }
var player: PlayerCharacter
var worm: Worm
var encounter: BossEncounter
var phase := Phase.APPROACH
var time := 0.0
var phase_time := 0.0
var verbose := false
var result := {}
var stats := {"jumps": 0, "armor_shots": 0, "mineral_strikes": 0, "climbs": 0, "sigils": 0, "stalls": []}
var _station := 0
var _plate := 0
var _jump_clock := 0.0
var _exit_rest := 0.0
var _exit_descending := false
func _ready() -> void:
	process_physics_priority = -5
func setup(p: PlayerCharacter, c: Worm, e: BossEncounter) -> void:
	player = p
	worm = c
	encounter = e
	p.bow.shot.connect(func(_a: Dictionary) -> void: stats.armor_shots += 1)
	for a in c.plates:
		a.mineral_hit.connect(func(source: StringName) -> void:
			if source == &"sword": stats.mineral_strikes += 1)
	for w in c.weak_points:
		w.destroyed.connect(func() -> void: stats.sigils += 1)
	e.encounter_reset.connect(func(_n: int) -> void:
		_station = 0
		_enter(Phase.APPROACH))
func _physics_process(delta: float) -> void:
	if player == null or phase == Phase.DONE: return
	time += delta
	phase_time += delta
	var a := player.actions
	a.move = Vector2.ZERO
	if worm.is_defeated():
		phase = Phase.DONE
		result = {"won": true, "time": time, "stats": stats.duplicate(true), "boss": worm.stats.duplicate(true)}
		a.attack_held = false
		finished.emit(result)
		return
	if player.dead:
		a.clear()
		return
	if worm.cycle == Worm.Cycle.LISTEN and phase not in [Phase.APPROACH, Phase.RHYTHM, Phase.EXIT]:
		_enter(Phase.APPROACH)
	if phase_time > 65.0:
		stats.stalls.append(Phase.keys()[phase])
		if verbose: print("Worm STALL %s p %s grip %s boss %s" % [Phase.keys()[phase], player.global_position, player.grip.local_point if player.grip else [], worm.debug_text()])
		phase_time = 0
	match phase:
		Phase.APPROACH:
			a.grab_held = false
			a.attack_held = false
			var at: Vector3 = worm.arena_frame * WormArena.PLATFORMS[_station]
			if _flat(at - player.global_position).length() < 0.35:
				# Brake before the first jump; airborne zero-input preserves momentum.
				_jump_clock = 0.8
				_enter(Phase.RHYTHM)
			else: _go(at)
		Phase.RHYTHM:
			a.grab_held = false
			_jump_clock += delta
			if worm.cycle != Worm.Cycle.LISTEN:
				_enter(Phase.WAIT)
			elif _jump_clock >= 1.3 and player.state == PlayerCharacter.State.GROUND:
				a.press_jump()
				stats.jumps += 1
				_jump_clock = 0
		Phase.WAIT:
			a.grab_held = false
			a.attack_held = false
			var safe_at: Vector3 = worm.arena_frame * WormArena.PLATFORMS[_station]
			if _flat(safe_at - player.global_position).length() > 0.2: _go(safe_at, 0.5)
			if worm.cycle == Worm.Cycle.ARMORED:
				_plate = 0
				_enter(Phase.SHOOT)
		Phase.SHOOT:
			a.grab_held = false
			_weapon(PlayerCharacter.Weapon.BOW)
			if _plate >= 2:
				_plate = 0
				a.attack_held = false
				_enter(Phase.MINERAL)
				return
			var target := worm.plates[_plate]
			if target.hits >= 2:
				_plate += 1
				a.attack_held = false
				return
			var from := player.bow.bow_point(player)
			var dir := PlayerBow.launch_direction(from, target.arrow_target.world_point(), player.bow.max_speed)
			if dir != Vector3.ZERO:
				a.view_basis = Basis.looking_at(dir, Vector3.UP)
				a.aim_origin = from
				a.attack_held = player.bow.state in [PlayerBow.State.IDLE, PlayerBow.State.DRAW]
		Phase.MINERAL:
			a.grab_held = false
			_weapon(PlayerCharacter.Weapon.SWORD)
			if worm.cycle == Worm.Cycle.EXPOSED:
				_enter(Phase.CLIMB)
				return
			if worm.plates[_plate].is_broken:
				_plate = mini(1, _plate + 1)
				return
			var target := worm.plates[_plate]
			var at := target.world_point() + worm.global_basis.z * 1.1
			_look(-worm.global_basis.z)
			if _reach(target) < 0.75: _strike()
			elif _flat(at - player.global_position).length() < 0.25:
				# A small step turns the avatar after crossing sideways between the
				# plates. Camera orientation alone does not rotate a standing sword.
				a.move = Vector2(0, 0.15)
			else: _go(at, 0.7)
		Phase.CLIMB:
			a.attack_held = false
			_weapon(PlayerCharacter.Weapon.SWORD)
			_look(-worm.global_basis.z)
			if player.is_climbing():
				a.grab_held = true
				a.move = Vector2(0, 1)
				if (player.grip.body as BodySegment).bone_name == &"crown" and player.grip.world_normal().y > 0.8:
					stats.climbs += 1
					_enter(Phase.CROWN)
			else:
				var at := worm.global_transform * Vector3(0, 0.95, 3.2)
				_go(at, 0.7)
				a.grab_held = int(time * 60) % 25 > 3
		Phase.CROWN:
			a.grab_held = true
			var target := worm.weak_points[_station]
			var to := target.world_point() - player.grip.world_point() if player.grip else Vector3.ZERO
			_look(to)
			if _reach(target) < 0.65: _enter(Phase.STRIKE)
			else: a.move = Vector2(0, 0.75)
		Phase.STRIKE:
			a.grab_held = true
			if worm.completed[_station]:
				_exit_rest = 0
				_exit_descending = false
				_enter(Phase.EXIT)
			else: _strike()
		Phase.EXIT:
			a.attack_held = false
			if not _exit_descending:
				# Stand on the crown to refill, then deliberately descend its seam.
				a.grab_held = false
				if player.state == PlayerCharacter.State.GROUND:
					_exit_rest += delta
					if _exit_rest > 3.0: _exit_descending = true
			else:
				var local_p := worm.arena_frame.affine_inverse() * player.global_position
				_look(worm.global_basis.z)
				a.grab_held = true
				if player.is_climbing():
					if player.grip.world_normal().y > 0.8: a.move = Vector2(0, 1)
					else: a.move = Vector2(0, -1)
					if local_p.y < 2:
						a.grab_held = false
				elif player.state == PlayerCharacter.State.GROUND and local_p.y < 2:
					a.grab_held = false
					if worm.cycle == Worm.Cycle.LISTEN:
						_station += 1
						_enter(Phase.APPROACH)
				else:
					_go(worm.global_transform * Vector3(0, 11.4, 1.8), 0.35)
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
func _reach(w: Node) -> float:
	var d := INF
	for p in player.sword.strike_points(player): d = minf(d, p.distance_to(w.world_point()))
	return d
func _enter(p: Phase) -> void:
	if verbose and p != phase: print("Worm %.1f %s -> %s" % [time, Phase.keys()[phase], Phase.keys()[p]])
	phase = p
	phase_time = 0
	player.actions.attack_held = false
static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)
