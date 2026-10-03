class_name SpiderBot
extends Node
signal finished(result: Dictionary)
var player: PlayerCharacter
var spider: Spider
var encounter: BossEncounter
var verbose := false
var result := {}
var time := 0.0
var stats := {"shots": 0, "web_cuts": 0, "grabs": 0, "weak_hits": 0, "dodges": 0, "deaths": 0}
var _entered := false
var _via := false

func _ready() -> void:
	process_physics_priority = -5

func setup(p: PlayerCharacter, boss: Spider, e: BossEncounter) -> void:
	player = p
	spider = boss
	encounter = e
	p.bow.shot.connect(func(_arrow: Dictionary) -> void: stats.shots += 1)
	p.sword.struck.connect(func(r: Dictionary) -> void:
		if r.get("accepted", false):
			if r.reason == &"hit":
				stats.weak_hits += 1
			elif r.reason == &"web_cut":
				stats.web_cuts += 1)
	p.grabbed.connect(func(anchor: SurfaceAnchor) -> void:
		if spider.owns_body(anchor.body):
			stats.grabs += 1)
	p.died.connect(func() -> void: stats.deaths += 1)
	e.encounter_reset.connect(func(_n: int) -> void:
		_entered = false
		_via = false)

func _physics_process(delta: float) -> void:
	if player == null or not result.is_empty():
		return
	time += delta
	var a := player.actions
	a.move = Vector2.ZERO
	a.attack_held = false
	a.grab_held = false
	a.beam_held = false
	if spider.is_defeated() or time > 180:
		result = {"won": spider.is_defeated(), "time": time, "stats": stats, "boss": spider.stats, "resets": encounter.resets}
		finished.emit(result)
		return
	if player.dead:
		return
	if not spider.route_open:
		if _evade():
			return
		var anchor: WebAnchor
		for knot in spider.anchors:
			if not knot.is_cut:
				anchor = knot
				break
		if anchor == null:
			return
		if player.weapon != PlayerCharacter.Weapon.BOW:
			a.press_switch_weapon()
			return
		# Northern knot is occluded by the guardian; walk around its flank first.
		if anchor == spider.anchors[2]:
			var local := spider.to_local(player.global_position)
			var goal := Vector3(23, 0.95, -20) if _via else Vector3(23, 0.95, 24)
			if _flat(player.global_position - spider.to_global(goal)).length() > 0.6:
				_go(spider.to_global(goal))
				return
			if not _via:
				_via = true
				return
		var from := player.bow.bow_point(player)
		var direction := PlayerBow.launch_direction(from, anchor.world_point(), player.bow.max_speed)
		a.view_basis = Basis.looking_at(direction)
		a.aim_origin = from
		a.attack_held = player.bow.state in [PlayerBow.State.IDLE, PlayerBow.State.DRAW] or player.bow.draw < 1
		return
	if player.weapon != PlayerCharacter.Weapon.SWORD:
		a.press_switch_weapon()
		return
	if player.is_climbing():
		a.grab_held = true
		var wp := spider.beam_weak_point()
		var n := player.grip.world_normal()
		if player.grip.body == spider.segments[0]:
			var to := wp.world_point() - player.grip.world_point()
			to -= n * to.dot(n)
			if n.y < 0.6:
				a.move = Vector2(0, 1)
			elif to.length() > 0.45 and player.sword.state == PlayerSword.State.READY:
				_look(to)
				a.move = Vector2(0, 0.7)
			else:
				a.attack_held = player.sword.state == PlayerSword.State.READY or player.sword.state == PlayerSword.State.CHARGE and player.sword.charge < 1
		else:
			_look(spider.segments[0].target_transform.origin - player.grip.world_point())
			a.move = Vector2(0, 1) if n.y < 0.6 else Vector2(0, 0.7)
		return
	if _evade():
		return
	var foot := spider.to_global(Spider.FOOT + Vector3(1, 0.55, 1))
	if not _entered and _flat(player.global_position - foot).length() > 0.6:
		_go(foot)
		return
	_entered = true
	_look(spider.get_focus_point() - player.global_position)
	a.move = Vector2(0, 0.8)
	a.grab_held = true
	if player.state == PlayerCharacter.State.GROUND and int(time * 60) % 30 == 0:
		a.press_jump()

func _evade() -> bool:
	var lash := spider.lash_segment()
	if lash.is_empty() or float(lash[2]) <= 0:
		return false
	var start: Vector3 = lash[0]
	var line: Vector3 = lash[1] - start
	var u := clampf(_flat(player.global_position - start).dot(line) / maxf(line.length_squared(), 0.01), 0, 1)
	var off := _flat(player.global_position - start - line * u)
	if off.length() < 3:
		var side := line.cross(Vector3.UP).normalized()
		if off.dot(side) < 0:
			side = -side
		_go(player.global_position + side * 4)
		stats.dodges += 1
		return true
	return false

func _go(point: Vector3) -> void:
	var d := _flat(point - player.global_position)
	if d.length() < 0.3:
		return
	_look(d)
	player.actions.move = Vector2(0, 1)

func _look(d: Vector3) -> void:
	var flat := _flat(d)
	if flat.length() > 0.01:
		player.actions.view_basis = Basis.looking_at(flat)
		player.actions.aim_origin = Vector3.INF

static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)
