extends Node3D
## Simulated poses exercise real CharacterBody collision and XR origin invariants.
## These checks make no headset/runtime/device compatibility claim.
const RigScript := preload("res://src/vr/pc_vr_rig.gd")
const DT := 1.0 / 60.0
var failures := 0
var cases: Array[String] = []
var deadline := Time.get_ticks_msec() + 60000
var actor: CharacterBody3D
var rig: PcVrRig

func _process(_delta: float) -> void:
	if Time.get_ticks_msec() > deadline:
		push_error("PCVR rig watchdog expired after a stopped coroutine/runtime error")
		get_tree().quit(1)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func xz(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z)

func frame(overrides: Dictionary = {}) -> Dictionary:
	var result := {"move": Vector2.ZERO, "turn": 0.0, "confirm": false, "back": false,
		"recenter": false, "pause": false, "left_tracked": true, "right_tracked": true}
	result.merge(overrides, true)
	return result

func advance(overrides: Dictionary = {}, tracked := true, delta := DT) -> void:
	await get_tree().physics_frame
	rig.step(delta, frame(overrides), tracked)

func neutral(count := 2) -> void:
	for i in count: await advance()

func confirm_ready() -> void:
	await neutral()
	await advance({"confirm": true})
	await neutral()
	check(rig.ready_for_motion and not rig.paused, "Released/fresh tracked confirmation could not ready the rig")

