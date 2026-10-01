class_name LocomotionController
extends RefCounted
## Continuous locomotion for a legged colossus.
##
##   desired_velocity / desired_turn_rate        (from the colossus, derived from its intent)
##     -> body:    jerk-limited speed, rate-limited yaw            (mass)
##     -> steps:   per-leg STANCE/SWING, need-based step timing, one ground probe per step
##     -> pelvis:  weight shift over the support, height from leg reach, lean from acceleration
##
## The controller knows nothing about bones (the rig maps its outputs to a skeleton with IK)
## and nothing about intents. It works for any number of legs; ``max_swinging`` limits how
## many swing at once (1 for a biped walk). Everything advances only in fixed physics ticks.

# --- body (mass) ----------------------------------------------------------------------
var max_accel := 0.5        ## m/s^2
var max_decel := 1.25       ## m/s^2
var max_jerk := 1.5         ## m/s^3
var max_turn_accel := 0.25  ## rad/s^2

# --- gait -----------------------------------------------------------------------------
var step_length_base := 1.4
var step_length_per_speed := 0.8
var max_step_length := 3.0
var min_step_period := 1.1
var idle_step_period := 1.8
## Fraction of a step period spent swinging; the rest is double support (weight transfer).
var swing_fraction := 0.6
var lift_height := 0.8
## A stopped (or slowly turning) body only corrects feet that are further off than this.
var settle_distance := 0.35
## While moving, a foot steps when its plan error exceeds this.
var moving_step_distance := 0.05
## Metres of error per radian of foot yaw error.
var yaw_error_weight := 1.5
var max_swinging := 1
var ground_mask := Layers.WORLD

# --- pelvis ---------------------------------------------------------------------------
var nominal_hip_height := 7.2   ## hip joint height above the ground, knees slightly bent
var leg_length := 7.2           ## upper + lower leg
var ankle_height := 0.4         ## ankle joint above the sole
## How far the pelvis moves over the supporting foot (0 = never, 1 = fully).
var sway := 0.35
var pelvis_stiffness := 4.5
## Extra pelvis drop (m), e.g. bracing while shaking.
var pelvis_drop := 0.0

# --- state ----------------------------------------------------------------------------
var position := Vector3.ZERO    ## body ground reference point (the colossus root)
var yaw := 0.0
var speed := 0.0
var speed_rate := 0.0
var yaw_rate := 0.0
var time := 0.0
var legs: Array[LegState] = []
var last_step_leg := -1
var last_touchdown := -999.0
var step_count := 0

# --- inputs (set every tick) ----------------------------------------------------------
## Desired horizontal velocity; its length is the desired forward speed.
var desired_velocity := Vector3.ZERO
var desired_turn_rate := 0.0

# --- outputs --------------------------------------------------------------------------
## Hip-joint centre (between the hip joints) in world space.
var pelvis := Vector3.ZERO
var pelvis_velocity := Vector3.ZERO
## Horizontal acceleration the upper body leans into (world, m/s^2).
var lean_accel := Vector3.ZERO
## Approximate centre of mass and its ground projection.
var com := Vector3.ZERO
var support_center := Vector3.ZERO
var support_state := "double"
var step_period := 1.8
var probes_this_tick := 0

var _initialised := false
var _prev_speed := 0.0


func add_leg(leg_name: StringName, foot_nominal: Vector3, hip_local: Vector3) -> LegState:
	var leg := LegState.new()
	leg.name = leg_name
	leg.foot_nominal = foot_nominal
	leg.hip_local = hip_local
	legs.append(leg)
	return leg


func forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func body_basis() -> Basis:
	return Basis(Vector3.UP, yaw)


## Plants every foot at its nominal place under the body (start of the simulation).
func reset(space: PhysicsDirectSpaceState3D, p_position: Vector3, p_yaw: float) -> void:
	position = p_position
	yaw = p_yaw
	speed = 0.0
	speed_rate = 0.0
	yaw_rate = 0.0
	var ys := 0.0
	for leg in legs:
		var g := probe_ground(space, position + body_basis() * leg.foot_nominal, position.y)
		leg.phase = LegState.Phase.STANCE
		leg.plant_pos = g[0]
		leg.plant_normal = g[1]
		leg.plant_yaw = yaw
		leg.foot_pos = leg.plant_pos
		leg.foot_normal = leg.plant_normal
		leg.foot_yaw = yaw
		ys += leg.plant_pos.y
	position.y = ys / maxf(1.0, legs.size())
	pelvis = position + Vector3.UP * nominal_hip_height
	pelvis_velocity = Vector3.ZERO
	_initialised = true


## Body motion: the colossus' mass. Call once per physics tick before update_steps().
func update_body(delta: float) -> void:
	time += delta
	var desired_speed := desired_velocity.length()
	var desired_accel := clampf((desired_speed - speed) * 1.5, -max_decel, max_accel)
	speed_rate = move_toward(speed_rate, desired_accel, max_jerk * delta)
	speed = maxf(0.0, speed + speed_rate * delta)
	yaw_rate = move_toward(yaw_rate, desired_turn_rate, max_turn_accel * delta)
	yaw = wrapf(yaw + yaw_rate * delta, -PI, PI)
	position += forward() * speed * delta


