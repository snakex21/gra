extends Node
## Visual smoke test for the Gaius fight: the real arena scene (renderer, art layer,
## camera, HUD, overlays) with the scripted bot playing. Saves tests/output/gaius_*.png.
## Run with tools/capture_screenshots.sh gaius.

var scene: Node3D
var refs := {}
var bot: GaiusBot
var taken := {}
var tick := 0
var _queue: Array[String] = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	scene = load("res://scenes/gaius_arena.tscn").instantiate()
	add_child(scene)
	await get_tree().physics_frame
	refs = scene.refs
	if refs.input:
		(refs.input as Node).queue_free()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	bot = GaiusBot.new()
	scene.add_child(bot)
	bot.setup(refs.player, refs.gaius, refs.encounter)
	var g: Gaius = refs.gaius
	g.attack_phase_changed.connect(func(a: ColossusAttack) -> void:
		if a.kind == Gaius.SWORD_SLAM and a.phase == ColossusAttack.Phase.TELEGRAPH:
			_overlay(true)
			_want("gaius_02_slam_telegraph_overlay")
		elif a.kind == Gaius.SWORD_SLAM and a.phase == ColossusAttack.Phase.RECOVERY:
			_overlay(false))
	g.helmet.cracked.connect(func(_n: int) -> void: _want("gaius_08_helmet_cracked"))
	g.helmet.broken.connect(func() -> void: _want("gaius_09_helmet_broken"))
	(refs.player as PlayerCharacter).sword.struck.connect(func(r: Dictionary) -> void:
		if r.get("accepted", false) and r.get("reason", &"") == &"hit":
			_want("gaius_10_weak_point_hit"))
	_overlay(false)


func _physics_process(_delta: float) -> void:
	tick += 1
	var g: Gaius = refs.gaius
	var p: PlayerCharacter = refs.player
	var cam: PlayerCamera = refs.camera
	var on_body := g.region_of(p) != &"" or p.is_climbing()
	p.actions.focus_held = not on_body
	if on_body:
		var to := g.get_focus_point() - p.global_position
		cam.yaw = lerp_angle(cam.yaw, atan2(-to.x, -to.z) + 0.6, 0.05)
		cam.pitch = lerpf(cam.pitch, -0.35, 0.05)
	if tick == 60:
		_want("gaius_01_entrance")
	if g.sword_stuck() and g.attack.phase_time > 0.6 and not on_body:
		_want("gaius_03_sword_stuck")
	if bot.phase == ValusBot.Phase.GRAB_LEG and bot._on_blade() and bot.phase_time > 0.5:
		_want("gaius_04_running_up_the_blade")
	if bot.phase == ValusBot.Phase.CLIMB_BODY and bot._grip_bone() in [&"forearm_r", &"upper_arm_r"]:
		_want("gaius_05_climbing_the_sword_arm")
	if bot.phase == ValusBot.Phase.REST and bot.phase_time > 1.0:
		_want("gaius_06_on_the_shoulders")
	if bot.phase == ValusBot.Phase.ON_HEAD and p.sword.state == PlayerSword.State.CHARGE and p.sword.charge > 0.6:
		_want("gaius_07_striking_the_helmet")
	if g.encounter == Gaius.Encounter.DEFEATED and g.encounter_time > 6.0:
		_want("gaius_11_defeated")
	if taken.has("gaius_11_defeated") or tick > 60 * 400:
		get_tree().quit()
	if not _queue.is_empty():
		var name: String = _queue.pop_front()
		_shot(name)


func _overlay(on: bool) -> void:
	(refs.debug_draw as CombatDebugDraw).visible = on
	(refs.gaius as Gaius).debug_draw.visible = on


func _want(name: String) -> void:
	if taken.has(name) or name in _queue:
		return
	taken[name] = true
	_queue.append(name)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://tests/output/%s.png" % name))
	var g: Gaius = refs.gaius
	print("shot %s  t=%.1f  %s | %s" % [name, tick / 60.0, g.debug_text().split("\n")[0], ValusBot.Phase.keys()[bot.phase]])
