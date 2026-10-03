class_name TravelerArt
extends Node3D
## Render adapter for the original Blender traveler. It reads player state and
## moves cosmetic joints only. PlayerVisual keeps orientation, dangle, shoulder
## raise, sword/light attachments; PlayerCharacter keeps every gameplay collider.
const FOLDER := "res://models/characters/travelers_v3/"
const LOD_NEAR := 12.0
const LOD_FAR := 35.0
var player: PlayerCharacter
var visual: PlayerVisual
var current_lod := -1
var auto_lod := true
var model: Node3D
var _arms: Array[Node3D] = []
var _forearms: Array[Node3D] = []
var _wrists: Array[Node3D] = []
var _grips: Array[Node3D] = []
var _legs: Array[Node3D] = []
var _knees: Array[Node3D] = []
var _ankles: Array[Node3D] = []
var _step := 0.0
var _lod_clock := 0.0
static var _scenes := {}

static func attach(to_visual: PlayerVisual, to_player: PlayerCharacter = null) -> TravelerArt:
	var existing := to_visual.get_node_or_null("TravelerArt") as TravelerArt
	if existing: return existing
	var art := TravelerArt.new()
	art.name = "TravelerArt"
	art.visual = to_visual
	art.player = to_player if to_player else to_visual.get_parent() as PlayerCharacter
	to_visual.add_child(art)
	return art

static func create_mono(parent: Node3D, local_position := Vector3.ZERO, yaw := 0.0, lod := 0) -> Node3D:
	var packed := _scene("mono_sleep", clampi(lod, 0, 2))
	if not packed: return null
	var mono := packed.instantiate() as Node3D
	mono.name = "MonoSleeping"
	mono.position = local_position
	mono.rotation.y = yaw
	parent.add_child(mono)
	# The GLB contains render geometry only. Its face is +Y, head +Z; local Y=0
	# is the support plane and should be placed at the altar's top surface.
	return mono

static func _scene(id: String, level: int) -> PackedScene:
	var path := FOLDER + id + "_lod%d.glb" % level
	if not _scenes.has(path): _scenes[path] = load(path) as PackedScene
	return _scenes[path]

func _ready() -> void:
	process_priority = 10
	_hide_legacy_meshes()
	set_lod(0)

func _hide_legacy_meshes() -> void:
	if not visual: return
	for child in visual.get_children():
		if child is MeshInstance3D and child != visual._flare and child != visual._beam:
			child.visible = false
	for arm in visual._arms:
		for child in arm.get_children():
			if child is MeshInstance3D and child != visual._blade: child.visible = false

func set_lod(level: int) -> void:
	level = clampi(level, 0, 2)
	if level == current_lod: return
	var packed := _scene("traveler", level)
	if not packed: return
	for arm in _arms:
		if is_instance_valid(arm): arm.queue_free()
	if is_instance_valid(model): model.queue_free()
	_arms.clear()
	_forearms.clear()
	_wrists.clear()
	_grips.clear()
	_legs.clear()
	_knees.clear()
	_ankles.clear()
	model = packed.instantiate() as Node3D
	model.name = "TravelerModelLOD%d" % level
	add_child(model)
	for i in 2:
		var arm := _part("Arm_%d" % i)
		var forearm := _part("Forearm_%d" % i)
		var leg := _part("Leg_%d" % i)
		var knee := _part("Knee_%d" % i)
		var ankle := _part("Ankle_%d" % i)
		if not arm or not forearm or not leg or not knee or not ankle:
			push_error("Traveler v3 GLB has no required rigid joints at LOD%d" % level)
			return
		_arms.append(arm)
		_forearms.append(forearm)
		_wrists.append(forearm.find_child("Wrist_%d*" % i, true, false) as Node3D)
		_grips.append(forearm.find_child("HandGrip_%d*" % i, true, false) as Node3D)
		_legs.append(leg)
		_knees.append(knee)
		_ankles.append(ankle)
		# Source shoulder positions match these pivots exactly. Remove only the
		# source shoulder transform after reparenting, retaining the forearm rig.
		arm.reparent(visual._arms[i], false)
		arm.transform = Transform3D.IDENTITY
	current_lod = level

