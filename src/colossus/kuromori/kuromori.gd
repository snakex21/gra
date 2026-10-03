class_name Kuromori
extends Colossus
## Playable wall-lizard prototype. The alternate dorsal climbing marks and the
## poison placement are design interpretations, not a historical Yamori A reconstruction.

signal phase_changed(phase: Phase)

enum Phase { DORMANT, CRAWL, CLIMB_WALL, ON_WALL, FALL, BELLY, RECOVER, DEFEATED }
@export var notice_radius := 46.0
@export var belly_time := 24.0
@export var poison_telegraph := 1.6
@export var poison_duration := 4.0
@export var poison_radius := 4.8
var phase := Phase.DORMANT
var phase_time := 0.0
var brain_seed := 67
var effects_enabled := true
var weak_point: WeakPoint
var arrow_targets: Array[ArrowTarget] = []
var marks_hit: Array[bool] = [false, false]
var stats := {"arrow_hits": 0, "falls": 0, "weak_point_hits": 0, "poison_casts": 0, "hits_on_player": 0, "defeated_at": -1.0}
var _home := Transform3D.IDENTITY
var _body: BodySegment
var _start_pose := Transform3D.IDENTITY
var _poison_wait := 5.0
var _poison_time := -1.0
var _poison_at := Vector3.ZERO
var _poison_hits := {}
var _poison_visual: MeshInstance3D
var _poison_mat: StandardMaterial3D
var _mark_visuals: Array[MeshInstance3D] = []

func _ready() -> void:
	super()
	_home = global_transform
	_home.origin -= global_basis * Vector3(0, 1.5, 0)
	arena_center = _home.origin
	add_to_group(&"danger_sources")
	weak_point = WeakPoint.create(_body, Vector3(0, -1.47, 0.5), 120.0)
	weak_point.rotation.z = PI
	weak_point.set_protected(true)
	weak_point.struck.connect(func(_damage: float, _health: float) -> void: stats.weak_point_hits += 1)
	weak_point.destroyed.connect(_on_defeated)
	for i in 2:
		var at := Vector3(-3.5 if i == 0 else 3.5, 1.45, 3.0)
		var target := ArrowTarget.create(_body, at, Vector3.UP, 1.05, i)
		target.enabled = false
		target.hit.connect(_on_mark_hit)
		arrow_targets.append(target)
		var mesh := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = 0.55
		ball.height = 1.1
		mesh.mesh = ball
		mesh.position = at
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.95, 0.9)
		mat.emission_enabled = true
		mat.emission = Color(0.2, 0.9, 0.85)
		mesh.material_override = mat
		_body.add_child(mesh)
		_mark_visuals.append(mesh)
	_poison_visual = MeshInstance3D.new()
	_poison_visual.top_level = true
	var disc := CylinderMesh.new()
	disc.top_radius = poison_radius
	disc.bottom_radius = poison_radius
	disc.height = 0.05
	_poison_visual.mesh = disc
	_poison_mat = StandardMaterial3D.new()
	_poison_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_poison_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_poison_mat.albedo_color = Color(0.6, 0.95, 0.16, 0.35)
	_poison_visual.material_override = _poison_mat
	_poison_visual.visible = false
	add_child(_poison_visual)
	body_height = 14.0

func _build_body() -> void:
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	add_child(skeleton)
	skeleton.add_bone("body")
	skeleton.set_bone_rest(0, Transform3D.IDENTITY)
	skeleton.reset_bone_poses()
	_body = BodySegment.new()
	_body.name = "Seg_body"
	_body.colossus = self
	_body.bone_name = &"body"
	_body.bone_idx = 0
	add_child(_body)
	segments.append(_body)
	_box(Vector3(6.2, 2.8, 10.2), Vector3.ZERO, Color(0.27, 0.3, 0.18), true)
	# Stone dorsal shell, fur belly and four spread toes. Only the belly window
	# admits sword damage even if a player reaches the body earlier.
	_box(Vector3(6.25, 0.3, 9.0), Vector3(0, 1.45, 0), Color(0.42, 0.45, 0.31), false)
	_box(Vector3(3.7, 1.8, 3), Vector3(0, 0.1, -6), Color(0.5, 0.48, 0.35), false)
	for x in [-1.0, 1.0]:
		for z in [-3.0, 3.0]:
			_box(Vector3(2.3, 1.2, 1.5), Vector3(x * 3.4, 0.1, z), Color(0.4, 0.42, 0.28), false)
	for i in 4:
		_box(Vector3(2.1 - i * 0.3, 1.2 - i * 0.17, 2.2), Vector3(0, 0.0, 5.5 + i * 1.65), Color(0.3, 0.34, 0.2), false)

