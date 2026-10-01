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
## Step slots per gait cycle: 2 for a biped (left, right), 4 for a four-legged walk. Each
## foot steps once per cycle, so the period between steps shrinks with more legs.
var cycle_steps := 2
var lift_height := 0.8
## Peak horizontal acceleration of a swinging foot (m/s^2).
var max_foot_accel := 16.0
## A stopped (or slowly turning) body only corrects feet that are further off than this.
var settle_distance := 0.35
## While moving, a foot steps when its plan error exceeds this.
var moving_step_distance := 0.05
## Metres of error per radian of foot yaw error.
var yaw_error_weight := 1.5
var max_swinging := 1
var ground_mask := Layers.WORLD
## Optional stepping order while moving (leg indices), e.g. a four-legged walk
## [rear_left, front_left, rear_right, front_right]. Empty = pick by need (bipeds).
var gait_sequence: Array[int] = []

# --- pelvis ---------------------------------------------------------------------------
var nominal_hip_height := 7.2   ## hip joint height above the ground, knees slightly bent
var leg_length := 7.2           ## upper + lower leg
var ankle_height := 0.4         ## ankle joint above the sole
## How far the pelvis moves over the supporting foot (0 = never, 1 = fully).
var sway := 0.35
var pelvis_stiffness := 4.5
var pelvis_stiffness_vertical := 3.0
## Extra pelvis drop (m), e.g. bracing while shaking.
var pelvis_drop := 0.0
## Braced stance: no settling steps unless a foot is far off.
var bracing := false
## Long bodies on several legs: the body pitches and rolls with what its legs reach (a plane
## fitted to every hip's allowed height) instead of keeping one level pelvis height.
var body_tilt := false
var max_body_tilt := 0.35
## A buckled leg (support 0) still holds the hip this share of its normal reach.
var buckle_reach := 0.5

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
var last_step_start := -999.0
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
## body_tilt: pitch (nose up +) and roll (+X side up +) of the body, radians, smoothed.
var body_pitch := 0.0
var body_roll := 0.0
var _tilt_v := Vector2.ZERO

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
	step_period = clampf(2.0 * step_length / (maxf(speed, 0.01) * cycle_steps), min_step_period, idle_step_period)
	var swing_time := swing_fraction * step_period
	var double_support := (1.0 - swing_fraction) * step_period

	# 1) Advance swinging legs.
	var swinging := 0
	for i in legs.size():
		var leg := legs[i]
		if leg.phase != LegState.Phase.SWING:
			continue
		if leg.scripted:
			swinging += 1
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
		# The landing spot follows a re-planned goal through a critically damped spring
		# (continuous velocity), so a re-plan never jerks the foot.
		StepMath.follow_goal(leg, delta)
		_update_swing_pose(leg)
		if leg.swing_t >= 1.0:
			StepMath.plant(leg, time)
			last_touchdown = time
		else:
			swinging += 1

	# 2) Start a new step when allowed and needed. A stance leg that is close to full
	# extension (the body has moved away from it, e.g. in a tight fast turn) steps at once,
	# without waiting for the rest of the double support.
	var moving := speed > 0.05 or absf(yaw_rate) > 0.03 or desired_velocity.length() > 0.05
	var urgent := false
	if swinging < max_swinging:
		var b := body_basis()
		for leg in legs:
			if leg.is_planted():
				var hip := hip_world(leg)
				if hip.distance_to(leg.plant_pos + Vector3.UP * ankle_height) > leg_length * 0.985:
					urgent = true
	# Bipeds wait for the double support after a touchdown; a gait order (several legs)
	# starts one step per beat (step_period), overlapping swings like a real walk.
	var ready := time - last_touchdown >= double_support * (1.0 if moving else 0.5)
	if not gait_sequence.is_empty():
		ready = time - last_step_start >= step_period * (1.0 if moving else 0.5)
	# A weakened leg (support < 1): the others hold the body up, so nothing steps unless
	# it has to, and never two at once.
	var weakened := false
	for leg in legs:
		weakened = weakened or leg.support < 0.99
	if weakened and (not urgent or swinging > 0):
		ready = false
		urgent = false
	if swinging < max_swinging and (urgent or ready):
		var best := -1
		var best_err := 0.0
		var seq_next := -1
		if not gait_sequence.is_empty():
			var at := gait_sequence.find(last_step_leg)
			seq_next = gait_sequence[(at + 1) % gait_sequence.size()]
		for i in legs.size():
			var leg := legs[i]
			if leg.phase != LegState.Phase.STANCE or leg.support < 0.5:
				continue
			var err := plan_error(leg, swing_time)
			if urgent:
				var hip_u := hip_world(leg)
				err += maxf(0.0, hip_u.distance_to(leg.plant_pos + Vector3.UP * ankle_height) - leg_length * 0.97) * 10.0
			# Alternate legs while walking (or follow the gait order).
			if moving and seq_next >= 0:
				if i != seq_next and not urgent:
					err *= 0.25
			elif moving and i == last_step_leg and legs.size() > 1:
				err *= 0.3
			if err > best_err:
				best_err = err
				best = i
		# Braced (e.g. shaking): only a really displaced foot is re-placed.
		var threshold := moving_step_distance if moving else (settle_distance * 4.0 if bracing else settle_distance)
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

	var tb := Perf.begin()
	_update_pelvis(delta, double_support)
	Perf.end(&"loco_balance", tb)


