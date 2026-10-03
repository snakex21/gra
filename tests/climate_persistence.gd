extends Node
## Real GameWorld integration. Checks the climate where time/state actually cross
## system boundaries, rather than repeating the pure model's unit assertions.

const Climate = preload("res://src/world/world_climate.gd")
const AutoSave = preload("res://src/game/auto_save.gd")
const SLOT := "res://data/tests/climate_persistence.json"
const CLIP := "res://data/tests/climate_persistence_clip.replay"
signal tick_finished

var failures := 0
var checks := 0
var deadline := Time.get_ticks_msec() + 120000


func _ready() -> void:
	# The watchdog and barriers must run during a real tree pause. Game worlds below
	# explicitly use PAUSABLE, so they do not inherit this test harness' ALWAYS mode.
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 2000
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	ReplayViewer._set_rate(1.0)
	cleanup()
	call_deferred("run")


func _physics_process(_delta: float) -> void:
	# After GameWorld (60), recorder checkpoints (900) and ReplayViewer (1000).
	tick_finished.emit()


func _process(_delta: float) -> void:
	if Time.get_ticks_msec() > deadline:
		push_error("Climate persistence test timed out or stopped after a runtime error")
		get_tree().paused = false
		ReplayViewer._set_rate(1.0)
		cleanup()
		get_tree().quit(1)


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func ticks(count: int) -> void:
	for i in count:
		await tick_finished


func cleanup() -> void:
	AutoSave.clear(SLOT)
	for path: String in [SLOT, SLOT + ".tmp", AutoSave.world_path(SLOT) + ".tmp", CLIP]:
		DirAccess.remove_absolute(PortablePaths.resolve(path))


func progress(elapsed: float, world_seed: int = 921331) -> Dictionary:
	var state := GameState.new()
	state.play_time = elapsed
	state.climate = Climate.new(world_seed)
	state.climate.advance(elapsed)
	return state.to_dict()


func make_world(saved: Dictionary = {}, slot: String = "") -> GameWorld:
	var game := GameWorld.new()
	game.process_mode = Node.PROCESS_MODE_PAUSABLE
	game.with_art = false
	game.with_input = false
	game.save_path = slot
	game.layout_version = 2
	add_child(game)
	if saved.is_empty():
		game.start(slot == "")
	else:
		game.start_from(saved)
	return game


func clock(game: GameWorld) -> PackedByteArray:
	return var_to_bytes(game.state.climate.to_dict())


func sample(game: GameWorld) -> Dictionary:
	return game.state.climate.sample(game.region_kind, game.state.defeated.size(), game.state.is_complete())


func run() -> void:
	await test_snapshot_and_continuation()
	await test_legacy()
	await test_pause_and_rebuild()
	await test_autosave_priority()
	await test_replay_seek_and_clip()
	get_tree().paused = false
	ReplayViewer._set_rate(1.0)
	cleanup()
	print("CLIMATE_PERSISTENCE failures=%d checks=%d; actual GameWorld physics, checkpoint continuation, legacy progress/checkpoint, paused/title clocks, arena/rebuild/fade, safe world vs newer JSON, replay seek and compressed clip continuation" % [failures, checks])
	get_tree().quit(1 if failures else 0)


func test_snapshot_and_continuation() -> void:
	var game := make_world(progress(1121.25))
	await ticks(45)
	var before := clock(game)
	var weather_before := sample(game)
	var checkpoint := bytes_to_var(var_to_bytes(WorldSnapshot.capture(game))) as Dictionary
	check(checkpoint.progress.has("climate"), "World checkpoint omitted climate from campaign progress")
	check(var_to_bytes(checkpoint.progress.climate) == before, "Checkpoint changed clock or seed during capture")
	var no_duplicate := true
	for object: Dictionary in checkpoint.objects:
		no_duplicate = no_duplicate and object.get("script", "") != "res://src/world/world_climate.gd"
	check(no_duplicate, "World climate was duplicated in the region object graph")
	await ticks(120)
	var continuation := clock(game)
	var continued_weather := sample(game)
	check(continuation != before, "Actual world physics did not advance climate")
	check(WorldSnapshot.restore(game, checkpoint), "Binary world checkpoint failed to restore")
	check(clock(game) == before and sample(game) == weather_before, "Checkpoint restored a different hour, seed or weather")
	await ticks(120)
	check(clock(game) == continuation and sample(game) == continued_weather, "Restored world climate diverged during identical subsequent physics")
	game.free()
	await ticks(2)


