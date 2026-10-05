extends Node
## Actual New Game/Continue hooks, with a disposable portable slot.
const AutoSave := preload("res://src/game/auto_save.gd")
const SLOT := "res://data/tests/layout_smoke.json"
var failures := 0
var deadline := Time.get_ticks_msec() + 120000

func _process(_delta: float) -> void:
	if Time.get_ticks_msec() > deadline:
		push_error("Main layout test did not finish within 120 seconds")
		get_tree().quit(1)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func ticks(n: int) -> void:
	for i in n: await get_tree().physics_frame

func _ready() -> void:
	Sfx.enabled = false
	Fx.enabled = false
	var scene = load("res://scenes/game.tscn").instantiate()
	add_child(scene)
	scene.with_input = false
	scene.with_art = false
	scene.save_path = SLOT
	scene.menu._close()
	scene._begin(true)
	await ticks(35)
	check(scene.layout_version == 4 and scene.refs.gates.size() == 21, "Main New Game did not choose the geographical layout")
	check(int(scene.replay.header.get("world_layout", 0)) == 4, "New recording did not identify the geographical map")
	var checkpoint := WorldSnapshot.capture(scene)
	check(int(checkpoint.get("world_layout", 0)) == 4, "World checkpoint forgot the new layout")
	check(AutoSave.save(scene, SLOT), "Main map could not save a safe portable checkpoint")
	var saved_at: Vector3 = scene.player().global_position
	scene._begin(false)
	check(scene.layout_version == 4 and scene.player().global_position.distance_to(saved_at) < .001, "Continue failed to resume the new map checkpoint")
	await ticks(4)
	var older := GameWorld.new()
	older.layout_version = 2
	older.with_input = false
	older.with_art = false
	older.save_path = ""
	add_child(older)
	older.start(true)
	await ticks(35)
	var old_checkpoint := WorldSnapshot.capture(older)
	var old_at := older.player().global_position
	older.free()
	check(WorldSnapshot.restore(scene, old_checkpoint), "Main game could not restore an older layout checkpoint")
	check(scene.layout_version == 2 and scene.player().global_position.distance_to(old_at) < .001, "Older checkpoint was moved onto the new geography")
	# A layout-3 checkpoint near a moved arena must retain old physical geography,
	# while layout-4 checkpoints keep their expanded arena roots and route cache.
	for layout in [1, 3, 4]:
		var source := GameWorld.new()
		source.layout_version = layout
		source.with_input = false
		source.with_art = false
		source.save_path = ""
		add_child(source)
		source.start(true)
		await ticks(4)
		var at := WorldMap.arena_transform(&"phaedra", layout) * Vector3(0, 2, 240)
		source.player().global_position = at
		(source.refs.horse as Horse).global_position = at + Vector3(3, 0, 0)
		var source_checkpoint := WorldSnapshot.capture(source)
		if layout == 1:
			source_checkpoint.erase("world_layout") # historical absent-header fallback
		var source_bytes := var_to_bytes(source_checkpoint)
		source.free()
		check(WorldSnapshot.restore(scene, bytes_to_var(source_bytes)), "Geography checkpoint restore failed")
		check(scene.layout_version == layout, "Restore silently changed geography revision")
		check(scene.player().global_position.distance_to(at) < .001, "Restore moved absolute player coordinates")
		check((scene.refs.horse as Horse).global_position.distance_to(at + Vector3(3, 0, 0)) < .001, "Restore moved absolute horse coordinates")
		check((scene.arenas[&"phaedra"].xf as Transform3D).is_equal_approx(WorldMap.arena_transform(&"phaedra", layout)), "Restore rebuilt the wrong arena geography")
		check(var_to_bytes(source_checkpoint) == source_bytes, "Restore mutated checkpoint input")
		scene._record({"test": "geography"})
		check(int(scene.replay.header.get("world_layout", 0)) == layout, "Recording header lost restored geography")
		await ticks(2)
	# Exercise the real replay header fallback/restart path without rewriting files.
	for layout in [1, 2, 3, 4]:
		var replay_game := GameWorld.new()
		replay_game.with_input = false
		replay_game.with_art = false
		replay_game.save_path = ""
		add_child(replay_game)
		var header := {"progress": {}, "seed_offset": 0}
		if layout != 1:
			header["world_layout"] = layout
		var viewer := ReplayViewer.new()
		viewer.setup(replay_game, {"header": header, "frames": [], "ticks": 1})
		add_child(viewer)
		check(replay_game.layout_version == layout, "Replay header/fallback chose wrong layout")
		check((replay_game.arenas[&"phaedra"].xf as Transform3D).is_equal_approx(WorldMap.arena_transform(&"phaedra", layout)), "Replay rebuilt wrong arena coordinates")
		var replay_checkpoint := WorldSnapshot.capture(replay_game)
		viewer.restart({"world": replay_checkpoint, "tick": 0, "cursor": 0, "segment": -1})
		check(replay_game.layout_version == layout, "Replay checkpoint restart changed geography")
		viewer.free()
		replay_game.free()
		await ticks(2)
	scene._begin(true)
	check(scene.layout_version == 4, "New Game retained the layout from an older Continue")
	scene.free()
	await ticks(3)
	AutoSave.clear(SLOT)
	DirAccess.remove_absolute(PortablePaths.resolve(SLOT))
	print("Main layout: %d failure(s); actual New Game, recording header, portable Continue, old checkpoint coordinates and new-game reset" % failures)
	get_tree().quit(1 if failures else 0)
