extends Node
## Visual smoke test for the Quadratus fight: the real arena scene (renderer, camera, HUD,
## debug overlays) with the scripted bot playing from Agro. Saves
## tests/output/quadratus_*.png at key moments. Run with tools/capture_screenshots.sh quadratus.

var scene: Node3D
var refs := {}
var bot: QuadratusBot
var taken := {}
var tick := 0
var _queue: Array[String] = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	scene = load("res://scenes/quadratus_arena.tscn").instantiate()
	add_child(scene)
	await get_tree().physics_frame
	refs = scene.refs
	if refs.input:
		(refs.input as Node).queue_free()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	bot = QuadratusBot.new()
	bot.use_horse = OS.get_environment("ON_FOOT") == ""
	scene.add_child(bot)
	bot.setup(refs.player, refs.quadratus, refs.encounter, refs.horse)
	var q: Quadratus = refs.quadratus
	q.attack_phase_changed.connect(_on_phase)
	q.foot_hit.connect(func(_leg: int) -> void:
		_overlay(true)
		_want("quadratus_04_arrow_hits_sole_overlay"))
	(refs.player as PlayerCharacter).sword.struck.connect(func(r: Dictionary) -> void:
		if r.get("accepted", false):
			_want("quadratus_09_weak_point_hit"))
	_overlay(false)


func _physics_process(_delta: float) -> void:
	tick += 1
	var q: Quadratus = refs.quadratus
	var p: PlayerCharacter = refs.player
	var cam: PlayerCamera = refs.camera
	var on_body := q.region_of(p) != &"" or p.is_climbing()
	if p.bow.is_aiming():
		# Look where the archer aims (over the shoulder).
		var d := -p.actions.view_basis.z
		cam.yaw = lerp_angle(cam.yaw, atan2(-d.x, -d.z), 0.2)
		cam.pitch = lerpf(cam.pitch, clampf(asin(d.y), -0.5, 0.3) - 0.12, 0.2)
		p.actions.focus_held = false
	elif on_body:
		p.actions.focus_held = false
		var to := q.get_focus_point() - p.global_position
		cam.yaw = lerp_angle(cam.yaw, atan2(-to.x, -to.z) + 0.6, 0.05)
		cam.pitch = lerpf(cam.pitch, -0.4, 0.05)
	else:
		p.actions.focus_held = true
	if tick == 60:
		_want("quadratus_01_entrance_dormant")
	if p.is_riding() and q.encounter == Quadratus.Encounter.COMBAT and tick > 600 and not p.bow.is_aiming():
		_want("quadratus_02_riding_in")
	if p.is_riding() and p.bow.state == PlayerBow.State.AIM:
		_overlay(true)
		_want("quadratus_03_aiming_from_agro_overlay")
	if q.buckle == Quadratus.Buckle.KNEEL and q.buckle_t > 1.0 and not on_body:
		_overlay(false)
		_want("quadratus_05_kneeling_body_lowered")
	match bot.phase:
		QuadratusBot.Phase.CLIMB:
			if bot.phase_time > 0.6:
				_want("quadratus_06_climbing_thigh")
		QuadratusBot.Phase.ON_BACK:
			if bot.phase_time > 0.5 and q.region_of(p) == &"rump":
				_want("quadratus_07_on_the_rump")
			if q.region_of(p) in [&"neck", &"head"]:
				_want("quadratus_10_towards_the_crown")
		QuadratusBot.Phase.STRIKE:
			if p.sword.state == PlayerSword.State.CHARGE and p.sword.charge > 0.6:
				_want("quadratus_08_charging_on_rump" if q.rump.state != WeakPoint.State.DESTROYED else "quadratus_11_charging_on_crown")
	if q.intent.kind == Quadratus.SHAKE_BODY and q._shake > 0.5 and on_body:
		_want("quadratus_12_shake_body")
	if q.encounter == Quadratus.Encounter.DEFEATED and q.encounter_time > 6.0:
		_overlay(false)
		_want("quadratus_13_defeated_lying_down")
	if q.encounter == Quadratus.Encounter.DEFEATED and q.encounter_time > 8.0 and taken.has("quadratus_13_defeated_lying_down"):
		_overlay(true)
		_want("quadratus_14_defeated_overlay")
	if taken.has("quadratus_14_defeated_overlay") or tick > 60 * 400:
		get_tree().quit()
	if not _queue.is_empty():
		var name: String = _queue.pop_front()
		_shot(name)
	if tick % 120 == 0 and taken.has("quadratus_04_arrow_hits_sole_overlay") and not taken.has("quadratus_05b_kneel_overlay") and q.buckle == Quadratus.Buckle.KNEEL and q.buckle_t > 2.0:
		_overlay(true)
		_want("quadratus_05b_kneel_overlay")
	elif tick % 120 == 60 and q.buckle == Quadratus.Buckle.NONE and not p.bow.is_aiming():
		_overlay(false)


func _on_phase(a: ColossusAttack) -> void:
	if a.phase == ColossusAttack.Phase.TELEGRAPH:
		_want("quadratus_%s_telegraph" % a.kind)
	elif a.phase == ColossusAttack.Phase.ACTIVE:
		_want("quadratus_%s_active" % a.kind)


func _overlay(on: bool) -> void:
	(refs.quadratus as Quadratus).debug_draw.visible = on
	(refs.bow_draw as BowDebugDraw).visible = on


func _want(name: String) -> void:
	if taken.has(name) or name in _queue:
		return
	taken[name] = true
	_queue.append(name)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://tests/output/%s.png" % name))
	var q: Quadratus = refs.quadratus
	var p: PlayerCharacter = refs.player
	print("shot %s  t=%.1f  %s | P %s HP %.0f st %.0f region %s | %s" % [name, tick / 60.0, q.debug_text().split("\n")[0], p.get_display_state(), p.health, p.stamina.value, q.region_of(p), QuadratusBot.Phase.keys()[bot.phase]])
