class_name PcVrRig
extends XROrigin3D
## Core-only PCVR locomotion preview. Tracking poses remain owned by OpenXR.
## This rig deliberately does not run climbing, combat, AI or replay simulation.

signal exit_requested
signal status_changed(text: String)

const InputReader := preload("res://src/vr/pc_vr_input.gd")
const BODY_HALF_HEIGHT := 0.9
const WALK_SPEED := 1.5
const SNAP_ANGLE := PI / 6.0
const DEADZONE := 0.2
const TURN_THRESHOLD := 0.7
const TURN_RELEASE := 0.25
const HEAD_GAP := 0.15
const MAX_PHYSICAL_STEP := 0.8
const COMFORT_SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled;
uniform float darkness = 0.0;
uniform float motion = 0.0;
void fragment() {
 ALBEDO = vec3(0.0);
 float edge = smoothstep(0.23, 0.52, length(UV - vec2(0.5)));
 ALPHA = max(darkness, edge * motion * 0.72);
}
"""

var body: CharacterBody3D
var head: XRCamera3D
var left: XRController3D
var right: XRController3D
var auto_step := true
var ready_for_motion := false
var paused := false
var blackout := 0.0
var motion_vignette := true
var status := "Naciśnij A, gdy masz już założone gogle."
var _previous := {}
var _confirm_released := false
var _turn_armed := false
var _move_armed := false
var _comfort: MeshInstance3D
var _comfort_material: ShaderMaterial
var _label: Label3D
var _left_visual: MeshInstance3D
var _right_visual: MeshInstance3D


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	process_physics_priority = -10
	world_scale = 1.0
	head = XRCamera3D.new()
	head.name = "Head"
	head.near = 0.06
	head.far = 1800.0
	add_child(head)
	left = _controller("LeftHand", &"left_hand")
	right = _controller("RightHand", &"right_hand")
	_left_visual = _hand_marker(left, Color(0.72, 0.81, 0.87))
	_right_visual = _hand_marker(right, Color(0.85, 0.75, 0.53))
	_build_comfort()
	_label = Label3D.new()
	_label.name = "ReadyPanel"
	_label.position = Vector3(0, -0.05, -1.5)
	_label.font_size = 40
	_label.pixel_size = 0.0015
	_label.outline_size = 8
	_label.no_depth_test = true
	_label.render_priority = 127
	_label.modulate = Color(0.94, 0.94, 0.87)
	head.add_child(_label)
	_update_panel()


func setup(actor: CharacterBody3D) -> void:
	body = actor
	body.set_physics_process(false)
	body.velocity = Vector3.ZERO
	body.floor_snap_length = 0.3
	body.floor_max_angle = deg_to_rad(46.0)
	global_position = body.global_position - Vector3.UP * BODY_HALF_HEIGHT
	head.current = true
	suspend("Naciśnij A, gdy masz już założone gogle.")


func _physics_process(delta: float) -> void:
	if auto_step:
		step(delta, InputReader.read(left, right), head_has_tracking())


static func head_has_tracking() -> bool:
	var tracker := XRServer.get_tracker(&"head") as XRPositionalTracker
	if tracker == null:
		return false
	var pose := tracker.get_pose(&"default")
	return pose != null and pose.has_tracking_data and pose.tracking_confidence != XRPose.XR_TRACKING_CONFIDENCE_NONE


func step(delta: float, raw_frame: Dictionary, head_tracked: bool) -> void:
	if not is_instance_valid(body) or not is_finite(delta) or delta <= 0.0:
		return
	var dt := minf(delta, 0.05)
	var frame := _sanitize(raw_frame)
	_left_visual.visible = frame.left_tracked
	_right_visual.visible = frame.right_tracked
	var right_continuous: bool = frame.right_tracked and bool(_previous.get("right_tracked", false))
	var left_continuous: bool = frame.left_tracked and bool(_previous.get("left_tracked", false))
	var confirm_edge: bool = right_continuous and frame.confirm and not bool(_previous.get("confirm", false))
	var pause_edge: bool = left_continuous and frame.pause and not bool(_previous.get("pause", false))
	var back_edge: bool = right_continuous and frame.back and not bool(_previous.get("back", false))
	var recenter_edge: bool = left_continuous and frame.recenter and not bool(_previous.get("recenter", false))
	_previous = frame.duplicate()
	if not frame.right_tracked:
		_turn_armed = false
	if not frame.left_tracked:
		_move_armed = false
	# Core OpenXR can report tracked orientation while position becomes zero.
	# Reject implausible floor-relative height as well as an invalid tracking flag.
	if not head_tracked or not head.transform.is_finite() or head.position.y < 0.3 or head.position.y > 2.6:
		if ready_for_motion:
			suspend("Utracono śledzenie. Przywróć je i naciśnij A.")
		blackout = 1.0
		_set_comfort(1.0, 0.0, dt)
		return
	if back_edge:
		exit_requested.emit()
		return
	# A missing controller is not evidence that a held button was released.
	if frame.right_tracked and not frame.confirm:
		_confirm_released = true
	if not ready_for_motion:
		if recenter_edge:
			recenter()
		if confirm_edge and _confirm_released and recenter():
			ready_for_motion = true
			paused = false
			_confirm_released = false
			_set_status("")
		else:
			_set_comfort(0.0, 0.0, dt)
			return
	if pause_edge:
		paused = not paused
		body.velocity = Vector3.ZERO
		_turn_armed = false
		_move_armed = false
		_set_status("Pauza — X: wróć   Y: wycentruj   B: wyjdź" if paused else "")
	if recenter_edge:
		recenter()
	var safe_physical := _physical_motion()
	var gap := Vector2(head.global_position.x - body.global_position.x, head.global_position.z - body.global_position.z).length()
	if not safe_physical or gap > HEAD_GAP:
		body.velocity = Vector3.ZERO
		_set_comfort(clampf(gap / HEAD_GAP, 0.0, 1.0), 0.0, dt)
		return
	if paused:
		_set_comfort(0.0, 0.0, dt)
		return
	if absf(frame.turn) < TURN_RELEASE and frame.right_tracked:
		_turn_armed = true
	elif absf(frame.turn) >= TURN_THRESHOLD and _turn_armed:
		_snap_turn(-signf(frame.turn) * SNAP_ANGLE)
		_turn_armed = false
	var move: Vector2 = frame.move
	if frame.left_tracked and move.length() <= DEADZONE:
		_move_armed = true
	var velocity := Vector3.ZERO
	if _move_armed and move.length() > DEADZONE:
		var heading := -head.global_basis.z
		heading.y = 0.0
		if heading.length_squared() > 0.001:
			heading = heading.normalized()
			var rightward := heading.cross(Vector3.UP)
			velocity = (rightward * move.x + heading * move.y) * WALK_SPEED
	if not _walkable(body.global_position + velocity * dt):
		velocity = Vector3.ZERO
	body.velocity.x = velocity.x
	body.velocity.z = velocity.z
	body.velocity.y = maxf(body.velocity.y - 18.0 * dt, -12.0)
	var before := body.global_position
	body.move_and_slide()
	global_position += body.global_position - before
	_set_comfort(0.0, 1.0 if motion_vignette and velocity.length() > 0.01 else 0.0, dt)


## Deliberate calibration only: do not recenter automatically on tracking recovery.
## Keep the world body and measured floor-relative head height intact.
func recenter() -> bool:
	if not is_instance_valid(body) or not head.transform.is_finite() or head.position.y < 0.6 or head.position.y > 2.4:
		_set_status("Sprawdź wysokość podłogi w goglach; potem naciśnij A.")
		return false
	var offset := head.global_position - body.global_position
	offset.y = 0.0
	global_position -= offset
	global_position.y = body.global_position.y - BODY_HALF_HEIGHT
	body.velocity = Vector3.ZERO
	_turn_armed = false
	_move_armed = false
	return true


func suspend(reason: String) -> void:
	ready_for_motion = false
	paused = false
	_confirm_released = false
	_turn_armed = false
	_move_armed = false
	if is_instance_valid(body):
		body.velocity = Vector3.ZERO
	_set_status(reason)


func _physical_motion() -> bool:
	var displacement := head.global_position - body.global_position
	displacement.y = 0.0
	if displacement.length() > MAX_PHYSICAL_STEP:
		suspend("Zmieniło się miejsce śledzenia. Y: wycentruj, potem A.")
		return false
	if displacement.length() < 0.001:
		return true
	if not _walkable(body.global_position + displacement):
		return false
	# Origin is a sibling of the actor. Physical walking moves only the collision
	# body; moving the origin here would counteract the real tracked head movement.
	body.move_and_collide(displacement)
	return true


func _snap_turn(angle: float) -> void:
	var pivot := head.global_position
	var rotation := Basis(Vector3.UP, angle)
	global_position = pivot + rotation * (global_position - pivot)
	global_basis = rotation * global_basis
	# The symmetric capsule stays put. Turning never nudges it into a nearby wall.


func _walkable(center: Vector3) -> bool:
	var foot := center - Vector3.UP * BODY_HALF_HEIGHT
	var query := PhysicsRayQueryParameters3D.create(foot + Vector3.UP * 0.45, foot - Vector3.UP * 0.65, Layers.WORLD)
	query.exclude = [body.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or (hit.normal as Vector3).dot(Vector3.UP) < cos(deg_to_rad(46.0)):
		return false
	var water_height := WaterBody.surface_at(get_tree(), center)
	return is_nan(water_height) or water_height < foot.y + 0.15


func _set_status(text: String) -> void:
	if status != text:
		status = text
		status_changed.emit(text)
	_update_panel()


func _update_panel() -> void:
	if not is_instance_valid(_label):
		return
	_label.text = "PCVR — próba skali\n" + status + "\nLewy drążek: chód   Prawy: obrót 30°\nY: wycentruj   X: pauza   B: wyjdź"
	_label.visible = not ready_for_motion or paused


func _set_comfort(darkness: float, motion: float, delta: float) -> void:
	blackout = move_toward(blackout, darkness, delta * 8.0)
	_comfort_material.set_shader_parameter("darkness", blackout)
	_comfort_material.set_shader_parameter("motion", motion)
	_comfort.visible = blackout > 0.001 or motion > 0.001


static func _sanitize(frame: Dictionary) -> Dictionary:
	var result := {"move": Vector2.ZERO, "turn": 0.0}
	var vector: Variant = frame.get("move", Vector2.ZERO)
	if vector is Vector2 and (vector as Vector2).is_finite():
		result.move = (vector as Vector2).limit_length(1.0)
	var turn: Variant = frame.get("turn", 0.0)
	if typeof(turn) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(turn)):
		result.turn = clampf(float(turn), -1.0, 1.0)
	for key in ["confirm", "back", "recenter", "pause", "left_tracked", "right_tracked"]:
		result[key] = frame.get(key, false) is bool and frame.get(key, false)
	if not result.left_tracked:
		result.move = Vector2.ZERO
	if not result.right_tracked:
		result.turn = 0.0
		result.confirm = false
		result.back = false
	if not result.left_tracked:
		result.recenter = false
		result.pause = false
	return result


func _controller(node_name: String, tracker: StringName) -> XRController3D:
	var controller := XRController3D.new()
	controller.name = node_name
	controller.tracker = tracker
	controller.pose = &"grip"
	add_child(controller)
	return controller


func _hand_marker(controller: XRController3D, color: Color) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.035
	mesh.height = 0.13
	mesh.radial_segments = 8
	mesh.rings = 1
	marker.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	marker.material_override = material
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.rotation.x = PI / 2.0
	marker.visible = false
	controller.add_child(marker)
	return marker


func _build_comfort() -> void:
	var shader := Shader.new()
	shader.code = COMFORT_SHADER
	_comfort_material = ShaderMaterial.new()
	_comfort_material.shader = shader
	_comfort_material.render_priority = 126
	_comfort = MeshInstance3D.new()
	_comfort.name = "ComfortMask"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.36, 0.36)
	_comfort.mesh = quad
	_comfort.material_override = _comfort_material
	_comfort.position.z = -0.09
	_comfort.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_comfort.visible = false
	head.add_child(_comfort)
