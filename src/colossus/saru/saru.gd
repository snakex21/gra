class_name Saru
extends Colossus
## A stone-throwing ruin guardian; committed shots operate suspended counterweights.
const START := Vector3(0, 0, -46)
var brain_seed := 101
var bridge: SaruBridge
var weak_points: Array[WeakPoint] = []
var stats := {"throws": 0, "counterweight_hits": 0, "player_hits": 0, "weak_point_hits": 0}
var throw_time := -1.0
var throw_target := Vector3.ZERO
var throw_player: PlayerCharacter
var _throw_wait := 4.0
var _stones: Array[Dictionary] = []
var _home := Transform3D.IDENTITY
var _won := false
var _fur: Array[ClimbPatch] = []
var _marker: MeshInstance3D
var _on_body := 0.0
var _shake_time := -1.0
var _shake_wait := 10.0

func _init() -> void:
	arena_radius = 175
	body_height = 13

func _ready() -> void:
	bridge = get_parent().get_node_or_null("SaruBridge") as SaruBridge
	super()
	_home = global_transform
	add_to_group(&"danger_sources")
	for spec in [[0, Vector3(0, 0.5, 3.14)], [1, Vector3(0, 1.4, 0.2)]]:
		var wp := WeakPoint.create(segments[spec[0]], spec[1], 80)
		wp.set_protected(true)
		wp.struck.connect(func(_d: float, _h: float) -> void:
			stats.weak_point_hits += 1
			_shake_wait = 8)
		wp.destroyed.connect(_check_victory)
		weak_points.append(wp)
	_marker = MeshInstance3D.new()
	_marker.top_level = true
	var disc := CylinderMesh.new()
	disc.top_radius = 2.5
	disc.bottom_radius = 2.5
	disc.height = 0.05
	_marker.mesh = disc
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.45, 0.05, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker.material_override = mat
	_marker.visible = false
	add_child(_marker)

func _build_body() -> void:
	skeleton = Skeleton3D.new()
	add_child(skeleton)
	skeleton.add_bone(&"body")
	skeleton.set_bone_rest(0, Transform3D(Basis.IDENTITY, Vector3(0, 8, 0)))
	var torso := _segment(&"body", 0)
	_box(torso, Vector3(6, 4, 6), Vector3.ZERO, false)
	_box(torso, Vector3(6.12, 4.12, 0.4), Vector3(0, 0, 3.1), true)
	_box(torso, Vector3(6.12, 0.3, 6.12), Vector3(0, 2.05, 0), true)
	var head_idx := skeleton.add_bone(&"head")
	skeleton.set_bone_parent(head_idx, 0)
	skeleton.set_bone_rest(head_idx, Transform3D(Basis.IDENTITY, Vector3(0, 2.8, 0)))
	var head := _segment(&"head", head_idx)
	_box(head, Vector3(3, 2.6, 3), Vector3.ZERO, false)
	_box(head, Vector3(3.12, 2.72, 3.12), Vector3.ZERO, true)
	for side: float in [-1, 1]:
		var idx := skeleton.add_bone("arm%d" % int(side))
		skeleton.set_bone_parent(idx, 0)
		skeleton.set_bone_rest(idx, Transform3D(Basis.IDENTITY, Vector3(side * 4, 0.5, 0)))
		var arm := _segment(StringName("arm%d" % int(side)), idx)
		_box(arm, Vector3(2, 8, 2), Vector3(0, -3, 0), false)
		var leg_idx := skeleton.add_bone("leg%d" % int(side))
		skeleton.set_bone_parent(leg_idx, 0)
		skeleton.set_bone_rest(leg_idx, Transform3D(Basis.IDENTITY, Vector3(side * 1.7, -4, 0)))
		var leg := _segment(StringName("leg%d" % int(side)), leg_idx)
		_box(leg, Vector3(1.6, 8, 2), Vector3.ZERO, false)
	skeleton.reset_bone_poses()

func _segment(bone_name: StringName, idx: int) -> BodySegment:
	var segment := BodySegment.new()
	segment.colossus = self
	segment.bone_name = bone_name
	segment.bone_idx = idx
	segment.name = "Seg_%s" % bone_name
	add_child(segment)
	segments.append(segment)
	return segment

func _box(segment: BodySegment, size: Vector3, at: Vector3, fur: bool) -> void:
	var shape: CollisionShape3D = ClimbPatch.new() if fur else CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = at
	if fur:
		shape.disabled = true
		_fur.append(shape)
	segment.add_child(shape)
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = size
	mesh.mesh = cube
	mesh.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.29, 0.2, 0.13) if fur else Color(0.38, 0.38, 0.3)
	mesh.material_override = mat
	segment.add_child(mesh)

func _choose_intent(_obs: ColossusObservation) -> ColossusIntent:
	return ColossusIntent.make(&"stone_guardian")

func _execute_intent(_it: ColossusIntent, delta: float) -> void:
	if _won:
		return
	var open := bridge != null and bridge.route_open
	for patch in _fur:
		if patch.disabled == open:
			patch.set_deferred(&"disabled", not open)
	for i in weak_points.size():
		weak_points[i].set_protected(not open or i == 1 and weak_points[0].state != WeakPoint.State.DESTROYED)
	var on_body := not _time_on_body.is_empty()
	_on_body = _on_body + delta if on_body else 0
	_throw_wait -= delta
	if throw_time < 0 and _throw_wait <= 0 and not on_body:
		var nearest: PlayerCharacter
		var best := 135.0
		for node in get_tree().get_nodes_in_group(&"players"):
			var p := node as PlayerCharacter
			if p != null and not p.dead:
				var dist := p.global_position.distance_to(global_position)
				if dist < best:
					best = dist
					nearest = p
		if nearest != null:
			throw_player = nearest
			throw_target = nearest.global_position
			throw_time = 0
			_throw_wait = 8.0
			_marker.visible = true
			_marker.global_position = throw_target + Vector3.DOWN * 0.86
	if throw_time >= 0:
		throw_time += delta
		if throw_time >= 2.0:
			_launch_stone()
			throw_time = -1
			_marker.visible = false
	_update_stones(delta)
	_shake_wait -= delta
	if on_body and _shake_wait <= 0 and _shake_time < 0:
		_shake_time = 0
		_shake_wait = 10
	if _shake_time >= 0:
		_shake_time += delta
		if _shake_time > 3:
			_shake_time = -1

