extends Node
## Visual smoke test for Agro: runs the real agro_test scene (renderer, camera, HUD, debug
## overlay) with a scripted rider driving PlayerActions, and saves screenshots to
## tests/output/agro_*.png. Run with tools/capture_screenshots.sh agro.

var scene: Node3D
var player: PlayerCharacter
var cam: PlayerCamera
var horse: Horse
var points := {}
var _hud: PlayerHud


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	scene = load("res://scenes/agro_test.tscn").instantiate()
	add_child(scene)
	await _wait(2)
	for n in scene.get_children():
		if n is FlatInputSource:
			n.queue_free()
	player = scene.players[0]
	horse = scene.horse
	points = scene.points
	for n in scene.find_children("*", "PlayerCamera", true, false):
		cam = n
	for n in scene.find_children("*", "PlayerHud", true, false):
		_hud = n
	horse.debug_draw.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _run()
	get_tree().quit()


func _run() -> void:
	var a := player.actions
	_view(PI * 0.8, -0.25)
	await _wait(30)
	await _shot("agro_01_approach")
	a.press_interact()
	await _wait(18)
	await _shot("agro_02_mounting")
	await _wait(40)
	# Through the rocks at a trot (avoidance rays in the overlay).
	_view(0.0, -0.3)
	a.move = Vector2(0, 1)
	a.press_jump()
	await _wait(150)
	await _shot("agro_03_trot_rocks")
	await _wait(120)
	await _shot("agro_04_rock_field")
	# Open ground: gallop, a long turn, and the camera looking away from the travel direction.
	_ride_from("flat")
	a.move = Vector2(0, 1)
	await _wait(10)
	a.press_jump()
	await _wait(20)
	a.press_jump()
	await _wait(300)
	await _shot("agro_05_gallop")
	a.move = Vector2(0.6, 0.8)
	await _wait(80)
	await _shot("agro_06_gallop_turn_lean")
	# From here on: horse-relative steering (F6), so the camera can look anywhere.
	player.riding.steer_relative = true
	a.move = Vector2(0, 1)
	cam.yaw += PI * 0.5
	await _wait(60)
	await _shot("agro_07_camera_looks_away")
	# The wall: galloping at it, the rider keeps pushing.
	_ride_from("wall")
	a.move = Vector2(0, 1)
	await _wait(10)
	a.press_jump()
	await _wait(20)
	a.press_jump()
	await _wait(150)
	await _shot("agro_08_gallop_at_wall")
	await _wait(600)
	_view(PI * 0.35, -0.2)
	await _wait(30)
	await _shot("agro_09_stopped_at_wall")
	# The cliff edge.
	_ride_from("cliff")
	a.move = Vector2(0, 1)
	await _wait(10)
	a.press_jump()
	await _wait(20)
	a.press_jump()
	await _wait(400)
	_view(PI * 0.4, -0.35)
	await _wait(30)
	await _shot("agro_10_stopped_at_cliff")
	# The course: ramp, bumps and the step down at a trot.
	_ride_from("course")
	a.move = Vector2(0, 1)
	await _wait(10)
	a.press_jump()
	await _wait(380)
	_view(PI * 0.3, -0.25)
	await _wait(20)
	await _shot("agro_11_ramp")
	await _wait(420)
	_view(PI * 0.45, -0.2)
	await _wait(20)
	await _shot("agro_12_bumps_step")
	# Stop, get off, send the horse away and call it back.
	a.move = Vector2.ZERO
	a.grab_held = true
	await _wait(150)
	a.grab_held = false
	a.press_interact()
	await _wait(12)
	await _shot("agro_13_dismount")
	await _wait(60)
	horse.teleport(Vector3(40, 0, 30), PI)
	player.global_position = Vector3(40, 0.95, 8)
	player.reset_physics_interpolation()
	await _wait(5)
	_view(PI, -0.15)
	a.press_call()
	await _wait(160)
	await _shot("agro_14_called_horse_coming")
	await _wait(700)
	await _shot("agro_15_horse_arrived")


## Mounted: puts the horse at a named start point (the rider stays in the saddle).
func _ride_from(name: String) -> void:
	var sp: Array = points[name]
	player.actions.move = Vector2.ZERO
	horse.teleport(sp[0], sp[1])
	_view(0.0, -0.3)


func _view(yaw: float, pitch: float) -> void:
	cam.yaw = horse.controller.yaw + yaw if player.is_riding() else yaw
	cam.pitch = pitch
	player.actions.view_basis = Basis.from_euler(Vector3(0, cam.yaw, 0))


func _wait(ticks: int) -> void:
	for i in ticks:
		await get_tree().physics_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://tests/output/%s.png" % name))
	print("shot %s  player=%s camera=%s | %s" % [name, player.get_display_state(), cam.debug_state, horse.debug_text().replace("\n", " | ")])
