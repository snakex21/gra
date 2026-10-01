class_name GreyboxHumanoid
extends Colossus
## ~17 m greybox humanoid used to prove climbing on a moving body (Milestone 1) and
## heavy, foot-planted locomotion (Etap 3).
##
## The rig is data driven (BONES / PARTS tables) so proportions and climbable areas
## can be tuned without touching code. Colossus forward is -Z; "_l" bones are on +X.
##
## Pipeline per physics tick:
##   intent -> desired movement (velocity, turn rate) -> LocomotionController (body mass,
##   step planner, pelvis) -> legs: two-bone IK onto the planned feet -> skeleton.
## Leg modes (F4) for the A/B comparison; the body motion, upper body, shake and head are
## identical in all modes:
##   PROCEDURAL - planned steps + IK (default)
##   ANIM_IK    - classic looping walk cycle + per-tick foot IK onto the terrain
##   LEGACY_FK  - the old cycle without IK (reference only)
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
	[&"foot_l", Kind.STONE, Vector3(1.7, 0.7, 3.6), Vector3(0, -0.05, -0.85)],
]

const COLORS := {
	Kind.FUR: Color(0.36, 0.27, 0.19),
	Kind.STONE: Color(0.55, 0.55, 0.52),
	Kind.ARMOR: Color(0.30, 0.31, 0.33),
}

enum LocomotionMode { PROCEDURAL, ANIM_IK, LEGACY_FK }
const MODE_NAMES := ["procedural + IK", "animation + IK", "legacy FK (no IK)"]
const LEG_BONES := [[&"thigh_l", &"shin_l", &"foot_l"], [&"thigh_r", &"shin_r", &"foot_r"]]
const THIGH_LEN := 3.8
const SHIN_LEN := 3.4
const ANKLE_HEIGHT := 0.4
## Sole point in the foot bone's space (straight below the ankle).
const SOLE_LOCAL := Vector3(0, -0.4, 0)

## Mode new colossi start in (tests and the A/B benchmark switch it).
static var default_mode := LocomotionMode.PROCEDURAL

@export var walk_speed := 1.4       ## m/s
@export var turn_rate := 0.3        ## rad/s at walking speed
@export var stride := 4.6           ## legacy cycle: m per step
@export var shake_frequency := 1.4  ## Hz
@export var shake_ramp := 0.6       ## seconds to reach full shake
## Torso roll (rad) towards the shaken player's side while they grip / while they stand.
@export var shake_lean := 0.15
@export var shake_lean_standing := 0.45
@export var shake_lean_rate := 0.9  ## rad/s

var locomotion_mode: LocomotionMode = default_mode
var loco := LocomotionController.new()
## Debug override &"manual": desired movement set directly (tests, tuning).
var debug_desired_speed := 0.0
var debug_desired_turn := 0.0
## Last desired movement handed to the locomotion controller (debug HUD).
var desired_speed := 0.0
var desired_turn := 0.0
var debug_draw: LocomotionDebugDraw
## Extra pelvis drop (m) requested by a subclass (crouch for an attack, kneeling).
var extra_pelvis_drop := 0.0

# Upper body / shake state.
var _shake := 0.0
var _target_shake := 0.0
var _target_speed := 0.0
var _goal := Vector3.ZERO
var _has_goal := false
var _gait_phase := 0.0
var _shake_phase := 0.0
var _shake_lean := 0.0
var _rattle := 1.0
var _shake_target: Node3D
var _breath_phase := 0.0
var _look := Vector2.ZERO           # yaw, pitch (radians, colossus space)
var _look_target: Node3D
var _hip_drop := 0.0
var _bone := {}                     # name -> idx
var _rest := {}                     # name -> Vector3 offset

