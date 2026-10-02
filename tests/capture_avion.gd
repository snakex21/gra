extends Node3D
## Visual smoke test for the Avion fight: the lake with its towers, the bot playing
## (swim out, climb a tower, the swoop's telegraph, the wing over the head, on its back,
## a roll, strikes, a dive under water). Saves tests/output/avion_*.png. Run with
## tools/capture_screenshots.sh avion.

var refs := {}
var bot: AvionBot
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
	refs = AvionArena.build_encounter(w, false, 41, not OS.has_environment("NO_ART"))
	(refs.hud as PlayerHud).show_help = false
	(refs.hud as PlayerHud).show_debug = false
	bot = AvionBot.new()
	w.add_child(bot)
	bot.setup(refs.player, refs.avion, refs.encounter, refs.towers)
	var av: Avion = refs.avion
	for wp in av.weak_points:
		wp.struck.connect(func(_d: float, _h: float) -> void: _want("avion_08_weak_point_hit"))


func _physics_process(_delta: float) -> void:
	tick += 1
	var av: Avion = refs.avion
	var p: PlayerCharacter = refs.player
	p.actions.focus_held = bot.phase in [AvionBot.Phase.WAIT, AvionBot.Phase.SWIM]
	if tick == 60:
		_want("avion_01_the_lake_and_towers")
	if p.is_swimming() and bot.phase_time > 2.0 and bot.phase == AvionBot.Phase.SWIM:
		_want("avion_02_swimming_to_a_tower")
	# Once on the way: a short dive (the breath ring, the light under water).
	p.actions.dive_held = taken.has("avion_02_swimming_to_a_tower") and not taken.has("avion_02b_diving") and p.is_swimming()
	if p.is_diving() and p.breath < p.breath_max - 2.5:
		_want("avion_02b_diving")
	if bot.phase == AvionBot.Phase.TOWER and p.global_position.y > 4.0:
		_want("avion_03_climbing_a_tower")
	if av.swoop == Avion.Swoop.TELEGRAPH and av.swoop_t > 1.0 and bot.phase == AvionBot.Phase.WAIT:
		_want("avion_04_swoop_telegraph")
	if av.swoop == Avion.Swoop.PASS and bot.phase == AvionBot.Phase.WAIT:
		_want("avion_05_the_wing_passes")
	if bot.phase == AvionBot.Phase.HANG and p.is_climbing():
		_want("avion_06_hanging_on_the_wing")
	if bot.phase in [AvionBot.Phase.ON_BACK, AvionBot.Phase.STRIKE] and av.owns_body(p.get_support_body()) and bot.phase_time > 1.0:
		_want("avion_07_on_its_back")
	if av.intent.kind == Avion.SHAKE_BODY and absf(av.roll) > 0.3:
		_want("avion_09_it_rolls")
	if av.is_defeated():
		_want("avion_10_defeated")
	if taken.has("avion_10_defeated") and _queue.is_empty() or tick > 60 * 500:
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
	var av: Avion = refs.avion
	print("shot %s  t=%.1f  %s %s swoop %s | %s" % [name, tick / 60.0, av.encounter_name(), av.intent.kind, av.swoop_name(), AvionBot.Phase.keys()[bot.phase]])
