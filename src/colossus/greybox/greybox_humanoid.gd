class_name GreyboxHumanoid
extends Colossus
## ~17 m greybox humanoid used to prove climbing on a moving body (Milestone 1).
##
## The rig is data driven (BONES / PARTS tables) so proportions and climbable areas
## can be tuned without touching code. Colossus forward is -Z, its left side is +X.
## Surfaces: FUR = climbable (ClimbPatch), STONE = solid, can be stood on,
## ARMOR = solid plates protruding over fur that block climbing routes.

enum Kind { FUR, STONE, ARMOR }

## [bone, parent, offset from parent joint]
const BONES := [
	[&"hips", &"", Vector3(0, 8.0, 0)],
	[&"spine", &"hips", Vector3(0, 1.0, 0)],
	[&"chest", &"spine", Vector3(0, 2.2, 0)],
	[&"neck", &"chest", Vector3(0, 2.8, 0)],
	[&"head", &"neck", Vector3(0, 1.0, 0)],
	[&"upper_arm_l", &"chest", Vector3(2.9, 2.3, 0)],
	[&"forearm_l", &"upper_arm_l", Vector3(0, -4.2, 0)],
	[&"hand_l", &"forearm_l", Vector3(0, -4.2, 0)],
	[&"upper_arm_r", &"chest", Vector3(-2.9, 2.3, 0)],
	[&"forearm_r", &"upper_arm_r", Vector3(0, -4.2, 0)],
	[&"hand_r", &"forearm_r", Vector3(0, -4.2, 0)],
	[&"thigh_l", &"hips", Vector3(1.3, -0.4, 0)],
	[&"shin_l", &"thigh_l", Vector3(0, -3.8, 0)],
	[&"foot_l", &"shin_l", Vector3(0, -3.4, 0)],
	[&"thigh_r", &"hips", Vector3(-1.3, -0.4, 0)],
	[&"shin_r", &"thigh_r", Vector3(0, -3.8, 0)],
	[&"foot_r", &"shin_r", Vector3(0, -3.4, 0)],
]

## [bone, kind, shape ("box" size | "capsule" Vector2(radius, height)), center in bone space]
## Parts ending in _l are mirrored automatically for _r.
const PARTS := [
	[&"hips", Kind.FUR, Vector3(4.2, 1.6, 2.6), Vector3(0, 0.2, 0)],
	[&"spine", Kind.FUR, Vector3(3.4, 2.4, 2.4), Vector3(0, 1.1, 0)],
	[&"chest", Kind.STONE, Vector3(5.0, 2.8, 3.0), Vector3(0, 1.4, 0)],
	[&"chest", Kind.FUR, Vector3(4.4, 2.9, 0.5), Vector3(0, 1.2, 1.6)],
	[&"neck", Kind.FUR, Vector2(0.8, 2.2), Vector3(0, 0.6, 0.1)],
	[&"head", Kind.STONE, Vector3(2.0, 2.2, 2.2), Vector3(0, 1.1, 0)],
	[&"head", Kind.FUR, Vector3(1.9, 0.4, 2.0), Vector3(0, 2.3, 0.1)],
	[&"head", Kind.FUR, Vector3(1.8, 1.8, 0.4), Vector3(0, 1.1, 1.2)],
	[&"upper_arm_l", Kind.FUR, Vector2(0.8, 4.6), Vector3(0, -2.0, 0)],
	[&"forearm_l", Kind.FUR, Vector2(0.7, 4.4), Vector3(0, -2.0, 0)],
	[&"forearm_l", Kind.ARMOR, Vector3(0.5, 2.6, 1.3), Vector3(0.75, -2.0, 0)],
	[&"hand_l", Kind.STONE, Vector3(1.3, 1.8, 1.1), Vector3(0, -0.9, 0)],
	[&"thigh_l", Kind.FUR, Vector2(1.0, 4.4), Vector3(0, -1.9, 0)],
	[&"shin_l", Kind.FUR, Vector2(0.85, 4.0), Vector3(0, -1.7, 0)],
	[&"shin_l", Kind.ARMOR, Vector3(1.3, 2.8, 0.45), Vector3(0, -1.7, -0.85)],
	[&"foot_l", Kind.STONE, Vector3(1.7, 0.7, 2.8), Vector3(0, -0.05, -0.45)],
]

const COLORS := {
	Kind.FUR: Color(0.36, 0.27, 0.19),
	Kind.STONE: Color(0.55, 0.55, 0.52),
	Kind.ARMOR: Color(0.30, 0.31, 0.33),
}

@export var walk_speed := 1.4       ## m/s
@export var walk_accel := 0.5       ## m/s^2, huge bodies speed up slowly
@export var turn_rate := 0.3        ## rad/s at walking speed
@export var stride := 4.6           ## m per step
@export var shake_frequency := 1.4  ## Hz
@export var shake_ramp := 0.6       ## seconds to reach full shake

