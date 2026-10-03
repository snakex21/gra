extends Node
## Both actor streams, late model advice, joins/leaves, sparse catch-up events,
## checkpoint seeking and trimmed binary clips in an actual GameWorld.
signal tick_finished
const CLIP := "res://data/tests/companion_clip.replay"
var failures := 0
var checks := 0
var deadline := Time.get_ticks_msec() + 120000

class HostPath extends Node:
	var game: GameWorld
	func _ready() -> void:
		process_physics_priority = -20
	func _physics_process(_delta: float) -> void:
		var host := game.player()
		if not host:
			return
		host.actions.clear()
		var directions := [Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT, Vector3.BACK]
		host.actions.view_basis = Basis.looking_at(directions[(host.ticks / 120) % 4])
		host.actions.move = Vector2(0, 1)

class LateRegroup extends Node:
	var game: GameWorld
	var recorder: ActionReplay
	var fired := false
	func _ready() -> void:
		process_physics_priority = 80
	func _physics_process(_delta: float) -> void:
		if not fired and recorder.tick == 600:
			fired = true
			var at := game.player().global_position + Vector3(5, 0, 5)
			game.regroup_companion(at)
			game.companion_regrouped.emit(at)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 2000
	Sfx.enabled = false
	Fx.enabled = false
	InputSetup.ensure_defaults()
	call_deferred("run")

func _physics_process(_delta: float) -> void:
	tick_finished.emit()

func _process(_delta: float) -> void:
	if Time.get_ticks_msec() > deadline:
		push_error("Companion replay test timed out")
		get_tree().paused = false
		ReplayViewer._set_rate(1)
		get_tree().quit(1)

func ticks(count: int) -> void:
	for i in count:
		await tick_finished

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func world() -> GameWorld:
	var game := GameWorld.new()
	game.process_mode = Node.PROCESS_MODE_PAUSABLE
	game.with_input = false
	game.with_art = false
	game.save_path = ""
	game.layout_version = 2
	add_child(game)
	return game

func actors(game: GameWorld) -> Array:
	var result := []
	for actor in [game.player(), game.companion()]:
		result.append([actor.global_position, actor.velocity, actor.health, actor.state, actor.ticks, actor.actions.snapshot(), actor.bow.shots] if is_instance_valid(actor) else [])
	return result

func compare(game: GameWorld, expected: Array, label: String) -> void:
	var actual := actors(game)
	check(actual.size() == expected.size(), label + " actor count")
	for i in expected.size():
		if expected[i].is_empty():
			check(actual[i].is_empty(), label + " removed companion returned")
			continue
		check(not actual[i].is_empty(), label + " missing actor")
		if actual[i].is_empty():
			continue
		check(actual[i][0].distance_to(expected[i][0]) < 0.003 and actual[i][1].distance_to(expected[i][1]) < 0.003, label + " actor position/velocity diverged: " + str([actual[i][0], expected[i][0]]))
		check(actual[i].slice(2) == expected[i].slice(2), label + " actor health/state/ticks/actions/shots diverged: " + str([actual[i].slice(2), expected[i].slice(2)]))

func run() -> void:
	ReplayViewer._set_rate(8)
	var game := world()
	game.start_from({}, &"local_model")
	# The fixture injects a real late advice response; it never uses a server.
	game._decision_t = -1000000.0
	var source := HostPath.new()
	source.game = game
	game.add_child(source)
	var recorder := ActionReplay.recorder(null, {"progress": game.state.to_dict()})
	recorder.player_source = game.player
	recorder.checkpoint_every = 120
	game.add_child(recorder)
	var regroup := LateRegroup.new()
	regroup.game = game
	regroup.recorder = recorder
	game.add_child(regroup)
	var expected := {}
	await ticks(180)
	game._on_companion_decision(&"hold", game._decision_generation)
	await ticks(180)
	game.set_companion_mode(&"off")
	await ticks(60)
	game.set_companion_mode(&"programmed")
	await ticks(180)
	await ticks(60)
	expected[recorder.tick] = actors(game)
	await ticks(420)
	expected[recorder.tick] = actors(game)
	await ticks(360)
	expected[recorder.tick] = actors(game)
	var data := bytes_to_var(var_to_bytes(recorder.to_dict())) as Dictionary
	check(not data.companion_frames.is_empty() and data.companion_events.size() == 2 and data.companion_regroups.size() == 1, "Recording omitted companion actions/mode changes/regroup")
	check(data.checkpoints[0].world.companion_mode == "local_model", "Initial checkpoint omitted companion mode")
	# Force a seek to run across the sparse event, rather than restoring after it.
	data.checkpoints = data.checkpoints.filter(func(saved: Dictionary) -> bool: return int(saved.tick) != 600)
	game.free()
	await ticks(2)

	var playback := world()
	var viewer := ReplayViewer.new()
	viewer.setup(playback, data)
	playback.add_child(viewer)
	# Seek past advice, removal/rejoin and the recorded teleport.
	for at: int in expected:
		viewer.seek(at)
		if viewer.tick() != at:
			await viewer.reached
		compare(playback, expected[at], "seek " + str(at))
		check(playback.replay_driven and playback.refs.companion_controller.external_drive and not playback.decision_client._pending, "Replay started inference or live controller")
	# Backwards seek before removal must recreate the local-model actor without inference.
	viewer.seek(240)
	if viewer.tick() != 240:
		await viewer.reached
	check(playback.companion_mode == &"local_model" and playback.companion() != null, "Backwards seek did not reconstruct the companion")
	var end_at: int = expected.keys()[1]
	var path := viewer.save_clip(end_at, CLIP)
	check(path != "", "Could not save companion binary clip")
	var clip := ActionReplay.load_file(CLIP)
	check(not clip.is_empty() and not clip.checkpoints.is_empty(), "Companion clip checkpoint missing")
	check(clip.companion_frames.size() < data.companion_frames.size(), "Clip did not trim companion action prefix/end")
	await get_tree().process_frame
	viewer.free()
	playback.free()
	get_tree().paused = false
	await ticks(2)
	var clipped_game := world()
	var clipped_viewer := ReplayViewer.new()
	clipped_viewer.setup(clipped_game, clip)
	clipped_game.add_child(clipped_viewer)
	clipped_viewer.seek(end_at)
	if clipped_viewer.tick() != end_at:
		await clipped_viewer.reached
	compare(clipped_game, expected[end_at], "binary clip")
	await get_tree().process_frame
	clipped_viewer.free()
	clipped_game.free()
	get_tree().paused = false
	ReplayViewer._set_rate(1)
	DirAccess.remove_absolute(PortablePaths.resolve(CLIP))
	await ticks(2)
	print("COMPANION_REPLAY failures=%d checks=%d" % [failures, checks])
	get_tree().quit(1 if failures else 0)