func _launch_stone() -> void:
	var start := global_transform * Vector3(-4, 13, 0)
	var flight := 2.6
	var velocity := (throw_target - start + Vector3.UP * 0.5 * 9.8 * flight * flight) / flight
	var mesh := MeshInstance3D.new()
	mesh.top_level = true
	var sphere := SphereMesh.new()
	sphere.radius = 0.65
	sphere.height = 1.3
	mesh.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.39, 0.31)
	mesh.material_override = mat
	add_child(mesh)
	mesh.global_position = start
	_stones.append({"pos": start, "vel": velocity, "age": 0.0, "mesh": mesh, "hit_ids": {}})
	stats.throws += 1

func _update_stones(delta: float) -> void:
	for i in range(_stones.size() - 1, -1, -1):
		var stone := _stones[i]
		var start: Vector3 = stone.pos
		var end: Vector3 = start + (stone.vel as Vector3) * delta + Vector3.DOWN * 0.5 * 9.8 * delta * delta
		stone.vel += Vector3.DOWN * 9.8 * delta
		stone.age += delta
		var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start, end, Layers.WORLD))
		if not hit.is_empty():
			var collider := hit.collider as Node
			if bridge != null and collider.has_meta(&"saru_counterweight") and bridge.stone_impact(int(collider.get_meta(&"saru_counterweight"))):
				stats.counterweight_hits += 1
			(stone.mesh as Node).queue_free()
			_stones.remove_at(i)
			continue
		for node in get_tree().get_nodes_in_group(&"players"):
			var p := node as PlayerCharacter
			if p == null or p.dead or owns_body(p.get_support_body()) or stone.hit_ids.has(p.get_instance_id()):
				continue
			var step := end - start
			var u := clampf((p.global_position - start).dot(step) / maxf(step.length_squared(), 0.001), 0, 1)
			if p.global_position.distance_to(start + step * u) < 1.6:
				stone.hit_ids[p.get_instance_id()] = true
				if p.apply_hit(25, (stone.vel as Vector3).normalized() * 6 + Vector3.UP * 2, 1.2, &"saru_stone"):
					stats.player_hits += 1
		stone.pos = end
		(stone.mesh as Node3D).global_position = end
		if stone.age > 6:
			(stone.mesh as Node).queue_free()
			_stones.remove_at(i)

func _pose_bones(_delta: float) -> void:
	var lean := -0.15 * sin(throw_time / 2 * PI) if throw_time >= 0 else 0.0
	if _shake_time > 1.5:
		lean += sin((_shake_time - 1.5) * 8) * 0.05
	skeleton.set_bone_pose_rotation(0, Quaternion.from_euler(Vector3(lean, 0, 0)))
	skeleton.set_bone_pose_rotation(2, Quaternion.from_euler(Vector3(-1.1 * sin(throw_time / 2 * PI) if throw_time >= 0 else 0, 0, 0)))

func _check_victory() -> void:
	if not _won and weak_points.all(func(w: WeakPoint) -> bool: return w.state == WeakPoint.State.DESTROYED):
		_won = true
		defeated.emit()

func beam_weak_point() -> WeakPoint:
	for wp in weak_points:
		if wp.state != WeakPoint.State.DESTROYED:
			return wp
	return null

func is_defeated() -> bool:
	return _won

func get_focus_point() -> Vector3:
	return global_position + Vector3.UP * 9

func get_danger_zones() -> Array:
	return [[throw_target, 2.5, maxf(0, 2 - throw_time)]] if throw_time >= 0 else []

func reset_encounter(xf := Transform3D.IDENTITY, use_xf := false) -> void:
	if use_xf:
		_home = xf
	global_transform = _home
	arena_center = _home.origin
	_time = 0
	_won = false
	throw_time = -1
	_throw_wait = 4
	_shake_time = -1
	_shake_wait = 10
	_on_body = 0
	_marker.visible = false
	_time_on_body.clear()
	_off_body_time.clear()
	stats = {"throws": 0, "counterweight_hits": 0, "player_hits": 0, "weak_point_hits": 0}
	for stone in _stones:
		(stone.mesh as Node).queue_free()
	_stones.clear()
	if bridge != null:
		bridge.reset()
	for wp in weak_points:
		wp.reset()
		wp.set_protected(true)
	for patch in _fur:
		patch.set_deferred(&"disabled", true)
	_pose_bones(0)
	_sync_segments()
	_sync_segments()

func debug_text() -> String:
	return "SARU | kamienie%d | bloki%d/2 | most%s | rzut%.1f" % [stats.throws, stats.counterweight_hits, str(bridge.route_open if bridge else false), throw_time]

func encounter_hint() -> String:
	if _won:
		return "Saru pokonany. Przeprawa jest wolna."
	if bridge == null or not bridge.route_open:
		return "Wejdź rampą na galerię. Ustaw złotą przeciwwagę między sobą a Saru. Po zapowiedzi rzutu odejdź w bok; zrób tak z obiema przeciwwagami."
	return "Dwa bloki tworzą most nad przepaścią. Przejdź nim na drugą galerię, chwyć grzbiet Saru i dotrzyj do obu znaków."
