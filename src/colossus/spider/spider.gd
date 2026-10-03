class_name Spider
extends Colossus
## Suspended ruin guardian: sever three ground knots to lower its leg route.
const ANCHORS := [Vector3(-19, 1.4, 18), Vector3(20, 1.4, 18), Vector3(0, 1.4, -21)]
const FOOT := Vector3(12, 0.4, 12)
var brain_seed := 97
var anchors: Array[WebAnchor] = []
var weak_points: Array[WeakPoint] = []
var route_open := false
var lowering := 0.0
var stats := {"anchors_cut": 0, "web_casts": 0, "player_hits": 0, "weak_point_hits": 0}
var _home := Transform3D.IDENTITY
var _lower_start := -1.0
var _fur: Array[ClimbPatch] = []
var _strands: Array[MeshInstance3D] = []
var _won := false
var _lash_wait := 4.0
var _lash_time := -1.0
var _lash_end := Vector3.ZERO
var _lash_hits := {}
var _lash_visual: MeshInstance3D
var _lash_mat: StandardMaterial3D
var _shake_time := -1.0
var _shake_wait := 8.0

func _init() -> void:
	arena_radius = 175
	body_height = 9

func _ready() -> void:
	super()
	_home = global_transform
	add_to_group(&"danger_sources")
	for i in ANCHORS.size():
		var anchor := WebAnchor.new()
		anchor.name = "WebAnchor%d" % i
		anchor.position = ANCHORS[i]
		add_child(anchor)
		anchor.severed.connect(func(_anchor: WebAnchor) -> void:
			stats.anchors_cut += 1
			if stats.anchors_cut == 3:
				_lower_start = _time)
		anchors.append(anchor)
		var strand := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.045
		cylinder.bottom_radius = 0.045
		cylinder.height = 1
		strand.mesh = cylinder
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.72, 0.83, 0.77)
		strand.material_override = mat
		add_child(strand)
		_strands.append(strand)
	for point in [Vector3(-1.5, 1.63, 1.5), Vector3(1.5, 1.63, -1.5)]:
		var wp := WeakPoint.create(segments[0], point, 80)
		wp.set_protected(true)
		wp.struck.connect(func(_d: float, _h: float) -> void: stats.weak_point_hits += 1)
		wp.destroyed.connect(_check_victory)
		weak_points.append(wp)
	_lash_visual = MeshInstance3D.new()
	_lash_visual.top_level = true
	var slab := BoxMesh.new()
	slab.size = Vector3(3.6, 0.08, 1)
	_lash_visual.mesh = slab
	_lash_mat = StandardMaterial3D.new()
	_lash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_lash_visual.material_override = _lash_mat
	_lash_visual.visible = false
	add_child(_lash_visual)

func _build_body() -> void:
	skeleton = Skeleton3D.new()
	add_child(skeleton)
	skeleton.add_bone(&"body")
	var body := _segment(&"body", 0)
	_box(body, Vector3(8, 3, 10), false)
	var fur := ClimbPatch.new()
	var fur_box := BoxShape3D.new()
	fur_box.size = Vector3(8.12, 3.12, 10.12)
	fur.shape = fur_box
	fur.disabled = true
	body.add_child(fur)
	_fur.append(fur)
	var i := 0
	for side: float in [-1, 1]:
		for z: float in [-3, -1, 1, 3]:
			var idx := skeleton.add_bone("leg%d" % i)
			skeleton.set_bone_parent(idx, 0)
			var start := Vector3(side * 3, 0, z)
			var end := Vector3(side * (12 if z == 3 else 11), -3.1, z * (4 if z == 3 else 3.5))
			var direction := end - start
			skeleton.set_bone_rest(idx, Transform3D(Basis.looking_at(direction), (start + end) * 0.5))
			var leg := _segment(StringName("leg%d" % i), idx)
			_box(leg, Vector3(2, 1.1, direction.length()), false)
			if side == 1 and z == 3:
				var patch := ClimbPatch.new()
				var box := BoxShape3D.new()
				box.size = Vector3(2.1, 1.2, direction.length() + 0.1)
				patch.shape = box
				patch.disabled = true
				leg.add_child(patch)
				_fur.append(patch)
			i += 1
	skeleton.reset_bone_poses()
	skeleton.set_bone_pose_position(0, Vector3(0, 7, 0))

func _segment(bone_name: StringName, idx: int) -> BodySegment:
	var segment := BodySegment.new()
	segment.name = "Seg_%s" % bone_name
	segment.colossus = self
	segment.bone_name = bone_name
	segment.bone_idx = idx
	add_child(segment)
	segments.append(segment)
	return segment

func _box(segment: BodySegment, size: Vector3, fur: bool) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	segment.add_child(shape)
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = size
	mesh.mesh = cube
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.25, 0.22) if not fur else Color(0.35, 0.2, 0.12)
	mesh.material_override = mat
	segment.add_child(mesh)

func _choose_intent(_obs: ColossusObservation) -> ColossusIntent:
	return ColossusIntent.make(&"web_guardian")

