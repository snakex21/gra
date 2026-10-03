extends Node3D
const RigScript := preload("res://src/vr/pc_vr_rig.gd")
const DT := 1.0 / 60.0
var failures := 0
var checks := 0
var rig: PcVrRig
var actor: PlayerCharacter
var wall: StaticBody3D
var deadline := Time.get_ticks_msec() + 60000

func _process(_delta: float) -> void:
	if Time.get_ticks_msec() > deadline:
		push_error("VR climbing fixture watchdog")
		get_tree().quit(1)

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func advance(overrides := {}, tracking := true) -> void:
	await get_tree().physics_frame
	var frame := {"left_tracked": true, "right_tracked": true}
	frame.merge(overrides, true)
	rig.step(DT, frame, tracking)

func ready_rig() -> void:
	await advance()
	await advance()
	await advance({"confirm": true})
	for i in 8: await advance()

func _ready() -> void:
	Sfx.enabled = false
	Fx.enabled = false
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.3, .2, .13)
	TerrainKit.box(self, Vector3(0, -.5, 0), Vector3(30, 1, 30), material)
	wall = StaticBody3D.new()
	wall.collision_layer = Layers.WORLD
	wall.position = Vector3(0, 3, -.7)
	var patch := ClimbPatch.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4, 6, .4)
	patch.shape = shape
	wall.add_child(patch)
	add_child(wall)
	actor = PlayerCharacter.new()
	add_child(actor)
	actor.position = Vector3(0, .9, 0)
	actor.visual.hide()
	rig = RigScript.new()
	rig.auto_step = false
	add_child(rig)
	rig.setup(actor)
	rig.head.position.y = 1.7
	rig.left.position = Vector3(-.2, 1.4, -.4)
	rig.right.position = Vector3(.2, 1.4, -.4)
	await ready_rig()
	check(rig.ready_for_motion, "Could not ready real player fixture")
	var before := actor.global_position
	await advance({"left_grip": .8})
	check(rig.climbing.anchors[0] != null and rig.climbing.anchors[1] == null, "Left squeeze did not acquire nearby real ClimbPatch")
	check(actor.global_position.distance_to(before) < .001, "Acquiring a grip jerked the body/origin")
	var raw_head := rig.head.transform
	var world_hand := rig.left.global_position
	for i in 25:
		rig.left.position.y -= .01
		await advance({"left_grip": .8})
	check(actor.global_position.y > before.y + .24 and rig.head.transform == raw_head, "Pulling the raw hand down failed to lift the capsule or modified tracked head")
	check(rig.left.global_position.distance_to(world_hand) < .005, "Climbing hand did not stay at its material anchor")
	check(rig.climbing.stamina < 100 and rig.climbing.stamina > 0, "Climbing did not consume bounded stamina")
	var basis_before := rig.global_basis
	await advance({"left_grip": .8, "turn": 1.0, "move": Vector2(0, 1)})
	await advance({"turn": 1.0, "move": Vector2(0, 1)})
	check(rig.global_basis.is_equal_approx(basis_before), "Releasing grip triggered a stale held snap-turn stick")
	await advance()
	await advance({"left_grip": .8})
	await advance({"left_grip": .8, "right_grip": .8})
	check(rig.climbing.anchors[0] != null and rig.climbing.anchors[1] != null, "Second hand did not acquire independent contact")
	await advance({"right_grip": .8})
	check(rig.climbing.anchors[0] == null and rig.climbing.anchors[1] != null, "Releasing left hand also lost right hand")
	before = actor.global_position
	wall.position.y += .02
	await advance({"right_grip": .8})
	check(actor.global_position.y > before.y + .015, "Moving support failed to carry its local hand anchor")
	await advance({"right_grip": .8, "right_tracked": false})
	check(not rig.climbing.is_climbing(), "Lost hand tracking retained an anchor")
	for i in 3: await advance({"right_grip": .8})
	check(not rig.climbing.is_climbing(), "Recovered held grip reacquired without release")
	await advance()
	await advance({"right_grip": .8})
	check(rig.climbing.anchors[1] != null, "Fresh right squeeze could not regrab after tracking recovery")
	await advance({"right_grip": .8}, false)
	check(not rig.ready_for_motion and not rig.climbing.is_climbing(), "Head loss failed to suspend and clear hand anchors")
	await ready_rig()
	await advance({"left_grip": .8})
	check(rig.climbing.anchors[0] != null, "Fresh left grab unavailable after ready")
	await advance({"left_grip": .8, "pause": true})
	check(rig.paused and not rig.climbing.is_climbing(), "Pause retained a grip constraint")
	await advance({"left_grip": .8})
	await advance({"left_grip": .8, "pause": true})
	await advance({"left_grip": .8})
	check(not rig.climbing.is_climbing(), "Pause recovery reused a held squeeze")
	await advance()
	await advance({"left_grip": .8})
	check(rig.climbing.is_climbing(), "Release/fresh squeeze did not rearm after pause")
	before = actor.global_position
	rig.left.position.y += 1.0
	await advance({"left_grip": .8})
	check(not rig.climbing.is_climbing() and actor.global_position.distance_to(before) < .03, "Jumped hand pose dragged the camera")
	rig.left.position = Vector3(-.2, 1.4, -.4)
	# A normal stone collision has no grippable patch, despite being in palm range.
	patch.disabled = true
	var stone := CollisionShape3D.new()
	stone.shape = shape
	wall.add_child(stone)
	await advance()
	await advance({"left_grip": .8})
	check(not rig.climbing.is_climbing(), "Plain stone became grippable")
	stone.queue_free()
	patch.disabled = false
	await advance()
	await advance({"left_grip": .8})
	check(rig.climbing.is_climbing(), "Restored fur unavailable to fresh hand grab")
	rig.climbing.stamina = .001
	await advance({"left_grip": .8})
	check(not rig.climbing.is_climbing(), "Exhausted grip did not release")
	# Even with the head blocked in a different wall, an old hand anchor must
	# clear and the released capsule must fall; blackout is not a hover state.
	TerrainKit.box(self, Vector3(.65, 4, 0), Vector3(.4, 8, 6), material)
	rig.climbing.stamina = 100
	actor.global_position = Vector3(0, 2, 0)
	rig.global_position = actor.global_position - Vector3.UP * .9 + Vector3.UP * rig.height_offset
	await advance()
	await advance({"left_grip": .8})
	check(rig.climbing.is_climbing(), "Blocked-head regression could not establish hanging grip")
	rig.head.position.x = .5
	await advance({"left_grip": .8, "left_tracked": false})
	check(not rig.climbing.is_climbing(), "Blocked head retained a lost controller anchor")
	for i in 90: await advance()
	check(actor.is_on_floor() and absf(actor.global_position.y - .9) < .03 and rig.blackout > .9, "Head-wall blackout made a released airborne capsule hover")
	rig.head.position.x = 0
	rig.recenter()
	# Release into air: gravity must still run with no safe floor at current feet.
	rig.climbing.release_all()
	actor.global_position.y = 3
	rig.global_position.y = 3 - .9 + rig.height_offset
	actor.velocity = Vector3.ZERO
	for i in 90: await advance()
	check(actor.is_on_floor() and absf(actor.global_position.y - .9) < .03, "Released climber hovered instead of falling to the real floor")
	check(actor.global_transform.is_finite() and rig.global_transform.is_finite(), "Climbing contaminated transforms")
	await sword_and_fur()
	await actual_valus_contact()
	if DisplayServer.get_name() != "headless":
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	print("PC_VR_CLIMBING: %d failure(s); %d checks; real colliders with simulated poses" % [failures, checks])
	get_tree().quit(1 if failures else 0)


