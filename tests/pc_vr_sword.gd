extends Node3D
const SwordScript := preload("res://src/vr/pc_vr_sword.gd")
const DT := 1.0 / 60.0
var failures := 0
var checks := 0
var deadline := Time.get_ticks_msec() + 60000
var sword: Node3D
var head: XRCamera3D
var left: XRController3D
var right: XRController3D
var player: CharacterBody3D
var tracking_space: Node3D

func _process(_delta: float) -> void:
	if Time.get_ticks_msec() > deadline:
		push_error("PCVR sword watchdog expired")
		get_tree().quit(1)

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func tick(overrides := {}, ready := true) -> Dictionary:
	await get_tree().physics_frame
	var frame := {"left_tracked": true, "right_tracked": true, "left_grip": 0.0, "right_grip": 0.0}
	frame.merge(overrides, true)
	return sword.step(DT, frame, ready)

func reset_near_right() -> void:
	sword.recall(false)
	right.global_transform = Transform3D(Basis.IDENTITY, sword.sword_body.global_position + Vector3.UP * 0.05)
	await tick()
	await tick()
	await tick({"right_grip": 0.8})
	check(sword.held_hand == 1, "Fresh nearby right squeeze could not take physical hilt")

func collider(size: Vector3, at: Vector3) -> StaticBody3D:
	var result := StaticBody3D.new()
	result.collision_layer = Layers.WORLD
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	result.add_child(collision)
	add_child(result)
	result.position = at
	return result

