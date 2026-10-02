extends Node3D
## Visual smoke test for the Phaedra fight: its fen arena with the Mirewood kit, the bot
## playing (hide, peek, grab the head, climb the mane, strike). Saves
## tests/output/phaedra_*.png. Run with tools/capture_screenshots.sh phaedra.

var refs := {}
var bot: PhaedraBot
var taken := {}
var tick := 0
var _queue: Array[String] = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	InputSetup.ensure_defaults()
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 160.0
	add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, -Valley.SUN_DIRECTION.normalized(), Vector3.UP)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_SKY
	env.environment.sky = Sky.new()
	env.environment.sky.sky_material = ProceduralSkyMaterial.new()
	add_child(env)
	ArenaArt._daylight(self)
	var w := Node3D.new()
	add_child(w)
	refs = PhaedraArena.build_encounter(w, false, 17, not OS.has_environment("NO_ART"))
	(refs.debug_draw as Node3D).visible = false
	(refs.hud as PlayerHud).show_help = false
	(refs.hud as PlayerHud).show_debug = false
	bot = PhaedraBot.new()
	w.add_child(bot)
	bot.setup(refs.player, refs.phaedra, refs.encounter)
	var ph: Phaedra = refs.phaedra
	ph.weak_points[0].struck.connect(func(_d: float, _h: float) -> void: _want("phaedra_07_neck_weak_point_hit"))
	ph.weak_points[1].struck.connect(func(_d: float, _h: float) -> void: _want("phaedra_08_withers_hit"))


func _physics_process(_delta: float) -> void:
	tick += 1
	var ph: Phaedra = refs.phaedra
	var p: PlayerCharacter = refs.player
	var on_body := ph.region_of(p) != &"" or p.is_climbing()
	p.actions.focus_held = not on_body and bot.phase != PhaedraBot.Phase.WAIT
	if tick == 60:
		_want("phaedra_01_entrance")
	if bot.phase == PhaedraBot.Phase.HIDE and bot.phase_time > 4.0:
		_want("phaedra_02_running_to_the_ruins")
	if ph.peek == Phaedra.Peek.APPROACH and ph.peek_t > 6.0:
		_want("phaedra_03_it_comes_to_look")
	if ph.peek in [Phaedra.Peek.LOWER, Phaedra.Peek.HOLD] and ph.peek_w > 0.5:
		_want("phaedra_04_head_in_the_mouth")
	if bot.phase == PhaedraBot.Phase.CLIMB and ph.peek == Phaedra.Peek.RAISE:
		_want("phaedra_05_lifted_with_the_head")
	if bot.phase == PhaedraBot.Phase.CLIMB and not p.is_climbing() and ph.region_of(p) == &"neck":
		_want("phaedra_06_on_the_mane")
	if ph.is_defeated() and ph.encounter_time > 5.0:
		_want("phaedra_09_defeated")
	if taken.has("phaedra_09_defeated") and _queue.is_empty() or tick > 60 * 400:
		get_tree().quit()
	_frame_camera(ph, p)
	if not _queue.is_empty():
		_shot(_queue.pop_front())


## While Phaedra looks into a tunnel: an observer camera beside the mouth (the player's
## own camera is inside the tunnel and sees only its wall).
func _frame_camera(ph: Phaedra, p: PlayerCharacter) -> void:
	var cam: PlayerCamera = refs.camera
	var watching := ph.peek != Phaedra.Peek.NONE and not p.is_climbing() and ph.region_of(p) == &""
	if watching:
		var side := ph.peek_out.cross(Vector3.UP)
		cam.process_mode = Node.PROCESS_MODE_DISABLED
		cam.global_position = ph.peek_mouth + ph.peek_out * 7.0 + side * 13.0 + Vector3.UP * 6.0
		cam.look_at(ph.peek_mouth + ph.peek_out * 4.0 + Vector3.UP * 3.0)
	elif cam.process_mode == Node.PROCESS_MODE_DISABLED:
		cam.process_mode = Node.PROCESS_MODE_INHERIT


func _want(name: String) -> void:
	if taken.has(name) or name in _queue:
		return
	taken[name] = true
	_queue.append(name)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tests/output/%s.png" % name))
	var ph: Phaedra = refs.phaedra
	print("shot %s  t=%.1f  %s peek %s | %s" % [name, tick / 60.0, ph.encounter_name(), ph.peek_name(), PhaedraBot.Phase.keys()[bot.phase]])
