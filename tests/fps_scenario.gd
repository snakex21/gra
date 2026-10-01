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
## "colossus" (default) or "horse".
var scenario := "colossus"
var horse: Horse
var boss: Dictionary = {}
var bot: ValusBot


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
		elif arg.begins_with("--scenario="):
			scenario = arg.trim_prefix("--scenario=")
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
	if scenario == "horse":
		_setup_horse()
		return
	if scenario == "boss":
		_setup_boss()
		return
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


## Mount, kick to a gallop on the arena course, turn, rein in, dismount. The camera is
## part of the run (it reads the rider's position every rendered frame).
func _setup_horse() -> void:
	var arena := Node3D.new()
	add_child(arena)
	var points := AgroArena.build(arena)
	horse = Horse.new()
	add_child(horse)
	var sp: Array = points.course
	horse.teleport(sp[0], sp[1])
	player = PlayerCharacter.new()
	add_child(player)
	player.global_position = (sp[0] as Vector3) + Vector3(-1.4, 0.95, 0.2)
	camera = PlayerCamera.new()
	camera.player = player
	add_child(camera)


func _horse_tick() -> void:
	var a := player.actions
	match tick:
		5:
			a.press_interact()
		60:
			a.view_basis = Basis.IDENTITY
			a.move = Vector2(0, 1)
			a.press_jump()
		90, 150:
			a.press_jump()
		420:
			a.move = Vector2(0.8, 0.6)
		600:
			a.move = Vector2(-0.5, 0.85)
		720:
			a.move = Vector2.ZERO
			a.grab_held = true
		900:
			a.grab_held = false
			a.press_interact()
	if tick == 1000:
		var feet := []
		for leg in horse.gait_planner.legs:
			feet.append_array([leg.foot_pos.x, leg.foot_pos.y, leg.foot_pos.z])
		var body := horse.body_transform().origin
		var data := {
			"frames": Engine.get_process_frames(),
			"horse": [horse.global_position.x, horse.global_position.y, horse.global_position.z],
			"yaw": horse.controller.yaw,
			"speed": horse.controller.speed,
			"body": [body.x, body.y, body.z],
			"feet": feet,
			"steps": horse.gait_planner.step_count,
			"player": [player.global_position.x, player.global_position.y, player.global_position.z],
			"riding": 1 if player.is_riding() else 0,
		}
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(data))
		f.close()
		get_tree().quit()


## The whole Valus fight played by the scripted bot (attacks, shakes, weak point,
## defeat) with the camera running every rendered frame.
func _setup_boss() -> void:
	# The ground node created above is not needed: the arena has its own.
	for c in get_children():
		c.queue_free()
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	var arena := Node3D.new()
	add_child(arena)
	boss = ValusArena.build_encounter(arena)
	bot = ValusBot.new()
	arena.add_child(bot)
	bot.setup(boss.player, boss.valus, boss.encounter)


func _boss_tick() -> void:
	if bot.phase != ValusBot.Phase.DONE and tick < 60 * 400:
		return
	var p: PlayerCharacter = boss.player
	var s: Valus = boss.valus
	var h: Horse = boss.horse
	var data := {
		"frames": Engine.get_process_frames(),
		"won": 1 if bot.result.get("won", false) else 0,
		"tick": tick,
		"player": [p.global_position.x, p.global_position.y, p.global_position.z],
		"boss": [s.global_position.x, s.global_position.z, s.loco.yaw],
		"horse": [h.global_position.x, h.global_position.z],
		"weak_point": s.weak_point.health,
		"attacks": s.stats.attacks.get(Valus.STOMP, 0) * 100 + s.stats.attacks.get(Valus.ARM_SWEEP, 0),
		"hits": s.stats.hits_on_player,
		"strikes": bot.stats.strikes,
		"steps": s.loco.step_count,
		"stamina": p.stamina.value,
		"health": p.health,
	}
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	get_tree().quit()


func _physics_process(_delta: float) -> void:
	tick += 1
	if scenario == "horse":
		_horse_tick()
		return
	if scenario == "boss":
		_boss_tick()
		return
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
