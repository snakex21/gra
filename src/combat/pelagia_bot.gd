class_name PelagiaBot
extends Node
## Route driver through the shared input interface: swim -> rear moss -> back ->
## steering teeth -> brace against the ruin -> shell sigil -> next tooth.
signal finished(result: Dictionary)
enum Phase { ENTER, CLIMB, DECK, STRIKE, DONE }
var player: PlayerCharacter
var pelagia: Pelagia
var encounter: BossEncounter
var phase := Phase.ENTER
var time := 0.0
var phase_time := 0.0
var result := {}
var verbose := false
var stats := {"grabs": 0, "strikes": 0, "weak_hits": 0, "falls": 0, "deaths": 0, "stalls": []}
var _off_body := 0.0
var _target: WeakPoint

func _ready() -> void:
	process_physics_priority = -5
func setup(p_player: PlayerCharacter, p_pelagia: Pelagia, p_encounter: BossEncounter) -> void:
	player = p_player
	pelagia = p_pelagia
	encounter = p_encounter
	player.sword.struck.connect(func(r: Dictionary) -> void:
		stats.strikes += 1
		if r.get("accepted", false):
			stats.weak_hits += 1)
	encounter.encounter_reset.connect(func(_n: int) -> void: _enter(Phase.ENTER))

func _physics_process(delta: float) -> void:
	if player == null or phase == Phase.DONE:
		return
	time += delta
	phase_time += delta
	var a := player.actions
	a.move = Vector2.ZERO
	if pelagia.is_defeated():
		result = {"won": true, "time": time, "stats": stats.duplicate(true), "boss": pelagia.stats.duplicate(true)}
		phase = Phase.DONE
		a.attack_held = false
		finished.emit(result)
		return
	if player.dead:
		a.clear()
		return
	var on_body := pelagia.owns_body(player.get_support_body())
	_off_body = 0.0 if on_body else _off_body + delta
	if phase != Phase.ENTER and _off_body > 0.6:
		stats.falls += 1
		_enter(Phase.ENTER)
	if phase_time > 70.0:
		stats.stalls.append(Phase.keys()[phase])
		if verbose:
			print("Pelagia STALL %s p %s %s, boss %s" % [Phase.keys()[phase], player.global_position, player.get_display_state(), pelagia.debug_text()])
		_enter(Phase.DECK if on_body else Phase.ENTER)
	match phase:
		Phase.ENTER:
			a.attack_held = false
			var rear := pelagia._back.target_transform * Vector3(0, 0, 6.5)
			_go(rear)
			a.grab_held = _flat(rear - player.global_position).length() < 3.0 and int(time * 60) % 24 > 3
			if player.is_climbing() and on_body:
				stats.grabs += 1
				_enter(Phase.CLIMB)
		Phase.CLIMB:
			a.attack_held = false
			a.grab_held = true
			if player.is_climbing():
				a.move = Vector2(0, 1)
				if verbose and int(time * 60) % 120 == 0:
					print("Pelagia climb local %s n %s up %s stamina %.1f body %s" % [player.grip.local_point, player.grip.world_normal(), player.climb_up, player.stamina.value, player.global_position])
				if player.grip.world_normal().y > 0.8 and player.grip.local_point.z < 5.2:
					a.grab_held = false
			elif on_body and player.state == PlayerCharacter.State.GROUND:
				_enter(Phase.DECK)
		Phase.DECK:
			a.attack_held = false
			a.grab_held = false
			if player.is_climbing():
				return
			if pelagia.ruin_phase in [Pelagia.RuinPhase.STEERING, Pelagia.RuinPhase.IMPACT_TELEGRAPH, Pelagia.RuinPhase.RECOVER]:
				return
			_target = pelagia.beam_weak_point()
			if _target and _blade_reach(_target) < _target.radius * 0.75:
				_enter(Phase.STRIKE)
			elif _target:
				_go(_target.world_point(), 0.45)
		Phase.STRIKE:
			a.grab_held = player.is_climbing()
			if not is_instance_valid(_target) or _target.state != WeakPoint.State.OPEN:
				a.attack_held = false
				_enter(Phase.DECK)
				return
			_look(_target.world_point() - player.global_position)
			if player.sword.state == PlayerSword.State.READY and _blade_reach(_target) > _target.radius:
				_enter(Phase.DECK)
				return
			match player.sword.state:
				PlayerSword.State.READY:
					a.attack_held = true
				PlayerSword.State.CHARGE:
					a.attack_held = player.sword.charge < 1.0
				_:
					a.attack_held = false

func _go(target: Vector3, speed := 1.0) -> void:
	var d := _flat(target - player.global_position)
	if d.length() > 0.1:
		_look(d)
		player.actions.move = Vector2(0, speed)
func _look(dir: Vector3) -> void:
	var d := _flat(dir)
	if d.length() > 0.02:
		player.actions.view_basis = Basis.looking_at(d.normalized())
func _blade_reach(wp: WeakPoint) -> float:
	var d := INF
	for q in player.sword.strike_points(player):
		d = minf(d, q.distance_to(wp.world_point()))
	return d
func _enter(p: Phase) -> void:
	if p != phase and verbose:
		print("Pelagia %.1f: %s -> %s" % [time, Phase.keys()[phase], Phase.keys()[p]])
	phase = p
	phase_time = 0.0
	player.actions.attack_held = false
static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)
