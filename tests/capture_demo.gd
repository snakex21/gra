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
	colossus.debug_override = &"frozen"
	await _wait(30)
	await _shot("01_arena")

	# Walk up behind the left leg.
	var seg := _segment(&"shin_l")
	var back := colossus.global_basis.z
	player.global_position = seg.global_transform * Vector3(0, -2.2, 0) + back * 4.0
	player.facing = -back
	player.reset_physics_interpolation()
	cam.snap_behind_player()
	cam.pitch = -0.15
	await _drive(Vector2(0, 1), 40)
	player.actions.grab_held = true
	await _drive(Vector2(0, 0.0), 20)
	await _shot("02_grip_leg")

	colossus.debug_override = &"walk"
	await _drive(Vector2(0, 1), 150)
	await _shot("03_climbing_thigh_walking")
	await _drive(Vector2(0, 1), 150)
	await _shot("04_hips_spine")
	cam.pitch = 0.25
	await _drive(Vector2(0, 1), 90)
	await _shot("05_under_ledge_or_back")
	var mantled := [false]
	player.mantled.connect(func() -> void: mantled[0] = true)
	for i in 200:
		if mantled[0]:
			break
		await _drive(Vector2(0, 1), 1)
	player.actions.grab_held = false
	await _drive(Vector2.ZERO, 30)
	await _shot("06_after_mantle")
	# Look around from the shoulders while the colossus walks.
	player.actions.look_delta = Vector2(PI * 0.6, 0.25)
	await _drive(Vector2.ZERO, 30)
	await _shot("07_on_shoulders_view")

	# Turn towards the neck, grab it and get shaken.
	player.actions.look_delta = Vector2(-PI * 0.6, -0.1)
	await _drive(Vector2.ZERO, 10)
	var neck := _segment(&"neck").global_position
	var to_neck := PlayerCharacter._flat_dir(neck - player.global_position, Vector3.FORWARD)
	cam.yaw = atan2(-to_neck.x, -to_neck.z)
	for i in 90:
		player.actions.grab_held = true
		if player.is_climbing():
			break
		await _drive(Vector2(0, 0.6), 1)
	await _drive(Vector2(0, 1), 40)
	colossus.debug_override = &"shake"
	await _drive(Vector2.ZERO, 50)
	await _shot("08_shaken")
	await _drive(Vector2.ZERO, 60)
	await _shot("09_shaken_later")
	player.actions.focus_held = true
	player.actions.grab_held = false
	colossus.debug_override = &""
	await _drive(Vector2.ZERO, 70)
	await _shot("10_fall_focus")
	player.actions.focus_held = false


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
	print("shot %s  state=%s grip=%s y=%.1f stamina=%.0f shake=%.2f intent=%s" % [name, PlayerCharacter.State.keys()[player.state], player.grip.body.name if player.grip else "-", player.global_position.y, player.stamina.value, player.shake_level, colossus.intent.kind])


func _segment(bone: StringName) -> BodySegment:
	for s in colossus.segments:
		if s.bone_name == bone:
			return s
	return null