func _ready() -> void:
	var floor_body := collider(Vector3(30, 1, 30), Vector3(0, -0.5, 0))
	var wall := collider(Vector3(5, 4, 0.1), Vector3(0, 2, -1.2))
	player = CharacterBody3D.new()
	player.collision_layer = Layers.PLAYER
	player.collision_mask = Layers.SOLID
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	shape.shape = capsule
	player.add_child(shape)
	add_child(player)
	player.position.y = 0.9
	tracking_space = Node3D.new()
	add_child(tracking_space)
	head = XRCamera3D.new()
	tracking_space.add_child(head)
	head.position.y = 1.7
	left = XRController3D.new()
	right = XRController3D.new()
	tracking_space.add_child(left)
	tracking_space.add_child(right)
	left.position = Vector3(-0.25, 1.3, -0.3)
	right.position = Vector3(0.25, 1.3, -0.3)
	sword = SwordScript.new()
	tracking_space.add_child(sword)
	sword.setup(head, left, right, player)
	# Newly placed static fixtures become authoritative in the first physics tick.
	await get_tree().physics_frame
	sword.sync_pose()
	check(sword.sword_body is RigidBody3D and sword.sword_body.top_level and sword.sword_body.get_child_count() >= 4, "Sword lacks independent rigid body, three convex colliders and imported model")
	check(sword.held_hand == -1 and sword.parked and sword.sword_body.visible and sword.sword_body.freeze, "Initial sword was auto-attached or missing at waist")
	check(sword.sword_body.global_position.distance_to(player.global_position) < 0.6 and sword.sword_body.global_basis.y.dot(Vector3.DOWN) > 0.999, "Initial hilt/blade does not park beside waist, blade downward")
	check(sword.sword_body.get_collision_exceptions().has(player) and sword.sword_body.continuous_cd, "Sword lacks player collision exception or thin-body CCD")
	var grip := sword.model.find_child("Grip*", true, false) as Node3D
	var tip := sword.model.find_child("BladeTip*", true, false) as Node3D
	check(grip != null and tip != null and grip.global_position.distance_to(sword.sword_body.global_position) < 0.0001 and absf(tip.global_position.distance_to(grip.global_position) - 1.09) < 0.002, "Imported physical grip/blade metre scale is incorrect")
	right.global_position = sword.sword_body.global_position + Vector3.UP * 0.05
	await tick({"right_grip": 0.8})
	check(sword.held_hand == -1, "Startup accepted stale held squeeze")
	await tick()
	right.global_position.x += 0.4
	await tick({"right_grip": 0.8})
	check(sword.held_hand == -1, "Sword pickup extended beyond physical18cm hilt reach")
	right.global_position = sword.sword_body.global_position + Vector3.UP * 0.05
	await tick({"right_grip": 0.8})
	check(sword.held_hand == -1, "Approaching hilt with stale held squeeze auto-picked up")
	await tick()
	var raw_hand := right.transform
	var acquired := await tick({"right_grip": 0.8})
	check(sword.held_hand == 1 and acquired.right_consumed and not acquired.left_consumed, "Sword did not arbitrate acquired squeeze against climbing")
	check(right.transform == raw_hand and sword.sword_body.global_transform.is_equal_approx(right.global_transform), "Held sword altered raw hand pose or does not use physical grip frame")
	await tick({"right_grip": 0.5})
	check(sword.held_hand == 1, "Grip hysteresis dropped sword between thresholds")
	var before: Vector3 = sword.sword_body.global_position
	right.position.x += 0.03
	await tick({"right_grip": 0.8})
	check(sword.sword_body.global_position.distance_to(right.global_position) < 0.004 and sword.sword_body.global_position.x > before.x + 0.025, "Held physical sword failed to follow clear tracked motion")
	sword.sync_pose(DT)
	var moving_release := await tick()
	check(moving_release.right_consumed and not sword.sword_body.freeze and sword.sword_body.linear_velocity.x > 1.2, "Additional stationary-origin sync erased measured hand velocity before release")
	await reset_near_right()
	left.global_transform = right.global_transform
	var transferred := await tick({"left_grip": 0.8})
	check(sword.held_hand == 0 and transferred.left_consumed and transferred.right_consumed, "Left pickup/handoff failed or release squeeze was not consumed")
	var dropped := await tick()
	check(sword.held_hand == -1 and not sword.parked and not sword.sword_body.freeze and dropped.left_consumed, "Released sword did not enable actual gravity or consume release frame")
	var drop_y: float = sword.sword_body.global_position.y
	var hit_bodies: Array[Node] = []
	sword.sword_body.contact_monitor = true
	sword.sword_body.max_contacts_reported = 8
	sword.sword_body.body_entered.connect(func(node: Node) -> void: hit_bodies.append(node))
	for i in 24: await tick()
	check(sword.sword_body.global_position.y < drop_y - 0.1, "Dropped rigid sword did not fall in actual physics")
	for i in 50: await tick()
	check(hit_bodies.has(floor_body), "Dropped sword passed through real floor instead of colliding")
	check(not sword.parked and sword.held_hand == -1, "Sword recalled before2seconds or auto-grabbed on landing")
	for i in 50: await tick()
	check(sword.parked and sword.held_hand == -1 and sword.sword_body.freeze and sword.recall_count > 0, "Lost sword did not recall to waist after2seconds")
	check(sword.sword_body.global_position.distance_to(player.global_position) < 0.6, "Timed recall returned sword far from current player")
	await reset_near_right()
	for i in 42:
		right.position.z -= 0.025
		await tick({"right_grip": 0.8})
	check(sword.held_hand == -1 and not sword.sword_body.freeze and sword.sword_body.global_position.z > -1.18, "Held sword teleported through real wall instead of dropping at contact")
	var blocked := await tick({"right_grip": 0.8})
	check(blocked.right_consumed, "Blocked drop reused held sword squeeze for climbing")
	await reset_near_right()
	sword.sword_body.linear_velocity = Vector3.ZERO
	await tick()
	sword.sword_body.linear_velocity = Vector3(0, 0, -4)
	for i in 26: await tick()
	check(hit_bodies.has(wall), "Free rigid sword did not collide with actual wall")
	await reset_near_right()
	await tick({"right_grip": 0.8, "right_tracked": false})
	check(sword.held_hand == -1 and sword.parked, "Hand tracking loss retained a sword attachment")
	right.global_position = sword.sword_body.global_position + Vector3.UP * 0.05
	for i in 3: await tick({"right_grip": 0.8})
	check(sword.held_hand == -1, "Recovered held squeeze auto-picked up recalled sword")
	await tick()
	await tick({"right_grip": 0.8})
	check(sword.held_hand == 1, "Fresh squeeze after tracking recovery could not reacquire")
	await tick({"right_grip": 0.8}, false)
	check(sword.parked and sword.held_hand == -1, "Pause/not-ready safety did not park sword")
	await tick({"right_grip": 0.8})
	check(sword.held_hand == -1, "Resume accepted held squeeze without neutral")
	var previous_direction: Basis = sword.sword_body.global_basis
	var head_pose := head.transform
	head.position.x = NAN
	await tick({"right_grip": 0.8}, false)
	check(sword.sword_body.global_transform.is_finite() and sword.sword_body.global_basis.is_equal_approx(previous_direction), "Invalid head pose contaminated waist recall instead of using last good direction")
	head.transform = head_pose
	var parked_at: Vector3 = sword.sword_body.global_position
	tracking_space.position.x += 0.5
	player.position.x += 0.5
	sword.sync_pose()
	check(sword.sword_body.global_position.distance_to(parked_at + Vector3.RIGHT * 0.5) < 0.001, "Parked sword did not follow current player after origin movement")
	await reset_near_right()
	await tick()
	var world_at: Vector3 = sword.sword_body.global_position
	tracking_space.position.x += 0.3
	player.position.x += 0.3
	check(sword.sword_body.global_position.distance_to(world_at) < 0.0001, "Free sword inherited moving rig/origin transform")
	sword.sword_body.freeze = true
	sword.sword_body.global_position = player.global_position + Vector3.RIGHT * 4.0
	await tick()
	check(sword.parked and sword.held_hand == -1 and sword.sword_body.global_position.distance_to(player.global_position) < 0.6, "Distance>3m recall failed or auto-attached")
	await reset_near_right()
	await tick()
	sword.sword_body.freeze = true
	sword.sword_body.global_position.y = -3.0
	await tick()
	check(sword.parked and sword.held_hand == -1 and sword.sword_body.global_transform.is_finite(), "Below-feet lost sword did not safely recall")
	var physical_body: RigidBody3D = sword.sword_body
	if DisplayServer.get_name() != "headless":
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	sword.free()
	check(not is_instance_valid(physical_body), "Sword teardown left its world rigid body alive")
	print("PC_VR_SWORD: %d failure(s); %d checks; real rigid physics with simulated hands" % [failures, checks])
	get_tree().quit(1 if failures else 0)
