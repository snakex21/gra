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
var _surface_pose: TravelerSurfacePose
var _draw_hand: MeshInstance3D
var _closed_right_hand: MeshInstance3D
var _string_contact: Node3D
var bow_string_fit_clamped := false
var archery_torso_basis := Basis.IDENTITY
var _head: Node3D
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
	_head = _part("Traveler_Head")
	_draw_hand = _wrists[1].find_child("Traveler_BowDrawHand_1*", true, false) as MeshInstance3D
	_closed_right_hand = _wrists[1].find_child("Traveler_Hand_1*", true, false) as MeshInstance3D
	_string_contact = _wrists[1].find_child("BowStringContact_1*", true, false) as Node3D
	set_bow_draw_hand(false)
	current_lod = level
	if not is_instance_valid(_surface_pose):
		_surface_pose = TravelerSurfacePose.new()
		_surface_pose.name = "TravelerSurfacePose"
		add_child(_surface_pose)
	# Invalid edited-source contracts report inactive + an error; there is no
	# silent rigid fallback. Their imported bind geometry may remain visible.
	_surface_pose.configure(self, model)

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
	if mode == &"ride" and player.riding.is_active(): visual.update_visual(player, 1.0)
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
				leg = Vector3.ZERO
				knee = .02
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
		# A transition sample has one reproducible leg pose, independent of how
		# many render frames preceded it. Other modes keep their existing smoothing.
		_legs[i].rotation = leg if mode == &"ride" else _legs[i].rotation.lerp(leg, blend)
		_knees[i].rotation = Vector3(knee, 0, 0) if mode == &"ride" else _knees[i].rotation.lerp(Vector3(knee, 0, 0), blend)
		_forearms[i].rotation = _forearms[i].rotation.lerp(Vector3(elbow, 0, 0), blend)
		if is_instance_valid(_wrists[i]):
			_wrists[i].rotation = _wrists[i].rotation.lerp(Vector3.ZERO, blend)
		_ankles[i].rotation = Vector3(-0.04 if mode == &"ride" else 0.0, 0, 0)
		# Existing PlayerVisual owns grip/beam shoulder elevation. Other states
		# get a cosmetic arm swing or reins pose after its physics update.
		if mode != &"climb" and player.beam.raise <= 0.01:
			visual._arms[i].rotation.x = lerpf(visual._arms[i].rotation.x, shoulder, blend)

	if mode == &"ride" and player.riding.is_active() and is_instance_valid(player.riding.horse):
		_pose_seated_legs()

## Legs solve to the fitted stirrup footbed, in the moving body-bone frame.
## Only imported render joints change. Physics root, capsule and locomotion stay put.
func _pose_seated_legs() -> void:
	var body := player.riding.horse.body_transform()
	var weight := 1.0
	var swing := 0.0
	var approach_side := -1.0
	if player.riding.phase == PlayerRiding.Phase.MOUNTING:
		weight = smoothstep(.15, .60, player.riding._t)
		swing = sin(PI * player.riding._t)
		approach_side = -1.0 if player.riding._from_local.x <= 0.0 else 1.0
	elif player.riding.phase == PlayerRiding.Phase.DISMOUNTING:
		weight = 1.0 - smoothstep(.40, .85, player.riding._t)
		swing = sin(PI * player.riding._t)
		approach_side = -1.0 if player.riding._to_local.x <= 0.0 else 1.0
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		# The far leg travels over the seat during the existing mount arc, rather
		# than blending down through the horse's barrel. The near leg stays outside.
		var far_leg_swing := swing if side != approach_side else 0.0
		var leg_weight := weight
		if side != approach_side:
			if player.riding.phase == PlayerRiding.Phase.MOUNTING:
				leg_weight = smoothstep(.48, .63, player.riding._t)
			elif player.riding.phase == PlayerRiding.Phase.DISMOUNTING:
				leg_weight = 1.0 - smoothstep(.40, .60, player.riding._t)
		var ankle_target := body * Vector3(side * .435, .100 + .62 * far_leg_swing, -.030)
		var pole := body.basis * Vector3(side * .8, .8 * far_leg_swing, -1.0)
		var solved := TwoBoneIK.solve(_legs[i].global_position, ankle_target, _knees[i].position.length(), _ankles[i].position.length(), pole)
		_legs[i].global_basis = Basis(_legs[i].global_basis.get_rotation_quaternion().slerp((solved.upper as Basis).get_rotation_quaternion(), leg_weight))
		_knees[i].global_basis = Basis(_knees[i].global_basis.get_rotation_quaternion().slerp((solved.lower as Basis).get_rotation_quaternion(), leg_weight))
		_ankles[i].global_basis = Basis(_ankles[i].global_basis.get_rotation_quaternion().slerp(body.basis.get_rotation_quaternion(), leg_weight))

## Free hands can be claimed by the equipment adapter after its weapon decision.
func pose_rein_hand(side: int) -> float:
	if not player.riding.is_active() or not is_instance_valid(player.riding.horse): return 0.0
	if player.riding.cosmetic_seat_weight() < .999: return 0.0
	var body := player.riding.horse.body_transform()
	return pose_hand(side, Transform3D(body.basis, body * Vector3(-.24 if side == 0 else .24, .71, -.32)))

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

