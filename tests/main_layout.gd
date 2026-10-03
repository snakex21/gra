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
	check(scene.layout_version == 3 and scene.refs.gates.size() == 21, "Main New Game did not choose the geographical layout")
	check(int(scene.replay.header.get("world_layout", 0)) == 3, "New recording did not identify the geographical map")
	var checkpoint := WorldSnapshot.capture(scene)
	check(int(checkpoint.get("world_layout", 0)) == 3, "World checkpoint forgot the new layout")
	check(AutoSave.save(scene, SLOT), "Main map could not save a safe portable checkpoint")
	var saved_at: Vector3 = scene.player().global_position
	scene._begin(false)
	check(scene.layout_version == 3 and scene.player().global_position.distance_to(saved_at) < .001, "Continue failed to resume the new map checkpoint")
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
	scene._begin(true)
	check(scene.layout_version == 3, "New Game retained the layout from an older Continue")
	scene.free()
	await ticks(3)
	AutoSave.clear(SLOT)
	DirAccess.remove_absolute(PortablePaths.resolve(SLOT))
	print("Main layout: %d failure(s); actual New Game, recording header, portable Continue, old checkpoint coordinates and new-game reset" % failures)
	get_tree().quit(1 if failures else 0)
