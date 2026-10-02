extends GameWorld
## The whole game: the title menu, the temple in the valley, the beam of the sword, the
## arenas behind their gates, the save. ``-- --new-game`` (or NEW_GAME=1) skips the menu
## and starts a new game; ``-- --continue`` skips it and loads the save.

var menu: GameMenu


func _ready() -> void:
	super()
	InputSetup.ensure_defaults()
	with_art = not OS.has_environment("NO_ART")
	settings.load_from()
	menu = GameMenu.new()
	menu.settings = settings
	add_child(menu)
	menu.new_game_chosen.connect(func() -> void: _begin(true))
	menu.continue_chosen.connect(func() -> void: _begin(false))
	menu.resume_chosen.connect(_resume)
	menu.quit_to_title_chosen.connect(_to_title)
	menu.quit_chosen.connect(func() -> void: get_tree().quit())
	menu.settings_changed.connect(func(s: Settings) -> void:
		apply_settings(s)
		s.save())
	var args := OS.get_cmdline_user_args()
	if OS.has_environment("NEW_GAME") or "--new-game" in args:
		_begin(true)
	elif "--continue" in args:
		_begin(false)
	else:
		_to_title()


func _begin(new_game: bool) -> void:
	get_tree().paused = false
	start(new_game)
	_capture_mouse(true)


func _resume() -> void:
	get_tree().paused = false
	_capture_mouse(true)


func _to_title() -> void:
	get_tree().paused = false
	stop()
	_capture_mouse(false)
	menu.show_title(has_save())


func _capture_mouse(on: bool) -> void:
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause") and region_kind != &"" and not menu.is_open():
		get_tree().paused = true
		_capture_mouse(false)
		menu.show_pause()
		get_viewport().set_input_as_handled()
		return
	if menu.is_open():
		return
	if event.is_action_pressed(&"encounter_reset") and refs.has("encounter"):
		(refs.encounter as BossEncounter).reset_encounter()
	elif event.is_action_pressed(&"respawn") and player():
		player().respawn()
	elif event.is_action_pressed(&"ride_steer_mode") and player():
		settings.ride_relative = not settings.ride_relative
		apply_settings(settings)
		settings.save()
	elif event.is_action_pressed(&"debug_draw"):
		for k in ["debug_draw", "bow_draw"]:
			if refs.get(k) is Node3D:
				(refs[k] as Node3D).visible = not (refs[k] as Node3D).visible
