class_name PhalanxBot
extends Node
signal finished(result: Dictionary)
enum Phase { MOUNT, RIDE, SHOOT, BOARD, CLIMB, DECK, STRIKE, DONE }
var player: PlayerCharacter
var phalanx: Phalanx
var horse: Horse
var encounter: BossEncounter
var phase := Phase.MOUNT
var time := 0.0
var phase_time := 0.0
var verbose := false
var result := {}
var stats := {"mounts": 0, "shots": 0, "shots_from_horse": 0, "jumps": 0, "grabs": 0, "strikes": 0, "stalls": [], "falls": 0}
var _off := 0.0
func _ready() -> void:
	process_physics_priority = -5
func setup(p: PlayerCharacter, c: Phalanx, e: BossEncounter, h: Horse) -> void:
	player = p
	phalanx = c
	encounter = e
	horse = h
	p.bow.shot.connect(func(_a: Dictionary) -> void:
		stats.shots += 1
		if p.is_riding(): stats.shots_from_horse += 1)
	p.sword.struck.connect(func(r: Dictionary) -> void:
		if r.get("accepted", false): stats.strikes += 1)
	e.encounter_reset.connect(func(_n: int) -> void: _enter(Phase.MOUNT))
func _physics_process(delta: float) -> void:
	if player == null or phase == Phase.DONE:
		return
	time += delta
	phase_time += delta
	var a := player.actions
	a.move = Vector2.ZERO
	if phalanx.is_defeated():
		result = {"won": true, "time": time, "stats": stats.duplicate(true), "boss": phalanx.stats.duplicate(true)}
		phase = Phase.DONE
		a.attack_held = false
		finished.emit(result)
		return
	if player.dead:
		a.clear()
		return
	if phase_time > 90.0:
		stats.stalls.append(Phase.keys()[phase])
		if verbose: print("Phalanx STALL %s p %s %s boss %s" % [Phase.keys()[phase], player.global_position, player.get_display_state(), phalanx.debug_text()])
		phase_time = 0.0
	var on_body := phalanx.owns_body(player.get_support_body())
	_off = 0.0 if on_body else _off + delta
	if phase in [Phase.CLIMB, Phase.DECK, Phase.STRIKE] and _off > 0.7:
		stats.falls += 1
		_enter(Phase.MOUNT)
	match phase:
		Phase.MOUNT:
			a.grab_held = false
			a.attack_held = false
			if player.is_riding() and player.riding.phase == PlayerRiding.Phase.RIDING:
				stats.mounts += 1
				_enter(Phase.RIDE)
			elif _flat(horse.saddle_transform().origin - player.global_position).length() < 2.0:
				a.press_interact()
			else:
				_go(horse.saddle_transform().origin)
		Phase.RIDE:
			_weapon(PlayerCharacter.Weapon.BOW)
			var goal := phalanx.arena_center + phalanx.start_transform.basis * Vector3(25, 0, 45)
			_ride_to(goal)
			if _flat(goal - player.global_position).length() < 3.0:
				_enter(Phase.SHOOT)
		Phase.SHOOT:
			if not player.is_riding():
				_enter(Phase.MOUNT)
				return
			_weapon(PlayerCharacter.Weapon.BOW)
			a.grab_held = true
			if phalanx.flight != Phalanx.Flight.PATROL:
				a.attack_held = false
				_enter(Phase.BOARD)
				return
			if _evade_wind():
				a.attack_held = false
				return
			_shoot_sac()
		Phase.BOARD:
			_weapon(PlayerCharacter.Weapon.SWORD)
			a.attack_held = false
			a.grab_held = false
			if player.is_climbing() and on_body:
				a.grab_held = true
				stats.grabs += 1
				_enter(Phase.CLIMB)
				return
			if not player.is_riding():
				a.grab_held = true
				if player.state == PlayerCharacter.State.GROUND and player.velocity.y < 1.0:
					_enter(Phase.MOUNT)
				return
			var goal := phalanx.boarding_point()
			_ride_to(goal)
			var near := _flat(goal - player.global_position).length() < 1.8
			if near and phalanx.flight == Phalanx.Flight.LOW:
				a.grab_held = true
				_look(phalanx.global_position - player.global_position)
				if int(time * 60) % 12 == 0:
					a.press_jump()
					stats.jumps += 1
		Phase.CLIMB:
			a.grab_held = true
			a.attack_held = false
			_look(phalanx.global_position - player.global_position)
			if player.is_climbing():
				a.move = Vector2(0, 1)
				if player.grip.world_normal().y > 0.8 and absf(player.grip.local_point.x) < 11.3:
					a.grab_held = false
			elif on_body:
				_enter(Phase.DECK)
		Phase.DECK:
			a.attack_held = false
			a.grab_held = false
			var local := phalanx.global_transform.affine_inverse() * player.global_position
			if absf(local.x) > 2.7:
				_go(phalanx.global_transform * Vector3(0, 2.2, 0), 0.55)
				if absf(local.x) < 4.5 and player.state == PlayerCharacter.State.GROUND and int(time * 60) % 20 == 0:
					a.press_jump()
				return
			var wp := phalanx.beam_weak_point()
			if wp and _reach(wp) < 0.8:
				_enter(Phase.STRIKE)
			elif wp:
				_go(wp.world_point(), 0.55)
		Phase.STRIKE:
			var wp := phalanx.beam_weak_point()
			a.grab_held = player.is_climbing()
			if wp == null:
				return
			_look(wp.world_point() - player.global_position)
			if _reach(wp) > wp.radius and player.sword.state == PlayerSword.State.READY:
				_enter(Phase.DECK)
				return
			if wp.state != WeakPoint.State.OPEN:
				a.attack_held = false
				return
			match player.sword.state:
				PlayerSword.State.READY: a.attack_held = true
				PlayerSword.State.CHARGE: a.attack_held = player.sword.charge < 1.0
				_: a.attack_held = false
			if player.sword.last_result.get("accepted", false) and player.sword.state == PlayerSword.State.RECOVERY:
				_enter(Phase.DECK)
