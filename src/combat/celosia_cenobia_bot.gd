class_name CelosiaCenobiaBot
extends Node
## The combined puzzle is solved with ordinary movement, the held sword beam and grip.
signal finished(result: Dictionary)
enum Phase { FIRE, COLUMN, CLIMB, STRIKE, DONE }
var player: PlayerCharacter
var boss: CelosiaCenobia
var encounter: BossEncounter
var phase := Phase.FIRE
var time := 0.0
var phase_time := 0.0
var verbose := false
var result := {}
var stats := {"grabs": 0, "weak_hits": 0, "deaths": 0, "dodges": 0, "fire_repositions": 0, "both_open_before_hit": true}
var _column := Vector3.INF
var _bait := Vector3.INF
var _dodge := Vector3.INF
var _beast: PairedSentinel
var _last_pos := Vector3.INF
var _stuck := 0.0
var _fire_dodge := Vector3.INF
var _fire_threat: PairedSentinel
var _fire_repositioning := false

func setup(p: PlayerCharacter, b: CelosiaCenobia, e: BossEncounter) -> void:
	player = p
	boss = b
	encounter = e
	player.sword.struck.connect(func(r: Dictionary) -> void:
		if r.get("accepted", false) and r.get("reason", &"") == &"hit":
			stats.weak_hits += 1
			stats.both_open_before_hit = stats.both_open_before_hit and boss.guardians.all(func(g: PairedSentinel) -> bool: return g.armour_open))
	player.died.connect(func() -> void: stats.deaths += 1)
	e.encounter_reset.connect(func(_n: int) -> void:
		phase = Phase.FIRE
		phase_time = 0.0
		_column = Vector3.INF
		_bait = Vector3.INF
		_dodge = Vector3.INF
		_fire_dodge = Vector3.INF
		_fire_threat = null
		_fire_repositioning = false)

func _ready() -> void:
	process_physics_priority = -5

func _physics_process(delta: float) -> void:
	if player == null or phase == Phase.DONE:
		return
	time += delta
	phase_time += delta
	if boss.is_defeated():
		_finish(true, "defeated")
		return
	if time > 240:
		_finish(false, "timeout")
		return
	var a := player.actions
	a.move = Vector2.ZERO
	a.attack_held = false
	a.beam_held = false
	a.grab_held = false
	if player.dead:
		return
	if player.weapon != PlayerCharacter.Weapon.SWORD:
		a.press_switch_weapon()
	match phase:
		Phase.FIRE:
			_fire()
		Phase.COLUMN:
			_column_puzzle()
		Phase.CLIMB:
			_climb()
		Phase.STRIKE:
			_strike()
	if verbose and int(time * 60) % 120 == 0:
		print("PAIR %.1f %s p%s %s C0 %s %s C1 %s %s" % [time, Phase.keys()[phase], str(boss.to_local(player.global_position).snapped(Vector3.ONE * 0.1)), player.get_display_state(), PairedSentinel.Mode.keys()[boss.guardians[0].mode], str(boss.to_local(boss.guardians[0].global_position).snapped(Vector3.ONE * 0.1)), PairedSentinel.Mode.keys()[boss.guardians[1].mode], str(boss.to_local(boss.guardians[1].global_position).snapped(Vector3.ONE * 0.1))])

func _fire() -> void:
	var guardian := boss.guardians[0]
	if guardian.armour_open:
		_enter(Phase.COLUMN)
		return
	var fire := boss.to_global(CelosiaCenobia.FIRE) + Vector3.UP * 0.95
	if not boss.torch_carriers.has(player):
		if _flat(fire - player.global_position).length() > 0.6:
			_go(fire)
		else:
			player.actions.beam_held = true
			player.actions.view_basis = Basis.looking_at((guardian.get_focus_point() - SwordBeam.tip(player)).normalized())
		return
	if guardian.mode in [PairedSentinel.Mode.FIRE_WARN, PairedSentinel.Mode.FIRE_RETREAT]:
		# The warning commits to the actual flame/player line. Do not move its
		# origin halfway through the announced retreat.
		player.actions.beam_held = true
		player.actions.view_basis = Basis.looking_at((guardian.get_focus_point() - SwordBeam.tip(player)).normalized())
		return
	if _fire_threat and _fire_threat.mode not in [PairedSentinel.Mode.WARN, PairedSentinel.Mode.CHARGE]:
		_fire_threat = null
		_fire_dodge = Vector3.INF
	if not _fire_threat:
		for g in boss.guardians:
			if g.mode in [PairedSentinel.Mode.WARN, PairedSentinel.Mode.CHARGE] and _flat(g.global_position - player.global_position).length() < 32:
				_fire_threat = g
				var side := g._direction.cross(Vector3.UP).normalized()
				if (player.global_position - g.global_position).dot(side) < 0: side = -side
				_fire_dodge = player.global_position + side * 8
				stats.dodges += 1
				break
	if _fire_threat:
		_go(_fire_dodge)
		return
	var away := _flat(guardian.global_position - player.global_position).normalized()
	var from := guardian.global_position + Vector3.UP * 1.3
	var hit := player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + away * 30, Layers.WORLD))
	var aligned := not hit.is_empty() and (hit.collider as Node).has_meta(&"celosia_fire_wall")
	if aligned and (guardian.get_focus_point() - SwordBeam.tip(player)).length() < 14.5:
		player.actions.beam_held = true
		player.actions.view_basis = Basis.looking_at((guardian.get_focus_point() - SwordBeam.tip(player)).normalized())
		return
	# Carry the acquired flame with the sword lowered, circle to the opposite side
	# of the guardian and align a physical retreat with the authored wall. The long
	# corridor can leave her north of the refuge; the original fixed hearth pose
	# would repeatedly push her north, past the wall, until timeout.
	if not _fire_repositioning:
		_fire_repositioning = true
		stats.fire_repositions += 1
	var local := boss.to_local(guardian.global_position)
	var wall := boss.to_global(Vector3(0, 0, clampf(local.z, 5, 19)))
	var to_wall := _flat(wall - guardian.global_position).normalized()
	_go(guardian.global_position - to_wall * 8 + Vector3.UP * .95)

