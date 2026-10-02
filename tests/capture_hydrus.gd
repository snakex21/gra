extends Node3D
## Visual smoke test for the Hydrus fight: the lake with its pillars, the bot
## playing (swim out, dodge a ram, grab a tuft, climb on, a dive, strikes). Saves
## tests/output/hydrus_*.png. Run with tools/capture_screenshots.sh hydrus.

var refs := {}
var bot: HydrusBot
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
	refs = HydrusArena.build_encounter(w, false, 29, not OS.has_environment("NO_ART"))
	(refs.hud as PlayerHud).show_help = false
	(refs.hud as PlayerHud).show_debug = false
	bot = HydrusBot.new()
	w.add_child(bot)
	bot.setup(refs.player, refs.hydrus, refs.encounter)
	var h: Hydrus = refs.hydrus
	h.weak_points[0].struck.connect(func(_d: float, _h: float) -> void: _want("hydrus_08_weak_point_hit"))


func _physics_process(_delta: float) -> void:
	tick += 1
	var h: Hydrus = refs.hydrus
	var p: PlayerCharacter = refs.player
	p.actions.focus_held = p.is_swimming() and not p.is_climbing()
	if tick == 60:
		_want("hydrus_01_the_lake")
	if p.is_swimming() and bot.phase_time > 2.0 and bot.phase == HydrusBot.Phase.WAIT:
		_want("hydrus_02_swimming_out")
	if h.intent.kind == Hydrus.RAM and h.rear_w > 0.8:
		_want("hydrus_03_ram_telegraph")
	if p.is_climbing() and p.is_swimming() == false and bot.phase == HydrusBot.Phase.CLIMB:
		_want("hydrus_04_grabbed_a_tuft")
	if bot.phase in [HydrusBot.Phase.ON_BACK, HydrusBot.Phase.STRIKE] and h.owns_body(p.get_support_body()) and not p.is_climbing():
		_want("hydrus_05_on_its_back")
	if h.dive == Hydrus.Dive.REAR and h.owns_body(p.get_support_body()) or h.dive == Hydrus.Dive.REAR and p.is_climbing():
		_want("hydrus_06_it_rears_up")
	if p.is_under_water() and p.is_climbing():
		_want("hydrus_07_holding_on_under_water")
	if h.is_defeated():
		_want("hydrus_09_defeated")
	if taken.has("hydrus_09_defeated") and _queue.is_empty() or tick > 60 * 400:
		get_tree().quit()
	if not _queue.is_empty():
		_shot(_queue.pop_front())


func _want(name: String) -> void:
	if taken.has(name) or name in _queue:
		return
	taken[name] = true
	_queue.append(name)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tests/output/%s.png" % name))
	var h: Hydrus = refs.hydrus
	print("shot %s  t=%.1f  %s %s dive %s | %s" % [name, tick / 60.0, h.encounter_name(), h.intent.kind, Hydrus.Dive.keys()[h.dive], HydrusBot.Phase.keys()[bot.phase]])