func _shoot_sac() -> void:
	var target: ArrowTarget
	for i in [2, 1, 0]:
		if not phalanx.popped[i]:
			target = phalanx.sacs[i]
			break
	if target == null:
		return
	var from := player.bow.bow_point(player)
	var velocity := (target.world_point() - target.previous_frame() * target.local_point) / get_physics_process_delta_time()
	var aim := target.world_point()
	for i in 3:
		var t := from.distance_to(aim) / player.bow.max_speed
		aim = target.world_point() + velocity * t
	var dir := PlayerBow.launch_direction(from, aim, player.bow.max_speed)
	if dir == Vector3.ZERO:
		return
	player.actions.view_basis = Basis.looking_at(dir, Vector3.UP)
	player.actions.aim_origin = from
	player.actions.attack_held = player.bow.state in [PlayerBow.State.IDLE, PlayerBow.State.DRAW] or (player.bow.state == PlayerBow.State.AIM and horse.controller.speed > 0.4)
func _ride_to(goal: Vector3) -> void:
	var d := _flat(goal - player.global_position)
	_look(d)
	player.actions.grab_held = d.length() < 2.0
	player.actions.move = Vector2(0, 1) if d.length() > 1.0 else Vector2.ZERO
	if d.length() > 8.0 and horse.controller.speed < 3.0 and int(time * 60) % 50 == 0:
		player.actions.press_jump()
func _evade_wind() -> bool:
	for z in phalanx.get_danger_zones():
		if _flat(player.global_position - z[0]).length() < 6.0:
			player.actions.grab_held = false
			player.actions.move = Vector2(0.5, 1.0)
			if int(time * 60) % 30 == 0: player.actions.press_jump()
			return true
	return false
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
	if verbose and p != phase: print("Phalanx %.1f %s -> %s" % [time, Phase.keys()[phase], Phase.keys()[p]])
	phase = p
	phase_time = 0.0
	player.actions.attack_held = false
static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)
