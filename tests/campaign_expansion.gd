extends Node
## New encounters must also work in the rotated, translated campaign arenas.
var failures := 0
var game: GameWorld

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
	var state := GameState.new()
	var old_wins: Array = BossRoster.LEGACY.map(func(k: StringName) -> String: return String(k))
	check(state.from_dict({"version": 1, "defeated": old_wins}), "legacy save migration rejected")
	check(state.defeated.size() == 6 and state.next_colossus() == &"barba", "new encounters erased legacy victories")
	check(BossRoster.ORDER.size() == 21 and BossRoster.ORDER[10] == &"celosia_cenobia" and BossRoster.ORDER[-1] == &"dormin", "requested roster changed")
	var kinds := [&"barba", &"kuromori", &"basaran", &"dirge", &"pelagia", &"argus", &"celosia_cenobia", &"phalanx", &"malus", &"devil", &"phoenix", &"spider", &"worm", &"saru", &"dormin"]
	for kind: StringName in kinds:
		if not BossRoster.PLAYABLE.has(kind):
			continue
		if not OS.get_cmdline_user_args().is_empty() and not String(kind) in OS.get_cmdline_user_args():
			continue
		check(ResourceLoader.exists(BossRoster.scene(kind)), "trial scene missing for " + String(kind))
		await play(kind)
	print("Expanded campaign: %d failure(s)" % failures)
	get_tree().quit(1 if failures else 0)

func play(kind: StringName) -> void:
	game = GameWorld.new()
	game.with_input = false
	game.with_art = false
	game.save_path = ""
	game.outro_time = 0.0
	game.fade_time = 0.1
	add_child(game)
	var previous: Array = []
	for k in BossRoster.PLAYABLE:
		if k == kind:
			break
		previous.append(String(k))
	game.start_from({"version": 2, "defeated": previous})
	game._wake(kind)
	var arena: Dictionary = game.arenas[kind]
	var p := game.player()
	var start: Array = arena.points.get("player", [GameWorld.arena_starts(kind)[0], 0.0])
	p.global_transform = arena.xf * Transform3D(Basis(Vector3.UP, float(start[1])), start[0])
	p.facing = -p.global_basis.z
	p.actions.view_basis = p.global_basis
	p.spawn_transform = p.global_transform
	p.reset_physics_interpolation()
	var horse: Horse = game.refs.horse
	var horse_start: Array = arena.points.get("horse", [GameWorld.arena_starts(kind)[1], 0.0])
	var horse_xf: Transform3D = arena.xf * Transform3D(Basis(Vector3.UP, float(horse_start[1])), horse_start[0])
	horse.teleport(horse_xf.origin, horse_xf.basis.get_euler().y)
	await ticks(3)
	if kind == &"saru":
		# Campaign ground normalization must not fill the authored chasm.
		var from: Vector3 = arena.xf * Vector3(0, 2, 0)
		var to: Vector3 = arena.xf * Vector3(0, -10, 0)
		var query := PhysicsRayQueryParameters3D.create(from, to, Layers.WORLD)
		check(game.get_world_3d().direct_space_state.intersect_ray(query).is_empty(), "Saru campaign chasm filled by ground integration")
	var controller := GameBot.new()
	add_child(controller)
	controller.setup(game)
	# No flight, climb, strike or terrain progression is bypassed by this test.
	for i in 60 * 320:
		await ticks(1)
		if not controller.stats.boss_results.is_empty() or not controller.result.is_empty():
			break
	var won: bool = not controller.stats.boss_results.is_empty() and bool(controller.stats.boss_results[0].won)
	check(won, "campaign fight failed for %s: %s %s, player %s, boss %s, bot %s" % [kind, controller.result, controller.stats.boss_results, p.global_position, game.colossus().call(&"debug_text"), controller.boss_bot.get("phase") if controller.boss_bot else null])
	if won:
		await ticks(60)
		check(game.state.defeated.has(kind), "victory not saved in campaign state for " + String(kind))
		if kind == &"dormin":
			check(game.state.is_complete() and game.state.defeated.size() == 21, "Dormin victory did not complete the requested campaign")
			check(game.region_kind == GameWorld.VALLEY and not game.player().dead, "Wander did not survive the finale")
			check((game.refs.hud as PlayerHud).message.contains("ocalał"), "finale outcome missing from temple")
			var path := "res://data/tests/campaign_finale_v2.json"
			check(game.state.save(path), "completed campaign could not be saved beside the game")
			var loaded := GameState.new()
			check(loaded.load_from(path) and loaded.is_complete() and loaded.defeated == game.state.defeated, "all21 victories did not survive a disk roundtrip")
			DirAccess.remove_absolute(PortablePaths.resolve(path))
		print("PASS campaign %s: %.2fs, transformed arena, victory persisted" % [kind, controller.stats.boss_results[0].time])
	controller.free()
	game.free()
	await ticks(3)
