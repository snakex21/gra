extends Node
## Genuine travel from the temple; completion diagnostics only.
func _ready() -> void:
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	var count := 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--defeated="):
			count = int(arg.trim_prefix("--defeated="))
	var game := GameWorld.new()
	game.with_input = false
	game.with_art = false
	game.save_path = ""
	game.seed_offset = 101
	add_child(game)
	game.start_from({"version": GameState.VERSION, "defeated": GameState.ORDER.slice(0, count).map(func(k: StringName) -> String: return String(k))})
	var bot := GameBot.new()
	add_child(bot)
	bot.setup(game)
	var stuck := 0
	var won := false
	for i in 60 * 500:
		await get_tree().physics_frame
		if is_instance_valid(bot.boss_bot):
			won = true
			break
		if game.region_kind != GameWorld.VALLEY and game.refs.horse.controller.speed < 0.05:
			stuck += 1
		else:
			stuck = 0
		if stuck >= 60 * 15:
			break
	var horse: Horse = game.refs.horse
	var ctl := horse.controller
	print("Arrival %s: %s t %.2f p %s horse %s local %s speed %.3f direction %s forward %s obstacle %s distance %.3f limit %.3f" % [GameState.ORDER[count], won, bot.time, game.player().global_position, horse.global_position, (game.arenas[GameState.ORDER[count]].xf as Transform3D).affine_inverse() * horse.global_position, ctl.speed, ctl.desired_dir, ctl.forward(), ctl.obstacle, ctl.obstacle_distance, ctl.speed_limit])
	for hit in ctl.probe_hits:
		print("Probe: ", hit)
	print("Events: ", bot.events.slice(-20))
	game.free()
	bot.free()
	get_tree().quit(0 if won else 1)
