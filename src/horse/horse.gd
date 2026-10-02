class_name Horse
extends CharacterBody3D
## Agro. A semi-autonomous animal, not a vehicle:
##
##   rider / AI / test -> HorseInputIntent -> HorseController (gait, mass, turn radius,
##   local avoidance) -> QuadrupedGait (four planted feet) -> body sway + two-bone leg IK
##   -> Skeleton3D -> visuals and the saddle the rider is anchored to.
##
## The body moves through move_and_slide (horizontal only), so even an ignored probe
## cannot carry it through a wall at full speed: a blocked body bleeds speed.
## Nothing here knows about keys or cameras; riders are any node implementing
## build_ride_intent(HorseInputIntent).

signal rider_changed(rider: Node3D)

enum Command { NONE, FOLLOW, COME, STOP }

## Rig: [bone, parent, rest offset] (horse-local, forward -Z, so the left side is -X).
const BONES := [
	[&"body", &"", Vector3(0, 1.27, 0)],
	[&"neck", &"body", Vector3(0, 0.22, -0.95)],
	[&"head", &"neck", Vector3(0, 0.9, 0)],
	[&"fl_up", &"body", Vector3(-0.24, -0.1, -0.78)],
	[&"fl_low", &"fl_up", Vector3(0, -0.62, 0)],
	[&"fl_hoof", &"fl_low", Vector3(0, -0.58, 0)],
	[&"fr_up", &"body", Vector3(0.24, -0.1, -0.78)],
	[&"fr_low", &"fr_up", Vector3(0, -0.62, 0)],
	[&"fr_hoof", &"fr_low", Vector3(0, -0.58, 0)],
	[&"rl_up", &"body", Vector3(-0.24, -0.1, 0.78)],
	[&"rl_low", &"rl_up", Vector3(0, -0.62, 0)],
	[&"rl_hoof", &"rl_low", Vector3(0, -0.58, 0)],
	[&"rr_up", &"body", Vector3(0.24, -0.1, 0.78)],
	[&"rr_low", &"rr_up", Vector3(0, -0.62, 0)],
	[&"rr_hoof", &"rr_low", Vector3(0, -0.58, 0)],
]
## Visual boxes: [bone, size, centre in bone space].
const PARTS := [
	[&"body", Vector3(0.7, 0.75, 2.1), Vector3(0, 0.05, 0)],
	[&"neck", Vector3(0.3, 0.95, 0.42), Vector3(0, 0.45, 0)],
	[&"head", Vector3(0.28, 0.32, 0.66), Vector3(0, 0.05, -0.25)],
	[&"fl_up", Vector3(0.17, 0.62, 0.22), Vector3(0, -0.31, 0)],
	[&"fl_low", Vector3(0.11, 0.58, 0.12), Vector3(0, -0.29, 0)],
	[&"fl_hoof", Vector3(0.15, 0.1, 0.2), Vector3(0, -0.05, -0.02)],
	[&"fr_up", Vector3(0.17, 0.62, 0.22), Vector3(0, -0.31, 0)],
	[&"fr_low", Vector3(0.11, 0.58, 0.12), Vector3(0, -0.29, 0)],
	[&"fr_hoof", Vector3(0.15, 0.1, 0.2), Vector3(0, -0.05, -0.02)],
	[&"rl_up", Vector3(0.2, 0.62, 0.3), Vector3(0, -0.31, 0)],
	[&"rl_low", Vector3(0.11, 0.58, 0.12), Vector3(0, -0.29, 0)],
	[&"rl_hoof", Vector3(0.15, 0.1, 0.2), Vector3(0, -0.05, -0.02)],
	[&"rr_up", Vector3(0.2, 0.62, 0.3), Vector3(0, -0.31, 0)],
	[&"rr_low", Vector3(0.11, 0.58, 0.12), Vector3(0, -0.29, 0)],
	[&"rr_hoof", Vector3(0.15, 0.1, 0.2), Vector3(0, -0.05, -0.02)],
]
const LEG_BONES := [[&"fl_up", &"fl_low", &"fl_hoof"], [&"fr_up", &"fr_low", &"fr_hoof"], [&"rl_up", &"rl_low", &"rl_hoof"], [&"rr_up", &"rr_low", &"rr_hoof"]]
const UPPER_LEN := 0.62
const LOWER_LEN := 0.58
const HOOF_HEIGHT := 0.1
## Body bone height above the ground at rest: hip joints at ~90% of the leg length, which
## leaves the feet about +-0.55 m of horizontal travel under the body.
const BODY_HEIGHT := 1.27
## Saddle in the body bone's space, and where a seated rider's centre is above it.
const SEAT_LOCAL := Vector3(0, 0.43, -0.05)
const RIDER_OFFSET := 0.55

