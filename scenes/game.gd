extends GameWorld
## The whole game: the title menu, the temple in the valley, the beam of the sword, the
## arenas behind their gates, the save. ``-- --new-game`` (or NEW_GAME=1) skips the menu
## and starts a new game; ``-- --continue`` skips it and loads the save;
## ``-- --replay=<file>`` plays a recording back (ReplayViewer: pause, seek, speed, free
## camera). F9 in a game saves a bug report: the recording so far and a short summary.

const LAST_REPLAY := "user://replays/last.replay"
const REPORTS := "user://replays/"

var menu: GameMenu
## Every game is recorded (PlayerActions per tick): a playtest can be replayed exactly.
var replay: ActionReplay
## Playing a recording back (--replay=).
var viewer: ReplayViewer
var _replay_saved_at := 0


func _ready() -> void:
	super()
	InputSetup.ensure_defaults()
	with_art = not OS.has_environment("NO_ART")
	settings.load_from()
	settings.apply_engine()
	save_path = GameState.slot_path(settings.slot)
	menu = GameMenu.new()
	menu.settings = settings
	add_child(menu)
	menu.new_game_chosen.connect(func() -> void: _begin(true))
	menu.continue_chosen.connect(func() -> void: _begin(false))
	menu.slot_chosen.connect(func(slot: int, new_game: bool) -> void:
		settings.slot = slot
		settings.save()
		save_path = GameState.slot_path(slot)
		_begin(new_game))
	menu.resume_chosen.connect(_resume)
	menu.quit_to_title_chosen.connect(_to_title)
	menu.quit_chosen.connect(func() -> void:
		if is_instance_valid(replay) and replay.mode == ActionReplay.Mode.RECORD:
			replay.save(LAST_REPLAY)
		get_tree().quit())
	menu.open_changed.connect(_hide_hud)
	menu.settings_changed.connect(func(s: Settings) -> void:
		apply_settings(s)
		s.apply_engine()
		s.save())
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--replay="):
			_play_replay(a.trim_prefix("--replay="))
			return
	if OS.has_environment("NEW_GAME") or "--new-game" in args:
		_begin(true)
	elif "--continue" in args:
		_begin(false)
	else:
		_to_title()


func _begin(new_game: bool) -> void:
	get_tree().paused = false
	start(new_game)
	# A new game is saved at once (the slot shows it, Continue finds it).
	if new_game and save_path != "":
		state.save(save_path)
	_record({"start": "new" if new_game else "continue", "progress": state.to_dict(), "seed_offset": seed_offset})
	_capture_mouse(true)


func _record(header: Dictionary) -> void:
	if is_instance_valid(replay):
		replay.queue_free()
	replay = ActionReplay.recorder(null, header)
	replay.player_source = player
	add_child(replay)
	_replay_saved_at = 0


func _play_replay(path: String) -> void:
	var data := ActionReplay.load_file(path)
	if data.is_empty():
		push_error("Cannot read replay " + path)
		_to_title()
		return
	with_input = false
	save_path = ""
	viewer = ReplayViewer.new()
	viewer.name = "ReplayViewer"
	viewer.setup(self, data)
	add_child(viewer)
	print("Replaying %s: %d recorded ticks" % [path, int(data.get("ticks", 0))])


## F9: the recording so far and what the game looked like, side by side in user://replays.
func save_bug_report() -> String:
	if not (is_instance_valid(replay) and replay.mode == ActionReplay.Mode.RECORD):
		return ""
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var base := REPORTS + "report_" + stamp
	replay.mark(&"report", stamp)
	replay.save(base + ".replay")
	var p := player()
	var info := {"time": stamp, "tick": replay.tick, "region": String(region_kind), "progress": state.to_dict(),
		"player": str(p.global_position) if p else "", "state": p.get_display_state() if p else ""}
	var f := FileAccess.open(base + ".json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(info, "\t"))
		f.close()
	if refs.get("hud") is PlayerHud:
		(refs.hud as PlayerHud).message = "Zapisano zgłoszenie: " + base.get_file()
	return base + ".replay"


func _physics_process(delta: float) -> void:
	super(delta)
	# Keep the last minute of play safe on disk (a crash keeps its replay).
	if is_instance_valid(replay) and replay.mode == ActionReplay.Mode.RECORD and replay.tick - _replay_saved_at >= 60 * 60:
		_replay_saved_at = replay.tick
		replay.save(LAST_REPLAY)


func _resume() -> void:
	get_tree().paused = false
	_capture_mouse(true)


func _to_title() -> void:
	get_tree().paused = false
	if is_instance_valid(replay) and replay.mode == ActionReplay.Mode.RECORD:
		replay.save(LAST_REPLAY)
		replay.queue_free()
	stop()
	_capture_mouse(false)
	menu.show_title(has_save())


func _hide_hud(hidden: bool) -> void:
	if refs.get("hud") is CanvasItem:
		(refs.hud as CanvasItem).visible = not hidden


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
	if event.is_action_pressed(&"bug_report"):
		save_bug_report()
	elif event.is_action_pressed(&"encounter_reset") and refs.has("encounter"):
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