## Side-on upper body opens the draw line without turning the seated pelvis.
## The head faces the target; both shoulder roots and the cosmetic torso use
## one girdle frame. Legs, gameplay root and hip-mounted equipment stay put.
func pose_bow_body(weight: float, draw_frame: Basis) -> void:
	archery_torso_basis = Basis.IDENTITY
	weight = clampf(weight, 0.0, 1.0)
	if weight > 0.0:
		var local_draw := visual.global_basis.inverse() * draw_frame
		archery_torso_basis = Basis.IDENTITY.slerp(local_draw * Basis(Vector3.UP, -.90), weight)
		if is_instance_valid(_head): _head.basis = Basis.IDENTITY.slerp(local_draw, weight)
	elif is_instance_valid(_head): _head.basis = Basis.IDENTITY
	for side in 2:
		var shoulder_half_width := lerpf(.30, .21, weight)
		var shoulder_height := lerpf(.40, .405, weight)
		visual._arms[side].position = archery_torso_basis * Vector3(-shoulder_half_width if side == 0 else shoulder_half_width, shoulder_height, 0)


## Separate string hook, preserving the closed sword/rein grip and its marker.
func set_bow_draw_hand(active: bool, release_open := 0.0) -> void:
	if is_instance_valid(_draw_hand):
		_draw_hand.visible = active
		var shape := _draw_hand.find_blend_shape_by_name("ReleaseOpen")
		if shape >= 0: _draw_hand.set_blend_shape_value(shape, clampf(release_open, 0.0, 1.0))
		for name in ["StringUpperX", "StringUpperY", "StringLowerX", "StringLowerY"]:
			var fit_shape := _draw_hand.find_blend_shape_by_name(name)
			if fit_shape >= 0: _draw_hand.set_blend_shape_value(fit_shape, 0.0)
	if is_instance_valid(_closed_right_hand): _closed_right_hand.visible = not active

## Adapt finger pads to the actual V-shaped string in wrist coordinates.
## Four small authored morphs preserve palm and nock, without moving equipment.
func fit_bow_string(top: Vector3, bottom: Vector3) -> void:
	if not is_instance_valid(_draw_hand) or not is_instance_valid(_string_contact): return
	bow_string_fit_clamped = false
	for pair in [["Upper", top], ["Lower", bottom]]:
		var point := _wrists[1].to_local(pair[1])
		var vertical := maxf(absf(point.z - _string_contact.position.z), .001)
		var slopes := Vector2(point.x - _string_contact.position.x, point.y - _string_contact.position.y) / vertical
		for axis in 2:
			var shape := _draw_hand.find_blend_shape_by_name("String" + pair[0] + ("X" if axis == 0 else "Y"))
			if shape >= 0: _draw_hand.set_blend_shape_value(shape, clampf(slopes[axis], -2.0, 2.0))
			bow_string_fit_clamped = bow_string_fit_clamped or absf(slopes[axis]) > 2.0

## Solve elbow to the string contact with forearm and hand as a single segment.
## This keeps a neutral wrist instead of twisting a hilt fist around the arrow.
func pose_bow_draw(nock: Transform3D, weight := 1.0) -> float:
	if not is_instance_valid(_string_contact): return INF
	var shoulder := visual._arms[1]
	var forearm := _forearms[1]
	var wrist := _wrists[1]
	var contact_axis := wrist.position + _string_contact.position
	# Backward pull and an outward right-arm bend form one anatomical plane.
	# The cheek anchor stays on this same side; neither elbow nor wrist is
	# teleported independently of the two fixed segment lengths.
	var pole := nock.basis.z + nock.basis.y * 0.10 + (visual.global_basis * archery_torso_basis).x * 0.15
	var solved := TwoBoneIK.solve(shoulder.global_position, nock.origin, forearm.position.length(), contact_axis.length(), pole)
	var forward: Vector3 = (solved.end - solved.mid).normalized()
	var up := nock.basis.y - forward * nock.basis.y.dot(forward)
	if up.length_squared() < 0.0001:
		up = visual.global_basis.y - forward * visual.global_basis.y.dot(forward)
	if up.length_squared() < 0.0001:
		up = visual.global_basis.x - forward * visual.global_basis.x.dot(forward)
	up = up.normalized()
	var local_forward := contact_axis.normalized()
	var local_up := Vector3.FORWARD - local_forward * Vector3.FORWARD.dot(local_forward)
	local_up = local_up.normalized()
	var hand_basis := Basis(up, forward.cross(up), forward) * Basis(local_up, local_forward.cross(local_up), local_forward).transposed()
	# Blend only during the post-release return; full hook is an exact contact.
	var old_forearm := forearm.global_basis
	var old_wrist := wrist.global_basis
	shoulder.global_basis = shoulder.global_basis.slerp(solved.upper, weight)
	forearm.global_basis = old_forearm.slerp(hand_basis, weight)
	wrist.global_basis = old_wrist.slerp(hand_basis, weight)
	return _string_contact.global_position.distance_to(nock.origin)

## Flush cosmetic skin after all existing shoulder/wrist IK, including captures.
func update_surface_pose() -> void:
	if is_instance_valid(_surface_pose): _surface_pose.update_surface_pose()

func surface_pose_report() -> Dictionary:
	if is_instance_valid(_surface_pose): return _surface_pose.last_report.duplicate(true)
	return {"active":false,"error":"Cosmetic surface driver absent"}

func set_surface_girdle_lift(amount: float) -> void:
	if is_instance_valid(_surface_pose): _surface_pose.girdle_lift_m = clampf(amount,0.0,.04)

func set_surface_logical_elbow_pole(enabled: bool) -> void:
	if is_instance_valid(_surface_pose): _surface_pose.use_logical_elbow_pole = enabled