var controller := HorseController.new()
var gait_planner := QuadrupedGait.new()
var skeleton: Skeleton3D
var intent := HorseInputIntent.new()
var current_rider: Node3D
var command := Command.NONE
var command_target: Node3D
var command_position := Vector3.ZERO
var debug_draw: HorseDebugDraw
## Accumulated foot statistics since reset_foot_stats() (tests / HUD).
var foot_stats := {}
## Ticks on which the body height had to be clamped hard to keep a planted hoof in reach.
var height_clamps := 0
var _bone := {}
var _rest := {}
var _visuals: Array = []        # [Node3D, bone idx]
var _exclude: Array[RID] = []
var _sole_prev: Array[Vector3] = []
var _contact_prev: Array[bool] = []
# Smoothed body pose (C2: everything that moves the saddle is spring-filtered).
var _height := 0.0
var _height_v := 0.0
var _tilt := Vector2.ZERO      # pitch, roll
var _tilt_v := Vector2.ZERO
var _bob := 0.0
var _bob_v := 0.0
var _gait_w: Array[float] = [1.0, 0.0, 0.0, 0.0]
var _neck := 0.0
var _neck_v := 0.0
var _head_yaw := 0.0
var _head_yaw_v := 0.0
var _prev_speed := 0.0
var _accel_s := 0.0
var _ai_waiting := false


func _ready() -> void:
	add_to_group(&"horses")
	collision_layer = Layers.HORSE
	collision_mask = Layers.WORLD | Layers.COLOSSUS
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	# Synced after the colossus (-10) and before players (0), so a rider reads this tick's saddle.
	process_physics_priority = -9
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 0.85, 2.3)
	col.shape = box
	col.position = Vector3(0, 1.3, 0)
	add_child(col)
	_exclude = [get_rid()]
	_build_rig()
	var hips: Array[Vector3] = []
	for i in 4:
		var up: Vector3 = _rest[LEG_BONES[i][0]]
		hips.append(Vector3(up.x, BODY_HEIGHT + up.y, up.z))
	gait_planner.setup(hips, UPPER_LEN + LOWER_LEN + HOOF_HEIGHT)
	teleport(global_position, rotation.y)
	debug_draw = HorseDebugDraw.new()
	debug_draw.horse = self
	add_child(debug_draw)


## Places the horse (feet re-planted on the ground there).
func teleport(pos: Vector3, yaw: float) -> void:
	controller.position = pos
	controller.yaw = yaw
	controller.speed = 0.0
	controller.speed_rate = 0.0
	controller.yaw_rate = 0.0
	controller.gait_level = 0
	controller.reset_heading()
	gait_planner.reset(get_world_3d().direct_space_state, pos, yaw)
	controller.position.y = gait_planner.ground_height()
	global_transform = Transform3D(controller.body_basis(), controller.position)
	_height = BODY_HEIGHT
	_height_v = 0.0
	_pose(0.0)
	reset_foot_stats()
	reset_physics_interpolation()
	for v in _visuals:
		(v[0] as Node3D).reset_physics_interpolation()


# --- riders and commands --------------------------------------------------------------

## Assigns (or clears with null) the rider. Any node with build_ride_intent() can ride.
func set_rider(rider: Node3D) -> void:
	if rider == current_rider:
		return
	current_rider = rider
	if rider:
		command = Command.NONE
	rider_changed.emit(rider)


func command_follow(target: Node3D) -> void:
	_ai_waiting = false
	command = Command.FOLLOW
	command_target = target


func command_come(target: Node3D) -> void:
	_ai_waiting = false
	command = Command.COME
	command_target = target


func command_stop() -> void:
	command = Command.STOP


