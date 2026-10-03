extends Node3D
## Actual imported grip markers, metre-sized hands and a native render; no HMD claim.
const HandsScript := preload("res://src/vr/pc_vr_hands.gd")
var failures := 0
var checks := 0
var deadline := Time.get_ticks_msec() + 60000

func _process(_delta: float) -> void:
	if Time.get_ticks_msec() > deadline:
		push_error("PCVR hands watchdog expired")
		get_tree().quit(1)

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png("res://tests/output/" + label + ".png") == OK, "Could not save portable VR hands capture")

func colliders(root: Node) -> int:
	var result := 1 if root is CollisionObject3D or root is CollisionShape3D else 0
	for child in root.get_children(): result += colliders(child)
	return result

func controller(label: String, at: Vector3, angles: Vector3) -> XRController3D:
	var result := XRController3D.new()
	result.name = label
	add_child(result)
	result.position = at
	result.rotation = angles
	return result

func _ready() -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.20, 0.25, 0.28)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.89, 0.90, 0.91)
	environment.ambient_light_energy = 0.65
	env.environment = environment
	add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -35, 0)
	light.light_energy = 1.2
	light.shadow_enabled = false
	add_child(light)
	var head := XRCamera3D.new()
	head.near = 0.04
	head.fov = 78
	head.current = true
	add_child(head)
	head.position = Vector3(0, 1.7, 0)
	head.rotation.x = -0.25
	var left := controller("Left", Vector3(-0.27, 1.23, -0.49), Vector3(-0.35, -0.12, -0.22))
	var right := controller("Right", Vector3(0.27, 1.22, -0.48), Vector3(-0.55, 0.03, 0.12))
	var preview_grip := right.global_position
	var actor := CharacterBody3D.new()
	add_child(actor)
	actor.position.y = 0.9
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	collision.shape = capsule
	actor.add_child(collision)
	var hands := HandsScript.new()
	add_child(hands)
	hands.setup(head, left, right)
	hands.setup_sword(actor)
	check(hands.sword is RigidBody3D and hands.sword.get_parent() != hands.right_hand and hands.sword_controller.held_hand == -1, "Sword remained permanently parented to a hand")
	right.global_position = hands.sword.global_position + Vector3.UP * 0.05
	var poses := [head.global_transform, left.global_transform, right.global_transform]
	await get_tree().physics_frame
	hands.step_sword(1.0 / 60.0, {"left_tracked": true, "right_tracked": true}, actor, true)
	await get_tree().physics_frame
	hands.step_sword(1.0 / 60.0, {"left_tracked": true, "right_tracked": true, "right_grip": 0.8}, actor, true)
	hands.set_grips(false, false)
	check(not hands.left_hand.visible and not hands.right_hand.visible, "Setup showed untracked hands")
	hands.update_hands(true, true)
	check(hands.left_hand.visible and hands.right_hand.visible and hands.sword != null, "Tracked hands/sword were not built")
	check(head.global_transform == poses[0] and left.global_transform == poses[1] and right.global_transform == poses[2], "Hands changed real head/controller poses")
	check(hands.left_hand.transform == Transform3D.IDENTITY and hands.right_hand.transform == Transform3D.IDENTITY and hands.sword_controller.model.transform == Transform3D.IDENTITY and hands.sword.global_transform.is_equal_approx(right.global_transform), "Visual grip/weapon origin contains an invented reach or scale offset")
	var grip := hands.sword.find_child("Grip*", true, false) as Node3D
	var tip := hands.sword.find_child("BladeTip*", true, false) as Node3D
	check(grip != null and tip != null, "Sword v4 imported grip/tip markers were not retained")
	check(grip.global_position.distance_to(right.global_position) < 0.0001, "Sword grip does not agree with the actual right-controller grip")
	check(absf(tip.global_position.distance_to(grip.global_position) - 1.09) < 0.002 and (tip.global_position - grip.global_position).normalized().dot(right.global_basis.y) > 0.999, "Sword has incorrect world metre scale or blade axis")
	var left_mesh := hands.left_hand.get_node("PalmAndFingers") as MeshInstance3D
	var right_mesh := hands.right_hand.get_node("PalmAndFingers") as MeshInstance3D
	check(left_mesh.mesh is ArrayMesh and right_mesh.mesh is ArrayMesh and left_mesh.mesh.get_surface_count() == 3 and right_mesh.mesh.get_surface_count() == 3, "Hands are not batched opaque procedural meshes")
	check(right_mesh.mesh.get_aabb().size.x > 0.060 and right_mesh.mesh.get_aabb().size.x < 0.11 and right_mesh.mesh.get_aabb().size.y > 0.09 and right_mesh.mesh.get_aabb().size.y < 0.15, "Hand proportions are outside adult metre-sized palm/wrist bounds")
	var triangles := (left_mesh.mesh.get_faces().size() + right_mesh.mesh.get_faces().size() + hands.left_forearm.mesh.get_faces().size() + hands.right_forearm.mesh.get_faces().size()) / 3
	check(triangles <= 3600, "Procedural hands/forearms exceeded the lightweight triangle budget")
	for mesh in [left_mesh, right_mesh, hands.left_forearm, hands.right_forearm]:
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			check(material != null and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "Hand geometry has transparent overdraw")
	check(colliders(hands.left_hand) + colliders(hands.right_hand) == 0, "Cosmetic hands introduced gameplay colliders")
	for i in 10: hands.update_hands(true, true)
	check(head.global_transform == poses[0] and left.global_transform == poses[1] and right.global_transform == poses[2], "Repeated visual updates moved tracked poses")
	for arm in [hands.left_forearm, hands.right_forearm]:
		check(arm.global_transform.is_finite() and arm.global_transform.basis.y.length() <= 1.001, "Forearm render transform is invalid or artificially extended")
	hands.set_grips(true, true)
	check(hands.sword.visible and left_mesh.mesh != null, "Cosmetic fur pose unexpectedly hid the independent physical sword")
	hands.set_grips(false, false)
	check(hands.sword.visible, "Cosmetic pose removed the physical sword")
	hands.update_hands(false, true)
	check(not hands.left_hand.visible and hands.right_hand.visible, "Left tracking loss hid the wrong hand")
	hands.update_hands(true, false)
	hands.step_sword(1.0 / 60.0, {"left_tracked": true, "right_tracked": false, "right_grip": 0.8}, actor, true)
	check(hands.left_hand.visible and not hands.right_hand.visible and hands.sword_controller.held_hand == -1 and hands.sword_controller.parked, "Right tracking loss retained a sword attachment")
	hands.update_hands(true, true)
	right.global_position = hands.sword.global_position + Vector3.UP * 0.05
	hands.step_sword(1.0 / 60.0, {"left_tracked": true, "right_tracked": true}, actor, true)
	hands.step_sword(1.0 / 60.0, {"left_tracked": true, "right_tracked": true, "right_grip": 0.8}, actor, true)
	hands.set_grips(false, false)
	right.global_position = preview_grip
	hands.step_sword(1.0 / 60.0, {"left_tracked": true, "right_tracked": true, "right_grip": 0.8}, actor, true)
	hands.sync_sword(1.0 / 60.0)
	hands.update_hands(true, true)
	await capture("pc_vr_hands_first_person")
	head.position = Vector3(0.32, 1.32, -0.09)
	head.look_at(right.global_position + Vector3(0, -0.015, 0.015), Vector3.UP)
	hands.update_hands(true, true)
	await capture("pc_vr_hands_detail")
	var other_left := controller("OtherLeft", Vector3(-3, 1.2, -0.5), Vector3.ZERO)
	var other_right := controller("OtherRight", Vector3(-3, 1.2, -0.5), Vector3.ZERO)
	var other := HandsScript.new()
	add_child(other)
	other.setup(head, other_left, other_right)
	check(other.left_hand.get_node("PalmAndFingers").mesh == left_mesh.mesh and other.right_forearm.mesh == hands.right_forearm.mesh, "Repeated setup duplicated cached meshes")
	other.free()
	check(other_left.get_child_count() == 0 and other_right.get_child_count() == 0, "Component teardown retained controller-child visuals")
	if DisplayServer.get_name() != "headless":
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	hands.free()
	check(left.get_child_count() == 0 and right.get_child_count() == 0, "Hands teardown retained scene/controller attachments")
	print("PC_VR_HANDS: %d failure(s); %d checks; %d procedural triangles; simulated poses, no HMD claim" % [failures, checks, triangles])
	get_tree().quit(1 if failures else 0)
