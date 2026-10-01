class_name StepMath
## Shared, rig-independent maths for one leg's step, used by every legged walker
## (colossus step planner, horse gait planner):
##   - C2-smooth swing arc (zero velocity and acceleration at lift-off and touchdown),
##   - landing spot following a re-planned goal through a critically damped spring,
##   - one straight-down ground probe.


## Places the foot of a swinging leg for its current ``swing_t``.
## Horizontal: smootherstep; vertical: 64 t^3 (1-t)^3 bump scaled by step distance and
## raised for steps up.
static func swing_pose(leg: LegState, lift_height: float, full_height_distance := 1.5) -> void:
	var t := leg.swing_t
	var s := t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
	var p := leg.lift_pos.lerp(leg.target_pos, s)
	var dist := Vector2(leg.target_pos.x - leg.lift_pos.x, leg.target_pos.z - leg.lift_pos.z).length()
	var clearance := lift_height * clampf(dist / full_height_distance, 0.35, 1.0) + maxf(0.0, leg.target_pos.y - leg.lift_pos.y) * 0.6
	p.y += clearance * 64.0 * pow(t * (1.0 - t), 3.0)
	leg.foot_pos = p
	leg.foot_normal = leg.lift_normal.slerp(leg.target_normal, s).normalized()
	leg.foot_yaw = lerp_angle(leg.lift_yaw, leg.target_yaw, s)


## The landing spot follows ``target_goal`` with continuous velocity (no jerk on re-plan).
static func follow_goal(leg: LegState, delta: float, k := 6.0) -> void:
	leg.target_velocity += ((leg.target_goal - leg.target_pos) * k * k - leg.target_velocity * 2.0 * k) * delta
	leg.target_pos += leg.target_velocity * delta


## Starts a swing from the current plant towards ``goal`` (already on the ground).
static func begin_swing(leg: LegState, goal: Vector3, goal_normal: Vector3, goal_yaw: float, duration: float) -> void:
	leg.phase = LegState.Phase.SWING
	leg.swing_t = 0.0
	leg.swing_duration = duration
	leg.replanned = false
	leg.lift_pos = leg.plant_pos
	leg.lift_normal = leg.plant_normal
	leg.lift_yaw = leg.plant_yaw
	leg.target_goal = goal
	leg.target_pos = goal
	leg.target_velocity = Vector3.ZERO
	leg.target_normal = goal_normal
	leg.target_yaw = goal_yaw


## Ends a swing: the foot is planted exactly where the arc ended.
static func plant(leg: LegState, time: float) -> void:
	leg.phase = LegState.Phase.STANCE
	leg.plant_pos = leg.target_pos
	leg.plant_normal = leg.target_normal
	leg.plant_yaw = leg.target_yaw
	leg.touchdown_time = time
	leg.foot_pos = leg.plant_pos
	leg.foot_normal = leg.plant_normal
	leg.foot_yaw = leg.plant_yaw


## One ray straight down. Returns [point, normal]; falls back to ``ref_y`` and up.
static func probe_ground(space: PhysicsDirectSpaceState3D, at: Vector3, ref_y: float, mask: int, up := 8.0, down := 12.0, perf_label := &"climb_rays") -> Array:
	var hit := ClimbQuery.ray(space, Vector3(at.x, ref_y + up, at.z), Vector3(at.x, ref_y - down, at.z), [], mask, perf_label)
	if hit.is_empty():
		return [Vector3(at.x, ref_y, at.z), Vector3.UP]
	return [hit.position, hit.normal]