## Saddle (rider centre) transform in world space, from this tick's body bone.
func saddle_transform() -> Transform3D:
	var body := skeleton.global_transform * skeleton.get_bone_global_pose(_bone[&"body"])
	return Transform3D(body.basis, body * SEAT_LOCAL + body.basis.y * RIDER_OFFSET)


## The body bone transform (riders store their local anchor against it).
func body_transform() -> Transform3D:
	return skeleton.global_transform * skeleton.get_bone_global_pose(_bone[&"body"])


func get_speed() -> float:
	return controller.speed


# --- simulation -----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var t0 := Perf.begin()
	var space := get_world_3d().direct_space_state
	intent.clear()
	if is_instance_valid(current_rider) and current_rider.has_method(&"build_ride_intent"):
		current_rider.build_ride_intent(intent)
	else:
		_ai_intent()

	controller.danger_zones.clear()
	for src in get_tree().get_nodes_in_group(&"danger_sources"):
		controller.danger_zones.append_array(src.get_danger_zones())
	var tc := Perf.begin()
	if Engine.get_physics_frames() % 30 == 0 or (controller.terrain_rids.is_empty() and Engine.get_physics_frames() % 30 == 1):
		_refresh_terrain()
	controller.update(intent, delta, space, _exclude)
	Perf.end(&"horse_controller", tc)

	# Move the body; walls stop it (and bleed the controller's speed).
	var from := global_position
	velocity = controller.forward() * controller.speed
	global_transform = Transform3D(controller.body_basis(), Vector3(from.x, controller.position.y, from.z))
	move_and_slide()
	var moved := global_position - from
	controller.report_actual_speed(moved.dot(controller.forward()) / delta)
	controller.position = Vector3(global_position.x, controller.position.y, global_position.z)

	var ts := Perf.begin()
	gait_planner.update(controller, delta, space)
	controller.position.y = lerpf(controller.position.y, gait_planner.ground_height(), 1.0 - exp(-8.0 * delta))
	global_position.y = controller.position.y
	Perf.end(&"horse_steps", ts)

	_pose(delta)
	_measure_feet(delta)
	Perf.end(&"horse", t0)


func _ai_intent() -> void:
	var target := command_position
	match command:
		Command.NONE, Command.STOP:
			intent.hold_speed = 0.0
			return
		Command.FOLLOW, Command.COME:
			if not is_instance_valid(command_target):
				command = Command.STOP
				return
			target = command_target.global_position
	var to := target - global_position
	to.y = 0.0
	var dist := to.length()
	# Stop near the target; a following horse only sets off again once it is clearly left
	# behind (no shuffling back and forth at the edge of the stop radius).
	var stop := 3.0 if command == Command.COME else 5.0
	var resume := stop if command == Command.COME else 8.0
	if dist <= stop or (_ai_waiting and dist <= resume):
		_ai_waiting = true
		intent.hold_speed = 0.0
		if command == Command.COME and controller.speed < 0.2:
			command = Command.STOP
		return
	_ai_waiting = false
	intent.direction = to.normalized()
	intent.drive = 1.0
	# Match a moving target's pace on top of the closing speed (follow keeps up), pick a
	# gait for the distance and that pace, and arrive softly.
	var target_speed := 0.0
	if command_target is CharacterBody3D:
		target_speed = maxf(0.0, (command_target as CharacterBody3D).velocity.dot(to / dist))
	var want: float = HorseController.GAIT_SPEED[1]
	if dist > 11.0 or target_speed > HorseController.GAIT_SPEED[2] - 1.0:
		want = HorseController.GAIT_SPEED[3]
	elif dist > 7.0 or target_speed > HorseController.GAIT_SPEED[1] - 0.5:
		want = HorseController.GAIT_SPEED[2]
	intent.hold_speed = minf(want, target_speed + sqrt(2.0 * 2.0 * maxf(0.0, dist - stop)) + 0.3)