## Where a leg should land if it started a step now, given ``t_ahead`` until touchdown.
func target_for(leg: LegState, t_ahead: float) -> Vector3:
	var yaw_p := yaw + yaw_rate * t_ahead
	var fwd_now := forward()
	var fwd_p := Vector3(-sin(yaw_p), 0.0, -cos(yaw_p))
	var body_p := position + (fwd_now + fwd_p) * 0.5 * speed * t_ahead
	# Land ahead by half of the distance the body covers while this foot stands, so the
	# body passes over the foot in the middle of its stance.
	var stance_time := step_period * (cycle_steps - swing_fraction)
	var lead := fwd_p * speed * stance_time * 0.5
	return body_p + Basis(Vector3.UP, yaw_p) * leg.foot_nominal + lead


## Hip joint of a leg in world space (on the tilted body plane when body_tilt is on).
func hip_world(leg: LegState) -> Vector3:
	var h := pelvis + body_basis() * Vector3(leg.hip_local.x, 0.0, leg.hip_local.z)
	if body_tilt:
		h.y += tan(body_roll) * leg.hip_local.x - tan(body_pitch) * leg.hip_local.z
	return h


func plan_error(leg: LegState, t_ahead: float) -> float:
	var t := target_for(leg, t_ahead)
	var yaw_p := yaw + yaw_rate * t_ahead
	return _flat(t - leg.plant_pos).length() + yaw_error_weight * absf(angle_difference(leg.plant_yaw, yaw_p))


## One ray straight down. Returns [point, normal].
func probe_ground(space: PhysicsDirectSpaceState3D, at: Vector3, ref_y: float) -> Array:
	probes_this_tick += 1
	return StepMath.probe_ground(space, at, ref_y, ground_mask)


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
	# Heavy limbs: a long step takes longer rather than whipping the foot (smootherstep peak
	# acceleration is 5.77 * distance / duration^2).
	var dist := _flat(goal - leg.plant_pos).length()
	leg.swing_duration = maxf(leg.swing_duration, sqrt(5.77 * dist / max_foot_accel))
	goal = target_for(leg, leg.swing_duration)
	var g := probe_ground(space, goal, leg.plant_pos.y)
	leg.target_goal = g[0]
	leg.target_pos = g[0]
	leg.target_velocity = Vector3.ZERO
	leg.target_normal = g[1]
	leg.target_yaw = yaw + yaw_rate * leg.swing_duration
	last_step_leg = i
	last_step_start = time
	step_count += 1


func _update_swing_pose(leg: LegState) -> void:
	StepMath.swing_pose(leg, lift_height)


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
	var carrying := 0.0
	for leg in legs:
		if leg.phase != LegState.Phase.SWING:
			carrying += leg.support
	for i in legs.size():
		var leg := legs[i]
		var target := 1.0 / legs.size()
		if legs.size() == 2:
			if leg.phase == LegState.Phase.SWING:
				target = 0.0
			elif moving and swinging_count() == 0:
				target = 0.0 if i == next else 1.0
			elif swinging_count() > 0:
				target = 1.0
		else:
			# Several legs: the standing ones share the weight by how well they carry it.
			target = 0.0 if leg.phase == LegState.Phase.SWING else leg.support / maxf(carrying, 1e-3)
		leg.load = move_toward(leg.load, target, rate)
	if legs.size() > 2:
		# Several legs: the shares always add up to the whole body weight.
		var sum := 0.0
		for leg in legs:
			sum += leg.load
		if sum > 1e-4:
			for leg in legs:
				leg.load /= sum
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
	# Height: nominal, but never higher than the legs can reach. Each leg constrains the
	# height through an *effective* foot: its plant, or while swinging a smooth blend from
	# lift-off to landing (so the constraint never appears or vanishes in one tick). The
	# constraints are combined with a soft minimum (no kinks where they cross).
	var nominal := position.y + nominal_hip_height - pelvis_drop
	if body_tilt:
		target.y = _tilted_height(target, b, nominal, delta)
	else:
		target.y = _level_height(target, b, nominal)
	# Critically damped spring: weight, not snapping.
	# Vertical motion is softer than sideways sway: a giant's bob is slow and heavy.
	var k := Vector3(pelvis_stiffness, pelvis_stiffness_vertical, pelvis_stiffness)
	# Feed-forward of the body velocity: no lag behind the feet while walking.
	var target_velocity := fwd * speed
	var acc := (target - pelvis) * k * k + (target_velocity - pelvis_velocity) * 2.0 * k
	pelvis_velocity += acc * delta
	pelvis += pelvis_velocity * delta
	# The body leans into its acceleration (forward/back, into turns, over the support).
	var centripetal := Vector3.UP.cross(fwd) * speed * yaw_rate
	lean_accel = fwd * clampf(accel, -1.5, 1.5) + centripetal + _flat(acc) * 0.1
	var up := (Vector3.UP + lean_accel / 9.8 * 2.0).normalized()
	com = pelvis + up * 3.5
	if not _initialised:
		pelvis = target