func _box(size: Vector3, at: Vector3, color: Color, fur: bool) -> void:
	var shape: CollisionShape3D = ClimbPatch.new() if fur else CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = at
	_body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = size
	mesh.mesh = cube
	mesh.position = at
	mesh.set_meta(&"kind", GreyboxHumanoid.Kind.FUR if fur else GreyboxHumanoid.Kind.STONE)
	mesh.set_meta(&"part_size", size)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	mesh.material_override = mat
	_body.add_child(mesh)

func _choose_intent(_obs: ColossusObservation) -> ColossusIntent:
	return ColossusIntent.make(ColossusIntent.IDLE)

func _execute_intent(_intent: ColossusIntent, delta: float) -> void:
	phase_time += delta
	var pose := Transform3D(Basis.IDENTITY, Vector3(0, 1.5, -11))
	match phase:
		Phase.DORMANT:
			pose.origin.z = -11
			for node in get_tree().get_nodes_in_group(&"players"):
				if node is PlayerCharacter and not node.dead and node.global_position.distance_to(arena_center) < notice_radius:
					_set_phase(Phase.CRAWL)
					break
		Phase.CRAWL:
			pose.origin.z = lerpf(-11.0, -21.0, smoothstep(0.0, 1.0, phase_time / 4.0))
			if phase_time >= 4.0:
				_set_phase(Phase.CLIMB_WALL)
		Phase.CLIMB_WALL:
			var t := smoothstep(0.0, 1.0, phase_time / 3.0)
			pose = Transform3D(Basis(Vector3.RIGHT, t * PI * 0.5), Vector3(0, lerpf(1.5, 9.0, t), -21.0))
			if phase_time >= 3.0:
				_set_phase(Phase.ON_WALL)
		Phase.ON_WALL:
			pose = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 9, -21))
			if marks_hit[0] and marks_hit[1]:
				_start_pose = _home.affine_inverse() * global_transform
				_set_phase(Phase.FALL)
			elif phase_time >= 22.0:
				_start_pose = pose
				_set_phase(Phase.RECOVER)
		Phase.FALL:
			var t := smoothstep(0.0, 1.0, phase_time / 2.0)
			pose = _start_pose.interpolate_with(Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, 1.6, -6)), t)
			if phase_time >= 2.0:
				stats.falls += 1
				_set_phase(Phase.BELLY)
		Phase.BELLY:
			pose = Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, 1.6, -6))
			if phase_time >= belly_time:
				_start_pose = pose
				_set_phase(Phase.RECOVER)
		Phase.RECOVER:
			var t := smoothstep(0.0, 1.0, phase_time / 3.0)
			pose = _start_pose.interpolate_with(Transform3D(Basis.IDENTITY, Vector3(0, 1.5, -11)), t)
			if phase_time >= 3.0:
				marks_hit = [false, false]
				_set_phase(Phase.CRAWL)
		Phase.DEFEATED:
			pose = Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, 1.6, -6))
	global_transform = _home * pose
	weak_point.set_protected(phase != Phase.BELLY)
	for i in arrow_targets.size():
		arrow_targets[i].enabled = phase == Phase.ON_WALL and not marks_hit[i]
		var mat := _mark_visuals[i].material_override as StandardMaterial3D
		mat.emission_energy_multiplier = 3.0 if arrow_targets[i].enabled else 0.05
	_update_poison(delta)

func _set_phase(next: Phase) -> void:
	phase = next
	phase_time = 0.0
	if next in [Phase.FALL, Phase.BELLY, Phase.RECOVER, Phase.DEFEATED]:
		_poison_time = -1.0
		_poison_visual.visible = false
	phase_changed.emit(next)

