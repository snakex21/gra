class_name PcVrInput
extends RefCounted
## Stateless PC OpenXR input. The rig owns deadzones, comfort thresholds and edges.
## OpenXR stick +Y means forward; the rig converts it to local -Z movement.
## Register controllers as left_hand/right_hand and use pose = &"grip" (the
## engine maps action grip_pose -> grip and aim_pose -> aim on the tracker).

static func read(left: XRController3D, right: XRController3D) -> Dictionary:
	var left_tracked := _tracked(left)
	var right_tracked := _tracked(right)
	var move := _finite_stick(left.get_vector2(&"move")) if left_tracked else Vector2.ZERO
	var turn := _finite_stick(right.get_vector2(&"turn")).x if right_tracked else 0.0
	var height := _finite_stick(right.get_vector2(&"turn")).y if right_tracked else 0.0
	return {
		"move": move,
		"turn": turn,
		"height": height,
		"left_grip": _grip(left) if left_tracked else 0.0,
		"right_grip": _grip(right) if right_tracked else 0.0,
		"confirm": right_tracked and right.is_button_pressed(&"confirm"),
		"back": right_tracked and right.is_button_pressed(&"back"),
		"recenter": left_tracked and left.is_button_pressed(&"recenter"),
		"pause": left_tracked and left.is_button_pressed(&"pause"),
		"left_tracked": left_tracked,
		"right_tracked": right_tracked,
	}


static func _tracked(controller: XRController3D) -> bool:
	return is_instance_valid(controller) and controller.get_is_active() and controller.get_has_tracking_data()


static func _finite_stick(value: Vector2) -> Vector2:
	if not is_finite(value.x) or not is_finite(value.y):
		return Vector2.ZERO
	return value.limit_length(1.0)


static func _grip(controller: XRController3D) -> float:
	var value := controller.get_float(&"grab")
	return clampf(value, 0.0, 1.0) if is_finite(value) else 0.0