# Feet measurement (all modes): sole positions, contact and slip.
var _sole_prev: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _contact_prev: Array[bool] = [false, false]
var _ground_y: Array[float] = [0.0, 0.0]
var _contact: Array[bool] = [false, false]
var _clip_height: Array[float] = [0.0, 0.0]
## Accumulated foot statistics since the last reset_foot_stats() (tests / A/B).
var foot_stats := {}
var _ik_usec := 0
var _anim_pelvis := 0.0
var _anim_pelvis_v := 0.0
# Second-order smoothed pose drivers. Every term that rotates the body must be C2-smooth:
# with 6-10 m between a joint and the shoulders, a mere kink in an angle is felt as a
# jolt by a player standing or hanging up there.
var _lean_s := Vector3.ZERO
var _lean_v := Vector3.ZERO
var _antic_s := 0.0
var _antic_v := 0.0
var _hip_rt := Vector2.ZERO         # roll, turn
var _hip_rt_v := Vector2.ZERO


func get_focus_point() -> Vector3:
	return skeleton.global_transform * skeleton.get_bone_global_pose(_bone[&"chest"]).origin


func get_speed() -> float:
	return loco.speed


func get_yaw_rate() -> float:
	return loco.yaw_rate


func set_locomotion_mode(mode: LocomotionMode) -> void:
	if mode == locomotion_mode:
		return
	locomotion_mode = mode
	# Re-plant the feet where the current pose has them, so switching never teleports.
	for i in 2:
		var leg := loco.legs[i]
		leg.phase = LegState.Phase.STANCE
		leg.plant_pos = sole_world(i)
		leg.plant_yaw = loco.yaw
		leg.foot_pos = leg.plant_pos
		leg.foot_yaw = loco.yaw
	reset_foot_stats()


## Moves the colossus (feet re-planted on the ground there). Tools / test scenes only.
func teleport(pos: Vector3, yaw: float) -> void:
	loco.reset(get_world_3d().direct_space_state, pos, yaw)
	global_transform = Transform3D(loco.body_basis(), loco.position)
	_sync_segments()
	_sync_segments()
	reset_foot_stats()
	for s in segments:
		s.reset_physics_interpolation()


func cycle_locomotion_mode() -> void:
	set_locomotion_mode(((locomotion_mode + 1) % 3) as LocomotionMode)


## Sole (contact point under the ankle) of leg i in world space, as currently posed.
func sole_world(i: int) -> Vector3:
	var foot: StringName = LEG_BONES[i][2]
	return skeleton.global_transform * (skeleton.get_bone_global_pose(_bone[foot]) * SOLE_LOCAL)


func reset_foot_stats() -> void:
	foot_stats = {"slip_max": 0.0, "slip_sum": 0.0, "contact_ticks": 0, "reach_max": 0.0, "ticks": 0}
	# The next tick starts a new measurement (no slip across a teleport or a mode switch).
	_contact_prev = [false, false]


func _setup_locomotion() -> void:
	loco.nominal_hip_height = 7.4
	loco.leg_length = THIGH_LEN + SHIN_LEN
	loco.ankle_height = ANKLE_HEIGHT
	for i in 2:
		var side := 1.0 if i == 0 else -1.0
		loco.add_leg(LEG_BONES[i][0], Vector3(1.3 * side, 0, 0), Vector3(1.3 * side, 0, 0))
	loco.reset(get_world_3d().direct_space_state, global_position, rotation.y)
	global_position = loco.position
	reset_foot_stats()
	debug_draw = LocomotionDebugDraw.new()
	debug_draw.colossus = self
	add_child(debug_draw)


# --- intent -> desired movement -------------------------------------------------------

