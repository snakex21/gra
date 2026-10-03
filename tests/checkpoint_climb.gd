extends Node
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
func _ready() -> void:
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	var game := GameWorld.new()
	game.with_input = false
	game.with_art = false
	game.save_path = ""
	add_child(game)
	game.start(true)
	game._wake(&"valus")
	var p := game.player()
	p.global_position = game.arenas[&"valus"].xf * ValusArena.PLAYER_START
	p.spawn_transform = p.global_transform
	var bot := ValusBot.new()
	add_child(bot)
	bot.setup(p, game.colossus(), game.refs.encounter)
	for i in 60 * 90:
		await ticks(1)
		if p.is_climbing():
			break
	check(p.is_climbing(), "checkpoint test did not reach a physical grip")
	bot.free()
	p.actions.clear()
	p.actions.grab_held = true
	p.actions.move = Vector2(0, 0.4)
	await ticks(30)
	var data: Dictionary = bytes_to_var(var_to_bytes(WorldSnapshot.capture(game)))
	var at := p.global_position
	var local := p.grip.local_point
	await ticks(120)
	var expected := p.global_position
	var expected_local := p.grip.local_point
	check(WorldSnapshot.restore(game, data), "climbing checkpoint could not restore")
	p = game.player()
	check(p.is_climbing() and p.global_position.distance_to(at) < 0.001 and p.grip.local_point == local, "climbing grip was lost at restore")
	await ticks(120)
	var drift := p.global_position.distance_to(expected)
	# Recreated physics broadphase can defer the first crawl by one 60Hz tick;
	# require continued grip and less than 5cm drift after two seconds.
	check(p.is_climbing() and drift < 0.05 and p.grip.local_point.distance_to(expected_local) < 0.05, "resumed climbing diverged by %.4fm" % drift)
	if drift < 0.05:
		print("PASS mid-climb binary checkpoint: continuation drift %.6fm" % drift)
	game.free()
	await ticks(2)
	game = GameWorld.new()
	game.with_input = false
	game.with_art = false
	game.save_path = ""
	add_child(game)
	game.start(true)
	game._wake(&"argus")
	var ruins: ArgusRuins = (game.colossus() as Argus).ruins
	ruins.receive_impact(ruins.to_global(ArgusRuins.PLATE))
	await ticks(75)
	var ramp_xf := ruins.ramp.transform
	data = bytes_to_var(var_to_bytes(WorldSnapshot.capture(game)))
	await ticks(75)
	check(WorldSnapshot.restore(game, data), "moving ruins checkpoint could not restore")
	ruins = (game.colossus() as Argus).ruins
	check(ruins.ramp.transform == ramp_xf and ruins.activated, "mid-rotation ruin collider lost its pose")
	await ticks(75)
	check(ruins.route_open, "restored terrain puzzle did not continue opening")
	print("PASS moving arena collider checkpoint")
	print("Climbing checkpoints: %d failure(s)" % failures)
	get_tree().quit(1 if failures else 0)
