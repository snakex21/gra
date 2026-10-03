class_name SaruBot
extends Node
## Inputs only: bait two committed throws, cross the spans, climb and strike.
signal finished(result: Dictionary)
var player: PlayerCharacter
var saru: Saru
var encounter: BossEncounter
var verbose := false
var result := {}
var time := 0.0
var stage := 0
var stats := {"grabs": 0, "weak_hits": 0, "deaths": 0, "dodges": 0, "bridge_crossings": 0}
var _dodge := Vector3.INF
var _cross_entry := false

func _ready() -> void:
	process_physics_priority = -5

func setup(p: PlayerCharacter, boss: Saru, e: BossEncounter) -> void:
	player = p
	saru = boss
	encounter = e
	p.grabbed.connect(func(anchor: SurfaceAnchor) -> void:
		if saru.owns_body(anchor.body):
			stats.grabs += 1)
	p.sword.struck.connect(func(r: Dictionary) -> void:
		if r.get("accepted", false) and r.reason == &"hit":
			stats.weak_hits += 1)
	p.died.connect(func() -> void: stats.deaths += 1)
	e.encounter_reset.connect(func(_n: int) -> void:
		stage = 0
		_cross_entry = false
		_dodge = Vector3.INF)

func _physics_process(delta: float) -> void:
	if player == null or not result.is_empty():
		return
	time += delta
	var a := player.actions
	a.move = Vector2.ZERO
	a.grab_held = false
	a.attack_held = false
	a.beam_held = false
	if saru.is_defeated() or time > 220:
		result = {"won": saru.is_defeated(), "time": time, "stats": stats, "boss": saru.stats, "resets": encounter.resets}
		finished.emit(result)
		return
	if player.dead:
		return
	if player.weapon != PlayerCharacter.Weapon.SWORD:
		a.press_switch_weapon()
	if stage == 0:
		var top := saru.bridge.to_global(Vector3(0, 6.95, 39))
		_go(top)
		var local := saru.bridge.to_local(player.global_position)
		if local.z < 41 and local.y > 6.7:
			stage = 1
	elif stage in [1, 2]:
		_bait()
	elif stage == 3:
		if not _cross_entry:
			var entry := saru.bridge.to_global(Vector3(0, 6.95, 36))
			_go(entry)
			if _flat(player.global_position - entry).length() < 0.6:
				_cross_entry = true
			return
		var across := saru.bridge.to_global(Vector3(0, 6.95, -40.5))
		_go(across)
		if _flat(player.global_position - across).length() < 0.6:
			stage = 4
			stats.bridge_crossings += 1
	else:
		_climb()
	if verbose and int(time * 60) % 120 == 0:
		print("SARU %.1f stage%d p%s %s throw%.2f target%s bridge%s/%s hp%s" % [time, stage, str(saru.bridge.to_local(player.global_position).snapped(Vector3.ONE * 0.1)), player.get_display_state(), saru.throw_time, str(saru.bridge.to_local(saru.throw_target)), str(saru.bridge.opened), str(saru.bridge.progress), str([saru.weak_points[0].health, saru.weak_points[1].health])])

func _bait() -> void:
	var index := stage - 1
	if saru.bridge.progress[index] >= 1:
		stage += 1
		_dodge = Vector3.INF
		return
	var bait := saru.bridge.to_global(SaruBridge.BAITS[index])
	if saru.throw_time >= 0 and _flat(saru.throw_target - bait).length() < 3:
		if _dodge == Vector3.INF:
			_dodge = bait + saru.bridge.global_basis.x * 5
			stats.dodges += 1
		_go(_dodge)
		return
	_dodge = Vector3.INF
	_go(bait)

func _climb() -> void:
	var a := player.actions
	var wp := saru.beam_weak_point()
	if wp == null:
		return
	if player.is_climbing():
		if not saru.owns_body(player.grip.body):
			return
		a.grab_held = true
		var n := player.grip.world_normal()
		var to := wp.world_point() - player.grip.world_point()
		if wp == saru.weak_points[1] and n.y < 0.65:
			a.move = Vector2(0, 1)
			return
		to -= n * to.dot(n)
		if to.length() > 0.45 and player.sword.state == PlayerSword.State.READY:
			if n.y > 0.55:
				_look(to)
				a.move = Vector2(0, 0.7)
			else:
				var right := player.climb_up.cross(n)
				a.move = Vector2(to.dot(right), to.dot(player.climb_up)).normalized() * 0.7
			return
		a.attack_held = player.sword.state == PlayerSword.State.READY or player.sword.state == PlayerSword.State.CHARGE and player.sword.charge < 1
		return
	if saru.owns_body(player.get_support_body()):
		_go(wp.world_point())
		a.grab_held = true
		return
	var entry := saru.bridge.to_global(Vector3(0, 6.95, -40.5))
	if _flat(player.global_position - entry).length() > 1.8:
		_go(entry)
		return
	_look(saru.weak_points[0].world_point() - player.global_position)
	a.move = Vector2(0, 0.6)
	a.grab_held = true
	if player.state == PlayerCharacter.State.GROUND and int(time * 60) % 30 == 0:
		a.press_jump()

func _go(point: Vector3) -> void:
	var d := _flat(point - player.global_position)
	if d.length() < 0.3:
		return
	_look(d)
	player.actions.move = Vector2(0, minf(1, d.length()))

func _look(direction: Vector3) -> void:
	var d := _flat(direction)
	if d.length() > 0.01:
		player.actions.view_basis = Basis.looking_at(d)
		player.actions.aim_origin = Vector3.INF

static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)
