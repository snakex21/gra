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
	colossus.debug_override = &"frozen"
	await _wait(30)

	# 1) Approach on foot: "near colossus" framing.
	var seg := _segment(&"shin_l")
	var back := colossus.global_basis.z
	player.global_position = seg.global_transform * Vector3(0, -2.2, 0) + back * 9.0
	player.facing = -back
	player.reset_physics_interpolation()
	cam.snap_behind_player()
	cam.pitch = -0.05
	await _drive(Vector2(0, 0.5), 60)
	await _shot("01_approach_scale")

	# 2) Grab the leg and climb a walking colossus (camera leads along the route).
	await _drive(Vector2(0, 1), 50)
	player.actions.grab_held = true
	colossus.debug_override = &"walk"
	await _drive(Vector2(0, 1), 200)
	await _shot("02_climb_lookahead")

	# 3) Pull up onto the shoulders, stand on the walking colossus.
	var mantled := [false]
	player.mantled.connect(func() -> void: mantled[0] = true)
	for i in 400:
		if mantled[0]:
			break
		await _drive(Vector2(0, 1), 1)
	player.actions.grab_held = false
	await _drive(Vector2.ZERO, 20)
	# Step out to the middle of the shoulder.
	var chest := _segment(&"chest")
	var to_side := (chest.global_transform * Vector3(1.9, 2.8, 0.0)) - player.global_position
	to_side.y = 0.0
	player.actions.view_basis = Basis.looking_at(to_side.normalized())
	for i in 30:
		if (chest.global_transform.affine_inverse() * player.global_position).x > 1.8:
			break
		player.actions.move = Vector2(0, 0.6)
		player.actions.view_basis = Basis.looking_at(to_side.normalized())
		await get_tree().physics_frame
	player.actions.move = Vector2.ZERO
	cam.yaw = colossus.rotation.y + PI * 0.5
	cam.pitch = -0.35
	await _drive(Vector2.ZERO, 90)
	await _shot("03_standing_on_walking_colossus")

	# 4) Shake: balance drains continuously.
	colossus.debug_override = &"shake"
	colossus._think_left = 0.0
	for i in 200:
		await _drive(Vector2.ZERO, 1)
		if player.balance.state >= Balance.State.UNSTABLE and not _taken.has("04"):
			await _drive(Vector2.ZERO, 10)
			await _shot("04_unstable")
		if player.balance.state >= Balance.State.STUMBLE:
			break
	await _shot("05_slipping")
	# 5) Save yourself: grab.
	player.actions.grab_held = true
	await _drive(Vector2.ZERO, 40)
	await _shot("06_rescue_grab")
	# 6) Let go while it shakes: thrown off, hard landing.
	player.actions.grab_held = false
	for i in 240:
		await _drive(Vector2.ZERO, 1)
		if player.state == PlayerCharacter.State.GROUND and player.last_impact_tier != FallImpact.Tier.NONE and not player.is_on_colossus():
			break
	await _drive(Vector2.ZERO, 15)
	await _shot("07_landed_after_throw")
	# 7) Back on the ground: frame the colossus (focus).
	colossus.debug_override = &""
	await _drive(Vector2.ZERO, 120)
	player.actions.focus_held = true
	await _drive(Vector2.ZERO, 90)
	await _shot("08_focus_colossus")
	player.actions.focus_held = false


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
	print("shot %s  state=%s balance=%.2f y=%.1f stamina=%.0f health=%.0f intent=%s camera=%s %.1f m" % [name, player.get_display_state(), player.balance.value, player.global_position.y, player.stamina.value, player.health, colossus.intent.kind, cam.debug_state, cam.get_distance()])


func _segment(bone: StringName) -> BodySegment:
	for s in colossus.segments:
		if s.bone_name == bone:
			return s
	return null
