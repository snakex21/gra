class_name KuromoriBot
extends Node
## Inputs-only driver: bow marks -> approach exposed belly -> climb -> charged stabs.
signal finished(result: Dictionary)
var player: PlayerCharacter
var kuromori: Kuromori
var encounter: BossEncounter
var result := {}
var time := 0.0
var verbose := false
var stats := {"shots": 0, "strikes": 0, "weak_hits": 0, "grabs": 0, "evades": 0}
var _grab_ticks := 0

func _ready() -> void:
	process_physics_priority = -5

func setup(p_player: PlayerCharacter, boss: Kuromori, p_encounter: BossEncounter) -> void:
	player = p_player
	kuromori = boss
	encounter = p_encounter
	player.bow.shot.connect(func(_arrow: Dictionary) -> void: stats.shots += 1)
	player.grabbed.connect(func(anchor: SurfaceAnchor) -> void:
		if kuromori.owns_body(anchor.body):
			stats.grabs += 1)
	ArrowSystem.of(player).impact.connect(func(info: Dictionary) -> void:
		if verbose and info.arrow.owner == player:
			print("KUROMORI arrow: %s at %s (marks %s)" % [info.reason, str(info.point), str(kuromori.marks_hit)]))
	player.sword.struck.connect(func(hit: Dictionary) -> void:
		stats.strikes += 1
		if hit.accepted:
			stats.weak_hits += 1)

func _physics_process(delta: float) -> void:
	if not player or not result.is_empty():
		return
	time += delta
	var a := player.actions
	a.move = Vector2.ZERO
	a.attack_held = false
	a.grab_held = false
	if kuromori.is_defeated():
		result = {"won": true, "time": time, "stats": stats, "boss": kuromori.stats}
		finished.emit(result)
		return
	if player.dead:
		return
	if kuromori.phase == Kuromori.Phase.BELLY:
		_belly()
		return
	if player.is_climbing():
		a.grab_held = false
		return
	if _evade():
		return
	if kuromori.phase == Kuromori.Phase.ON_WALL:
		player.set_weapon(PlayerCharacter.Weapon.BOW)
		var mark: ArrowTarget
		for target in kuromori.arrow_targets:
			if target.enabled:
				mark = target
				break
		if mark:
			var from := player.bow.bow_point(player)
			var dir := PlayerBow.launch_direction(from, mark.world_point(), player.bow.max_speed)
			a.view_basis = Basis.looking_at(dir)
			a.aim_origin = from
			a.attack_held = player.bow.state in [PlayerBow.State.IDLE, PlayerBow.State.DRAW] or player.bow.draw < 1.0
	else:
		_run_to(kuromori.arena_center + kuromori._home.basis * Vector3(0, 0.95, 10))

func _belly() -> void:
	var a := player.actions
	player.set_weapon(PlayerCharacter.Weapon.SWORD)
	if player.is_climbing():
		a.grab_held = true
		var to := kuromori.weak_point.world_point() - player.grip.world_point()
		to -= player.grip.world_normal() * to.dot(player.grip.world_normal())
		if player.grip.world_normal().y < 0.6:
			_look(kuromori.global_position - player.global_position)
			a.move = Vector2(0, 1)
		elif to.length() > 0.45:
			_look(to)
			a.move = Vector2(0, 0.65)
		else:
			a.attack_held = player.sword.state == PlayerSword.State.READY or player.sword.state == PlayerSword.State.CHARGE and player.sword.charge < 1.0
		return
	var body := kuromori.segments[0]
	var local := body.target_transform.affine_inverse() * player.global_position
	if absf(local.x) < 2.6 and absf(local.z) < 4.6 and local.y < -1.3:
		_run_to(kuromori.weak_point.world_point(), 0.5)
		_grab_ticks += 1
		a.grab_held = _grab_ticks % 15 > 2
		return
	var entry := body.target_transform * Vector3(3.65, 0, 0.5)
	entry.y = kuromori.arena_center.y + 0.95
	if _flat(entry - player.global_position).length() > 0.7:
		# The spread stone toes are solid. Approach the unarmoured flank between
		# the feet, passing outside the toes rather than through their colliders.
		var me := body.target_transform.affine_inverse() * player.global_position
		var via := entry
		if absf(me.z - 0.5) > 1.0:
			via = body.target_transform * Vector3(6.0, 0, me.z if me.x < 5.6 else 0.5)
			via.y = entry.y
		_run_to(via)
	else:
		_look(kuromori.global_position - player.global_position)
		a.move = Vector2(0, 0.6)
		a.grab_held = true

func _evade() -> bool:
	for zone in kuromori.get_danger_zones():
		var offset := _flat(player.global_position - (zone[0] as Vector3))
		if offset.length() < float(zone[1]) + 1.0:
			if offset.length() < 0.1:
				offset = Vector3.RIGHT
			_run_to(player.global_position + offset.normalized() * 5.0)
			stats.evades += 1
			return true
	return false

func _run_to(goal: Vector3, speed := 1.0) -> void:
	var d := _flat(goal - player.global_position)
	if d.length() < 0.2:
		return
	_look(d)
	player.actions.move = Vector2(0, minf(speed, d.length()))

func _look(dir: Vector3) -> void:
	var flat := _flat(dir)
	if flat.length() > 0.01:
		player.actions.view_basis = Basis.looking_at(flat)
		player.actions.aim_origin = Vector3.INF

static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)