func test_legacy() -> void:
	var old := {"version": GameState.VERSION, "defeated": [], "play_time": 903.25, "deaths": 2}
	var game := make_world(old)
	check(game.state.climate.to_dict().elapsed == 903.25, "Old campaign save reset climate instead of using play_time")
	var expected := Climate.new()
	expected.advance(903.25)
	check(sample(game) == expected.sample(), "Legacy campaign recovered the wrong weather/time")
	await ticks(60)
	check(absf(float(game.state.climate.to_dict().elapsed) - 904.25) < 1.0e-9, "Legacy climate did not continue in real world physics")
	var checkpoint := WorldSnapshot.capture(game)
	checkpoint.progress.erase("climate")
	var legacy_time := float(checkpoint.progress.play_time)
	await ticks(60)
	check(WorldSnapshot.restore(game, checkpoint), "Legacy checkpoint without climate was rejected")
	check(absf(float(game.state.climate.to_dict().elapsed) - legacy_time) < 1.0e-9, "Legacy checkpoint climate did not derive from saved play_time")
	var malformed := old.duplicate(true)
	malformed.climate = ["corrupt optional field"]
	var recovered := GameState.new()
	check(recovered.from_dict(malformed) and recovered.climate.to_dict().elapsed == 903.25, "Malformed optional climate invalidated otherwise valid legacy progress")
	game.free()
	await ticks(2)


func test_pause_and_rebuild() -> void:
	var game := make_world(progress(456.125, 73))
	await ticks(45)
	var before := clock(game)
	var play_time := game.state.play_time
	get_tree().paused = true
	await ticks(20)
	check(clock(game) == before and game.state.play_time == play_time, "Tree pause advanced the world climate or play counter")
	get_tree().paused = false
	await ticks(60)
	check(absf(float(game.state.climate.to_dict().elapsed) - float(bytes_to_var(before).elapsed) - 1.0) < 1.0e-9, "Unpausing did not resume the climate once per physics tick")
	before = clock(game)
	game._wake(&"valus")
	check(clock(game) == before and game.region_kind == &"valus", "Entering an arena reset/advanced climate")
	game._sleep()
	check(clock(game) == before and game.region_kind == GameWorld.VALLEY, "Leaving an arena reset/advanced climate")
	game._build_world()
	check(clock(game) == before, "World rebuild reset clock/seed/compensation")
	var elapsed_before := float(game.state.climate.to_dict().elapsed)
	play_time = game.state.play_time
	game._go(GameWorld.VALLEY, false)
	await ticks(100)
	check(game.phase == GameWorld.Phase.PLAYING, "Real fade/rebuild fixture did not return to playing")
	check(absf((float(game.state.climate.to_dict().elapsed) - elapsed_before) - (game.state.play_time - play_time)) < 1.0e-8, "Climate lost or doubled time while the temple rebuilt during a fade")
	before = clock(game)
	var stopped_progress := game.state.to_dict()
	game.stop()
	await ticks(20)
	check(clock(game) == before, "Title/stopped world continued climate without a loaded region")
	game.start_from(stopped_progress)
	check(clock(game) == before, "Starting from saved progress lost the clock after stopping")
	game.free()
	await ticks(2)


