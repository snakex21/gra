extends Node
## Visual smoke test: runs the real sandbox (renderer, camera, HUD) with a scripted
## "autopilot" driving PlayerActions, and saves screenshots to tests/output/.
##
## Run (needs a display; in CI/containers use xvfb-run):
##   xvfb-run -a godot --rendering-method gl_compatibility --fixed-fps 60 res://tests/capture_demo.tscn

var sandbox: Node3D
var player: PlayerCharacter
var cam: PlayerCamera
var colossus: Colossus
var _shots := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	sandbox = load("res://scenes/sandbox.tscn").instantiate()
	add_child(sandbox)
	await _wait(2)
	# Take over input: remove the flat input sources, drive actions directly.
	for n in sandbox.get_children():
		if n is FlatInputSource:
			n.queue_free()
	player = sandbox.players[0]
	cam = sandbox.cameras[0]
	colossus = sandbox.colossus
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.grip_released.connect(func(reason: StringName) -> void:
		print("  t=%.2f released: %s at y=%.1f stamina=%.0f" % [Engine.get_physics_frames() / 60.0, reason, player.global_position.y, player.stamina.value]))
	player.mantled.connect(func() -> void: print("  t=%.2f mantled at y=%.1f" % [Engine.get_physics_frames() / 60.0, player.global_position.y]))
	await _run()
	get_tree().quit()


func _run() -> void:
	var hud: PlayerHud = null
	for n in sandbox.find_children("*", "PlayerHud", true, false):
		hud = n
	_hud = hud
	var g := colossus as GreyboxHumanoid
	g.debug_draw.visible = true
	g.debug_override = &"manual"
	# Colossus just before the test course (ramp starts at z = -16), walking -Z.
	g.teleport(Vector3(26, 0, -10), 0.0)
	_watch_from(Vector3(38, 0.95, -12))
	g.debug_desired_speed = 1.4
	await _drive(Vector2.ZERO, 150)
	await _shot("01_walk_steps_overlay")
	await _drive(Vector2.ZERO, 250)
	_watch_from(Vector3(37, 0.95, -22))
	await _drive(Vector2.ZERO, 1)
	await _shot("02_ramp")
	await _drive(Vector2.ZERO, 500)
	_watch_from(Vector3(36, 4.5, -36))
	await _drive(Vector2.ZERO, 1)
	await _shot("03_bumps")
	await _drive(Vector2.ZERO, 300)
	_watch_from(Vector3(36, 2.7, -52))
	await _drive(Vector2.ZERO, 60)
	await _shot("04_step_down")
	g.debug_desired_speed = 0.0
	g.debug_desired_turn = 0.3
	await _drive(Vector2.ZERO, 240)
	await _shot("05_turn_in_place")
	# A/B: classic cycle + foot IK on the same bumps.
	g.debug_desired_turn = 0.0
	g.set_locomotion_mode(GreyboxHumanoid.LocomotionMode.ANIM_IK)
	g.teleport(Vector3(26, 3.53, -33), 0.0)
	g.debug_desired_speed = 1.4
	await _drive(Vector2.ZERO, 200)
	_watch_from(Vector3(35, 4.5, -38))
	await _drive(Vector2.ZERO, 60)
	await _shot("06_anim_ik_bumps")
	g.set_locomotion_mode(GreyboxHumanoid.LocomotionMode.PROCEDURAL)
	g.teleport(Vector3(26, 3.53, -33), 0.0)
	await _drive(Vector2.ZERO, 200)
	_watch_from(Vector3(35, 4.5, -38))
	await _drive(Vector2.ZERO, 60)
	await _shot("07_procedural_bumps")
	# Player on a stepping leg.
	g.teleport(Vector3(0, 0, -20), 0.0)
	g.debug_desired_speed = 1.2
	await _drive(Vector2.ZERO, 60)
	var seg := _segment(&"shin_l")
	for attempt in 4:
		if player.is_climbing():
			break
		while not g.loco.legs[0].is_planted():
			await _drive(Vector2.ZERO, 1)
		player.global_position = seg.global_transform * Vector3(0, -1.6, 1.25)
		player.velocity = Vector3.ZERO
		player.facing = -colossus.global_basis.z
		player.reset_physics_interpolation()
		cam.snap_behind_player()
		player.actions.grab_held = true
		await _drive(Vector2.ZERO, 3)
	await _drive(Vector2(0, 1), 140)
	await _shot("08_climbing_stepping_leg")
	# Player standing on the shoulder of the walking colossus.
	var chest := _segment(&"chest")
	player.actions.grab_held = false
	await _drive(Vector2.ZERO, 2)
	player.global_position = chest.global_transform * Vector3(1.9, 3.8, 0.0)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	cam.yaw = colossus.rotation.y + PI * 0.6
	cam.pitch = -0.3
	g.debug_desired_turn = 0.15
	await _drive(Vector2.ZERO, 180)
	await _shot("09_standing_on_walking_colossus")


## Puts the (idle) player at a viewpoint and points the camera at the colossus' legs.
func _watch_from(p: Vector3) -> void:
	player.global_position = p
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	player.actions.focus_held = false
	var to := colossus.global_position + Vector3.UP * 3.0 - p
	cam.yaw = atan2(-to.x, -to.z)
	cam.pitch = atan2(to.y, Vector2(to.x, to.z).length())


var _hud: PlayerHud
var _taken := {}


func _drive(move: Vector2, ticks: int) -> void:
	for i in ticks:
		player.actions.move = move
		player.actions.view_basis = cam.global_basis
		await get_tree().physics_frame


func _wait(ticks: int) -> void:
	for i in ticks:
		await get_tree().physics_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "res://tests/output/%s.png" % name
	img.save_png(ProjectSettings.globalize_path(path))
	_shots += 1
	_taken[name.substr(0, 2)] = true
	if _hud:
		print("---- %s HUD ----\n%s" % [name, _hud._label.text])
	var g := colossus as GreyboxHumanoid
	print("shot %s  player=%s balance=%.2f | %s | slip max %.4f m/s" % [name, player.get_display_state(), player.balance.value, g.locomotion_debug_text().replace("\n", " | "), g.foot_stats.slip_max])


func _segment(bone: StringName) -> BodySegment:
	for s in colossus.segments:
		if s.bone_name == bone:
			return s
	return null