func _column_puzzle() -> void:
	var g := boss.guardians[1]
	if g.armour_open:
		_enter(Phase.CLIMB)
		return
	if _column == Vector3.INF:
		var best := INF
		for c in CelosiaCenobiaArena.COLUMNS:
			var point := boss.to_global(c)
			var behind := point + _flat(point - g.global_position).normalized() * 7
			var dist := _flat(player.global_position - behind).length()
			if dist < best:
				best = dist
				_column = point
		var dir := _flat(_column - g.global_position).normalized()
		_bait = _column + dir * 7 + Vector3.UP * 0.95
	if g.mode == PairedSentinel.Mode.WARN:
		# Commit to the line before dodging; a warning cannot track the player.
		if _dodge == Vector3.INF:
			var side := _flat(_bait - g.global_position).cross(Vector3.UP).normalized()
			_dodge = player.global_position + side * 8
			stats.dodges += 1
		_go(_dodge)
		return
	if g.mode == PairedSentinel.Mode.CHARGE:
		if _dodge != Vector3.INF:
			_go(_dodge)
		return
	if g.mode == PairedSentinel.Mode.RECOVER and _dodge != Vector3.INF:
		_column = Vector3.INF
		_dodge = Vector3.INF
		return
	_go(_bait)

func _climb() -> void:
	if _beast == null or _beast.is_defeated():
		_beast = boss.guardians[0] if not boss.guardians[0].is_defeated() else boss.guardians[1]
	if player.is_climbing():
		if not _beast.owns_body(player.grip.body):
			return
		player.actions.grab_held = true
		if player.grip.world_normal().y > 0.6:
			stats.grabs += 1
			_enter(Phase.STRIKE)
		else:
			player.actions.move = Vector2(0, 1)
		return
	# Walk to the rear fur. The guardians rest while a player holds an exposed body.
	var rear := _beast.segments[0].target_transform * Vector3(0, -0.5, 3.5)
	var local := _beast.to_local(player.global_position)
	if local.z < 2.8 and absf(local.x) < 4.5 and _flat(player.global_position - _beast.global_position).length() < 8:
		var side := 1.0 if local.x > 0 else -1.0
		rear = _beast.to_global(Vector3(side * 5, 0.95, 4.5))
		_go(rear)
		return
	_go(rear)
	if _flat(player.global_position - rear).length() < 2.5:
		player.actions.grab_held = true
		if player.state == PlayerCharacter.State.GROUND and int(time * 60) % 30 == 0:
			player.actions.press_jump()

func _strike() -> void:
	if _beast.is_defeated():
		player.actions.grab_held = false
		_go(_beast.global_position + _beast.global_basis.z * 7)
		if not player.is_climbing() and not _beast.owns_body(player.get_support_body()):
			_beast = null
			_enter(Phase.CLIMB)
		return
	if not player.is_climbing():
		_enter(Phase.CLIMB)
		return
	var a := player.actions
	a.grab_held = true
	var wp := _beast.weak_point
	var normal := player.grip.world_normal()
	var to := wp.world_point() - player.grip.world_point()
	to -= normal * to.dot(normal)
	if to.length() > 0.45 and player.sword.state == PlayerSword.State.READY:
		if normal.y > 0.55:
			a.view_basis = Basis.looking_at(_flat(to).normalized())
			a.move = Vector2(0, 0.7)
		else:
			var right := player.climb_up.cross(normal)
			a.move = Vector2(to.dot(right), to.dot(player.climb_up)).normalized() * 0.7
		return
	match player.sword.state:
		PlayerSword.State.READY:
			a.attack_held = true
		PlayerSword.State.CHARGE:
			a.attack_held = player.sword.charge < 1.0

func _go(point: Vector3) -> void:
	var d := _flat(point - player.global_position)
	if d.length() < 0.4:
		return
	var from := player.global_position + Vector3.UP * 0.2
	var hit := player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + d.normalized() * minf(d.length(), 2), Layers.WORLD | Layers.COLOSSUS))
	if not hit.is_empty():
		for angle: float in [0.8, -0.8, 1.6, -1.6, 2.4, -2.4]:
			var candidate := d.normalized().rotated(Vector3.UP, angle)
			var probe := player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + candidate * 2, Layers.WORLD | Layers.COLOSSUS))
			if probe.is_empty():
				d = candidate
				break
	if player.global_position.distance_to(_last_pos) > 0.2:
		_last_pos = player.global_position
		_stuck = 0
	else:
		_stuck += get_physics_process_delta_time()
	if _stuck > 1:
		d = d.rotated(Vector3.UP, 1.2 * (1 if int(_stuck) % 2 == 0 else -1))
	player.actions.view_basis = Basis.looking_at(d.normalized())
	player.actions.move = Vector2(0, 1)

func _enter(next: Phase) -> void:
	phase = next
	phase_time = 0

func _finish(won: bool, why: String) -> void:
	result = {"won": won, "why": why, "time": time, "stats": stats, "boss": boss.stats, "guardians": [boss.guardians[0].stats, boss.guardians[1].stats], "resets": encounter.resets}
	phase = Phase.DONE
	player.actions.clear()
	finished.emit(result)

static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)