func _execute_intent(it: ColossusIntent, delta: float) -> void:
	var t0 := Perf.begin()
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
			_shake_target = it.target_player if it.target_player else _player_on_body()
	if _look_target == null:
		_look_target = _nearest_player()

	# Steering: desired turn rate towards the goal; sharp turns lower the desired speed
	# (down to turning almost on the spot, which the step planner handles with steps).
	var turn := 0.0
	if _has_goal:
		var to_goal := _flat(_goal - global_position)
		if to_goal.length() > 0.5:
			var angle := (-global_basis.z).signed_angle_to(to_goal.normalized(), Vector3.UP)
			var max_rate := turn_rate * (0.5 + 0.5 * clampf(loco.speed / walk_speed, 0.0, 1.0))
			turn = clampf(angle * 1.5, -max_rate, max_rate)
			_target_speed *= clampf(1.2 - absf(angle), 0.1, 1.0)
	desired_speed = _target_speed
	desired_turn = turn
	if debug_override == &"manual":
		desired_speed = debug_desired_speed
		desired_turn = debug_desired_turn
	_adjust_movement(it, delta)

	_shake = move_toward(_shake, _target_shake, delta / shake_ramp)
	# Shake style depends on HOW the target is attached: a climber gripping fur gets
	# rattled (stamina); a player standing on the body gets tipped off (balance).
	var lean_target := 0.0
	var rattle_target := 1.0
	if _target_shake > 0.0 and is_instance_valid(_shake_target):
		var standing: bool = _shake_target.has_method(&"is_climbing") and not _shake_target.is_climbing()
		var side := (global_transform.affine_inverse() * _shake_target.global_position).x
		var lean := shake_lean_standing if standing else shake_lean
		lean_target = -signf(side) * lean * clampf(absf(side) / 1.0, 0.0, 1.0)
		rattle_target = 0.7 if standing else 1.0
	_shake_lean = move_toward(_shake_lean, lean_target * _shake, delta * shake_lean_rate)
	_rattle = move_toward(_rattle, rattle_target, delta)

	# Body motion (mass) lives in the locomotion controller.
	loco.desired_velocity = -global_basis.z * desired_speed * (1.0 - _shake)
	loco.desired_turn_rate = desired_turn * (1.0 - _shake)
	loco.update_body(delta)
	global_transform = Transform3D(loco.body_basis(), loco.position)

	_gait_phase = fmod(_gait_phase + loco.speed / stride * PI * delta, TAU)
	_shake_phase = fmod(_shake_phase + shake_frequency * TAU * delta, TAU * 8.0)
	_breath_phase = fmod(_breath_phase + 0.25 * TAU * delta, TAU)
	Perf.end(&"locomotion", t0)


# --- posing ---------------------------------------------------------------------------

func _pose_bones(delta: float) -> void:
	var t0 := Perf.begin()
	var space := get_world_3d().direct_space_state
	var sh := _shake * _rattle
	_ik_usec = 0
	_update_pose_drivers(delta)
	match locomotion_mode:
		LocomotionMode.PROCEDURAL:
			loco.pelvis_drop = 0.55 * sh + extra_pelvis_drop
			loco.bracing = _target_shake > 0.0
			loco.update_steps(delta, space)
			_pose_hips_procedural()
			_pose_legs_ik()
		LocomotionMode.ANIM_IK:
			_follow_ground(space, delta)
			_pose_legacy_hips_and_legs(delta, sh)
			_correct_legs_ik(space)
		LocomotionMode.LEGACY_FK:
			_pose_legacy_hips_and_legs(delta, sh)
	_pose_upper_body(delta, sh)
	_pose_overrides(delta)
	Perf.end(&"locomotion", t0 + _ik_usec)
	Perf.end(&"ik", Time.get_ticks_usec() - _ik_usec)


func _update_pose_drivers(delta: float) -> void:
	var k := 3.0
	var a := loco.lean_accel
	_lean_v += ((a - _lean_s) * k * k - _lean_v * 2.0 * k) * delta
	_lean_s += _lean_v * delta
	var antic := clampf(loco.yaw_rate * 0.6, -0.25, 0.25)
	_antic_v += ((antic - _antic_s) * k * k - _antic_v * 2.0 * k) * delta
	_antic_s += _antic_v * delta
	# Pelvis drops a little on the swinging side and turns with the stepping leg.
	var rt := Vector2.ZERO
	if locomotion_mode == LocomotionMode.PROCEDURAL:
		for i in 2:
			var leg := loco.legs[i]
			if leg.phase == LegState.Phase.SWING:
				var side := 1.0 if i == 0 else -1.0
				var e := pow(sin(PI * leg.swing_t), 2.0)
				rt += Vector2(-side * 0.035 * e, side * 0.04 * e * clampf(loco.speed / walk_speed, 0.0, 1.0))
	var kh := 4.0
	_hip_rt_v += ((rt - _hip_rt) * kh * kh - _hip_rt_v * 2.0 * kh) * delta
	_hip_rt += _hip_rt_v * delta