## Body sway, neck/head and leg IK. Every term that moves the saddle is spring-smoothed.
func _pose(delta: float) -> void:
	var tik := Perf.begin()
	var dt := maxf(delta, 1e-4)
	var c := controller
	var legs := gait_planner.legs
	var inv := global_transform.affine_inverse()
	# Gait weights blend continuously between gaits (no pops when the gait changes).
	for g in 4:
		_gait_w[g] = move_toward(_gait_w[g], 1.0 if g == c.gait else 0.0, delta * 2.5)
	var clock := gait_planner.clock * TAU
	var bob: float = _gait_w[1] * 0.02 * cos(2.0 * clock) + _gait_w[2] * 0.045 * cos(2.0 * clock) + _gait_w[3] * 0.07 * cos(clock)
	var rock: float = _gait_w[3] * 0.05 * sin(clock)
	# Terrain: pitch from front vs rear feet, roll from left vs right.
	var front := (legs[0].foot_pos.y + legs[1].foot_pos.y) * 0.5
	var rear := (legs[2].foot_pos.y + legs[3].foot_pos.y) * 0.5
	var left := (legs[0].foot_pos.y + legs[2].foot_pos.y) * 0.5
	var right := (legs[1].foot_pos.y + legs[3].foot_pos.y) * 0.5
	var accel := (c.speed - _prev_speed) / dt
	_prev_speed = c.speed
	_accel_s = lerpf(_accel_s, accel, 1.0 - exp(-6.0 * dt))
	var pitch := atan2(front - rear, 1.56) + clampf(_accel_s * 0.015, -0.06, 0.06) + rock
	# Positive roll lifts the right (+X) side: the body follows the ground half way and leans
	# into a turn (a left turn, yaw_rate > 0, lowers the left side).
	var roll := atan2(right - left, 0.48) * 0.5 + clampf(c.speed * c.yaw_rate * 0.03, -0.12, 0.12)
	_spring2(Vector2(pitch, roll), 7.0, dt)
	# Height above the root: nominal, limited by what the legs reach (soft), plus the gait bob.
	var nominal: float = BODY_HEIGHT - 0.05 * _gait_w[3]
	var reach := (UPPER_LEN + LOWER_LEN) * 0.97
	var reach_hard := (UPPER_LEN + LOWER_LEN) * 0.995
	# The gait bob only rises as far as the legs allow (it never lifts a planted hoof).
	var max_h := nominal + bob
	var planted_h := INF
	var tilt := Basis.from_euler(Vector3(_tilt.x, 0.0, _tilt.y))
	var ahead := c.forward() * minf(c.speed * 0.06, 0.25)
	for i in 4:
		# Hip relative to the body bone, with the current pitch/roll (a pitched body lifts
		# the hind hips: that must be in the reach limit, or a planted hoof gets dragged).
		var hr: Vector3 = tilt * (_rest[LEG_BONES[i][0]] as Vector3)
		var hip := c.position + c.body_basis() * hr
		var leg := legs[i]
		if leg.is_planted():
			planted_h = minf(planted_h, _reach_height(hip, leg.foot_pos, leg.foot_normal, reach_hard))
			# Look a moment ahead: the hip moves on over the planted hoof, so lower in time.
			max_h = minf(max_h, _reach_height(hip + ahead, leg.foot_pos, leg.foot_normal, reach))
		max_h = minf(max_h, _reach_height(hip, leg.foot_pos, leg.foot_normal, reach))
		if not leg.is_planted():
			# Lower the body before a hoof lands on lower ground (a step down), not after:
			# the landing height counts more and more as the swing progresses (continuous).
			var t := leg.swing_t
			var s := t * t * (3.0 - 2.0 * t)
			var land := leg.target_pos.y + HOOF_HEIGHT - hip.y + sqrt(reach * reach - 0.35 * 0.35)
			max_h = minf(max_h, lerpf(nominal + 1.0, land, s))
	var k := 9.0
	_height_v += ((max_h - _height) * k * k - _height_v * 2.0 * k) * dt
	_height += _height_v * dt
	# Hard guarantee after the smoothing: a planted hoof is always within reach (otherwise
	# the IK would drag it: foot sliding). Only bites when the ground drops away quickly.
	if _height > planted_h:
		height_clamps += 1
		_height = planted_h
		_height_v = minf(_height_v, 0.0)
	var body_basis := Basis.from_euler(Vector3(_tilt.x, 0.0, _tilt.y))
	skeleton.set_bone_pose_position(_bone[&"body"], Vector3(0, _height, 0))
	skeleton.set_bone_pose_rotation(_bone[&"body"], body_basis.get_rotation_quaternion())
	# Neck and head: carriage lowers with speed, nods with the gait, looks where it is going.
	var neck_target := -0.75 - 0.25 * clampf(c.speed / 9.5, 0.0, 1.0) + 0.06 * sin(2.0 * clock) * (_gait_w[1] + _gait_w[3])
	_neck_v += ((neck_target - _neck) * 36.0 - _neck_v * 12.0) * dt
	_neck += _neck_v * dt
	var look := clampf(c.forward().signed_angle_to(c.steer_dir, Vector3.UP), -0.6, 0.6)
	_head_yaw_v += ((look - _head_yaw) * 25.0 - _head_yaw_v * 10.0) * dt
	_head_yaw += _head_yaw_v * dt
	skeleton.set_bone_pose_rotation(_bone[&"neck"], Quaternion.from_euler(Vector3(_neck - _tilt.x, _head_yaw * 0.5, 0)))
	skeleton.set_bone_pose_rotation(_bone[&"head"], Quaternion.from_euler(Vector3(-_neck * 0.9 + 0.2, _head_yaw * 0.5, 0)))
	# Legs: two-bone IK onto the planned feet. Fore knees point forward, hind hocks back.
	var body_xf := Transform3D(body_basis, Vector3(0, _height, 0))
	for i in 4:
		var bones: Array = LEG_BONES[i]
		var hip_local: Vector3 = body_xf * (_rest[bones[0]] as Vector3)
		var sole_local := inv * legs[i].foot_pos
		var n_local := (inv.basis * legs[i].foot_normal).normalized()
		var ankle := sole_local + n_local * HOOF_HEIGHT
		var pole := Vector3.FORWARD if i < 2 else Vector3.BACK
		var r := TwoBoneIK.solve(hip_local, ankle, UPPER_LEN, LOWER_LEN, pole)
		var upper: Basis = r.upper
		var lower: Basis = r.lower
		skeleton.set_bone_pose_rotation(_bone[bones[0]], (body_basis.inverse() * upper).get_rotation_quaternion())
		skeleton.set_bone_pose_rotation(_bone[bones[1]], (upper.inverse() * lower).get_rotation_quaternion())
		var fwd := inv.basis * Vector3(-sin(legs[i].foot_yaw), 0, -cos(legs[i].foot_yaw))
		var z := -(fwd - n_local * fwd.dot(n_local)).normalized()
		skeleton.set_bone_pose_rotation(_bone[bones[2]], (lower.inverse() * Basis(n_local.cross(z), n_local, z)).get_rotation_quaternion())
		legs[i].reach_error = r.error
	for v in _visuals:
		var node := v[0] as Node3D
		node.global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(v[1])
	Perf.end(&"horse_ik", tik)


