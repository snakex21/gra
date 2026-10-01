extends Node
## Visual smoke test for the Sentinel fight: the real arena scene (renderer, camera, HUD,
## debug overlays) with the scripted bot playing. Saves tests/output/boss_*.png at key
## moments. Run with tools/capture_screenshots.sh boss.

var scene: Node3D
var refs := {}
var bot: SentinelBot
var taken := {}
var tick := 0
var _queue: Array[String] = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	scene = load("res://scenes/sentinel_arena.tscn").instantiate()
	add_child(scene)
	await get_tree().physics_frame
	refs = scene.refs
	if refs.input:
		(refs.input as Node).queue_free()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	bot = SentinelBot.new()
	scene.add_child(bot)
	bot.setup(refs.player, refs.sentinel, refs.encounter)
	var s: Sentinel = refs.sentinel
	s.attack_phase_changed.connect(_on_phase)
	(refs.player as PlayerCharacter).sword.struck.connect(func(r: Dictionary) -> void:
		if r.get("accepted", false):
			_want("boss_09_weak_point_hit"))
	_overlay(false)


func _physics_process(_delta: float) -> void:
	tick += 1
	var s: Sentinel = refs.sentinel
	var p: PlayerCharacter = refs.player
	var cam: PlayerCamera = refs.camera
	# Frame the boss and the player like a player holding Q would, except while high up.
	p.actions.focus_held = not p.is_climbing() and s.region_of(p) == &""
	if p.is_climbing() or s.region_of(p) != &"":
		var to := s.get_focus_point() - p.global_position
		cam.yaw = lerp_angle(cam.yaw, atan2(-to.x, -to.z) + 0.5, 0.05)
		cam.pitch = lerpf(cam.pitch, -0.35, 0.05)
	if tick == 60:
		_want("boss_01_entrance_dormant")
	if s.encounter == Sentinel.Encounter.NOTICE:
		_want("boss_02_notice")
	match bot.phase:
		SentinelBot.Phase.CLIMB_BODY:
			if bot.phase_time > 1.0 and p.global_position.y < 5.0:
				_want("boss_05_climbing_calf")
			if p.global_position.y > 8.5:
				_want("boss_06_climbing_back")
		SentinelBot.Phase.REST:
			if bot.phase_time > 1.0:
				_want("boss_07_rest_on_shoulders")
		SentinelBot.Phase.CLIMB_HEAD:
			if bot.phase_time > 0.4:
				_want("boss_08_mane")
		SentinelBot.Phase.STRIKE:
			if p.sword.state == PlayerSword.State.CHARGE and p.sword.charge > 0.6:
				_want("boss_08b_charging_on_head")
			if s.intent.kind == ColossusIntent.SHAKE_PLAYER and s._shake > 0.6:
				_want("boss_10_shake_on_head")
	if s.weak_point.state == WeakPoint.State.PROTECTED:
		_want("boss_11_weak_point_protected")
	if s.encounter == Sentinel.Encounter.DEFEATED and s.encounter_time > 5.0:
		_overlay(false)
		_want("boss_12_defeated_kneeling")
	if s.encounter == Sentinel.Encounter.DEFEATED and s.encounter_time > 7.0 and taken.has("boss_12_defeated_kneeling"):
		_overlay(true)
		_want("boss_13_defeated_overlay")
	if taken.has("boss_13_defeated_overlay") or tick > 60 * 400:
		get_tree().quit()
	if not _queue.is_empty():
		var name: String = _queue.pop_front()
		_shot(name)


func _on_phase(a: ColossusAttack) -> void:
	if a.kind == Sentinel.STOMP and a.phase == ColossusAttack.Phase.TELEGRAPH:
		_overlay(true)
		_want("boss_03_stomp_telegraph_overlay")
	elif a.kind == Sentinel.STOMP and a.phase == ColossusAttack.Phase.RECOVERY:
		_overlay(false)
		_want("boss_04_stomp_impact")
	elif a.kind == Sentinel.ARM_SWEEP and a.phase == ColossusAttack.Phase.ACTIVE:
		_want("boss_03b_arm_sweep")


func _overlay(on: bool) -> void:
	(refs.debug_draw as CombatDebugDraw).visible = on
	(refs.sentinel as Sentinel).debug_draw.visible = on


func _want(name: String) -> void:
	if taken.has(name) or name in _queue:
		return
	taken[name] = true
	_queue.append(name)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://tests/output/%s.png" % name))
	var s: Sentinel = refs.sentinel
	var p: PlayerCharacter = refs.player
	print("shot %s  t=%.1f  %s | P %s HP %.0f st %.0f region %s | %s" % [name, tick / 60.0, s.debug_text().split("\n")[0], p.get_display_state(), p.health, p.stamina.value, s.region_of(p), SentinelBot.Phase.keys()[bot.phase]])