func sword_and_fur() -> void:
	rig.climbing.release_all()
	rig.climbing.stamina = 100
	rig.recenter()
	rig.left.position = Vector3(-.2, 1.4, -.4)
	rig.hands.recall_sword()
	var sword_body := rig.hands.sword as RigidBody3D
	check(sword_body != null and sword_body.top_level, "Sword is not an independent world-space physics object")
	if sword_body == null:
		return
	rig.right.global_transform = sword_body.global_transform
	await advance()
	var raw_hand := rig.right.transform
	await advance({"right_grip": .8})
	check(rig.hands.sword_controller.held_hand == 1 and rig.right.transform == raw_hand, "Fresh right squeeze failed to pick up sword or rewrote a tracked pose")
	await advance({"left_grip": .8, "right_grip": .8})
	check(rig.climbing.anchors[0] != null and rig.climbing.anchors[1] == null, "Sword hand also acquired fur or prevented the other hand from climbing")
	# Moving a held weapon into the fur can stop/drop the sword, but that same
	# squeeze must never acquire a second, incompatible hand constraint.
	rig.right.position = Vector3(.2, 1.4, -.4)
	rig.right.basis = Basis.IDENTITY
	await advance({"left_grip": .8, "right_grip": .8})
	check(rig.climbing.anchors[1] == null, "Held or collision-dropped sword reused its squeeze to grab fur")
	await advance()
	rig.recenter()
	rig.right.global_transform = sword_body.global_transform
	await advance()
	await advance({"right_grip": .8})
	check(rig.hands.sword_controller.held_hand == 1, "Sword could not be picked up again after a deliberate recall")
	await advance({"right_grip": .8, "pause": true})
	check(rig.paused and rig.hands.sword_controller.held_hand == -1 and sword_body.freeze, "Pause did not return sword safely beside player")
	await advance({"right_grip": .8})
	await advance({"right_grip": .8, "pause": true})
	check(not rig.paused and rig.hands.sword_controller.held_hand == -1, "Unpause automatically glued sword to a still-squeezed hand")
	rig.right.global_transform = sword_body.global_transform
	await advance()
	await advance({"right_grip": .8})
	check(rig.hands.sword_controller.held_hand == 1, "Fresh release and squeeze could not rearm sword after pause")
	await advance({"right_grip": .8}, false)
	check(not rig.ready_for_motion and rig.hands.sword_controller.held_hand == -1 and sword_body.global_transform.is_finite(), "Lost head tracking retained weapon or contaminated its recalled transform")
	await advance({"right_grip": .8})
	await advance({"right_grip": .8})
	await advance({"right_grip": .8, "confirm": true})
	check(rig.ready_for_motion and rig.hands.sword_controller.held_hand == -1, "Tracking recovery automatically reattached sword without a fresh squeeze")
	await advance()


