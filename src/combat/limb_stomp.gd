class_name LimbStomp
extends RefCounted
## A stomp with one leg, shared by every colossus that stomps (Valus with a foot,
## Quadratus with a front hoof): the leg leaves the step planner (``scripted``), rises
## over the target during the telegraph, drifts after the target for the first part of
## the wind-up only (a late dodge always works), slams down in ``drop_time`` and is
## planted again by the planner's own rule. Pure motion; damage stays with the colossus.

var height := 3.2
## Share of the telegraph spent lifting the foot.
var lift_share := 0.75
## Seconds from the top to the ground (inside ACTIVE).
var drop_time := 0.18
## The raised foot follows the target only until this share of the telegraph...
var track_until := 0.6
## ...and at most this fast (m/s).
var track_speed := 2.0

var leg: LegState
var slam_point := Vector3.ZERO
var hover_point := Vector3.ZERO
var impacted := false


## Takes the leg out of the planner and aims it at ``slam``.
func begin(p_leg: LegState, slam: Vector3) -> void:
	leg = p_leg
	leg.scripted = true
	leg.phase = LegState.Phase.SWING
	leg.swing_t = 0.0
	leg.lift_pos = leg.plant_pos
	leg.lift_normal = leg.plant_normal
	leg.lift_yaw = leg.plant_yaw
	leg.target_yaw = leg.plant_yaw
	leg.target_normal = Vector3.UP
	impacted = false
	slam_point = slam
	hover_point = leg.plant_pos
	leg.target_pos = slam


## Telegraph: drift the slam point towards ``want`` (already a valid ground point).
## ``ground`` maps a point to the ground under it.
func track(want: Vector3, attack: ColossusAttack, delta: float, ground: Callable) -> void:
	if attack.phase_t() > track_until:
		return
	var step := Vector3(want.x - slam_point.x, 0.0, want.z - slam_point.z)
	if step.length() > track_speed * delta:
		step = step.normalized() * track_speed * delta
	if step.length() > 1e-4:
		slam_point = ground.call(slam_point + step)
	leg.target_pos = slam_point


## Poses the foot for this tick. Returns true on the tick it hits the ground.
func update(attack: ColossusAttack, now: float) -> bool:
	if leg == null or not leg.scripted:
		return false
	var up := Vector3.UP * height
	match attack.phase:
		ColossusAttack.Phase.TELEGRAPH:
			var t := minf(1.0, attack.phase_t() / lift_share)
			var s := t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
			hover_point = leg.lift_pos.lerp(slam_point, s * 0.85) + up * s
			# A slight tremble at the top of the wind-up.
			if t >= 1.0:
				hover_point += Vector3.UP * 0.05 * sin(attack.phase_time * 30.0)
			leg.foot_pos = hover_point
			leg.swing_t = 0.5 * s
		ColossusAttack.Phase.ACTIVE:
			var t := minf(1.0, attack.phase_time / drop_time)
			leg.foot_pos = hover_point.lerp(slam_point, t * t)
			leg.swing_t = 0.5 + 0.5 * t
			if t >= 1.0 and not impacted:
				impacted = true
				leg.target_pos = slam_point
				StepMath.plant(leg, now)
				leg.scripted = false
				return true
	return false


## Ends early: never leave a foot hanging, plant it on ``ground_point`` (under it).
func abort(ground_point: Vector3, now: float) -> void:
	if leg == null or not leg.scripted:
		return
	leg.target_pos = ground_point
	leg.target_normal = Vector3.UP
	StepMath.plant(leg, now)
	leg.scripted = false
