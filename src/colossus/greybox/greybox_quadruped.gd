class_name GreyboxQuadruped
extends Colossus
## Four-legged greybox colossus: the shared rig / locomotion part of every quadruped boss
## (Quadratus now). The same pipeline as the humanoid, nothing boss-specific:
##
##   intent -> desired movement -> LocomotionController (4 legs, gait order, body that
##   pitches and rolls with what its legs reach, legs that can be weakened) -> body bone
##   from pelvis + tilt + shake -> two-bone IK on every leg -> skeleton -> segments
##
## A concrete quadruped supplies its anatomy through _rig() and _parts() and adds its
## behaviour through the hooks (_adjust_movement, _pose_overrides). Forward is -Z, the
## left side is -X. Legs are ordered front_left, front_right, rear_left, rear_right.

enum Kind { FUR, STONE, ARMOR }

const COLORS := {
	Kind.FUR: Color(0.34, 0.27, 0.2),
	Kind.STONE: Color(0.56, 0.55, 0.51),
	Kind.ARMOR: Color(0.32, 0.33, 0.34),
}
const LEG_NAMES := [&"front_left", &"front_right", &"rear_left", &"rear_right"]

@export var walk_speed := 1.2       ## m/s
@export var turn_rate := 0.16       ## rad/s at walking speed
@export var shake_frequency := 0.9  ## Hz, a heavy roll of the whole torso
@export var shake_ramp := 0.8
## A swinging hoof tips its sole backwards (rad at mid-swing): the heel comes up first.
@export var swing_hoof_flip := 0.9

var loco := LocomotionController.new()
var debug_draw: QuadrupedDebugDraw
## Debug override &"manual": desired movement set directly (tests, tuning).
var debug_desired_speed := 0.0
var debug_desired_turn := 0.0
var desired_speed := 0.0
var desired_turn := 0.0
## Extra pelvis drop (m) and body pitch / roll (rad) requested by a subclass.
var extra_pelvis_drop := 0.0
var extra_pitch := 0.0
var extra_roll := 0.0
## Accumulated foot statistics since reset_foot_stats() (tests / HUD).
var foot_stats := {}

# Anatomy (from _rig()).
var leg_bones: Array = []         # [[upper, lower, foot], ...] in LEG_NAMES order
var upper_len := 4.0
var lower_len := 3.6
var ankle_height := 0.6
var body_above_hips := 1.4

var _bone := {}
var _rest := {}
var _shake := 0.0
var _target_shake := 0.0
var _shake_phase := 0.0
var _shake_target_node: Node3D
var _goal := Vector3.ZERO
var _has_goal := false
var _look := Vector2.ZERO
var _look_target: Node3D
var _sole_prev: Array[Vector3] = []
var _contact_prev: Array[bool] = []
var _ik_usec := 0


# --- anatomy (override) --------------------------------------------------------------

## {"bones": [[name, parent, offset], ...], "legs": [[upper, lower, foot] x4],
##  "upper": m, "lower": m, "ankle": m, "body_above_hips": m, "hip_height": m}
func _rig() -> Dictionary:
	return {}


## [bone, Kind, size (Vector3 box | Vector2(radius, height) capsule), centre, (tag)]
func _parts() -> Array:
	return []


## Hook: adjust desired_speed / desired_turn / _target_shake after the intent was mapped.
func _adjust_movement(_it: ColossusIntent, _delta: float) -> void:
	pass


## Hook: extra bone poses after the base pose (attacks, reactions).
func _pose_overrides(_delta: float) -> void:
	pass


## Hook: extra debug markers (arrow targets, climb route, weak points).
func _draw_debug_extra(_d: QuadrupedDebugDraw) -> void:
	pass


# --- API ------------------------------------------------------------------------------

func get_speed() -> float:
	return loco.speed


func get_focus_point() -> Vector3:
	return skeleton.global_transform * skeleton.get_bone_global_pose(_bone[&"body"]).origin