func collider(size: Vector3, at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.position = at

func _ready() -> void:
	collider(Vector3(30, 1, 30), Vector3(0, -.5, 0))
	collider(Vector3(.5, 3, 8), Vector3(2.5, 1.5, 0))
	actor = CharacterBody3D.new()
	actor.collision_layer = Layers.PLAYER
	actor.collision_mask = Layers.SOLID
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .3
	capsule.height = 1.8
	collision.shape = capsule
	actor.add_child(collision)
	add_child(actor)
	actor.position = Vector3(0, .9, 0)
	rig = RigScript.new()
	rig.auto_step = false
	add_child(rig)
	rig.setup(actor)
	rig.head.position = Vector3(0, 1.65, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(rig.head is XRCamera3D and rig.left is XRController3D and rig.right is XRController3D and rig.head.get_parent() == rig, "Rig did not create core XR nodes under the tracking origin")
	check(not rig.ready_for_motion and not actor.is_physics_processing(), "Rig started moving without explicit confirmation")
	var start := actor.global_position
	for i in 3: await advance({"confirm": true, "move": Vector2(1, 0)}, false)
	for i in 3: await advance({"confirm": true, "move": Vector2(1, 0)})
	check(not rig.ready_for_motion and actor.global_position == start, "Tracking recovery accepted stale held confirmation or moved before calibration")
	await confirm_ready()
	await neutral(15)
	check(actor.is_on_floor() and absf(actor.global_position.y - .9) < .015, "VR capsule did not settle on the actual collision floor")
	cases.append("core XR nodes, fail-closed readiness and actual floor")
	var origin_before := rig.global_transform
	rig.head.position.x = .5
	var head_before := rig.head.global_transform
	await advance()
	check(absf(actor.global_position.x - .5) < .01 and rig.global_transform.is_equal_approx(origin_before) and rig.head.global_transform.is_equal_approx(head_before), "Physical room-scale movement moved the tracking origin/head instead of only the collision capsule")
	var actor_before := actor.global_position
	var origin_position := rig.global_position
	var head_position := rig.head.global_position
	for i in 12: await advance({"move": Vector2(0, 1)})
	var movement := actor.global_position - actor_before
	check(movement.z < -.20 and absf(movement.x) < .005 and (rig.global_position - origin_position).distance_to(movement) < .001 and (rig.head.global_position - head_position).distance_to(movement) < .001, "Virtual forward walking did not shift actor/origin/head by identical actual displacement")
	actor_before = actor.global_position
	for i in 5: await advance({"move": Vector2(.1, .1), "turn": .2})
	check(xz(actor.global_position).distance_to(xz(actor_before)) < .001, "Input deadzone caused unintended walking")
	cases.append("physical versus virtual displacement and stick deadzone")
	await neutral()
	head_position = rig.head.global_position
	actor_before = actor.global_position
	var basis_before := rig.global_basis
	await advance({"turn": 1.0})
	var one_turn := rig.global_basis
	check(absf(basis_before.x.angle_to(one_turn.x) - PI / 6.0) < .001 and rig.head.global_position.distance_to(head_position) < .001 and xz(actor.global_position).distance_to(xz(actor_before)) < .001, "Snap turn was not exactly30deg about the tracked head, or orbited the body")
	for i in 5: await advance({"turn": 1.0})
	check(rig.global_basis.is_equal_approx(one_turn), "Held snap-turn stick repeated without neutral rearm")
	await advance({"turn": 0.0})
	await advance({"turn": -1.0})
	check(rig.global_basis.is_equal_approx(basis_before), "Neutral stick did not rearm the opposite snap turn")
	await neutral()
	basis_before = rig.global_basis
	await advance({"right_tracked": false, "turn": 1.0})
	for i in 3: await advance({"turn": 1.0})
	check(rig.global_basis.is_equal_approx(basis_before), "Recovered controller accepted a held deflected turn without neutral")
	await neutral()
	await advance({"turn": 1.0})
	check(not rig.global_basis.is_equal_approx(basis_before), "Recovered controller could not turn after deliberate neutral rearm")
	await neutral()
	await advance({"turn": -1.0})
	await neutral()
	cases.append("head-pivot snap30, hold/rearm and right-controller recovery")
	for i in 120: await advance({"move": Vector2(1, 0)})
	check(actor.global_position.x > 1.8 and actor.global_position.x < 1.97 and xz(rig.head.global_position).distance_to(xz(actor.global_position)) < .005, "Virtual walking crossed the actual wall or left camera/body displacement inconsistent")
	actor_before = actor.global_position
	origin_before = rig.global_transform
	rig.head.position.x += .45
	head_before = rig.head.global_transform
	for i in 12: await advance({"move": Vector2(1, 0)})
	check(xz(actor.global_position).distance_to(xz(actor_before)) < .01 and rig.global_transform.is_equal_approx(origin_before) and rig.head.global_transform.is_equal_approx(head_before) and rig.blackout > .9, "Physical head-wall penetration moved the camera backwards, crossed the wall, or failed to black out")
	var height := rig.head.position.y
	actor_before = actor.global_position
	check(rig.recenter() and actor.global_position == actor_before and absf(rig.head.position.y - height) < .001 and absf(rig.head.global_position.y - (actor.global_position.y - .9 + height)) < .001 and xz(rig.head.global_position).distance_to(xz(actor.global_position)) < .001, "Recenter moved world body or altered measured head height")
	await neutral(10)
	check(rig.blackout < .01, "Comfort blackout did not clear after deliberate safe recenter")
	cases.append("real wall collision, physical penetration fade and recenter invariants")
	await advance({"pause": true, "move": Vector2(0, 1), "turn": 1.0})
	actor_before = actor.global_position
	basis_before = rig.global_basis
	for i in 3: await advance({"pause": true, "move": Vector2(0, 1), "turn": 1.0})
	check(rig.paused and actor.global_position == actor_before and rig.global_basis.is_equal_approx(basis_before), "Held pause button resumed or virtual movement/turning ran while paused")
	await advance({"move": Vector2(0, 1)})
	await advance({"pause": true, "move": Vector2(0, 1)})
	await advance({"move": Vector2(0, 1)})
	check(not rig.paused and xz(actor.global_position).distance_to(xz(actor_before)) < .001, "Resume restarted a stale held movement stick before neutral")
	await neutral()
	await advance({"move": Vector2(0, 1)})
	check(xz(actor.global_position).distance_to(xz(actor_before)) > .01, "Neutral stick did not permit explicit walking after pause")
	await neutral()
	await advance({"confirm": true})
	actor_before = actor.global_position
	for i in 8: await advance({"confirm": true, "move": Vector2(0, 1)}, false)
	check(not rig.ready_for_motion and actor.global_position == actor_before and rig.blackout > .9, "Head tracking loss left locomotion enabled or did not darken view")
	for i in 3: await advance({"confirm": true, "move": Vector2(0, 1)})
	check(not rig.ready_for_motion and actor.global_position == actor_before, "Tracking recovery auto-resumed stale held confirmation")
	await advance({"right_tracked": false})
	await advance({"confirm": true})
	check(not rig.ready_for_motion, "Missing controller was treated as proof of button release")
	await confirm_ready()
	actor_before = actor.global_position
	await advance({"left_tracked": false, "move": Vector2(0, 1)})
	for i in 3: await advance({"move": Vector2(0, 1)})
	check(xz(actor.global_position).distance_to(xz(actor_before)) < .001, "Left controller recovery resumed a held movement stick without neutral")
	await neutral()
	await advance({"move": Vector2(0, 1)})
	check(xz(actor.global_position).distance_to(xz(actor_before)) > .01, "Recovered left controller did not walk after neutral rearm")
	cases.append("pause and tracking loss require fresh controls, never stale held resume")
	await neutral()
	actor_before = actor.global_position
	basis_before = rig.global_basis
	await advance({"move": Vector2(INF, NAN), "turn": NAN, "pause": "yes", "back": 1})
	check(actor.global_transform.is_finite() and rig.global_transform.is_finite() and xz(actor.global_position).distance_to(xz(actor_before)) < .001 and rig.global_basis.is_equal_approx(basis_before), "Malformed/nonfinite controls contaminated transforms or activated buttons")
	for bad_delta in [0.0, -1.0, NAN, INF]:
		await advance({"move": Vector2(0, 1)}, true, bad_delta)
	check(actor.global_position == actor_before, "Invalid delta moved the rig")
	await advance({"move": Vector2(1000000, 1000000)}, true, 1000000.0)
	check(actor.global_transform.is_finite() and rig.global_transform.is_finite() and actor.global_position.distance_to(actor_before) < .10, "Oversized finite controls/delta caused unbounded movement")
	var exits: Array[bool] = []
	rig.exit_requested.connect(func() -> void: exits.append(true))
	# A tracker can report orientation confidence with an unusable zero-height
	# position. Explicit tracked=true must not make that pose safe for locomotion.
	actor_before = actor.global_position
	var valid_height := rig.head.position.y
	rig.head.position.y = 0.0
	await advance({"move": Vector2(0, 1), "confirm": true, "back": true})
	check(not rig.ready_for_motion and actor.global_position == actor_before and rig.blackout >= .99 and exits.is_empty(), "Tracked zero-height pose moved/exited the rig or failed to suspend with immediate blackout")
	rig.head.position.y = valid_height
	await advance({"confirm": true})
	check(not rig.ready_for_motion and actor.global_position == actor_before, "Valid pose recovery resumed stale held confirmation")
	await confirm_ready()
	await advance({"back": true}, false)
	check(exits.is_empty() and not rig.ready_for_motion, "Back press during lost head tracking emitted an exit")
	await advance({"back": true})
	check(exits.is_empty() and not rig.ready_for_motion, "Tracking recovery consumed a stale held Back press")
	await confirm_ready()
	await advance({"back": true})
	await advance({"back": true})
	await advance()
	await advance({"back": true})
	check(exits.size() == 2, "Back exit did not use explicit press edges")
	cases.append("sanitized finite/bounded inputs, invalid delta, zero-height pose and tracked exit edges")
	if DisplayServer.get_name() != "headless":
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	print("PC_VR_RIG: %d failure(s); cases=%s; simulated poses, no HMD claim" % [failures, str(cases)])
	get_tree().quit(1 if failures else 0)
