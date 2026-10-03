extends Node
const AutoSave := preload("res://src/game/auto_save.gd")
const SLOT := "res://data/tests/autosave_v3.json"
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func make_world() -> GameWorld:
	var game := GameWorld.new()
	game.with_art = false
	game.with_input = false
	game.save_path = ""
	add_child(game)
	game.start(true)
	return game

func cleanup() -> void:
	AutoSave.clear(SLOT)
	DirAccess.remove_absolute(PortablePaths.resolve(SLOT))
	DirAccess.remove_absolute(AutoSave.world_path(SLOT) + ".tmp")

func _ready() -> void:
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	cleanup()
	var game := make_world()
	await ticks(60)
	var p := game.player()
	var horse: Horse = game.refs.horse
	p.global_position = horse.saddle_transform().origin - horse.global_basis.x * 1.4
	p.global_position.y = horse.global_position.y + 0.95
	p.reset_physics_interpolation()
	await ticks(20)
	p.actions.press_interact()
	await ticks(120)
	check(p.is_riding(), "autosave fixture failed to mount Agro through actions")
	var position := p.global_position
	check(AutoSave.save(game, SLOT), "portable mounted checkpoint could not be saved")
	check(FileAccess.file_exists(AutoSave.world_path(SLOT)), "safe checkpoint missing beside slot")
	check(not FileAccess.file_exists(AutoSave.world_path(SLOT) + ".tmp"), "atomic world save left its temporary file")
	game.free()
	await ticks(3)
	game = make_world()
	check(AutoSave.restore(game, SLOT), "portable mounted checkpoint could not be restored")
	check(game.player().is_riding() and game.player().riding.horse == game.refs.horse, "mounted restore lost rider or Agro reference")
	check(game.player().global_position.distance_to(position) < 0.001, "checkpoint did not resume the saved place")
	await ticks(120)
	check(game.player().is_riding() and not game.player().dead, "restored mounted checkpoint failed in subsequent physics")
	# Real climbing must retain the preceding safe checkpoint, never a dangling save.
	var previous_world := FileAccess.get_file_as_bytes(AutoSave.world_path(SLOT))
	game.player().actions.press_interact()
	await ticks(60)
	check(not game.player().is_riding(), "autosave fixture could not dismount through actions")
	game._wake(&"valus")
	p = game.player()
	p.global_position = game.arenas[&"valus"].xf * ValusArena.PLAYER_START
	p.spawn_transform = p.global_transform
	p.reset_physics_interpolation()
	var bot := ValusBot.new()
	add_child(bot)
	bot.setup(p, game.colossus(), game.refs.encounter)
	for i in 60 * 90:
		await ticks(1)
		if p.is_climbing():
			break
	check(p.is_climbing(), "autosave fixture did not reach a real climbing grip")
	bot.free()
	check(not AutoSave.safe_to_checkpoint(game), "climbing incorrectly counted as a safe load point")
	check(AutoSave.save(game, SLOT), "progress could not be saved while retaining a safe checkpoint")
	check(FileAccess.get_file_as_bytes(AutoSave.world_path(SLOT)) == previous_world, "climbing overwrote the preceding safe checkpoint")
	# A later campaign victory is authoritative over an earlier safe-world file.
	game.state.mark_defeated(&"valus")
	check(game.state.save(SLOT), "later victory could not be committed")
	game.free()
	await ticks(3)
	game = make_world()
	check(not AutoSave.restore(game, SLOT), "stale checkpoint undid a later victory")
	var progress := GameState.new()
	check(progress.load_from(SLOT) and progress.defeated == [&"valus"], "stale restore changed durable progress")
	game.free()
	await ticks(3)
	cleanup()
	# Test the actual main scene's minute cadence and load hook with an isolated slot.
	var scene: GameWorld = load("res://scenes/game.tscn").instantiate()
	add_child(scene)
	scene.with_art = false
	scene.save_path = SLOT
	scene._begin(true)
	await ticks(60 * 61)
	check(FileAccess.file_exists(AutoSave.world_path(SLOT)), "main scene did not autosave after a minute")
	var saved_position: Vector3 = scene.player().global_position
	scene._to_title()
	scene._begin(false)
	check(scene.player().global_position.distance_to(saved_position) < 0.01, "Continue did not use the world autosave")
	scene._to_title()
	scene.free()
	await ticks(3)
	cleanup()
	print("Auto save: %d failure(s); local atomic files, mounted resume, climbing safety, stale victory protection, minute cadence and Continue" % failures)
	get_tree().quit(1 if failures else 0)
