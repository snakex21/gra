class_name PcVrRig
extends XROrigin3D
## Core PCVR locomotion and hand climbing. Tracking poses stay owned by OpenXR.
## Combat, AI and replay simulation are outside this isolated interaction scene.

signal exit_requested
signal status_changed(text: String)

const InputReader := preload("res://src/vr/pc_vr_input.gd")
const HandsScript := preload("res://src/vr/pc_vr_hands.gd")
const ClimbingScript := preload("res://src/vr/pc_vr_climbing.gd")
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
var eye_height := 1.70
var height_offset := 0.0
var recenter_forward := Vector3.FORWARD
var hands: Node3D
var climbing: PcVrClimbing
var status := "Naciśnij A, gdy masz już założone gogle."
var _previous := {}
var _confirm_released := false
var _turn_armed := false
var _move_armed := false
var _comfort: MeshInstance3D
var _comfort_material: ShaderMaterial
var _label: Label3D
var _grip_label: Label3D


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
	hands = HandsScript.new()
	hands.name = "Hands"
	add_child(hands)
	hands.setup(head, left, right)
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
	_grip_label = Label3D.new()
	_grip_label.position = Vector3(0, -.42, -1.4)
	_grip_label.font_size = 24
	_grip_label.pixel_size = .0012
	_grip_label.no_depth_test = true
	_grip_label.render_priority = 127
	_grip_label.visible = false
	head.add_child(_grip_label)
	_update_panel()


func setup(actor: CharacterBody3D) -> void:
	body = actor
	body.set_physics_process(false)
	body.velocity = Vector3.ZERO
	body.floor_snap_length = 0.3
	body.floor_max_angle = deg_to_rad(46.0)
	global_position = body.global_position - Vector3.UP * BODY_HALF_HEIGHT
	recenter_forward = -global_basis.z
	hands.setup_sword(body)
	climbing = ClimbingScript.new()
	climbing.setup(self, body, left, right)
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
	hands.update_hands(frame.left_tracked, frame.right_tracked)
	if not ready_for_motion or paused:
		_update_panel()
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
			hands.step_sword(dt, frame, body, false)
			_set_comfort(0.0, 0.0, dt)
			return
	if pause_edge:
		paused = not paused
		climbing.release_all()
		hands.recall_sword()
		body.velocity = Vector3.ZERO
		_turn_armed = false
		_move_armed = false
		_set_status("Pauza — X: wróć   Y: wycentruj   B: wyjdź\nPrawy drążek góra/dół: wysokość" if paused else "")
	if recenter_edge:
		recenter()
	if paused and absf(frame.height) > .25:
		var previous_height := eye_height
		eye_height = clampf(eye_height + frame.height * dt * .25, 1.4, 2.1)
		height_offset += eye_height - previous_height
		global_position.y += eye_height - previous_height
		_update_panel()
	var physical_before := body.global_position
	var safe_physical := _physical_motion(climbing.is_climbing() or not _walkable(body.global_position))
	var gap := Vector2(head.global_position.x - body.global_position.x, head.global_position.z - body.global_position.z).length()
	if not safe_physical or gap > HEAD_GAP:
		# A blocked room-scale capsule must not preserve an old grip forever.
		climbing.release_all()
		_turn_armed = false
		_move_armed = false
		hands.set_grips(false, false)
		_grip_label.visible = false
		if ready_for_motion and not paused:
			body.velocity = Vector3(0, maxf(body.velocity.y - 18.0 * dt, -12.0), 0)
			body.move_and_slide()
		else:
			body.velocity = Vector3.ZERO
		# Physical collision recovery and gravity can cancel each other. Apply
		# their net movement under blackout instead of accumulating camera drift.
		global_position += body.global_position - physical_before
		hands.recall_sword()
		_set_comfort(1.0, 0.0, dt)
		return
	# Room-scale walking follows the physical head in XZ, but any vertical
	# collision recovery belongs to the virtual body and must carry the origin.
	global_position.y += body.global_position.y - physical_before.y
	if paused:
		hands.step_sword(dt, frame, body, false)
		hands.set_grips(false, false)
		_grip_label.visible = false
		_set_comfort(0.0, 0.0, dt)
		return
	var sword_frame := frame.duplicate()
	# An established fur grip owns that hand until it is released. A new
	# squeeze near the sword gets priority and cannot also acquire fur.
	for i in 2:
		if climbing.anchors[i] != null:
			sword_frame["left_tracked" if i == 0 else "right_tracked"] = false
			sword_frame["left_grip" if i == 0 else "right_grip"] = 0.0
	var weapon: Dictionary = hands.step_sword(dt, sword_frame, body, true)
	var climb_frame := frame.duplicate()
	if weapon.left_consumed:
		climb_frame.left_tracked = false
		climb_frame.left_grip = 0.0
	if weapon.right_consumed:
		climb_frame.right_tracked = false
		climb_frame.right_grip = 0.0
	var gripping := climbing.step(dt, climb_frame, head)
	hands.set_grips(climbing.anchors[0] != null, climbing.anchors[1] != null)
	_grip_label.visible = gripping
	if gripping:
		_turn_armed = false
		_move_armed = false
		_grip_label.text = "Chwyt %s%s  •  Wytrzymałość %d%%" % ["L " if climbing.anchors[0] != null else "", "P" if climbing.anchors[1] != null else "", int(climbing.stamina)]
		hands.sync_sword(dt)
		_set_comfort(0.0, 1.0 if motion_vignette and climbing.displacement.length() > .001 else 0.0, dt)
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
	hands.sync_sword(dt)
	_set_comfort(0.0, 1.0 if motion_vignette and velocity.length() > 0.01 else 0.0, dt)