## Places the colossus (feet re-planted on the ground there).
func teleport(pos: Vector3, yaw: float) -> void:
	loco.reset(get_world_3d().direct_space_state, pos, yaw)
	loco.body_pitch = 0.0
	loco.body_roll = 0.0
	global_transform = Transform3D(loco.body_basis(), loco.position)
	_pose_bones(0.0)
	_sync_segments()
	_sync_segments()
	reset_foot_stats()
	for s in segments:
		s.reset_physics_interpolation()


func sole_world(i: int) -> Vector3:
	var foot: StringName = leg_bones[i][2]
	return skeleton.global_transform * (skeleton.get_bone_global_pose(_bone[foot]) * Vector3(0, -ankle_height, 0))


func reset_foot_stats() -> void:
	foot_stats = {"slip_max": 0.0, "slip_sum": 0.0, "contact_ticks": 0, "reach_max": 0.0, "ticks": 0}
	_contact_prev = [false, false, false, false]
	_sole_prev = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]


## Share of the body weight per leg (LEG_NAMES order).
func leg_loads() -> Array[float]:
	var out: Array[float] = []
	for leg in loco.legs:
		out.append(leg.load)
	return out


# --- simulation ------------------------------------------------------------------------

func _execute_intent(it: ColossusIntent, delta: float) -> void:
	var t0 := Perf.begin()
	var target_speed := 0.0
	_target_shake = 0.0
	_has_goal = false
	_look_target = it.target_player
	match it.kind:
		ColossusIntent.REPOSITION:
			_goal = it.target_position
			_has_goal = true
			target_speed = walk_speed
		ColossusIntent.FOCUS_PLAYER:
			if is_instance_valid(it.target_player):
				_goal = it.target_player.global_position
				_has_goal = true
				var d := _flat(_goal - global_position).length()
				target_speed = walk_speed * clampf((d - 18.0) / 12.0, 0.0, 1.0)
	if it.kind in _shake_kinds() or it.kind == ColossusIntent.SHAKE_PLAYER:
		_target_shake = clampf(it.strength, 0.0, 1.0)
		_shake_target_node = it.target_player
	var turn := 0.0
	if _has_goal:
		var to_goal := _flat(_goal - global_position)
		if to_goal.length() > 0.5:
			var angle := (-global_basis.z).signed_angle_to(to_goal.normalized(), Vector3.UP)
			# A heavy body turns slowly, faster when walking than on the spot.
			var max_rate := turn_rate * (0.6 + 0.4 * clampf(loco.speed / walk_speed, 0.0, 1.0))
			turn = clampf(angle * 1.2, -max_rate, max_rate)
			target_speed *= clampf(1.1 - absf(angle), 0.15, 1.0)
	desired_speed = target_speed
	desired_turn = turn
	if debug_override == &"manual":
		desired_speed = debug_desired_speed
		desired_turn = debug_desired_turn
	_adjust_movement(it, delta)
	_shake = move_toward(_shake, _target_shake, delta / shake_ramp)
	loco.desired_velocity = -global_basis.z * desired_speed * (1.0 - _shake)
	loco.desired_turn_rate = desired_turn * (1.0 - _shake)
	loco.update_body(delta)
	global_transform = Transform3D(loco.body_basis(), loco.position)
	_shake_phase = fmod(_shake_phase + shake_frequency * TAU * delta, TAU * 8.0)
	Perf.end(&"locomotion", t0)


func _pose_bones(delta: float) -> void:
	var t0 := Perf.begin()
	_ik_usec = 0
	if delta > 0.0:
		loco.pelvis_drop = extra_pelvis_drop + 0.6 * _shake
		loco.bracing = _target_shake > 0.0
		loco.update_steps(delta, get_world_3d().direct_space_state)
	var inv := global_transform.affine_inverse()
	# Body: pelvis (hip centre) + tilt from the legs + shake (roll and a buck) + extras.
	var sh := _shake
	var roll := loco.body_roll + extra_roll + sin(_shake_phase) * 0.13 * sh
	var pitch := loco.body_pitch + extra_pitch + sin(_shake_phase * 2.0 + 0.6) * 0.05 * sh
	var body_basis := Basis.from_euler(Vector3(pitch, 0.0, roll))
	var hips_local := inv * loco.pelvis
	skeleton.set_bone_pose_rotation(_bone[&"body"], body_basis.get_rotation_quaternion())
	skeleton.set_bone_pose_position(_bone[&"body"], hips_local + body_basis * Vector3(0, body_above_hips, 0))
	_pose_head(delta)
	_pose_overrides(delta)
	_pose_legs(inv)
	Perf.end(&"locomotion", t0 + _ik_usec)
	Perf.end(&"ik", Time.get_ticks_usec() - _ik_usec)