func _update_poison(delta: float) -> void:
	if phase not in [Phase.CRAWL, Phase.CLIMB_WALL, Phase.ON_WALL]:
		return
	_poison_wait -= delta
	if _poison_time < 0.0 and _poison_wait <= 0.0:
		var nearest: PlayerCharacter = null
		var best := INF
		for node in get_tree().get_nodes_in_group(&"players"):
			if node is PlayerCharacter and not node.dead and not owns_body(node.get_support_body()):
				var d: float = node.global_position.distance_to(global_position)
				if d < best:
					nearest = node
					best = d
		if nearest:
			_poison_at = nearest.global_position + Vector3.DOWN * 0.87
			_poison_time = 0.0
			_poison_wait = 9.0
			_poison_hits.clear()
			stats.poison_casts += 1
	if _poison_time < 0.0:
		return
	_poison_time += delta
	_poison_visual.visible = true
	_poison_visual.global_position = _poison_at
	_poison_mat.albedo_color = Color(0.7, 1, 0.15, 0.25 + 0.1 * sin(_poison_time * 10)) if _poison_time < poison_telegraph else Color(0.25, 0.55, 0.07, 0.7)
	if _poison_time >= poison_telegraph:
		for node in get_tree().get_nodes_in_group(&"players"):
			if not node is PlayerCharacter or node.dead:
				continue
			var off: Vector3 = node.global_position - _poison_at
			var id: int = node.get_instance_id()
			if Vector2(off.x, off.z).length() < poison_radius and absf(off.y) < 2.4 and _time >= float(_poison_hits.get(id, -1.0)):
				var accepted: bool = node.apply_hit(10.0, Vector3.ZERO, 0.0, &"poison")
				_poison_hits[id] = _time + 1.0
				if accepted:
					stats.hits_on_player += 1
	if _poison_time >= poison_telegraph + poison_duration:
		_poison_time = -1.0
		_poison_visual.visible = false

func get_danger_zones() -> Array:
	return [[_poison_at, poison_radius, maxf(0.0, poison_telegraph - _poison_time)]] if _poison_time >= 0.0 else []

func _on_mark_hit(info: Dictionary) -> void:
	if phase == Phase.ON_WALL and info.get("accepted", false):
		marks_hit[int(info.tag)] = true
		stats.arrow_hits += 1

func _on_defeated() -> void:
	if phase == Phase.DEFEATED:
		return
	_set_phase(Phase.DEFEATED)
	stats.defeated_at = _time
	defeated.emit()

func beam_weak_point() -> WeakPoint:
	return weak_point

func get_focus_point() -> Vector3:
	return global_position

func region_of(player: Node3D) -> StringName:
	return &"belly" if owns_body(player.get_support_body()) else &""

func is_defeated() -> bool:
	return phase == Phase.DEFEATED

func reset_encounter(_xf := Transform3D.IDENTITY, _use_xf := false) -> void:
	if _use_xf:
		_home = _xf
		_home.origin -= _home.basis * Vector3(0, 1.5, 0)
	phase = Phase.DORMANT
	phase_time = 0.0
	_time = 0.0
	marks_hit = [false, false]
	_poison_wait = 5.0
	_poison_time = -1.0
	_poison_hits.clear()
	_poison_visual.visible = false
	_time_on_body.clear()
	_off_body_time.clear()
	_start_pose = Transform3D.IDENTITY
	for i in arrow_targets.size():
		arrow_targets[i].enabled = false
		arrow_targets[i].hits_accepted = 0
		arrow_targets[i].hits_rejected = 0
		(_mark_visuals[i].material_override as StandardMaterial3D).emission_energy_multiplier = 0.05
	weak_point.reset()
	weak_point.set_protected(true)
	stats = {"arrow_hits": 0, "falls": 0, "weak_point_hits": 0, "poison_casts": 0, "hits_on_player": 0, "defeated_at": -1.0}
	global_transform = _home * Transform3D(Basis.IDENTITY, Vector3(0, 1.5, -11))
	_sync_segments()
	_sync_segments()
	phase_changed.emit(phase)

func encounter_hint() -> String:
	match phase:
		Phase.DORMANT, Phase.CRAWL:
			return "Kuromori strzeże zatrutego przejścia. Gdy wejdzie na mur, wytrąć dwa świecące punkty łukiem."
		Phase.CLIMB_WALL, Phase.ON_WALL:
			return "Odsuń się od zielonego kręgu. Traf łukiem oba świecące punkty na grzbiecie."
		Phase.FALL, Phase.BELLY:
			return "Brzuch jest odsłonięty. Podejdź między kamienne łapy, chwyć futro i zaatakuj znak mieczem."
		Phase.RECOVER:
			return "Kuromori odzyskuje oparcie. Zejdź z ciała i przygotuj następne wytrącenie."
	return "Przejście jest wolne."

func debug_text() -> String:
	return "KUROMORI %s %.1fs | marks %s | belly %.0f/120 | poison %.1fs" % [Phase.keys()[phase], phase_time, str(marks_hit), weak_point.health, _poison_time]