# Continuous controller state.
var _speed := 0.0
var _target_speed := 0.0
var _goal := Vector3.ZERO
var _has_goal := false
var _gait_phase := 0.0
var _shake := 0.0
var _target_shake := 0.0
var _shake_phase := 0.0
var _breath_phase := 0.0
var _look := Vector2.ZERO           # yaw, pitch (radians, colossus space)
var _look_target: Node3D
var _hip_drop := 0.0
var _bone := {}                     # name -> idx
var _rest := {}                     # name -> Vector3 offset


func _build_body() -> void:
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	add_child(skeleton)
	for b in BONES:
		var idx := skeleton.add_bone(b[0])
		_bone[b[0]] = idx
		_rest[b[0]] = b[2]
		if b[1] != &"":
			skeleton.set_bone_parent(idx, _bone[b[1]])
		skeleton.set_bone_rest(idx, Transform3D(Basis.IDENTITY, b[2]))
	skeleton.reset_bone_poses()

	var materials := {}
	for k in COLORS:
		var m := StandardMaterial3D.new()
		m.albedo_color = COLORS[k]
		m.roughness = 1.0 if k == Kind.FUR else 0.8
		materials[k] = m

	var seg_by_bone := {}
	for part in _all_parts():
		var bone: StringName = part[0]
		var seg: BodySegment = seg_by_bone.get(bone)
		if seg == null:
			seg = BodySegment.new()
			seg.name = "Seg_" + bone
			seg.colossus = self
			seg.bone_name = bone
			seg.bone_idx = _bone[bone]
			add_child(seg)
			segments.append(seg)
			seg_by_bone[bone] = seg
		_add_part(seg, part[1], part[2], part[3], materials[part[1]])


func _all_parts() -> Array:
	var out := []
	for p in PARTS:
		out.append(p)
		var bone := String(p[0])
		if bone.ends_with("_l"):
			var center: Vector3 = p[3]
			out.append([StringName(bone.trim_suffix("_l") + "_r"), p[1], p[2], Vector3(-center.x, center.y, center.z)])
	return out


func _add_part(seg: BodySegment, kind: Kind, size: Variant, center: Vector3, material: Material) -> void:
	var col: CollisionShape3D = ClimbPatch.new() if kind == Kind.FUR else CollisionShape3D.new()
	var mesh := MeshInstance3D.new()
	if size is Vector3:
		var s := BoxShape3D.new()
		s.size = size
		col.shape = s
		var m := BoxMesh.new()
		m.size = size
		mesh.mesh = m
	else:
		var s := CapsuleShape3D.new()
		s.radius = size.x
		s.height = size.y
		col.shape = s
		var m := CapsuleMesh.new()
		m.radius = size.x
		m.height = size.y
		m.radial_segments = 16
		m.rings = 6
		mesh.mesh = m
	col.position = center
	mesh.position = center
	mesh.material_override = material
	seg.add_child(col)
	seg.add_child(mesh)


func get_focus_point() -> Vector3:
	return skeleton.global_transform * skeleton.get_bone_global_pose(_bone[&"chest"]).origin


# --- continuous controller ----------------------------------------------------------

func _execute_intent(it: ColossusIntent, delta: float) -> void:
	_target_speed = 0.0
	_target_shake = 0.0
	_has_goal = false
	_look_target = it.target_player
	match it.kind:
		ColossusIntent.REPOSITION:
			_goal = it.target_position
			_has_goal = true
			_target_speed = walk_speed
		ColossusIntent.FOCUS_PLAYER:
			if is_instance_valid(it.target_player):
				_goal = it.target_player.global_position
				_has_goal = true
				var d := _flat(_goal - global_position).length()
				_target_speed = walk_speed * clampf((d - 14.0) / 10.0, 0.0, 1.0)
		ColossusIntent.SHAKE_PLAYER:
			_target_shake = clampf(it.strength, 0.0, 1.0)
	if _look_target == null:
		_look_target = _nearest_player()

	# Big bodies change state slowly and continuously.
	var accel := walk_accel * (2.5 if _target_speed < _speed else 1.0)
	_speed = move_toward(_speed, _target_speed * (1.0 - _shake), accel * delta)
	_shake = move_toward(_shake, _target_shake, delta / shake_ramp)

	if _has_goal:
		var to_goal := _flat(_goal - global_position)
		if to_goal.length() > 0.5:
			var fwd := -global_basis.z
			var angle := fwd.signed_angle_to(to_goal.normalized(), Vector3.UP)
			var max_turn := turn_rate * (0.35 + 0.65 * clampf(_speed / walk_speed, 0.0, 1.0)) * delta
			rotate_y(clampf(angle, -max_turn, max_turn))
			# Slow down for sharp turns instead of walking in circles.
			_speed = minf(_speed, walk_speed * clampf(1.2 - absf(angle), 0.25, 1.0) + 0.001)
	global_position += -global_basis.z * _speed * delta

	_gait_phase = fmod(_gait_phase + _speed / stride * PI * delta, TAU)
	_shake_phase = fmod(_shake_phase + shake_frequency * TAU * delta, TAU * 8.0)
	_breath_phase = fmod(_breath_phase + 0.25 * TAU * delta, TAU)