func _post_sync(delta: float) -> void:
	_measure_feet(delta)


func _pose_hips_procedural() -> void:
	var inv := global_transform.affine_inverse()
	var pelvis_local := inv * loco.pelvis
	var lean := _lean_rotation(0.3)
	var hips_basis := lean * Basis.from_euler(Vector3(0, _hip_rt.y, _hip_rt.x))
	skeleton.set_bone_pose_rotation(_bone[&"hips"], hips_basis.get_rotation_quaternion())
	skeleton.set_bone_pose_position(_bone[&"hips"], pelvis_local + hips_basis * Vector3(0, -(_rest[&"thigh_l"] as Vector3).y, 0))


func _pose_legs_ik() -> void:
	var t0 := Time.get_ticks_usec()
	var inv := global_transform.affine_inverse()
	for i in 2:
		var leg := loco.legs[i]
		var fwd := Vector3(-sin(leg.foot_yaw), 0.0, -cos(leg.foot_yaw))
		_solve_leg(i, inv * leg.foot_pos, (inv.basis * leg.foot_normal).normalized(), inv.basis * fwd, -1.0)
		leg.reach_error = _last_reach_error
	_ik_usec += Time.get_ticks_usec() - t0


var _last_reach_error := 0.0


## Two-bone IK for leg i in skeleton space: sole at ``sole``, sole normal ``nrm``, foot
## pointing along ``fwd``. ``keep_foot`` >= 0 keeps the current foot pose rotation instead
## of aligning it to ``nrm`` (animation mode while the foot is in the air).
func _solve_leg(i: int, sole: Vector3, nrm: Vector3, fwd: Vector3, keep_foot: float) -> void:
	var bones: Array = LEG_BONES[i]
	var thigh: int = _bone[bones[0]]
	var shin: int = _bone[bones[1]]
	var foot: int = _bone[bones[2]]
	# hips is the root bone: its pose is its skeleton-space transform (no skeleton update).
	var hips_xf := Transform3D(Basis(skeleton.get_bone_pose_rotation(_bone[&"hips"])), skeleton.get_bone_pose_position(_bone[&"hips"]))
	var hips_basis := hips_xf.basis
	var hip := hips_xf * (_rest[bones[0]] as Vector3)
	var side := 1.0 if i == 0 else -1.0
	var pole := (fwd + Vector3(side * 0.15, 0, 0)).normalized()
	var ankle := sole + nrm * ANKLE_HEIGHT
	var r := TwoBoneIK.solve(hip, ankle, THIGH_LEN, SHIN_LEN, pole)
	var upper: Basis = r.upper
	var lower: Basis = r.lower
	skeleton.set_bone_pose_rotation(thigh, (hips_basis.inverse() * upper).get_rotation_quaternion())
	skeleton.set_bone_pose_rotation(shin, (upper.inverse() * lower).get_rotation_quaternion())
	if keep_foot < 0.0:
		var y := nrm
		var z := -(fwd - y * fwd.dot(y)).normalized()
		var foot_basis := Basis(y.cross(z), y, z)
		skeleton.set_bone_pose_rotation(foot, (lower.inverse() * foot_basis).get_rotation_quaternion())
	_last_reach_error = r.error


# --- mode B reference: classic looping cycle (+ IK correction in ANIM_IK) --------------

