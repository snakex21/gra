class_name PairedSentinel
extends Colossus
## One physical guardian in the shared encounter. Armour locks its fur and sigil.
enum Mode { HUNT, WARN, CHARGE, FIRE_WARN, FIRE_RETREAT, RECOVER, DEAD }
var coordinator: CelosiaCenobia
var index := 0
var target: PlayerCharacter
var mode := Mode.HUNT
var timer := 0.0
var cooldown := 0.0
var armour_open := false
var weak_point: WeakPoint
var stats := {"charges": 0, "hits": 0, "armour_breaks": 0, "weak_hits": 0}
var _home := Transform3D.IDENTITY
var _direction := Vector3.FORWARD
var _fur: Array[ClimbPatch] = []
var _material: StandardMaterial3D
var _hit_ids := {}
var _on_body := 0.0

func _ready() -> void:
	super()
	add_to_group(&"danger_sources")
	_home = global_transform
	weak_point = WeakPoint.create(segments[0], Vector3(0, 1.36, 0.4), 80.0)
	weak_point.set_protected(true)
	weak_point.struck.connect(func(_d: float, _h: float) -> void:
		stats.weak_hits += 1
		_set_mode(Mode.RECOVER)
		cooldown = 3.0)
	weak_point.destroyed.connect(func() -> void:
		_set_mode(Mode.DEAD)
		coordinator.on_guardian_defeated())

func _build_body() -> void:
	skeleton = Skeleton3D.new()
	add_child(skeleton)
	var bone := skeleton.add_bone(&"body")
	skeleton.set_bone_rest(bone, Transform3D(Basis.IDENTITY, Vector3(0, 1.8, 0)))
	skeleton.reset_bone_poses()
	var segment := BodySegment.new()
	segment.name = "Body"
	segment.colossus = self
	segment.bone_name = &"body"
	segment.bone_idx = bone
	add_child(segment)
	segments.append(segment)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3, 2.4, 4.6)
	shape.shape = box
	segment.add_child(shape)
	var mesh := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = box.size
	mesh.mesh = body_mesh
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.36, 0.3, 0.22) if index == 0 else Color(0.29, 0.34, 0.36)
	mesh.material_override = _material
	segment.add_child(mesh)
	for spec in [[Vector3(3.1, 0.3, 4.6), Vector3(0, 1.15, 0)], [Vector3(3.1, 2.3, 0.35), Vector3(0, 0, 2.4)]]:
		var patch := ClimbPatch.new()
		var fur_shape := BoxShape3D.new()
		fur_shape.size = spec[0]
		patch.shape = fur_shape
		patch.position = spec[1]
		patch.disabled = true
		segment.add_child(patch)
		_fur.append(patch)
	var head := MeshInstance3D.new()
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(2.2, 1.4, 1.2)
	head.mesh = head_mesh
	head.position = Vector3(0, -0.1, -2.65)
	head.material_override = _material
	segment.add_child(head)
	for side: float in [-1.0, 1.0]:
		for z: float in [-1.5, 1.5]:
			var leg := MeshInstance3D.new()
			var leg_mesh := BoxMesh.new()
			leg_mesh.size = Vector3(0.65, 1.5, 0.65)
			leg.mesh = leg_mesh
			leg.position = Vector3(side * 1.3, -1.1, z)
			leg.material_override = _material
			segment.add_child(leg)

func _choose_intent(_obs: ColossusObservation) -> ColossusIntent:
	return ColossusIntent.make(&"paired_guard")

func _execute_intent(_it: ColossusIntent, delta: float) -> void:
	timer += delta
	cooldown = maxf(0.0, cooldown - delta)
	if mode == Mode.DEAD:
		return
	var riders := false
	for node in get_tree().get_nodes_in_group(&"players"):
		var p := node as PlayerCharacter
		if p != null and not p.dead and owns_body(p.get_support_body()):
			riders = true
	_on_body = _on_body + delta if riders else 0.0
	if riders:
		# An exposed back bucks with a warning and a long rest; no charge can target
		# someone who is already hanging on either guardian.
		if _on_body > 5.0 and cooldown <= 0.0:
			cooldown = 8.0
			_on_body = 0.0
		return
	if index == 0 and not armour_open and mode in [Mode.HUNT, Mode.WARN, Mode.RECOVER] and coordinator.fire_faces(self):
		var carrier := coordinator.fire_carrier(self)
		_direction = _flat(global_position - carrier.global_position).normalized()
		_set_mode(Mode.FIRE_WARN)
	match mode:
		Mode.FIRE_WARN:
			if timer >= 1.0:
				_set_mode(Mode.FIRE_RETREAT)
		Mode.FIRE_RETREAT:
			_move(_direction, 10.0, delta, true)
			if timer > 3.0:
				_set_mode(Mode.RECOVER)
		Mode.WARN:
			if timer >= 1.35:
				_hit_ids.clear()
				stats.charges += 1
				_set_mode(Mode.CHARGE)
		Mode.CHARGE:
			_move(_direction, 12.0, delta, true)
			_test_charge_hits()
			if timer > 2.8:
				_set_mode(Mode.RECOVER)
		Mode.RECOVER:
			if timer >= (7.0 if armour_open else 1.8):
				cooldown = maxf(cooldown, 3.0)
				_set_mode(Mode.HUNT)
		Mode.HUNT:
			if target == null or target.dead:
				return
			var to := _flat(target.global_position - global_position)
			var protected := coordinator.sheltered(target) or coordinator.owns_body(target.get_support_body())
			if protected:
				if to.length() > 10.0:
					_move(to.normalized(), 2.0, delta, false)
				return
			if to.length() < 24.0 and to.length() > 3.0 and cooldown <= 0.0:
				_direction = to.normalized()
				_set_mode(Mode.WARN)
			elif to.length() > 5.0:
				_move(to.normalized(), 2.0, delta, false)