## Deliberate calibration only: do not recenter automatically on tracking recovery.
## Keep raw poses and the capsule intact; offset origin for explicit eye height.
func recenter() -> bool:
	if not is_instance_valid(body) or not head.transform.is_finite() or head.position.y < 0.6 or head.position.y > 2.4:
		_set_status("Sprawdź wysokość podłogi w goglach; potem naciśnij A.")
		return false
	if climbing != null:
		climbing.release_all()
	var forward := -head.global_basis.z
	forward.y = 0.0
	var desired := recenter_forward
	desired.y = 0.0
	if forward.length_squared() > .001 and desired.length_squared() > .001:
		_snap_turn(forward.normalized().signed_angle_to(desired.normalized(), Vector3.UP))
	var offset := head.global_position - body.global_position
	offset.y = 0.0
	global_position -= offset
	height_offset = eye_height - head.position.y
	global_position.y = body.global_position.y - BODY_HALF_HEIGHT + height_offset
	body.velocity = Vector3.ZERO
	_turn_armed = false
	_move_armed = false
	if is_instance_valid(hands):
		hands.recall_sword()
		hands.set_grips(false, false)
	if is_instance_valid(_grip_label):
		_grip_label.visible = false
	return true


func suspend(reason: String) -> void:
	ready_for_motion = false
	paused = false
	_confirm_released = false
	_turn_armed = false
	_move_armed = false
	if climbing != null:
		climbing.release_all()
	if is_instance_valid(hands):
		hands.recall_sword()
		hands.set_grips(false, false)
	if is_instance_valid(_grip_label):
		_grip_label.visible = false
	if is_instance_valid(body):
		body.velocity = Vector3.ZERO
	_set_status(reason)


func _physical_motion(allow_air := false) -> bool:
	var displacement := head.global_position - body.global_position
	displacement.y = 0.0
	if displacement.length() > MAX_PHYSICAL_STEP:
		suspend("Zmieniło się miejsce śledzenia. Y: wycentruj, potem A.")
		return false
	if displacement.length() < 0.001:
		return true
	if not allow_air and not _walkable(body.global_position + displacement):
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
	var query := PhysicsRayQueryParameters3D.create(foot + Vector3.UP * 0.45, foot - Vector3.UP * 0.65, Layers.WORLD | Layers.COLOSSUS)
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
	var raw_height := head.position.y if head.transform.is_finite() else 0.0
	var text := "PCVR — chwyt i miecz\n" + status + "\nWysokość oczu: %.2f m  •  Gogle nad podłogą: %.2f m\nBoczne przyciski: chwyć futro lub rękojeść miecza przy pasie\nFutro: pociągnij dłoń w dół   Miecz: puść, aby upuścić\nLewy drążek: chód   Prawy: obrót 30°\nY: wycentruj   X: pauza   B: wyjdź" % [eye_height, raw_height]
	if _label.text != text:
		_label.text = text
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
	for key in ["height", "left_grip", "right_grip"]:
		var value: Variant = frame.get(key, 0.0)
		result[key] = clampf(float(value), -1.0 if key == "height" else 0.0, 1.0) if typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) else 0.0
	for key in ["confirm", "back", "recenter", "pause", "left_tracked", "right_tracked"]:
		result[key] = frame.get(key, false) is bool and frame.get(key, false)
	if not result.left_tracked:
		result.move = Vector2.ZERO
		result.left_grip = 0.0
	if not result.right_tracked:
		result.turn = 0.0
		result.confirm = false
		result.back = false
		result.right_grip = 0.0
		result.height = 0.0
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