func _pose_bones(delta: float) -> void:
	var w := clampf(_speed / walk_speed, 0.0, 1.0)
	var s := sin(_gait_phase)
	var c := cos(_gait_phase)
	var breath := sin(_breath_phase)
	var sh := _shake
	var sp := _shake_phase

	# Legs: swing + knee lift on the forward swing; feet stay roughly level.
	var thigh_l := s * 0.33 * w
	var thigh_r := -thigh_l
	var knee_l := -maxf(0.0, c) * 0.55 * w
	var knee_r := -maxf(0.0, -c) * 0.55 * w
	# Shaking: brace with bent knees.
	thigh_l += 0.18 * sh
	thigh_r += 0.18 * sh
	knee_l -= 0.3 * sh
	knee_r -= 0.3 * sh
	_rot(&"thigh_l", Vector3(thigh_l, 0, 0))
	_rot(&"thigh_r", Vector3(thigh_r, 0, 0))
	_rot(&"shin_l", Vector3(knee_l, 0, 0))
	_rot(&"shin_r", Vector3(knee_r, 0, 0))
	_rot(&"foot_l", Vector3(-(thigh_l + knee_l), 0, 0))
	_rot(&"foot_r", Vector3(-(thigh_r + knee_r), 0, 0))

	# Hips: lower when legs are apart / knees bent (keeps the stance foot near the ground).
	var target_drop := 0.42 * s * s * w + 0.55 * sh
	_hip_drop = lerpf(_hip_drop, target_drop, 1.0 - exp(-10.0 * delta))
	var hips_pos: Vector3 = _rest[&"hips"] + Vector3(0, -_hip_drop + breath * 0.03, 0)
	skeleton.set_bone_pose_position(_bone[&"hips"], hips_pos)
	_rot(&"hips", Vector3(0, s * 0.05 * w, s * 0.035 * w))

	# Torso: breathing, counter-rotation while walking, violent twist while shaking.
	_rot(&"spine", Vector3(breath * 0.015 + 0.1 * sh, -s * 0.04 * w + sin(sp * 0.5 + 1.0) * 0.07 * sh, sin(sp) * 0.09 * sh))
	_rot(&"chest", Vector3(breath * 0.02, sin(sp * 0.5) * 0.05 * sh, sin(sp + 0.7) * 0.11 * sh))

	# Arms: counter-swing, flail when shaking.
	var arm := -s * 0.22 * w
	_rot(&"upper_arm_l", Vector3(arm + sin(sp + 2.0) * 0.25 * sh, 0, 0.08 + 0.55 * sh + sin(sp) * 0.2 * sh))
	_rot(&"upper_arm_r", Vector3(-arm + sin(sp + 0.5) * 0.25 * sh, 0, -0.08 - 0.55 * sh - sin(sp + 1.3) * 0.2 * sh))
	_rot(&"forearm_l", Vector3(-0.25 - 0.1 * w - 0.35 * sh, 0, 0))
	_rot(&"forearm_r", Vector3(-0.25 - 0.1 * w - 0.35 * sh, 0, 0))
	_rot(&"hand_l", Vector3.ZERO)
	_rot(&"hand_r", Vector3.ZERO)

	# Head: track the look target with soft limits, split over neck and head.
	var target_look := Vector2.ZERO
	if is_instance_valid(_look_target):
		var head_pos := skeleton.global_transform * skeleton.get_bone_global_pose(_bone[&"head"]).origin
		var dir := global_basis.inverse() * (_look_target.global_position - head_pos)
		if dir.length() > 0.1:
			dir = dir.normalized()
			target_look = Vector2(atan2(-dir.x, -dir.z), atan2(dir.y, Vector2(dir.x, dir.z).length()))
			target_look.x = clampf(target_look.x, -1.0, 1.0)
			target_look.y = clampf(target_look.y, -0.7, 0.4)
	_look = _look.lerp(target_look, 1.0 - exp(-1.5 * delta))
	var head_shake := sin(sp * 1.3) * 0.15 * sh
	_rot(&"neck", Vector3(_look.y * 0.4, _look.x * 0.4, 0))
	_rot(&"head", Vector3(_look.y * 0.6, _look.x * 0.6 + head_shake, 0))


func debug_text() -> String:
	return super() + "\nspeed %.2f  shake %.2f  look %.2f/%.2f" % [_speed, _shake, _look.x, _look.y]


func _rot(bone: StringName, euler: Vector3) -> void:
	skeleton.set_bone_pose_rotation(_bone[bone], Quaternion.from_euler(euler))


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _nearest_player() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group(&"players"):
		var d: float = p.global_position.distance_squared_to(global_position)
		if d < best_d:
			best_d = d
			best = p
	return best
