extends Node
## Visual smoke test for the whole game: the valley with the art kit, the sword's beam,
## the ride to the gate and the arrival in the arena, played by GameBot. Then (a
## shortcut, this is a capture, not a test) the valley after two victories: the canyon
## ride to Gaius' gate. Saves tests/output/game_*.png. Run with
## tools/capture_screenshots.sh game.

var game: GameWorld
var bot: GameBot
var taken := {}
var tick := 0
var _queue: Array[String] = []
var _shortcut := false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	InputSetup.ensure_defaults()
	game = GameWorld.new()
	game.with_input = false
	game.with_art = not OS.has_environment("NO_ART")
	game.save_path = ""
	add_child(game)
	game.start(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	bot = GameBot.new()
	add_child(bot)
	bot._heading = Vector3.BACK
	bot.setup(game)


func _physics_process(_delta: float) -> void:
	tick += 1
	var p := game.player()
	if p == null or game.phase != GameWorld.Phase.PLAYING:
		return
	var cam: PlayerCamera = game.refs.camera
	if game.region_kind == GameWorld.VALLEY:
		if tick == 90:
			_want("game_01_temple")
		if bot.phase == GameBot.Phase.FIND and p.beam.raise >= 1.0 and p.beam.focus < 0.2 and bot.phase_time > 1.0:
			_want("game_02_beam_scattered")
		if p.beam.locked and bot.phase == GameBot.Phase.FIND:
			_want("game_03_beam_gathered")
		if bot.phase == GameBot.Phase.RIDE and bot.phase_time > 6.0 and not _shortcut:
			_want("game_04_riding_the_valley")
		if bot.phase == GameBot.Phase.RIDE and p.beam.focus > 0.9 and not _shortcut:
			_want("game_05_beam_from_the_saddle")
		var next := game.state.next_colossus()
		if next != &"":
			var gate: Dictionary = game.refs.gates[next]
			var d := Vector2(p.global_position.x - gate.pos.x, p.global_position.z - gate.pos.z).length()
			if d < 35.0:
				_want("game_06_gate" if not _shortcut else "game_09_gaius_gate")
		if _shortcut and p.global_position.x < -75.0 and bot.phase == GameBot.Phase.RIDE:
			_want("game_08_canyon_ride")
	else:
		# In the arena: look at the colossus once arrived.
		p.actions.focus_held = game.region_time < 6.0
		if game.region_time > 2.5:
			_want("game_07_arrival_valus")
		if taken.has("game_07_arrival_valus") and _queue.is_empty() and not _shortcut:
			# Shortcut to the third journey: Valus and Quadratus defeated, back at the temple.
			_shortcut = true
			game.state.mark_defeated(&"valus")
			game.state.mark_defeated(&"quadratus")
			if is_instance_valid(bot.boss_bot):
				bot.boss_bot.queue_free()
			game._go(GameWorld.VALLEY, false)
	if taken.has("game_09_gaius_gate") or tick > 60 * 300:
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
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://tests/output/%s.png" % name))
	var p := game.player()
	print("shot %s  t=%.1f  region %s  %s  pos %s  beam %.2f (lit %s)" % [name, tick / 60.0, game.region_kind, GameBot.Phase.keys()[bot.phase], str(p.global_position.snapped(Vector3.ONE * 0.1)), p.beam.focus, str(p.beam.lit)])
