class_name PcVrSword
extends Node3D
## One loose, metre-sized sword. Only a fresh squeeze near its physical grip picks it up.
## Dropped physics are owned by RigidBody3D; a recalled sword parks at the waist.
const MODEL_PATH := "res://models/weapons_v4/sword_lod1.glb"
const PRESS := 0.65
const RELEASE := 0.35
const PICKUP_REACH := 0.18
const RECALL_TIME := 2.0
const RECALL_DISTANCE := 3.0
const MAX_POSE_STEP := 0.65
static var _packed: PackedScene

var head: XRCamera3D
var controllers: Array[XRController3D] = []
var player_body: CharacterBody3D
var sword_body: RigidBody3D
var model: Node3D
var held_hand := -1
var parked := true
var recall_count := 0
var _armed := [false, false]
var _reserved := [false, false]
var _lost_time := 0.0
var _last_velocity := Vector3.ZERO
var _last_right := Vector3.RIGHT
var _shapes: Array[CollisionShape3D] = []
var _query := PhysicsShapeQueryParameters3D.new()

func setup(to_head: XRCamera3D, left: XRController3D, right: XRController3D, owner_body: CharacterBody3D) -> void:
	head = to_head
	controllers = [left, right]
	player_body = owner_body
	if is_instance_valid(player_body) and player_body.global_transform.is_finite():
		_last_right = player_body.global_basis.x
		_last_right.y = 0.0
		_last_right = _last_right.normalized() if _last_right.length_squared() > 0.001 else Vector3.RIGHT
	if is_instance_valid(sword_body): sword_body.free()
	_shapes.clear()
	sword_body = RigidBody3D.new()
	sword_body.name = "LooseSword"
	sword_body.top_level = true
	sword_body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	sword_body.collision_layer = 0
	sword_body.collision_mask = Layers.SOLID
	sword_body.mass = 1.4
	sword_body.continuous_cd = true
	sword_body.linear_damp = 0.2
	sword_body.angular_damp = 0.4
	sword_body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	sword_body.freeze = true
	var physics_material := PhysicsMaterial.new()
	physics_material.friction = 0.75
	physics_material.bounce = 0.05
	sword_body.physics_material_override = physics_material
	add_child(sword_body)
	if is_instance_valid(player_body): sword_body.add_collision_exception_with(player_body)
	_box(Vector3(0.055, 0.97, 0.022), Vector3(0, 0.605, 0))
	_box(Vector3(0.25, 0.045, 0.045), Vector3(0, 0.105, 0))
	_box(Vector3(0.060, 0.36, 0.055), Vector3(0, -0.060, 0))
	if _packed == null and ResourceLoader.exists(MODEL_PATH): _packed = load(MODEL_PATH) as PackedScene
	if _packed:
		model = _packed.instantiate() as Node3D
		model.name = "SwordV4"
		sword_body.add_child(model)
		model.transform = Transform3D.IDENTITY
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_query.collision_mask = Layers.SOLID
	_query.margin = 0.001
	_query.exclude = [sword_body.get_rid(), player_body.get_rid()] if is_instance_valid(player_body) else [sword_body.get_rid()]
	recall(false)

func step(delta: float, frame: Dictionary, ready: bool) -> Dictionary:
	var consumed := [false, false]
	if not is_instance_valid(sword_body) or not is_instance_valid(player_body): return _result(consumed)
	if not ready or not is_instance_valid(head) or not head.transform.is_finite() or head.position.y < 0.3 or head.position.y > 2.6:
		recall(false)
		return _result(consumed)
	if not is_finite(delta) or delta <= 0.0: return _result(_reserved.duplicate())
	var dt := minf(delta, 0.05)
	var tracked := [false, false]
	var strength := [0.0, 0.0]
	for i in 2:
		var key := "left" if i == 0 else "right"
		var flag: Variant = frame.get(key + "_tracked", false)
		tracked[i] = flag is bool and flag and is_instance_valid(controllers[i]) and controllers[i].global_transform.is_finite() and controllers[i].global_position.distance_to(head.global_position) <= 1.5
		var value: Variant = frame.get(key + "_grip", 0.0)
		strength[i] = clampf(float(value), 0.0, 1.0) if typeof(value) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(value)) else 0.0
		consumed[i] = _reserved[i]
		if not tracked[i]:
			_armed[i] = false
			if held_hand == i:
				recall(false)
				consumed[i] = true
			elif strength[i] <= RELEASE: _reserved[i] = false
		elif strength[i] <= RELEASE:
			_armed[i] = true
			_reserved[i] = false
	if held_hand >= 0:
		var holder := held_hand
		consumed[holder] = true
		if strength[holder] <= RELEASE:
			_drop()
		else:
			sync_held_pose(dt)
	if held_hand < 0:
		if not parked:
			_lost_time += dt
			var feet_y := player_body.global_position.y - 0.9
			if _lost_time >= RECALL_TIME or not sword_body.global_transform.is_finite() or sword_body.global_position.distance_to(player_body.global_position) > RECALL_DISTANCE or sword_body.global_position.y < feet_y - 1.0:
				recall()
		if parked: _park_near_player()
		for i in [1, 0]:
			if not tracked[i] or strength[i] < PRESS or not _armed[i] or _reserved[i]: continue
			_armed[i] = false
			if sword_body.visible and controllers[i].global_position.distance_to(sword_body.global_position) <= PICKUP_REACH:
				_reserved[i] = true
				consumed[i] = true
				if _pickup(i, dt): break
	for i in 2: consumed[i] = consumed[i] or _reserved[i] or held_hand == i
	return _result(consumed)