func test_autosave_priority() -> void:
	var game := make_world(progress(713.5, 104729))
	await ticks(45)
	check(AutoSave.safe_to_checkpoint(game), "Autosave fixture did not settle on safe real ground")
	var safe_clock := clock(game)
	var safe_weather := sample(game)
	check(AutoSave.save(game, SLOT), "Safe portable checkpoint could not be saved")
	var safe_world := FileAccess.get_file_as_bytes(AutoSave.world_path(SLOT))
	# A real held sword charge keeps the last safe world while the progress JSON is
	# updated, exactly as unsafe climbing/falling saves do, without a fake state.
	game.player().actions.attack_held = true
	await ticks(120)
	check(game.player().sword.is_busy() and not AutoSave.safe_to_checkpoint(game), "Held sword charge was not an unsafe checkpoint state")
	check(AutoSave.save(game, SLOT), "Unsafe progress JSON could not be saved")
	check(FileAccess.get_file_as_bytes(AutoSave.world_path(SLOT)) == safe_world, "Unsafe save replaced the safe world's clock")
	var latest := GameState.new()
	check(latest.load_from(SLOT), "Newest progress JSON could not load")
	var latest_play_time := latest.play_time
	check(var_to_bytes(latest.climate.to_dict()) != safe_clock and latest.climate.to_dict().elapsed > float(bytes_to_var(safe_clock).elapsed), "Unsafe JSON did not actually carry a newer clock")
	game.free()
	game = make_world({}, SLOT)
	check(game.state.play_time == latest_play_time, "Fresh world failed to load newer JSON play_time")
	check(AutoSave.restore(game, SLOT), "Safe world refused same-victory newer JSON progress")
	check(clock(game) == safe_clock and sample(game) == safe_weather, "Autosave replaced the safe-world climate with newer JSON climate")
	check(game.state.play_time == latest_play_time, "Restoring safe climate discarded the accumulated play counter")
	await ticks(60)
	check(absf(float(game.state.climate.to_dict().elapsed) - float(bytes_to_var(safe_clock).elapsed) - 1.0) < 1.0e-9, "Safe restored clock failed to continue independently of newer play_time")
	game.free()
	await ticks(2)
	cleanup()


func test_replay_seek_and_clip() -> void:
	var game := make_world(progress(227.7, 312997))
	var recorder := ActionReplay.recorder(null, {"progress": game.state.to_dict()})
	recorder.player_source = game.player
	recorder.checkpoint_every = 240
	game.add_child(recorder)
	var at_300 := PackedByteArray()
	var at_1037 := PackedByteArray()
	for frame in 1320:
		if frame in [120, 360, 720, 1080]:
			game.player().actions.press_jump()
		await ticks(1)
		if recorder.tick == 300:
			at_300 = clock(game)
		if recorder.tick == 1037:
			at_1037 = clock(game)
	var data := recorder.to_dict().duplicate(true)
	check(not at_300.is_empty() and not at_1037.is_empty(), "Replay fixture did not record its reference ticks")
	check(data.checkpoints.size() >= 6 and data.frames.size() > 4, "Replay fixture lacked periodic checkpoints/action changes")
	check(data.header.progress.has("climate") and data.checkpoints[0].world.progress.has("climate"), "Replay header/checkpoint omitted initial clock and seed")
	game.remove_child(recorder)
	recorder.free()
	var viewer := ReplayViewer.new()
	viewer.setup(game, data)
	add_child(viewer)
	viewer.set_paused(true)
	viewer.seek(1037)
	check(viewer.tick() == 960, "Seek did not resume from its nearest recorded checkpoint")
	await viewer.reached
	check(viewer.tick() == 1037 and clock(game) == at_1037, "Checkpoint seek changed clock after replaying the remaining input suffix")
	await get_tree().process_frame
	await get_tree().process_frame
	var path := PortablePaths.resolve(CLIP)
	check(viewer.save_clip(1200, path) == path, "Climate replay clip could not be saved beside the project")
	var clip := ActionReplay.load_file(path)
	check(not clip.is_empty() and clip.frames.size() < data.frames.size(), "Compressed clip failed to trim the input prefix")
	check(not clip.get("checkpoints", []).is_empty() and clip.checkpoints[0].tick == 240 and clip.checkpoints[0].world.progress.has("climate"), "Clip did not retain its starting world climate checkpoint")
	viewer.free()
	get_tree().paused = false
	game.free()
	await ticks(2)
	game = make_world()
	viewer = ReplayViewer.new()
	viewer.setup(game, clip)
	add_child(viewer)
	await viewer.reached
	check(viewer.tick() == 300 and clock(game) == at_300, "Clip playback reset climate to the original header instead of its saved checkpoint")
	# Auto-play resumes after the opening seek. Let that public viewer hook finish,
	# then pause and seek to the same non-checkpoint tick in the compact clip.
	await get_tree().process_frame
	await get_tree().process_frame
	viewer.set_paused(true)
	viewer.seek(1037)
	await viewer.reached
	check(viewer.tick() == 1037 and clock(game) == at_1037, "Trimmed replay clip diverged from full recording climate during continuation")
	await get_tree().process_frame
	await get_tree().process_frame
	viewer.free()
	get_tree().paused = false
	game.free()
	await ticks(2)