## Steps, pelvis and support. Call after update_body() each physics tick.
func update_steps(delta: float, space: PhysicsDirectSpaceState3D) -> void:
	probes_this_tick = 0
	var step_length := clampf(step_length_base + step_length_per_speed * speed, step_length_base, max_step_length)
	step_period = clampf(step_length / maxf(speed, 0.01), min_step_period, idle_step_period)
	var swing_time := swing_fraction * step_period
	var double_support := (1.0 - swing_fraction) * step_period

	# 1) Advance swinging legs.
	var swinging := 0
	for i in legs.size():
		var leg := legs[i]
		if leg.phase != LegState.Phase.SWING:
			continue
		leg.swing_t = minf(1.0, leg.swing_t + delta / leg.swing_duration)
		if not leg.replanned and leg.swing_t >= 0.5:
			# One mid-swing re-plan if the body changed its mind (speed / turn).
			leg.replanned = true
			var goal := target_for(leg, (1.0 - leg.swing_t) * leg.swing_duration)
			if _flat(goal - leg.target_goal).length() > 0.3:
				var g := probe_ground(space, goal, leg.target_goal.y)
				leg.target_goal = g[0]
				leg.target_normal = g[1]
		if leg.swing_t < 0.85:
			leg.target_pos = leg.target_pos.lerp(leg.target_goal, 1.0 - exp(-6.0 * delta))
		_update_swing_pose(leg)
		if leg.swing_t >= 1.0:
			leg.phase = LegState.Phase.STANCE
			leg.plant_pos = leg.target_pos
			leg.plant_normal = leg.target_normal
			leg.plant_yaw = leg.target_yaw
			leg.touchdown_time = time
			last_touchdown = time
			_set_foot(leg, leg.plant_pos, leg.plant_normal, leg.plant_yaw)
		else:
			swinging += 1

	# 2) Start a new step when allowed and needed.
	var moving := speed > 0.05 or absf(yaw_rate) > 0.03 or desired_velocity.length() > 0.05
	if swinging < max_swinging and time - last_touchdown >= double_support * (1.0 if moving else 0.5):
		var best := -1
		var best_err := 0.0
		for i in legs.size():
			var leg := legs[i]
			if leg.phase != LegState.Phase.STANCE:
				continue
			var err := plan_error(leg, swing_time)
			# Alternate legs while walking.
			if moving and i == last_step_leg and legs.size() > 1:
				err *= 0.3
			if err > best_err:
				best_err = err
				best = i
		var threshold := moving_step_distance if moving else settle_distance
		if best >= 0 and best_err > threshold:
			_start_swing(best, swing_time, space)

	# 3) Ground reference follows the planted feet.
	var ground_y := 0.0
	var n := 0
	for leg in legs:
		ground_y += leg.plant_pos.y if leg.is_planted() else leg.lift_pos.y
		n += 1
	if n > 0:
		position.y = lerpf(position.y, ground_y / n, 1.0 - exp(-3.0 * delta))

	_update_pelvis(delta, double_support)


## Where a leg should land if it started a step now, given ``t_ahead`` until touchdown.
func target_for(leg: LegState, t_ahead: float) -> Vector3:
	var yaw_p := yaw + yaw_rate * t_ahead
	var fwd_now := forward()
	var fwd_p := Vector3(-sin(yaw_p), 0.0, -cos(yaw_p))
	var body_p := position + (fwd_now + fwd_p) * 0.5 * speed * t_ahead
	# Land ahead by half of the distance the body covers while this foot stands, so the
	# body passes over the foot in the middle of its stance.
	var stance_time := step_period * (2.0 - swing_fraction)
	var lead := fwd_p * speed * stance_time * 0.5
	return body_p + Basis(Vector3.UP, yaw_p) * leg.foot_nominal + lead


func plan_error(leg: LegState, t_ahead: float) -> float:
	var t := target_for(leg, t_ahead)
	var yaw_p := yaw + yaw_rate * t_ahead
	return _flat(t - leg.plant_pos).length() + yaw_error_weight * absf(angle_difference(leg.plant_yaw, yaw_p))


## One ray straight down. Returns [point, normal].
func probe_ground(space: PhysicsDirectSpaceState3D, at: Vector3, ref_y: float) -> Array:
	probes_this_tick += 1
	var hit := ClimbQuery.ray(space, Vector3(at.x, ref_y + 8.0, at.z), Vector3(at.x, ref_y - 12.0, at.z), [], ground_mask)
	if hit.is_empty():
		return [Vector3(at.x, ref_y, at.z), Vector3.UP]
	return [hit.position, hit.normal]


func swinging_count() -> int:
	var c := 0
	for leg in legs:
		if leg.phase == LegState.Phase.SWING:
			c += 1
	return c


# --- internals ------------------------------------------------------------------------