func _pose_head(delta: float) -> void:
	if not _bone.has(&"neck"):
		return
	var target_look := Vector2.ZERO
	var watch := is_instance_valid(_look_target)
	if watch and _look_target.has_method(&"get_support_body") and owns_body(_look_target.get_support_body()):
		watch = false
	if watch:
		var head_pos := skeleton.global_transform * skeleton.get_bone_global_pose(_bone[&"head"]).origin
		var dir := global_basis.inverse() * (_look_target.global_position - head_pos)
		if dir.length() > 0.1:
			dir = dir.normalized()
			target_look = Vector2(clampf(atan2(-dir.x, -dir.z), -0.8, 0.8), clampf(atan2(dir.y, Vector2(dir.x, dir.z).length()), -0.5, 0.3))
	_look = _look.lerp(target_look, 1.0 - exp(-1.2 * delta)) if delta > 0.0 else target_look
	var toss := sin(_shake_phase * 1.5) * 0.2 * _shake
	skeleton.set_bone_pose_rotation(_bone[&"neck"], Quaternion.from_euler(Vector3(_look.y * 0.5 + toss, _look.x * 0.5, 0)))
	skeleton.set_bone_pose_rotation(_bone[&"head"], Quaternion.from_euler(Vector3(_look.y * 0.5, _look.x * 0.5, 0)))


func _pose_legs(inv: Transform3D) -> void:
	var t0 := Time.get_ticks_usec()
	var body_idx: int = _bone[&"body"]
	var body_xf := Transform3D(Basis(skeleton.get_bone_pose_rotation(body_idx)), skeleton.get_bone_pose_position(body_idx))
	for i in 4:
		var bones: Array = leg_bones[i]
		var leg := loco.legs[i]
		var up_idx: int = _bone[bones[0]]
		var parent := skeleton.get_bone_parent(up_idx)
		var parent_xf := body_xf if parent == body_idx else skeleton.get_bone_global_pose(parent)
		var hip := parent_xf * (_rest[bones[0]] as Vector3)
		var sole := inv * leg.foot_pos
		var nrm := (inv.basis * leg.foot_normal).normalized()
		var ankle := sole + nrm * ankle_height
		var fwd := inv.basis * Vector3(-sin(leg.foot_yaw), 0.0, -cos(leg.foot_yaw))
		var pole := (Vector3.FORWARD if i < 2 else Vector3.BACK)
		var r := TwoBoneIK.solve(hip, ankle, upper_len, lower_len, pole)
		var upper: Basis = r.upper
		var lower: Basis = r.lower
		skeleton.set_bone_pose_rotation(up_idx, (parent_xf.basis.orthonormalized().inverse() * upper).get_rotation_quaternion())
		skeleton.set_bone_pose_rotation(_bone[bones[1]], (upper.inverse() * lower).get_rotation_quaternion())
		var z := -(fwd - nrm * fwd.dot(nrm)).normalized()
		var foot_basis := Basis(nrm.cross(z), nrm, z)
		if leg.phase == LegState.Phase.SWING:
			foot_basis = foot_basis * Basis(Vector3.RIGHT, -swing_hoof_flip * sin(PI * clampf(leg.swing_t, 0.0, 1.0)))
		skeleton.set_bone_pose_rotation(_bone[bones[2]], (lower.inverse() * foot_basis).get_rotation_quaternion())
		leg.reach_error = r.error
	_ik_usec += Time.get_ticks_usec() - t0