func _follow_ground(space: PhysicsDirectSpaceState3D, delta: float) -> void:
	var g := loco.probe_ground(space, global_position, global_position.y)
	loco.position.y = lerpf(loco.position.y, (g[0] as Vector3).y, 1.0 - exp(-5.0 * delta))
	global_position = loco.position


func _pose_legacy_hips_and_legs(delta: float, sh: float) -> void:
	var w := clampf(loco.speed / walk_speed, 0.0, 1.0)
	var s := sin(_gait_phase)
	var c := cos(_gait_phase)
	var breath := sin(_breath_phase)
	var thigh_l := s * 0.33 * w + 0.18 * sh
	var thigh_r := -s * 0.33 * w + 0.18 * sh
	var knee_l := -maxf(0.0, c) * 0.55 * w - 0.3 * sh
	var knee_r := -maxf(0.0, -c) * 0.55 * w - 0.3 * sh
	_rot(&"thigh_l", Vector3(thigh_l, 0, 0))
	_rot(&"thigh_r", Vector3(thigh_r, 0, 0))
	_rot(&"shin_l", Vector3(knee_l, 0, 0))
	_rot(&"shin_r", Vector3(knee_r, 0, 0))
	_rot(&"foot_l", Vector3(-(thigh_l + knee_l), 0, 0))
	_rot(&"foot_r", Vector3(-(thigh_r + knee_r), 0, 0))
	var target_drop := 0.42 * s * s * w + 0.55 * sh
	_hip_drop = lerpf(_hip_drop, target_drop, 1.0 - exp(-10.0 * delta))
	skeleton.set_bone_pose_position(_bone[&"hips"], _rest[&"hips"] + Vector3(0, -_hip_drop + breath * 0.03, 0))
	skeleton.set_bone_pose_rotation(_bone[&"hips"], (_lean_rotation(0.3) * Basis.from_euler(Vector3(0, s * 0.05 * w, s * 0.035 * w))).get_rotation_quaternion())


## Classic foot IK on top of an animation: keep the clip's horizontal foot motion, move the
## foot by the terrain height under it, align planted feet to the ground, and lower the
## pelvis so the lower foot can reach. Two ground rays per tick (plus one for the body).
func _correct_legs_ik(space: PhysicsDirectSpaceState3D) -> void:
	var t0 := Time.get_ticks_usec()
	var inv := global_transform.affine_inverse()
	var targets := []
	var lowest := 0.0
	for i in 2:
		var ankle_local := skeleton.get_bone_global_pose(_bone[LEG_BONES[i][2]]).origin
		var clip_h := ankle_local.y - ANKLE_HEIGHT
		var world := global_transform * ankle_local
		var g := loco.probe_ground(space, world, global_position.y)
		var ground_local := inv * (g[0] as Vector3)
		_ground_y[i] = (g[0] as Vector3).y
		_clip_height[i] = clip_h
		lowest = minf(lowest, ground_local.y)
		targets.append([Vector3(ankle_local.x, ground_local.y + maxf(clip_h, 0.0), ankle_local.z), (inv.basis * (g[1] as Vector3)).normalized()])
	# Pelvis offset smoothed (standard practice), otherwise terrain edges pop the body.
	var dt := get_physics_process_delta_time()
	_anim_pelvis_v += ((lowest - _anim_pelvis) * 9.0 - _anim_pelvis_v * 6.0) * dt
	_anim_pelvis += _anim_pelvis_v * dt
	var hips := skeleton.get_bone_pose_position(_bone[&"hips"])
	skeleton.set_bone_pose_position(_bone[&"hips"], hips + Vector3(0, _anim_pelvis, 0))
	for i in 2:
		var contact := _clip_stance(i)
		_solve_leg(i, targets[i][0], targets[i][1], Vector3.FORWARD, -1.0 if contact else 1.0)
		loco.legs[i].reach_error = _last_reach_error
	_ik_usec += Time.get_ticks_usec() - t0


# --- upper body (shared by all modes) -------------------------------------------------