## The foot a leg's reach is measured from: its plant, or while swinging a smooth blend
## from lift-off to landing (the constraint never appears or vanishes in one tick).
func _effective_foot(leg: LegState) -> Vector3:
	if leg.phase == LegState.Phase.SWING:
		# Phase the landing spot in during the first ~60% of the swing, so the (soft)
		# pelvis is already low enough when the foot lands lower (step down, downhill).
		var t := minf(1.0, leg.swing_t * 1.6)
		return leg.lift_pos.lerp(leg.target_pos, t * t * (3.0 - 2.0 * t))
	return leg.plant_pos


## Highest hip height a leg allows for a hip at ``hip`` (xz).
func _allowed_hip_height(leg: LegState, hip: Vector3) -> float:
	var foot := _effective_foot(leg)
	var d := _flat(foot - hip).length()
	var reach := leg_length * 0.95 * lerpf(buckle_reach, 1.0, clampf(leg.support, 0.0, 1.0))
	leg.hip_height_allowed = foot.y + ankle_height + sqrt(maxf(0.0, reach * reach - d * d))
	return leg.hip_height_allowed


## Plane through the hips (centre height, pitch, roll) fitted to what every leg allows,
## lowered until no hip is above its leg's reach (soft maximum of the overshoots). The
## tilt is spring-smoothed; the height goes through the pelvis spring.
func _tilted_height(target: Vector3, b: Basis, nominal: float, delta: float) -> float:
	var n := legs.size()
	var hs: Array[float] = []
	var sx := 0.0
	var sz := 0.0
	var sxx := 0.0
	var szz := 0.0
	var sh := 0.0
	var sxh := 0.0
	var szh := 0.0
	for leg in legs:
		var hip := target + b * Vector3(leg.hip_local.x, 0.0, leg.hip_local.z)
		var h := _allowed_hip_height(leg, hip)
		hs.append(h)
		sx += leg.hip_local.x
		sz += leg.hip_local.z
		sxx += leg.hip_local.x * leg.hip_local.x
		szz += leg.hip_local.z * leg.hip_local.z
		sh += h
		sxh += leg.hip_local.x * h
		szh += leg.hip_local.z * h
	# Least squares h = c + a x + e z (hips placed symmetrically: the normal equations
	# decouple once the means are removed).
	var mx := sx / n
	var mz := sz / n
	var mh := sh / n
	var vx := sxx / n - mx * mx
	var vz := szz / n - mz * mz
	var a := (sxh / n - mx * mh) / vx if vx > 1e-4 else 0.0
	var e := (szh / n - mz * mh) / vz if vz > 1e-4 else 0.0
	var slope_max := tan(max_body_tilt)
	a = clampf(a, -slope_max, slope_max)
	e = clampf(e, -slope_max, slope_max)
	var tilt_target := Vector2(atan(-e), atan(a))   # pitch (nose = -z up), roll (+x up)
	var k := pelvis_stiffness_vertical
	var cur := Vector2(body_pitch, body_roll)
	_tilt_v += ((tilt_target - cur) * k * k - _tilt_v * 2.0 * k) * delta
	cur += _tilt_v * delta
	body_pitch = cur.x
	body_roll = cur.y
	# Centre height: as high as the fitted plane, never above any leg's reach.
	var over: Array[float] = []
	var c := mh - a * mx - e * mz
	for i in n:
		var leg := legs[i]
		var plane := c + tan(body_roll) * leg.hip_local.x - tan(body_pitch) * leg.hip_local.z
		over.append(-(plane - hs[i]))
	var lower := -_soft_min(over, 0.08)
	var h_centre := c - maxf(lower, 0.0)
	return minf(h_centre, nominal)


func _level_height(target: Vector3, b: Basis, nominal: float) -> float:
	var terms: Array[float] = [nominal]
	for leg in legs:
		var foot := leg.plant_pos
		if leg.phase == LegState.Phase.SWING:
			# Phase the landing spot in during the first ~60% of the swing, so the (soft)
			# pelvis is already low enough when the foot lands lower (step down, downhill).
			var t := minf(1.0, leg.swing_t * 1.6)
			foot = leg.lift_pos.lerp(leg.target_pos, t * t * (3.0 - 2.0 * t))
		var hip := target + b * Vector3(leg.hip_local.x, 0.0, leg.hip_local.z)
		var d := _flat(foot - hip).length()
		var reach := leg_length * 0.95
		terms.append(foot.y + ankle_height + sqrt(maxf(0.0, reach * reach - d * d)))
	return _soft_min(terms, 0.08)


## Smooth minimum (log-sum-exp); ``k`` is the blend width in the values' units.
static func _soft_min(values: Array[float], k: float) -> float:
	var m: float = values[0]
	for v in values:
		m = minf(m, v)
	var sum := 0.0
	for v in values:
		sum += exp(-(v - m) / k)
	return m - k * log(sum)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