func _part(prefix: String) -> Node3D:
	# Blender adds numeric suffixes to export copies; Godot normalizes the dots.
	return model.find_child(prefix + "*", true, false) as Node3D

func _process(delta: float) -> void:
	if not player or current_lod < 0: return
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	_step += delta * (2.8 + speed * 1.4)
	var mode := &"walk" if player.state == PlayerCharacter.State.GROUND and speed > 0.25 else &"idle"
	if player.state == PlayerCharacter.State.RIDE: mode = &"ride"
	elif player.state == PlayerCharacter.State.CLIMB: mode = &"climb"
	elif player.state == PlayerCharacter.State.SWIM: mode = &"swim"
	elif player.state == PlayerCharacter.State.AIR: mode = &"air"
	_apply_pose(mode, _step, clampf(speed / player.run_speed, 0, 1), delta)
	_lod_clock += delta
	if auto_lod and _lod_clock >= 0.25:
		_lod_clock = 0
		var camera := get_viewport().get_camera_3d()
		if camera:
			var distance := camera.global_position.distance_to(player.global_position)
			set_lod(0 if distance < LOD_NEAR else (1 if distance < LOD_FAR else 2))

## Capture/inspection helper: changes render joints only, never gameplay state.
func pose_preview(mode: StringName, step := 0.0) -> void:
	_apply_pose(mode, step, 0.8, 1.0)
	if mode == &"climb":
		for shoulder in visual._arms: shoulder.rotation.x = PI * 0.95

func _apply_pose(mode: StringName, step: float, speed: float, delta: float) -> void:
	if _arms.size() != 2: return
	var blend := 1.0 - exp(-12.0 * delta)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var stride := sin(step + (PI if i == 0 else 0))
		var leg := Vector3.ZERO
		var knee := 0.02
		var elbow := 0.05
		var shoulder := 0.0
		match mode:
			&"walk":
				leg.x = stride * 0.38 * speed
				knee = -maxf(0, stride) * 0.48 * speed
				shoulder = -stride * 0.27 * speed
			&"ride":
				leg = Vector3(1.13, 0, side * 0.29)
				knee = -1.14
				shoulder = 0.58
				elbow = 0.28
			&"climb":
				leg = Vector3(0.23 + stride * 0.07, 0, side * 0.07)
				knee = -0.33
				elbow = 0.02
			&"swim":
				leg.x = 0.35 + stride * 0.16
				knee = -0.22
				shoulder = 0.55
				elbow = 0.35
			&"air":
				leg.x = 0.20 + side * 0.08
				knee = -0.28
		_legs[i].rotation = _legs[i].rotation.lerp(leg, blend)
		_knees[i].rotation.x = lerpf(_knees[i].rotation.x, knee, blend)
		_forearms[i].rotation = _forearms[i].rotation.lerp(Vector3(elbow, 0, 0), blend)
		if is_instance_valid(_wrists[i]):
			_wrists[i].rotation = _wrists[i].rotation.lerp(Vector3.ZERO, blend)
		_ankles[i].rotation.x = -0.04 if mode == &"ride" else 0.0
		# Existing PlayerVisual owns grip/beam shoulder elevation. Other states
		# get a cosmetic arm swing or reins pose after its physics update.
		if mode != &"climb" and player.beam.raise <= 0.01:
			visual._arms[i].rotation.x = lerpf(visual._arms[i].rotation.x, shoulder, blend)

## Cosmetic IK for real imported grips; the gameplay grip and capsule never move.
func pose_hand(side: int, goal: Transform3D) -> float:
	if side < 0 or side >= _forearms.size() or not is_instance_valid(_wrists[side]) or not is_instance_valid(_grips[side]): return 0.0
	var shoulder := visual._arms[side]
	var forearm := _forearms[side]
	var wrist := _wrists[side]
	var grip := _grips[side]
	var wrist_target := goal.origin - goal.basis * grip.position
	var pole := visual.global_basis * Vector3(-0.8 if side == 0 else 0.8, -0.6, 0.3)
	var solved := TwoBoneIK.solve(shoulder.global_position, wrist_target, forearm.position.length(), wrist.position.length(), pole)
	shoulder.global_basis = solved.upper
	forearm.global_basis = solved.lower
	wrist.global_basis = goal.basis
	return grip.global_position.distance_to(goal.origin)