func _pose_upper_body(delta: float, sh: float) -> void:
	var breath := sin(_breath_phase)
	var sp := _shake_phase
	var w := clampf(loco.speed / walk_speed, 0.0, 1.0)
	# Arm swing / torso counter-rotation follow the feet (which foot is ahead).
	var swing := 0.0
	if locomotion_mode == LocomotionMode.PROCEDURAL:
		var fwd := -global_basis.z
		# tanh, not clamp: a clamp's kink at long strides is a jolt at the shoulders.
		swing = tanh((loco.legs[0].foot_pos - loco.legs[1].foot_pos).dot(fwd) / 2.5)
	else:
		swing = sin(_gait_phase) * w
	# Upper body starts turns early and leans into acceleration.
	var anticipate := _antic_s
	var lean := _lean_rotation(0.35)
	var spine := lean * Basis.from_euler(Vector3(breath * 0.015 + 0.1 * sh, -swing * 0.04 + anticipate * 0.4 + sin(sp * 0.5 + 1.0) * 0.07 * sh, sin(sp) * 0.09 * sh + _shake_lean * 0.5))
	skeleton.set_bone_pose_rotation(_bone[&"spine"], spine.get_rotation_quaternion())
	var chest := lean * Basis.from_euler(Vector3(breath * 0.02, sin(sp * 0.5) * 0.05 * sh + anticipate * 0.6, sin(sp + 0.7) * 0.11 * sh + _shake_lean * 0.5))
	skeleton.set_bone_pose_rotation(_bone[&"chest"], chest.get_rotation_quaternion())

	var arm := -swing * 0.22
	_rot(&"upper_arm_l", Vector3(arm + sin(sp + 2.0) * 0.25 * sh, 0, 0.08 + 0.55 * sh + sin(sp) * 0.2 * sh))
	_rot(&"upper_arm_r", Vector3(-arm + sin(sp + 0.5) * 0.25 * sh, 0, -0.08 - 0.55 * sh - sin(sp + 1.3) * 0.2 * sh))
	_rot(&"forearm_l", Vector3(-0.25 - 0.1 * w - 0.35 * sh, 0, 0))
	_rot(&"forearm_r", Vector3(-0.25 - 0.1 * w - 0.35 * sh, 0, 0))
	_rot(&"hand_l", Vector3.ZERO)
	_rot(&"hand_r", Vector3.ZERO)

	# Head: track the look target with soft limits, lead turns, split over neck and head.
	var target_look := Vector2(anticipate * 1.5, 0.0)
	# A player on the body is felt, not watched: staring at its own shoulder would sweep
	# the head through the space the player stands in.
	var watch := is_instance_valid(_look_target)
	if watch and _look_target.has_method(&"get_support_body") and owns_body(_look_target.get_support_body()):
		watch = false
	if watch:
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


## Rotation that tilts "up" towards the body's acceleration (a share of the full lean).
func _lean_rotation(share: float) -> Basis:
	var a := global_basis.inverse() * _lean_s
	a.y = 0.0
	if a.length() < 1e-4:
		return Basis.IDENTITY
	var angle := atan(a.length() / 9.8) * 2.0 * share
	return Basis(Vector3.UP.cross(a.normalized()), angle)


# --- measurement ----------------------------------------------------------------------

## Foot contact and slip, measured on the final pose in every mode (the A/B metric).
func _measure_feet(delta: float) -> void:
	foot_stats.ticks += 1
	for i in 2:
		var sole := sole_world(i)
		var leg := loco.legs[i]
		var contact := false
		match locomotion_mode:
			LocomotionMode.PROCEDURAL:
				contact = leg.is_planted()
				_ground_y[i] = leg.plant_pos.y
			LocomotionMode.ANIM_IK:
				contact = _clip_stance(i)
			LocomotionMode.LEGACY_FK:
				_ground_y[i] = global_position.y
				contact = _clip_stance(i)
		_contact[i] = contact
		leg.slip_speed = 0.0
		if contact and _contact_prev[i]:
			leg.slip_speed = Vector2(sole.x - _sole_prev[i].x, sole.z - _sole_prev[i].z).length() / delta
			foot_stats.slip_max = maxf(foot_stats.slip_max, leg.slip_speed)
			foot_stats.slip_sum += leg.slip_speed
			foot_stats.contact_ticks += 1
		foot_stats.reach_max = maxf(foot_stats.reach_max, leg.reach_error if contact else 0.0)
		_sole_prev[i] = sole
		_contact_prev[i] = contact


