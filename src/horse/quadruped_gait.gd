class_name QuadrupedGait
extends RefCounted
## Four-legged step planner driven by a gait clock.
##
## Each gait gives every leg a phase offset and a duty factor (share of the cycle on the
## ground). Legs change phase only on events: a planted leg lifts when its clock enters
## the swing part of the cycle; a swinging leg lands when its arc ends. Changing gait
## (walk -> trot -> gallop) therefore never moves a planted foot: no sliding, no jumps.
## Swing arcs, landing-spot springs and ground probes come from StepMath (shared with
## the colossus step planner).

enum Leg { FL, FR, RL, RR }
const LEG_NAMES := [&"front_left", &"front_right", &"rear_left", &"rear_right"]

## Per gait (HorseController.Gait): [stride frequency at 0 m/s, Hz per m/s, duty factor,
## phase offsets FL, FR, RL, RR]. Walk: 4-beat lateral sequence; trot: diagonal pairs;
## gallop: simplified rotary gallop (hind pair, then fore pair).
const GAITS := [
	[0.75, 0.0, 0.70, [0.25, 0.75, 0.0, 0.5]],    # IDLE (only used for settling steps)
	[0.85, 0.12, 0.65, [0.25, 0.75, 0.0, 0.5]],   # WALK
	[1.30, 0.07, 0.40, [0.0, 0.5, 0.5, 0.0]],     # TROT
	[1.55, 0.09, 0.25, [0.5, 0.6, 0.0, 0.12]],    # GALLOP (short stance, two flight phases)
]

var legs: Array[LegState] = []
## Hip/shoulder joint positions in the body frame (y = joint height above the ground).
var hip_local: Array[Vector3] = []
var leg_length := 1.3          ## upper + lower + hoof
var lift_height := 0.35
var max_reach := 0.5          ## max horizontal hip-to-foot distance before a forced step
var ground_mask := Layers.WORLD
var time := 0.0
var clock := 0.0               ## 0..1 gait cycle
var frequency := 0.85
var duty := 0.65
var offsets: Array = [0.25, 0.75, 0.0, 0.5]
var probes_this_tick := 0
var lift_offs_this_tick := 0
var step_count := 0


func setup(p_hip_local: Array[Vector3], p_leg_length: float) -> void:
	hip_local = p_hip_local
	leg_length = p_leg_length
	legs.clear()
	for i in 4:
		var leg := LegState.new()
		leg.name = LEG_NAMES[i]
		leg.foot_nominal = Vector3(p_hip_local[i].x, 0.0, p_hip_local[i].z)
		leg.hip_local = p_hip_local[i]
		legs.append(leg)


func reset(space: PhysicsDirectSpaceState3D, position: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	for leg in legs:
		var g := StepMath.probe_ground(space, position + b * leg.foot_nominal, position.y, ground_mask, 3.0, 6.0, &"horse_rays")
		leg.phase = LegState.Phase.STANCE
		leg.plant_pos = g[0]
		leg.plant_normal = g[1]
		leg.plant_yaw = yaw
		leg.foot_pos = leg.plant_pos
		leg.foot_normal = leg.plant_normal
		leg.foot_yaw = yaw


## Advances the feet for one tick along the body path given by ``c``.
func update(c: HorseController, delta: float, space: PhysicsDirectSpaceState3D) -> void:
	time += delta
	probes_this_tick = 0
	lift_offs_this_tick = 0
	var g: Array = GAITS[c.gait]
	frequency = g[0] + g[1] * c.speed
	duty = g[2]
	offsets = g[3]
	var moving := c.gait != HorseController.Gait.IDLE
	if moving:
		clock = fposmod(clock + frequency * delta, 1.0)

	for i in 4:
		var leg := legs[i]
		if leg.phase == LegState.Phase.SWING:
			leg.swing_t = minf(1.0, leg.swing_t + delta / leg.swing_duration)
			if not leg.replanned and leg.swing_t >= 0.5:
				leg.replanned = true
				var goal := _target(c, i, (1.0 - leg.swing_t) * leg.swing_duration)
				if Vector2(goal.x - leg.target_goal.x, goal.z - leg.target_goal.z).length() > 0.15:
					var gr := _probe(space, goal, leg.target_goal.y)
					leg.target_goal = gr[0]
					leg.target_normal = gr[1]
			StepMath.follow_goal(leg, delta, 10.0)
			StepMath.swing_pose(leg, lift_height, 0.8)
			if leg.swing_t >= 1.0:
				StepMath.plant(leg, time)
			continue
		# Planted: lift when the gait clock says so, or when the body has moved too far.
		var phase := fposmod(clock - float(offsets[i]), 1.0)
		var due := moving and phase >= duty and time - leg.touchdown_time > 0.08
		var hip := c.position + c.body_basis() * Vector3(leg.hip_local.x, 0.0, leg.hip_local.z)
		var stretched := Vector2(leg.plant_pos.x - hip.x, leg.plant_pos.z - hip.z).length() > max_reach
		var settle := not moving and _plan_error(c, i) > 0.25 and _swinging() == 0
		if due or stretched or settle:
			var period := 1.0 / maxf(frequency, 0.3)
			var swing_time := clampf((1.0 - duty) * period, 0.18, 0.6)
			if not moving:
				swing_time = 0.45
			var goal := _target(c, i, swing_time)
			var gr := _probe(space, goal, leg.plant_pos.y)
			StepMath.begin_swing(leg, gr[0], gr[1], c.yaw + c.yaw_rate * swing_time, swing_time)
			lift_offs_this_tick += 1
			step_count += 1


## Landing spot: under the hip at touchdown, ahead by half of the distance the body
## covers while this foot stands, clamped to what the leg can reach.
func _target(c: HorseController, i: int, t_ahead: float) -> Vector3:
	var yaw_p := c.yaw + c.yaw_rate * t_ahead
	var fwd_p := Vector3(-sin(yaw_p), 0.0, -cos(yaw_p))
	var body_p := c.position + (c.forward() + fwd_p) * 0.5 * c.speed * t_ahead
	var period := 1.0 / maxf(frequency, 0.3)
	var stance_time := duty * period
	var lead := fwd_p * clampf(c.speed * stance_time * 0.5, 0.0, max_reach * 0.9)
	return body_p + Basis(Vector3.UP, yaw_p) * legs[i].foot_nominal + lead


func _plan_error(c: HorseController, i: int) -> float:
	var t := _target(c, i, 0.45)
	return Vector2(t.x - legs[i].plant_pos.x, t.z - legs[i].plant_pos.z).length() + 0.5 * absf(angle_difference(legs[i].plant_yaw, c.yaw))


func _swinging() -> int:
	var n := 0
	for leg in legs:
		if leg.phase == LegState.Phase.SWING:
			n += 1
	return n


func _probe(space: PhysicsDirectSpaceState3D, at: Vector3, ref_y: float) -> Array:
	probes_this_tick += 1
	return StepMath.probe_ground(space, at, ref_y, ground_mask, 2.5, 4.0, &"horse_rays")


func ground_height() -> float:
	var y := 0.0
	for leg in legs:
		y += leg.plant_pos.y if leg.is_planted() else leg.lift_pos.lerp(leg.target_pos, leg.swing_t).y
	return y / 4.0
