class_name LegState
extends RefCounted
## One leg of a LocomotionController. Pure data; world space unless noted.

enum Phase { STANCE, SWING }

var name: StringName
## Nominal foot (sole) position in the body frame, on the ground (x = side, z = forward axis).
var foot_nominal := Vector3.ZERO
## Hip joint position in the body frame at nominal hip height (y is set by the controller).
var hip_local := Vector3.ZERO

var phase := Phase.STANCE
## Planted sole point / normal / yaw (valid in STANCE; start point of the next swing).
var plant_pos := Vector3.ZERO
var plant_normal := Vector3.UP
var plant_yaw := 0.0
## Swing: start, goal (smoothed towards the latest plan), progress.
var lift_pos := Vector3.ZERO
var lift_normal := Vector3.UP
var lift_yaw := 0.0
var target_pos := Vector3.ZERO
var target_goal := Vector3.ZERO
var target_velocity := Vector3.ZERO
var target_normal := Vector3.UP
var target_yaw := 0.0
var swing_t := 0.0
var swing_duration := 1.0
var replanned := false
## Current sole pose the rig should reach.
var foot_pos := Vector3.ZERO
var foot_normal := Vector3.UP
var foot_yaw := 0.0
var touchdown_time := -999.0
## Share of the body weight on this leg (0..1), changes continuously.
var load := 0.5
## Filled by the rig after IK: distance between the planned sole and the achieved one.
var reach_error := 0.0
## Filled by the rig: measured horizontal sole speed while in ground contact (m/s).
var slip_speed := 0.0


func is_planted() -> bool:
	return phase == Phase.STANCE


func phase_name() -> String:
	return "STANCE" if phase == Phase.STANCE else "SWING %.0f%%" % (swing_t * 100.0)