## Body bone height (above the root) at which a hip still reaches the ankle above a sole
## (``leg`` = usable leg length). ``hip`` is the hip position for a body bone at the root
## (its y is the hip's offset from the bone).
func _reach_height(hip: Vector3, sole: Vector3, normal: Vector3, leg: float) -> float:
	var ankle := sole + normal * HOOF_HEIGHT
	var d := Vector2(ankle.x - hip.x, ankle.z - hip.z).length()
	return ankle.y - hip.y + sqrt(maxf(0.0, leg * leg - d * d))


func _spring2(target: Vector2, k: float, dt: float) -> void:
	_tilt_v += ((target - _tilt) * k * k - _tilt_v * 2.0 * k) * dt
	_tilt += _tilt_v * dt


# --- measurement / debug ----------------------------------------------------------------

func reset_foot_stats() -> void:
	foot_stats = {"slip_max": 0.0, "slip_sum": 0.0, "contact_ticks": 0, "reach_max": 0.0}
	_contact_prev = [false, false, false, false]
	_sole_prev = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]


func sole_world(i: int) -> Vector3:
	var hoof: StringName = LEG_BONES[i][2]
	return skeleton.global_transform * (skeleton.get_bone_global_pose(_bone[hoof]) * Vector3(0, -HOOF_HEIGHT, 0))


func _measure_feet(delta: float) -> void:
	for i in 4:
		var leg := gait_planner.legs[i]
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