func _move(direction: Vector3, speed: float, delta: float, committed: bool) -> void:
	if direction.length() < 0.1:
		return
	var yaw := atan2(-direction.x, -direction.z)
	global_rotation.y = yaw if committed else rotate_toward(global_rotation.y, yaw, delta * 1.5)
	var forward := -global_basis.z
	var from := global_position + Vector3.UP * 1.3
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + forward * (3.0 + speed * delta), Layers.WORLD))
	if not hit.is_empty():
		if committed and coordinator.wall_impact(self, hit.collider):
			open_armour()
		if committed:
			_set_mode(Mode.RECOVER)
			return
		# Follow an obstacle's edge during pursuit; the charge itself never steers.
		var found := false
		for angle: float in [0.8, -0.8, 1.6, -1.6, 2.4, -2.4]:
			var candidate := direction.rotated(Vector3.UP, angle)
			var probe := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + candidate * 3.3, Layers.WORLD))
			if probe.is_empty():
				forward = candidate
				global_rotation.y = atan2(-forward.x, -forward.z)
				found = true
				break
		if not found:
			return
	var next := global_position + forward * speed * delta
	var local := coordinator.to_local(next)
	if absf(local.x) < 70.0 and absf(local.z) < 70.0:
		global_position = next

func _test_charge_hits() -> void:
	for node in get_tree().get_nodes_in_group(&"players"):
		var p := node as PlayerCharacter
		if p == null or p.dead or _hit_ids.has(p.get_instance_id()) or coordinator.owns_body(p.get_support_body()) or coordinator.sheltered(p) or p.balance.state == Balance.State.FALLEN:
			continue
		if _flat(p.global_position - (global_position - global_basis.z * 2.8)).length() < 2.7 and p.global_position.y - global_position.y < 2.8:
			_hit_ids[p.get_instance_id()] = true
			if p.apply_hit(24.0, -global_basis.z * 6.0 + Vector3.UP * 2.0, 1.2, &"paired_charge"):
				stats.hits += 1

func _pose_bones(_delta: float) -> void:
	if skeleton == null:
		return
	var pitch := 0.0
	if mode in [Mode.WARN, Mode.FIRE_WARN]:
		pitch = sin(clampf(timer / 1.35, 0.0, 1.0) * PI * 0.5) * 0.18
	if mode == Mode.DEAD:
		pitch = -0.2
	var buck := 0.08 * sin(timer * 9.0) if _on_body < 1.2 and cooldown > 6.5 else 0.0
	skeleton.set_bone_pose_rotation(0, Quaternion.from_euler(Vector3(pitch, 0, buck)))

func open_armour() -> void:
	if armour_open:
		return
	armour_open = true
	stats.armour_breaks += 1
	weak_point.set_protected(false)
	_material.albedo_color = Color(0.38, 0.23, 0.12)
	for patch in _fur:
		patch.set_deferred(&"disabled", false)

func reset_guardian() -> void:
	global_transform = _home
	mode = Mode.HUNT
	timer = 0.0
	cooldown = 1.0
	armour_open = false
	_on_body = 0.0
	weak_point.reset()
	weak_point.set_protected(true)
	stats = {"charges": 0, "hits": 0, "armour_breaks": 0, "weak_hits": 0}
	_material.albedo_color = Color(0.36, 0.3, 0.22) if index == 0 else Color(0.29, 0.34, 0.36)
	_pose_bones(0.0)
	for patch in _fur:
		patch.set_deferred(&"disabled", true)
	_sync_segments()
	_sync_segments()

func is_defeated() -> bool:
	return mode == Mode.DEAD

func _set_mode(next: Mode) -> void:
	mode = next
	timer = 0.0

func beam_weak_point() -> WeakPoint:
	return weak_point if not is_defeated() else null

func get_focus_point() -> Vector3:
	return global_position + Vector3.UP * 2.0

func get_danger_zones() -> Array:
	if mode in [Mode.WARN, Mode.CHARGE]:
		return [[global_position - global_basis.z * 8, 4.0, maxf(0.0, 1.35 - timer)]]
	return []

static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)