## Call after origin/capsule movement to keep a held, collision-constrained grip current.
func sync_held_pose(delta := 1.0 / 90.0) -> void:
	if held_hand < 0 or not is_instance_valid(sword_body): return
	var hand := controllers[held_hand]
	if not is_instance_valid(hand) or not hand.global_transform.is_finite():
		recall(false)
		return
	var before := sword_body.global_position
	var target := Transform3D(hand.global_basis.orthonormalized(), hand.global_position)
	if before.distance_to(target.origin) > MAX_POSE_STEP or not _move_held(target):
		_drop()
		return
	_last_velocity = ((sword_body.global_position - before) / maxf(delta, 0.001)).limit_length(4.0)

func sync_pose(delta := 1.0 / 90.0) -> void:
	if held_hand >= 0:
		# The main input step measures tracked-hand motion once per tick; this
		# second sync adds only displacement caused by locomotion/climbing.
		var hand_velocity := _last_velocity
		sync_held_pose(delta)
		if held_hand >= 0: _last_velocity = (hand_velocity + _last_velocity).limit_length(4.0)
	elif parked and is_instance_valid(sword_body): _park_near_player()

## Pause, head loss and deliberate recenter park the sword, never bind it to a hand.
func recall(count_event := true) -> void:
	held_hand = -1
	parked = true
	_lost_time = 0.0
	_armed = [false, false]
	_reserved = [false, false]
	_last_velocity = Vector3.ZERO
	if count_event: recall_count += 1
	if not is_instance_valid(sword_body): return
	sword_body.freeze = true
	sword_body.linear_velocity = Vector3.ZERO
	sword_body.angular_velocity = Vector3.ZERO
	_park_near_player()

func _result(consumed: Array) -> Dictionary:
	return {"left_consumed": bool(consumed[0]), "right_consumed": bool(consumed[1]), "held_hand": held_hand}

func _pickup(index: int, dt: float) -> bool:
	var target := Transform3D(controllers[index].global_basis.orthonormalized(), controllers[index].global_position)
	var ray := PhysicsRayQueryParameters3D.create(sword_body.global_position, target.origin, Layers.SOLID, _query.exclude)
	if target.origin.distance_to(sword_body.global_position) > 0.001 and not sword_body.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): return false
	if not _pose_clear(target): return false
	sword_body.collision_mask = Layers.SOLID
	var was_frozen := sword_body.freeze
	sword_body.freeze = true
	if not _move_held(target):
		sword_body.freeze = was_frozen
		return false
	held_hand = index
	parked = false
	_lost_time = 0.0
	_last_velocity = Vector3.ZERO
	sync_held_pose(dt)
	return held_hand == index

func _drop() -> void:
	held_hand = -1
	parked = false
	_lost_time = 0.0
	sword_body.collision_mask = Layers.SOLID
	sword_body.freeze = false
	sword_body.sleeping = false
	sword_body.linear_velocity = _last_velocity
	sword_body.angular_velocity = Vector3.ZERO
	_last_velocity = Vector3.ZERO

func _move_held(target: Transform3D) -> bool:
	var rotation_from := sword_body.global_basis.orthonormalized()
	var motion := target.origin - sword_body.global_position
	if motion.length_squared() > 0.00000001: sword_body.move_and_collide(motion, false, 0.001, true)
	if sword_body.global_position.distance_to(target.origin) > 0.004: return false
	var angle := rotation_from.get_rotation_quaternion().angle_to(target.basis.get_rotation_quaternion())
	var samples := maxi(1, ceili(angle / deg_to_rad(3.0)))
	for i in samples:
		var basis := rotation_from.slerp(target.basis, float(i + 1) / float(samples))
		var pose := Transform3D(basis, sword_body.global_position)
		if not _pose_clear(pose): return false
		sword_body.global_basis = basis
	return true

func _pose_clear(pose: Transform3D) -> bool:
	var space := sword_body.get_world_3d().direct_space_state
	for shape in _shapes:
		_query.shape = shape.shape
		_query.transform = pose * shape.transform
		if not space.intersect_shape(_query, 1).is_empty(): return false
	return true

func _park_near_player() -> void:
	if not is_instance_valid(player_body) or not player_body.global_transform.is_finite(): return
	var rightward := head.global_basis.x if is_instance_valid(head) and head.global_transform.is_finite() else _last_right
	rightward.y = 0.0
	if rightward.length_squared() < 0.001: rightward = _last_right
	rightward = rightward.normalized()
	_last_right = rightward
	var forward := Vector3.UP.cross(rightward)
	var basis := Basis(rightward, Vector3.DOWN, rightward.cross(Vector3.DOWN))
	var waist := player_body.global_position + Vector3.UP * 0.2
	var preferred := Transform3D(basis, waist + rightward * 0.28 + forward * 0.30)
	for offset in [rightward * 0.28 + forward * 0.30, -rightward * 0.28 + forward * 0.30, rightward * 0.32 - forward * 0.25, -rightward * 0.32 - forward * 0.25]:
		var candidate := Transform3D(basis, waist + offset)
		if _pose_clear(candidate):
			sword_body.visible = true
			sword_body.collision_mask = Layers.SOLID
			sword_body.global_transform = candidate
			sword_body.reset_physics_interpolation()
			return
	sword_body.visible = false
	sword_body.collision_mask = 0
	sword_body.global_transform = preferred

func _box(size: Vector3, at: Vector3) -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = at
	sword_body.add_child(collision)
	_shapes.append(collision)