func _execute_intent(_it: ColossusIntent, delta: float) -> void:
	if _won:
		return
	if _lower_start >= 0:
		lowering = smoothstep(0, 1, (_time - _lower_start) / 2.5)
		if lowering >= 1 and not route_open:
			route_open = true
			for patch in _fur:
				patch.set_deferred(&"disabled", false)
			for wp in weak_points:
				wp.set_protected(false)
	_lash_wait -= delta
	if _lash_time < 0 and _lash_wait <= 0:
		var target: PlayerCharacter
		var best := 80.0
		for node in get_tree().get_nodes_in_group(&"players"):
			var p := node as PlayerCharacter
			if p != null and not p.dead and not owns_body(p.get_support_body()):
				var dist := _flat(p.global_position - global_position).length()
				if dist < best:
					best = dist
					target = p
		if target != null:
			_lash_end = Vector3(target.global_position.x, global_position.y + 0.05, target.global_position.z)
			_lash_time = 0
			_lash_hits.clear()
			_lash_wait = 8.0
			stats.web_casts += 1
	if _lash_time >= 0:
		_lash_time += delta
		_update_lash()
		if _lash_time >= 3.0:
			_lash_time = -1
			_lash_visual.visible = false
	_shake_wait -= delta
	if route_open and _shake_wait <= 0 and not _time_on_body.is_empty() and _shake_time < 0:
		_shake_time = 0
		_shake_wait = 10.0
	if _shake_time >= 0:
		_shake_time += delta
		if _shake_time > 3.0:
			_shake_time = -1

func _pose_bones(_delta: float) -> void:
	skeleton.set_bone_pose_position(0, Vector3(0, lerpf(7, 3.5, lowering), 0))
	var roll := 0.0
	if _shake_time > 1.5 and _shake_time < 3:
		roll = sin((_shake_time - 1.5) * 7) * 0.06
	skeleton.set_bone_pose_rotation(0, Quaternion.from_euler(Vector3(0, 0, roll)))

func _post_sync(_delta: float) -> void:
	for i in anchors.size():
		var strand := _strands[i]
		strand.visible = not anchors[i].is_cut
		if strand.visible:
			var a := anchors[i].position
			var b := Vector3(0, lerpf(7, 3.5, lowering), 0)
			var direction := b - a
			strand.transform = Transform3D(Basis.looking_at(direction) * Basis(Vector3.RIGHT, PI * 0.5), (a + b) * 0.5)
			strand.scale.y = direction.length()

func _update_lash() -> void:
	var start := global_position + Vector3.UP * 0.05
	var line := _lash_end - start
	_lash_visual.visible = true
	_lash_visual.global_transform = Transform3D(Basis.looking_at(line), (start + _lash_end) * 0.5)
	_lash_visual.scale.z = maxf(0.1, line.length())
	_lash_mat.albedo_color = Color(0.95, 0.4, 0.12, 0.35 + 0.15 * sin(_lash_time * 10)) if _lash_time < 2 else Color(0.72, 0.9, 0.8, 0.8)
	if _lash_time < 2:
		return
	for node in get_tree().get_nodes_in_group(&"players"):
		var p := node as PlayerCharacter
		if p == null or p.dead or owns_body(p.get_support_body()) or _lash_hits.has(p.get_instance_id()):
			continue
		var u := clampf(_flat(p.global_position - start).dot(line) / maxf(line.length_squared(), 0.01), 0, 1)
		var near := start + line * u
		if _flat(p.global_position - near).length() < 1.8 and p.global_position.y - global_position.y < 2.8:
			_lash_hits[p.get_instance_id()] = true
			if p.apply_hit(20, Vector3.UP * 2 + line.normalized() * 3, 1.0, &"spider_web_lash"):
				stats.player_hits += 1

func lash_segment() -> Array:
	return [global_position + Vector3.UP * 0.05, _lash_end, maxf(0, 2 - _lash_time)] if _lash_time >= 0 else []

func _check_victory() -> void:
	if not _won and weak_points.all(func(w: WeakPoint) -> bool: return w.state == WeakPoint.State.DESTROYED):
		_won = true
		_lash_visual.visible = false
		defeated.emit()

func beam_weak_point() -> WeakPoint:
	for wp in weak_points:
		if wp.state != WeakPoint.State.DESTROYED:
			return wp
	return null

func get_focus_point() -> Vector3:
	return global_position + Vector3.UP * lerpf(7, 3.5, lowering)

func get_danger_zones() -> Array:
	return [[_lash_end, 2.0, maxf(0, 2 - _lash_time)]] if _lash_time >= 0 else []

func is_defeated() -> bool:
	return _won

func reset_encounter(xf := Transform3D.IDENTITY, use_xf := false) -> void:
	if use_xf:
		_home = xf
	global_transform = _home
	arena_center = _home.origin
	_time = 0
	_won = false
	_lower_start = -1
	lowering = 0
	route_open = false
	_lash_time = -1
	_lash_wait = 4
	_shake_time = -1
	_shake_wait = 8
	_lash_hits.clear()
	_time_on_body.clear()
	_off_body_time.clear()
	_lash_visual.visible = false
	stats = {"anchors_cut": 0, "web_casts": 0, "player_hits": 0, "weak_point_hits": 0}
	for anchor in anchors:
		anchor.reset()
	for wp in weak_points:
		wp.reset()
		wp.set_protected(true)
	for patch in _fur:
		patch.set_deferred(&"disabled", true)
	_pose_bones(0)
	_sync_segments()
	_sync_segments()
	_post_sync(0)

func debug_text() -> String:
	return "SPIDER | kotwice %d/3 | odnóże %s | ciosy%d | sieć%.1fs" % [stats.anchors_cut, str(route_open), stats.weak_point_hits, _lash_time]

func encounter_hint() -> String:
	if _won:
		return "Sieć strażnika przestała więzić przejście."
	if not route_open:
		return "Przetnij trzy świecące węzły sieci łukiem lub naładowanym ciosem miecza. Pomarańczowa linia zapowiada bicz — odejdź w bok."
	return "Odnóże dotknęło ziemi. Wejdź po futrze na grzbiet i zniszcz oba znaki."

static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)
