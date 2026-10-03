extends GameWorld
## The whole game: the title menu, the temple in the valley, the beam of the sword, the
## arenas behind their gates, the save. ``-- --new-game`` (or NEW_GAME=1) skips the menu
## and starts a new game; ``-- --continue`` skips it and loads the save;
## ``-- --replay=<file> [--seek=<s>]`` plays a recording back (ReplayViewer: pause, seek,
## speed, markers, clips, free camera). F9 in a game saves a bug report: the recording so far and a short summary.

const LAST_REPLAY := "res://data/replays/last.replay"
const REPORTS := "res://data/replays/"
const AutoSave := preload("res://src/game/auto_save.gd")

var menu: GameMenu
## Every game is recorded (PlayerActions per tick): a playtest can be replayed exactly.
var replay: ActionReplay
## Playing a recording back (--replay=).
var viewer: ReplayViewer
var _replay_saved_at := 0
var _autosave_elapsed := 0.0


func _ready() -> void:
	super()
	get_tree().auto_accept_quit = false
	InputSetup.ensure_defaults()
	with_art = not OS.has_environment("NO_ART")
	settings.load_from()
	settings.apply_engine()
	save_path = GameState.slot_path(settings.slot)
	menu = GameMenu.new()
	menu.settings = settings
	add_child(menu)
	menu.new_game_chosen.connect(func() -> void: _begin(true))
	menu.trial_chosen.connect(func(kind: StringName) -> void:
		get_tree().paused = false
		stop()
		get_tree().change_scene_to_file(BossRoster.scene(kind)))
	menu.continue_chosen.connect(func() -> void: _begin(false))
	menu.slot_chosen.connect(func(slot: int, new_game: bool) -> void:
		settings.slot = slot
		settings.save()
		save_path = GameState.slot_path(slot)
		_begin(new_game))
	menu.resume_chosen.connect(_resume)
	menu.quit_to_title_chosen.connect(_to_title)
	menu.quit_chosen.connect(func() -> void:
		_quit_game())
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
		if TrialMenu.return_to_trials:
			TrialMenu.return_to_trials = false
			menu._show(&"trials")


func _begin(new_game: bool) -> void:
	get_tree().paused = false
	start(new_game)
	_autosave_elapsed = 0.0
	# A new game is saved at once (the slot shows it, Continue finds it).
	if new_game and save_path != "":
		AutoSave.clear(save_path)
		state.save(save_path)
	elif not new_game and AutoSave.restore(self, save_path):
		(refs.hud as PlayerHud).message = "Wczytano ostatni bezpieczny zapis"
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
	print("Replaying %s: %d recorded ticks, %d markers" % [path, int(data.get("ticks", 0)), (data.get("markers", []) as Array).size()])
	# ``-- --seek=<s>``: straight to that moment (a time from a bug report).
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seek="):
			viewer.seek(int(float(a.trim_prefix("--seek=")) * ReplayViewer.BASE_TICKS))


## F9: the recording and world summary, side by side in the local data/replays folder.
func save_bug_report() -> String:
	if not (is_instance_valid(replay) and replay.mode == ActionReplay.Mode.RECORD):
		return ""
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var base := PortablePaths.prepare(REPORTS + "report_" + stamp)
	if base == "":
		return ""
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
	if region_kind != &"" and not is_instance_valid(viewer):
		_autosave_elapsed += delta
		if _autosave_elapsed >= AutoSave.INTERVAL:
			_autosave_elapsed = 0.0
			_save_checkpoint()
	# Keep the last minute of play safe on disk (a crash keeps its replay).
	if is_instance_valid(replay) and replay.mode == ActionReplay.Mode.RECORD and replay.tick - _replay_saved_at >= 60 * 60:
		_replay_saved_at = replay.tick
		replay.save(LAST_REPLAY)


func _resume() -> void:
	get_tree().paused = false
	_capture_mouse(true)


func _to_title() -> void:
	get_tree().paused = false
	_save_checkpoint()
	if is_instance_valid(replay) and replay.mode == ActionReplay.Mode.RECORD:
		replay.save(LAST_REPLAY)
		replay.queue_free()
	stop()
	_capture_mouse(false)
	menu.show_title(has_save())

func _save_checkpoint() -> void:
	if region_kind == &"" or is_instance_valid(viewer):
		return
	if not AutoSave.save(self, save_path) and refs.get("hud") is PlayerHud:
		(refs.hud as PlayerHud).message = "Nie udało się zapisać w folderze gry"

func _quit_game() -> void:
	_save_checkpoint()
	if is_instance_valid(replay) and replay.mode == ActionReplay.Mode.RECORD:
		replay.save(LAST_REPLAY)
	get_tree().quit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit_game()


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
