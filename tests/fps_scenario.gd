extends Node
## Deterministic scenario for test_locomotion_is_independent_of_render_fps.
## Everything is scheduled by physics tick, never by rendered frame. Writes the final
## simulation state as JSON to --out=<path> and quits.

const END_TICK := 660

var colossus: GreyboxHumanoid
var player: PlayerCharacter
var camera: PlayerCamera
var tick := 0
var out_path := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
	process_physics_priority = 100  # after the colossus and the player
	var ground := StaticBody3D.new()
	ground.collision_layer = Layers.WORLD
	var gs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 2, 400)
	gs.shape = box
	gs.position = Vector3(0, -1, 0)
	ground.add_child(gs)
	add_child(ground)
	TerrainKit.build_course(self, Vector3(0, 0, -6))
	colossus = GreyboxHumanoid.new()
	colossus.debug_override = &"manual"
	add_child(colossus)
	player = PlayerCharacter.new()
	add_child(player)
	player.global_position = Vector3(0, 0.95, 20)
	camera = PlayerCamera.new()
	camera.player = player
	camera.focus_target = colossus
	add_child(camera)


func _physics_process(_delta: float) -> void:
	tick += 1
	match tick:
		10:
			colossus.debug_desired_speed = 1.4
		60:
			var shin: BodySegment
			for s in colossus.segments:
				if s.bone_name == &"shin_r":
					shin = s
			player.global_position = shin.global_transform * Vector3(0, -1.5, 1.25)
			player.velocity = Vector3.ZERO
			player.facing = -colossus.global_basis.z
			player.actions.grab_held = true
		120:
			player.actions.move = Vector2(0, 1)
		300:
			colossus.debug_desired_speed = 0.8
			colossus.debug_desired_turn = 0.3
		480:
			colossus.debug_desired_speed = 0.0
			colossus.debug_desired_turn = 0.0
	if tick >= 60:
		var d := PlayerCharacter._flat_dir(colossus.global_position - player.global_position, Vector3.FORWARD)
		player.actions.view_basis = Basis.looking_at(d)
	if tick == END_TICK:
		_write()
		get_tree().quit()


func _write() -> void:
	var l := colossus.loco.legs[0].plant_pos
	var r := colossus.loco.legs[1].plant_pos
	var g := player.grip.local_point if player.grip else Vector3.ZERO
	var data := {
		"frames": Engine.get_process_frames(),
		"colossus": [colossus.global_position.x, colossus.global_position.y, colossus.global_position.z],
		"yaw": colossus.loco.yaw,
		"feet": [l.x, l.y, l.z, r.x, r.y, r.z],
		"player": [player.global_position.x, player.global_position.y, player.global_position.z],
		"grip": [g.x, g.y, g.z],
		"steps": colossus.loco.step_count,
		"stamina": player.stamina.value,
		"climbing": 1 if player.is_climbing() else 0,
	}
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
