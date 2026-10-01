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
var qbot: QuadratusBot
var gbot: GaiusBot
var bow_world := {}
var bow_log := []


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
	if scenario == "quadratus" or scenario == "quadratus_horse":
		_setup_quadratus()
		return
	if scenario == "bow":
		_setup_bow()
		return
	if scenario == "gaius":
		_setup_gaius()
		return
	if scenario == "art":
		_setup_art()
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


## The whole Quadratus fight played by the scripted bot (on foot or from Agro): arrows,
## the foot reaction, climbing, both weak points, defeat.
func _setup_quadratus() -> void:
	for c in get_children():
		c.queue_free()
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	var arena := Node3D.new()
	add_child(arena)
	boss = QuadratusArena.build_encounter(arena)
	qbot = QuadratusBot.new()
	qbot.use_horse = scenario == "quadratus_horse"
	arena.add_child(qbot)
	qbot.setup(boss.player, boss.quadratus, boss.encounter, boss.horse)


func _quadratus_tick() -> void:
	if qbot.phase != QuadratusBot.Phase.DONE and tick < 60 * 400:
		return
	var p: PlayerCharacter = boss.player
	var q: Quadratus = boss.quadratus
	var h: Horse = boss.horse
	var arrows := ArrowSystem.of(p)
	var li: Dictionary = arrows.last_impact
	var data := {
		"frames": Engine.get_process_frames(),
		"won": 1 if qbot.result.get("won", false) else 0,
		"tick": tick,
		"player": [p.global_position.x, p.global_position.y, p.global_position.z],
		"boss": [q.global_position.x, q.global_position.z, q.loco.yaw, q.loco.body_pitch, q.loco.body_roll],
		"horse": [h.global_position.x, h.global_position.z],
		"weak_points": [q.rump.health, q.crown.health],
		"foot_hits": q.stats.foot_hits,
		"shots": arrows.shots,
		"impact": [li.point.x, li.point.y, li.point.z] if not li.is_empty() else [0, 0, 0],
		"hits": q.stats.hits_on_player,
		"strikes": qbot.stats.strikes,
		"steps": q.loco.step_count,
		"stamina": p.stamina.value,
		"health": p.health,
	}
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	get_tree().quit()


## Bow only: three shots (weak, half, full draw) at fixed times with a fixed aim, then a
## shot from a galloping Agro; every arrow's impact point and flight time is recorded.
func _setup_bow() -> void:
	var arena := Node3D.new()
	add_child(arena)
	TerrainKit.box(arena, Vector3(0, 3, -60), Vector3(30, 6, 1), StandardMaterial3D.new())
	player = PlayerCharacter.new()
	add_child(player)
	player.global_position = Vector3(0, 0.95, 0)
	player.set_weapon(PlayerCharacter.Weapon.BOW)
	player.actions.view_basis = Basis.looking_at(Vector3(0, 0.08, -1).normalized())
	horse = Horse.new()
	add_child(horse)
	horse.teleport(Vector3(30, 0, 40), PI)
	camera = PlayerCamera.new()
	camera.player = player
	add_child(camera)
	ArrowSystem.of(player).impact.connect(func(info: Dictionary) -> void:
		var pt: Vector3 = info.point
		bow_log.append_array([pt.x, pt.y, pt.z, info.flight_time]))


func _bow_tick() -> void:
	var a := player.actions
	# Shots on foot: hold 0.25 s / 0.5 s / 1.2 s.
	for sh in [[20, 35], [120, 150], [240, 312]]:
		if tick == sh[0]:
			a.attack_held = true
		if tick == sh[1]:
			a.attack_held = false
	match tick:
		400:
			player.global_position = Vector3(30, 0.95, 42)
			player.reset_physics_interpolation()
			player.set_weapon(PlayerCharacter.Weapon.SWORD)
		405:
			a.press_interact()
		460:
			a.view_basis = Basis.looking_at(Vector3(0, 0, -1))
			a.move = Vector2(0, 1)
			a.press_jump()
		500:
			a.press_jump()
			a.move = Vector2.ZERO
			player.set_weapon(PlayerCharacter.Weapon.BOW)
		520:
			a.view_basis = Basis.looking_at(Vector3(-1, 0.05, -0.4).normalized())
			a.attack_held = true
		600:
			a.attack_held = false
	if tick == 900:
		var data := {
			"frames": Engine.get_process_frames(),
			"impacts": bow_log,
			"horse": [horse.global_position.x, horse.global_position.z, horse.controller.yaw],
			"player": [player.global_position.x, player.global_position.y, player.global_position.z],
		}
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(data))
		f.close()
		get_tree().quit()


## The whole Gaius fight played by the scripted bot (slams, the blade, the arm, the
## helmet, the weak point).
func _setup_gaius() -> void:
	for c in get_children():
		c.queue_free()
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	var arena := Node3D.new()
	add_child(arena)
	boss = GaiusArena.build_encounter(arena)
	gbot = GaiusBot.new()
	arena.add_child(gbot)
	gbot.setup(boss.player, boss.gaius, boss.encounter)


func _gaius_tick() -> void:
	if gbot.phase != ValusBot.Phase.DONE and tick < 60 * 400:
		return
	var p: PlayerCharacter = boss.player
	var g: Gaius = boss.gaius
	var data := {
		"frames": Engine.get_process_frames(),
		"won": 1 if gbot.result.get("won", false) else 0,
		"tick": tick,
		"player": [p.global_position.x, p.global_position.y, p.global_position.z],
		"boss": [g.global_position.x, g.global_position.z, g.loco.yaw],
		"slam": [g.slam_point.x, g.slam_point.z],
		"weak_point": g.weak_point.health,
		"helmet": g.helmet.hits,
		"slams": g.stats.attacks.get(Gaius.SWORD_SLAM, 0),
		"hits": g.stats.hits_on_player,
		"strikes": gbot.stats.strikes,
		"steps": g.loco.step_count,
		"stamina": p.stamina.value,
		"health": p.health,
	}
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	get_tree().quit()


## Valus walking and turning in its arena, with or without the art layer (--art).
func _setup_art() -> void:
	for c in get_children():
		c.queue_free()
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	var arena := Node3D.new()
	add_child(arena)
	boss = ValusArena.build_encounter(arena, false, 7, "--art" in OS.get_cmdline_user_args())
	var v: Valus = boss.valus
	v.debug_override = &"manual"
	v.debug_desired_speed = 1.2
	v.debug_desired_turn = 0.1


func _art_tick() -> void:
	if tick < 60 * 8:
		return
	var v: Valus = boss.valus
	var feet := []
	for leg in v.loco.legs:
		feet.append_array([leg.plant_pos.x, leg.plant_pos.z])
	var data := {"frames": Engine.get_process_frames(), "pos": [v.global_position.x, v.global_position.y, v.global_position.z], "yaw": v.loco.yaw, "feet": feet, "steps": v.loco.step_count}
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	get_tree().quit()


func _physics_process(_delta: float) -> void:
	tick += 1
	if scenario == "art":
		_art_tick()
		return
	if scenario == "gaius":
		_gaius_tick()
		return
	if scenario == "quadratus" or scenario == "quadratus_horse":
		_quadratus_tick()
		return
	if scenario == "bow":
		_bow_tick()
		return
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