func debug_text() -> String:
	var c := controller
	var lines := PackedStringArray()
	var rider: String = String(current_rider.name) if is_instance_valid(current_rider) else "none"
	lines.append("Agro: %s (level %d)  rider %s  command %s" % [HorseController.GAIT_NAMES[c.gait], c.gait_level, rider, Command.keys()[command]])
	lines.append("speed desired %.2f actual %.2f m/s  accel %.2f m/s2 | turn %.2f rad/s (max %.2f)  radius %s" % [c.desired_speed, c.speed, c.speed_rate, c.yaw_rate, c.max_turn_rate(c.speed), "%.1f m" % c.turn_radius() if c.turn_radius() < 1e5 else "-"])
	lines.append("danger %s  direction desired %.0f deg  actual %.0f deg  avoid %+.0f deg  obstacle %s %s" % [c.danger_response, rad_to_deg(atan2(-c.desired_dir.x, -c.desired_dir.z)), rad_to_deg(c.yaw), rad_to_deg(c.avoid_angle), c.obstacle, ("%.1f m" % c.obstacle_distance) if c.obstacle_distance < 1e5 else ""])
	var feet := PackedStringArray()
	for leg in gait_planner.legs:
		feet.append("%s %s slip %.3f" % [String(leg.name).substr(0, 1) + String(leg.name).split("_")[1].substr(0, 1), "ST" if leg.is_planted() else "SW%.0f" % (leg.swing_t * 100.0), leg.slip_speed])
	lines.append("feet: " + "  ".join(feet) + "  | rays %d" % (c.rays_this_tick + gait_planner.probes_this_tick))
	return "\n".join(lines)


func _refresh_terrain() -> void:
	var rids: Array[RID] = []
	for t in get_tree().get_nodes_in_group(&"walkable_terrain"):
		if t is CollisionObject3D:
			rids.append((t as CollisionObject3D).get_rid())
	controller.terrain_rids = rids
	controller.waters = WaterBody.all(get_tree())


func _build_rig() -> void:
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
	# Render only: a dark bay coat, black points (lower legs, mane, tail), dark hooves.
	var coat := ProcTextures.or_plain(&"coat", Color(0.13, 0.11, 0.1))
	var points := ProcTextures.or_plain(&"mane", Color(0.05, 0.04, 0.035))
	var hoof := ProcTextures.or_plain(&"hoof", Color(0.4, 0.38, 0.35))
	var nodes := {}
	for part in PARTS:
		var bone: StringName = part[0]
		var node: Node3D = nodes.get(bone)
		if node == null:
			node = Node3D.new()
			node.name = "Vis_" + bone
			node.top_level = true
			add_child(node)
			nodes[bone] = node
			_visuals.append([node, _bone[bone]])
		var mesh := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = part[1]
		mesh.mesh = bm
		mesh.position = part[2]
		var b := String(bone)
		mesh.material_override = hoof if b.ends_with("hoof") else (points if b.ends_with("low") else coat)
		node.add_child(mesh)
	# Saddle marker.
	var saddle := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.6, 0.08, 0.55)
	saddle.mesh = sm
	saddle.position = SEAT_LOCAL - Vector3(0, 0.02, 0)
	saddle.material_override = ProcTextures.or_plain(&"leather", Color(0.45, 0.25, 0.12))
	(nodes[&"body"] as Node3D).add_child(saddle)
	# Saddle blanket, mane and tail: visual only.
	var blanket := MeshInstance3D.new()
	var blm := BoxMesh.new()
	blm.size = Vector3(0.76, 0.34, 0.7)
	blanket.mesh = blm
	# Drapes over the back and down both flanks, under the saddle.
	blanket.position = SEAT_LOCAL - Vector3(0, 0.2, 0)
	blanket.material_override = ProcTextures.or_plain(&"blanket", Color(0.48, 0.16, 0.12))
	(nodes[&"body"] as Node3D).add_child(blanket)
	var mane := MeshInstance3D.new()
	var mm := BoxMesh.new()
	mm.size = Vector3(0.08, 0.9, 0.16)
	mane.mesh = mm
	mane.position = Vector3(0, 0.5, 0.2)
	mane.material_override = points
	(nodes[&"neck"] as Node3D).add_child(mane)
	var tail := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.12, 0.75, 0.12)
	tail.mesh = tm
	tail.position = Vector3(0, -0.2, 1.1)
	tail.rotation.x = 0.35
	tail.material_override = points
	(nodes[&"body"] as Node3D).add_child(tail)