## Stance phase of the looping cycle (the clip's "foot plant" markers): the leg moves
## backwards (thigh angle decreasing) and its knee is straight.
func _clip_stance(i: int) -> bool:
	var c := cos(_gait_phase)
	if loco.speed < 0.05:
		return true
	return c <= 0.0 if i == 0 else c >= 0.0


func foot_in_contact(i: int) -> bool:
	return _contact[i]


func locomotion_debug_text() -> String:
	var l := loco.legs[0]
	var r := loco.legs[1]
	var lines := PackedStringArray()
	lines.append("locomotion: %s   support %s   steps %d" % [MODE_NAMES[locomotion_mode], loco.support_state, loco.step_count])
	lines.append("desired v %.2f m/s  turn %.2f rad/s | actual v %.2f m/s  turn %.2f rad/s" % [desired_speed, desired_turn, loco.speed, loco.yaw_rate])
	lines.append("L %s slip %.3f m/s reach err %.3f | R %s slip %.3f m/s reach err %.3f" % [
		l.phase_name() if locomotion_mode == LocomotionMode.PROCEDURAL else ("contact" if _contact[0] else "air"), l.slip_speed, l.reach_error,
		r.phase_name() if locomotion_mode == LocomotionMode.PROCEDURAL else ("contact" if _contact[1] else "air"), r.slip_speed, r.reach_error])
	var swing := l if l.phase == LegState.Phase.SWING else r
	lines.append("foot target %s   COM-support %.2f m" % [str(swing.target_pos.snapped(Vector3.ONE * 0.01)), _flat(loco.com - loco.support_center).length()])
	return "\n".join(lines)


func debug_text() -> String:
	return super() + "\nspeed %.2f  shake %.2f  look %.2f/%.2f\n%s" % [loco.speed, _shake, _look.x, _look.y, locomotion_debug_text()]


func _rot(bone: StringName, euler: Vector3) -> void:
	skeleton.set_bone_pose_rotation(_bone[bone], Quaternion.from_euler(euler))


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _player_on_body() -> Node3D:
	for p in get_tree().get_nodes_in_group(&"players"):
		if p.has_method(&"get_support_body") and owns_body(p.get_support_body()):
			return p
	return null


func _nearest_player() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group(&"players"):
		var d: float = p.global_position.distance_squared_to(global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


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
		var col := _add_part(seg, part[1], part[2], part[3], materials[part[1]])
		# Optional 5th column: a surface tag for gameplay / debug (e.g. &"rest").
		if part.size() > 4:
			col.set_meta(&"surface", part[4])
	_setup_locomotion()


## Hook for subclasses: change desired_speed / desired_turn / _target_shake after the
## intent was mapped to movement (e.g. stand still while an attack winds up).
func _adjust_movement(_it: ColossusIntent, _delta: float) -> void:
	pass


## Hook for subclasses: extra bone poses after the upper body (attacks, gestures).
func _pose_overrides(_delta: float) -> void:
	pass


## Body parts table (see PARTS); subclasses can return their own.
func _parts() -> Array:
	return PARTS


func _all_parts() -> Array:
	var out := []
	for p in _parts():
		out.append(p)
		var bone := String(p[0])
		if bone.ends_with("_l"):
			var center: Vector3 = p[3]
			var mirrored := [StringName(bone.trim_suffix("_l") + "_r"), p[1], p[2], Vector3(-center.x, center.y, center.z)]
			mirrored.append_array(p.slice(4))
			out.append(mirrored)
	return out


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