func actual_valus_contact() -> void:
	var scene := preload("res://src/vr/pc_vr_scene.gd").new()
	scene.simulated = true
	scene.with_art = false
	add_child(scene)
	scene.set_physics_process(false)
	for i in 3: await get_tree().physics_frame
	var preview_rig := scene.rig
	var player := scene.world.player()
	var boss := scene.world.colossus() as Valus
	var patch: ClimbPatch
	for segment in boss.segments:
		if segment.bone_name == &"shin_l":
			for child in segment.get_children():
				if child is ClimbPatch:
					patch = child
	check(patch != null, "Actual Valus has no left calf fur patch")
	if patch != null:
		# Exact synchronized surface and player size, rather than an assumed
		# location in the skeleton's unposed rest frame.
		var surface := patch.global_transform * Vector3(0, -.55, (patch.shape as CapsuleShape3D).radius)
		var normal := (patch.global_basis * Vector3.BACK).normalized()
		var xf: Transform3D = scene.world.arenas[&"valus"].xf
		var center := surface + normal * .6
		center.y = (xf * Vector3(0, .9, 0)).y
		player.global_position = center
		preview_rig.global_position = center - Vector3.UP * .9
		preview_rig.head.position = Vector3(0, 1.65, 0)
		preview_rig.climbing.stamina = 100
		for input in [{}, {}, {"confirm": true}, {}]:
			await get_tree().physics_frame
			var frame := {"left_tracked": true, "right_tracked": true}
			frame.merge(input, true)
			preview_rig.step(DT, frame, true)
		preview_rig.left.global_position = surface + normal * .10
		await get_tree().physics_frame
		preview_rig.step(DT, {"left_tracked": true, "right_tracked": true, "left_grip": .8}, true)
		var anchor: SurfaceAnchor = preview_rig.climbing.anchors[0]
		check(anchor != null and anchor.shape == patch and boss.owns_body(anchor.body), "VR palm could not grip actual reachable Valus calf")
		var before := player.global_position
		for i in 10:
			preview_rig.left.position.y -= .01
			await get_tree().physics_frame
			preview_rig.step(DT, {"left_tracked": true, "right_tracked": true, "left_grip": .8}, true)
		check(player.global_position.y > before.y + .095, "Real Valus calf grip did not lift the player")
	if DisplayServer.get_name() != "headless":
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	scene.free()
	await get_tree().physics_frame