func _post_sync(delta: float) -> void:
	_measure_feet(delta)


func _measure_feet(delta: float) -> void:
	if delta <= 0.0:
		return
	foot_stats.ticks += 1
	for i in 4:
		var leg := loco.legs[i]
		var sole := sole_world(i)
		var contact := leg.is_planted()
		leg.slip_speed = 0.0
		if contact and _contact_prev[i]:
			leg.slip_speed = Vector2(sole.x - _sole_prev[i].x, sole.z - _sole_prev[i].z).length() / delta
			foot_stats.slip_max = maxf(foot_stats.slip_max, leg.slip_speed)
			foot_stats.slip_sum += leg.slip_speed
			foot_stats.contact_ticks += 1
			foot_stats.reach_max = maxf(foot_stats.reach_max, leg.reach_error)
		_sole_prev[i] = sole
		_contact_prev[i] = contact


func locomotion_debug_text() -> String:
	var parts := PackedStringArray()
	for i in 4:
		var leg := loco.legs[i]
		parts.append("%s %s load %.2f support %.2f slip %.3f" % [String(LEG_NAMES[i]).replace("front_", "F").replace("rear_", "R"), "ST" if leg.is_planted() else "SW%.0f" % (leg.swing_t * 100.0), leg.load, leg.support, leg.slip_speed])
	return "legs: %s\nbody pitch %.2f roll %.2f  height %.2f  speed %.2f  turn %.2f  steps %d" % ["  ".join(parts), loco.body_pitch, loco.body_roll, loco.pelvis.y - global_position.y, loco.speed, loco.yaw_rate, loco.step_count]


func debug_text() -> String:
	return super() + "\n" + locomotion_debug_text()


# --- building --------------------------------------------------------------------------

func _build_body() -> void:
	var rig := _rig()
	leg_bones = rig.legs
	upper_len = rig.upper
	lower_len = rig.lower
	ankle_height = rig.ankle
	body_above_hips = rig.body_above_hips
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	add_child(skeleton)
	for b in rig.bones:
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
	for part in _parts():
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
		var col := _add_part(seg, part[1], part[2], part[3], materials[part[1]])
		if part.size() > 4:
			col.set_meta(&"surface", part[4])
	# Locomotion: four legs, hips from the rig (body space, relative to the hip centre).
	loco.nominal_hip_height = rig.hip_height
	loco.leg_length = upper_len + lower_len
	loco.ankle_height = ankle_height
	loco.cycle_steps = 4
	loco.max_swinging = 2
	loco.body_tilt = true
	loco.gait_sequence = [2, 0, 3, 1]   # rear left, front left, rear right, front right
	loco.sway = 0.25
	for i in 4:
		var up: Vector3 = _rest[leg_bones[i][0]]
		var hip := _hip_in_body(leg_bones[i][0])
		loco.add_leg(LEG_NAMES[i], Vector3(hip.x * 1.05, 0, hip.z), Vector3(hip.x, 0, hip.z))
	loco.reset(get_world_3d().direct_space_state, global_position, rotation.y)
	global_position = loco.position
	reset_foot_stats()
	debug_draw = QuadrupedDebugDraw.new()
	debug_draw.colossus = self
	add_child(debug_draw)


## Hip joint of an upper-leg bone in body-bone space (bones are unrotated at rest).
func _hip_in_body(upper: StringName) -> Vector3:
	var p: Vector3 = _rest[upper]
	var parent := skeleton.get_bone_parent(_bone[upper])
	while parent >= 0 and parent != _bone[&"body"]:
		p += _rest[skeleton.get_bone_name(parent)]
		parent = skeleton.get_bone_parent(parent)
	return p


func _add_part(seg: BodySegment, kind: Kind, size: Variant, center: Vector3, material: Material) -> CollisionShape3D:
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
	# What the part is made of (art layers reskin greybox parts by kind).
	mesh.set_meta(&"kind", kind)
	mesh.set_meta(&"part_size", size)
	seg.add_child(col)
	seg.add_child(mesh)
	return col


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