func _start_swing(i: int, swing_time: float, space: PhysicsDirectSpaceState3D) -> void:
	var leg := legs[i]
	leg.phase = LegState.Phase.SWING
	leg.swing_t = 0.0
	leg.swing_duration = maxf(0.6, swing_time)
	leg.replanned = false
	leg.lift_pos = leg.plant_pos
	leg.lift_normal = leg.plant_normal
	leg.lift_yaw = leg.plant_yaw
	var goal := target_for(leg, leg.swing_duration)
	var g := probe_ground(space, goal, leg.plant_pos.y)
	leg.target_goal = g[0]
	leg.target_pos = g[0]
	leg.target_normal = g[1]
	leg.target_yaw = yaw + yaw_rate * leg.swing_duration
	last_step_leg = i
	step_count += 1


## Smooth arc: horizontal smootherstep (zero velocity and acceleration at both ends) and a
## sin^2 lift (zero vertical velocity at lift-off and touchdown), so anything attached to
## the foot (a climbing player) never gets a velocity jump.
func _update_swing_pose(leg: LegState) -> void:
	var t := leg.swing_t
	var s := t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
	var p := leg.lift_pos.lerp(leg.target_pos, s)
	var dist := _flat(leg.target_pos - leg.lift_pos).length()
	var clearance := lift_height * clampf(dist / 1.5, 0.35, 1.0) + maxf(0.0, leg.target_pos.y - leg.lift_pos.y) * 0.6
	p.y += clearance * pow(sin(PI * t), 2.0)
	_set_foot(leg, p, leg.lift_normal.slerp(leg.target_normal, s).normalized(), lerp_angle(leg.lift_yaw, leg.target_yaw, s))


func _set_foot(leg: LegState, p: Vector3, nrm: Vector3, foot_yaw: float) -> void:
	leg.foot_pos = p
	leg.foot_normal = nrm
	leg.foot_yaw = foot_yaw


func _update_pelvis(delta: float, double_support: float) -> void:
	var b := body_basis()
	var fwd := forward()
	var moving := speed > 0.05 or absf(yaw_rate) > 0.03
	# Weight (load) per leg changes continuously: a swinging leg carries nothing; in double
	# support the weight moves onto the leg that stays before the other one lifts; standing
	# still the weight is shared. The support centre is the load-weighted foot position, so
	# it never jumps when a foot lifts or lands.
	var rate := delta / maxf(double_support, 0.2)
	var next := 1 - last_step_leg if last_step_leg >= 0 else 0
	for i in legs.size():
		var leg := legs[i]
		var target := 1.0 / legs.size()
		if leg.phase == LegState.Phase.SWING:
			target = 0.0
		elif moving and legs.size() == 2 and swinging_count() == 0:
			target = 0.0 if i == next else 1.0
		elif swinging_count() > 0:
			target = 1.0
		leg.load = move_toward(leg.load, target, rate)
	var total := 0.0
	support_center = Vector3.ZERO
	for leg in legs:
		var p := leg.plant_pos if leg.is_planted() else leg.foot_pos
		support_center += p * leg.load
		total += leg.load
	support_center = support_center / total if total > 1e-4 else position
	support_state = "double"
	for leg in legs:
		if leg.phase == LegState.Phase.SWING:
			support_state = "single " + String(legs[1 - legs.find(leg)].name) if legs.size() == 2 else "partial"

	# Horizontal target: body point shifted sideways over the support, slightly ahead when moving.
	var to_support := _flat(support_center - position)
	var lateral := b.x * to_support.dot(b.x) * sway
	var accel := speed_rate
	_prev_speed = speed
	var ahead := fwd * (speed * 0.12 + clampf(accel, -1.0, 1.0) * 0.3)
	var target := position + lateral + ahead
	# Height: nominal, but never higher than the legs can reach. A swinging leg's landing
	# spot is phased in over its swing, so the constraint changes continuously.
	var h := position.y + nominal_hip_height - pelvis_drop
	for leg in legs:
		var foot := leg.plant_pos
		var weight := 1.0
		if leg.phase == LegState.Phase.SWING:
			foot = leg.target_pos
			weight = smoothstep(0.3, 1.0, leg.swing_t)
		var hip := target + b * Vector3(leg.hip_local.x, 0.0, leg.hip_local.z)
		var d := _flat(foot - hip).length()
		var reach := leg_length * 0.97
		var max_h := foot.y + ankle_height + sqrt(maxf(0.0, reach * reach - d * d))
		h = minf(h, lerpf(h, max_h, weight))
	target.y = h
	# Critically damped spring: weight, not snapping.
	var k := pelvis_stiffness
	var acc := (target - pelvis) * k * k - pelvis_velocity * 2.0 * k
	pelvis_velocity += acc * delta
	pelvis += pelvis_velocity * delta
	# The body leans into its acceleration (forward/back, into turns, over the support).
	var centripetal := Vector3.UP.cross(fwd) * speed * yaw_rate
	lean_accel = fwd * clampf(accel, -1.5, 1.5) + centripetal + _flat(acc) * 0.1
	var up := (Vector3.UP + lean_accel / 9.8 * 2.0).normalized()
	com = pelvis + up * 3.5
	if not _initialised:
		pelvis = target


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
