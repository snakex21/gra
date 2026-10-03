class_name WingedGuardianBot
extends Node
## Shared short rear-climb controller. Only PlayerActions drive the player.
signal finished(result: Dictionary)
enum Phase { PUZZLE, APPROACH, GRAB, CLIMB, STRIKE, DONE }
var player: PlayerCharacter
var guardian: WingedGuardian
var encounter: BossEncounter
var phase := Phase.PUZZLE
var phase_time := 0.0
var time := 0.0
var stats := {"grabs": 0, "weak_hits": 0, "falls": 0, "stalls": [], "deaths": 0}
var result := {}
var verbose := false
var _last_phase := Phase.PUZZLE
var _approach_step := 0

func _ready() -> void:
	process_physics_priority = -5

func setup(p: PlayerCharacter, c: WingedGuardian, e: BossEncounter) -> void:
	player = p
	guardian = c
	encounter = e
	p.sword.struck.connect(func(hit: Dictionary) -> void:
		if hit.get("accepted", false):
			stats.weak_hits += 1)
	p.died.connect(func() -> void: stats.deaths += 1)
	e.encounter_reset.connect(func(_n: int) -> void: _phase(Phase.PUZZLE))

func _physics_process(delta: float) -> void:
	if player == null or phase == Phase.DONE:
		return
	time += delta
	phase_time += delta
	var actions := player.actions
	actions.move = Vector2.ZERO
	actions.beam_held = false
	actions.attack_held = actions.attack_held and phase == Phase.STRIKE
	if guardian.is_defeated():
		result = {"won": true, "time": time, "stats": stats.duplicate(true), "boss": guardian.stats.duplicate(true), "resets": encounter.resets}
		_phase(Phase.DONE)
		finished.emit(result)
		return
	if player.dead:
		actions.clear()
		return
	var on := guardian.owns_body(player.get_support_body())
	if phase in [Phase.CLIMB, Phase.STRIKE] and not on and not player.is_climbing() and player.state == PlayerCharacter.State.GROUND:
		stats.falls += 1
		_phase(Phase.APPROACH if guardian._patch_open else Phase.PUZZLE)
	if phase_time > (95 if phase == Phase.PUZZLE else 35):
		stats.stalls.append(Phase.keys()[phase])
		_phase(Phase.PUZZLE)
	match phase:
		Phase.PUZZLE:
			actions.grab_held = false
			_puzzle(delta)
			if _can_board():
				_phase(Phase.APPROACH)
		Phase.APPROACH:
			actions.grab_held = false
			if not guardian._patch_open:
				_phase(Phase.PUZZLE)
				return
			var local := guardian.global_transform.affine_inverse() * player.global_position
			var side := 1.0 if local.x >= 0 else -1.0
			var target_local := Vector3(0, 0, 3.35)
			# Walk around a forward-facing body before approaching its rear fur.
			if _approach_step == 0 and local.z < 3.0:
				target_local = Vector3(side * 3.25, 0, local.z)
				if absf(local.x) > 3.0:
					_approach_step = 1
			elif _approach_step == 0:
				_approach_step = 2
			if _approach_step == 1:
				target_local = Vector3(side * 3.25, 0, 3.6)
				if local.z > 3.3:
					_approach_step = 2
			var target := guardian.global_transform * target_local
			target.y = guardian.arena_center.y + .95
			if _approach_step == 2 and _flat(target - player.global_position).length() < .25:
				_phase(Phase.GRAB)
			else:
				_go(target)
		Phase.GRAB:
			actions.grab_held = phase_time > .08
			_look(guardian.global_position - player.global_position)
			actions.move = Vector2(0, .40)
			if player.is_climbing():
				stats.grabs += 1
				_phase(Phase.CLIMB)
			elif phase_time > 2:
				_phase(Phase.APPROACH)
		Phase.CLIMB:
			actions.grab_held = true
			if not player.is_climbing():
				if on:
					_walk_to_core()
				return
			if player.grip.world_normal().y > .72:
				var to := guardian.weak_point.world_point() - player.grip.world_point()
				to -= player.grip.world_normal() * to.dot(player.grip.world_normal())
				if to.length() < .45:
					_phase(Phase.STRIKE)
				else:
					_look(to)
					actions.move = Vector2(0, .55)
			else:
				_look(guardian.global_position - player.global_position)
				actions.move = Vector2(0, 1)
		Phase.STRIKE:
			actions.grab_held = player.is_climbing()
			if not player.is_climbing():
				_walk_to_core()
				if phase != Phase.STRIKE:
					return
			var sword := player.sword
			match sword.state:
				PlayerSword.State.READY:
					actions.attack_held = guardian.weak_point.state == WeakPoint.State.OPEN
				PlayerSword.State.CHARGE:
					actions.attack_held = sword.charge < 1.0
				_:
					actions.attack_held = false

func _walk_to_core() -> void:
	var wp := guardian.weak_point
	var reach := INF
	for point in player.sword.strike_points(player):
		reach = minf(reach, point.distance_to(wp.world_point()))
	if reach < wp.radius * .75:
		_phase(Phase.STRIKE)
		return
	player.actions.grab_held = false
	_go(wp.world_point(), .4)

func _puzzle(_delta: float) -> void:
	pass

func _can_board() -> bool:
	return guardian._patch_open

func _phase(next: Phase) -> void:
	if phase == next:
		return
	if verbose:
		print("[", snappedf(time, .1), "] ", Phase.keys()[phase], " -> ", Phase.keys()[next])
	phase = next
	phase_time = 0
	if next == Phase.APPROACH:
		_approach_step = 0
	player.actions.attack_held = false

func _go(target: Vector3, speed := 1.0) -> void:
	var direction := _flat(target - player.global_position)
	_look(direction)
	player.actions.move = Vector2(0, minf(speed, direction.length() / .5))

func _look(direction: Vector3) -> void:
	var flat := _flat(direction)
	if flat.length() > .01:
		player.actions.view_basis = Basis.looking_at(flat.normalized())

static func _flat(point: Vector3) -> Vector3:
	return Vector3(point.x, 0, point.z)
