extends Node3D
## Regressions found by independent integration review: safe capsule placement and
## complete second-actor stream through hot joins/leaves, without checkpoint skips.
signal tick_finished
var deadline := Time.get_ticks_msec() + 30000
var failures := 0


class RegroupOnce extends Node:
	var game: GameWorld
	var recorder: ActionReplay
	var done := false
	func _ready() -> void:
		process_physics_priority = 65
	func _physics_process(_delta: float) -> void:
		if not done and recorder.tick == 300:
			done = true
			var at := game._companion_join_position(game.player().global_position + Vector3.RIGHT * 20.0, true)
			if at != Vector3.INF:
				game.regroup_companion(at)
				game.companion_regrouped.emit(at)


func _ready() -> void:
	process_physics_priority = 2000
	call_deferred("run")


func _physics_process(_delta: float) -> void:
	tick_finished.emit()


func _process(_delta: float) -> void:
	if Time.get_ticks_msec() > deadline:
		push_error("Companion integration review watchdog")
		get_tree().quit(1)


func box(parent: Node3D, where: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = where
	body.collision_layer = Layers.WORLD
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	return body


func run() -> void:
	var game := GameWorld.new()
	game.with_art = false
	game.with_input = false
	game.save_path = ""
	add_child(game)
	game.set_physics_process(false)
	game.region = Node3D.new()
	game.add_child(game.region)
	game.region_kind = GameWorld.VALLEY
	box(game.region, Vector3(0, -0.5, 0), Vector3(100, 1, 100))
	var wall := box(game.region, Vector3(3, 3.5, 7), Vector3(3, 8, 3))
	var host := PlayerCharacter.new()
	host.position = Vector3(0, 0.95, 0)
	game.region.add_child(host)
	host.set_physics_process(false)
	game.refs.player = host
	await tick_finished
	await tick_finished
	var candidate := game._companion_join_position(host.global_position, true)
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.8
	capsule.radius = 0.35
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, candidate)
	query.collision_mask = Layers.SOLID
	var overlaps := get_world_3d().direct_space_state.intersect_shape(query, 8)
	var in_wall := false
	for hit in overlaps:
		in_wall = in_wall or hit.collider == wall
	check(not in_wall and candidate != Vector3.INF, "Companion join placed its capsule inside a physical wall")
	await render_barrier()
	game.free()
	await full_stream_probe()
	print("COMPANION_INTEGRATION_REVIEW failures=%d; safe capsule placement, from-zero hot join/leave/rejoin and end-of-tick regroup replay" % failures)
	get_tree().quit(1 if failures else 0)


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func ticks(count: int) -> void:
	for i in count:
		await tick_finished


func render_barrier() -> void:
	# Compatibility has a native dirty-Sky lifetime issue if a fresh whole world is
	# freed before its first draw. The application keeps its GameWorld alive; these
	# short-lived integration fixtures must allow the renderer to initialise it.
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw


func world() -> GameWorld:
	var game := GameWorld.new()
	game.with_art = false
	game.with_input = false
	game.save_path = ""
	add_child(game)
	return game


func full_stream_probe() -> void:
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	var game := world()
	game.start_from({}, &"off")
	var recorder := ActionReplay.recorder(null, {"progress": game.state.to_dict()})
	recorder.player_source = game.player
	game.add_child(recorder)
	await ticks(60)
	game.set_companion_mode(&"programmed")
	await ticks(120)
	game.set_companion_mode(&"off")
	await ticks(30)
	game.set_companion_mode(&"programmed")
	var regroup := RegroupOnce.new()
	regroup.game = game
	regroup.recorder = recorder
	game.add_child(regroup)
	await ticks(150)
	var expected := [game.companion().global_position, game.companion().ticks, game.companion().actions.snapshot()]
	var data: Dictionary = bytes_to_var(var_to_bytes(recorder.to_dict()))
	await render_barrier()
	game.free()
	await ticks(2)
	var playback := world()
	var viewer := ReplayViewer.new()
	viewer.setup(playback, data)
	playback.add_child(viewer)
	await ticks(int(data.ticks))
	var actual := [playback.companion().global_position, playback.companion().ticks, playback.companion().actions.snapshot()]
	check(data.companion_events.size() == 3 and data.companion_regroups.size() == 1, "Review fixture did not record hot mode transitions and the physics-end regroup")
	check(viewer.tick() == data.ticks and actual[1] == expected[1] and actual[2] == expected[2] and (actual[0] as Vector3).distance_to(expected[0]) < 0.001, "From-zero companion replay diverged: ticks=%s positions=%s" % [[actual[1], expected[1]], [actual[0], expected[0]]])
	await render_barrier()
	viewer.free()
	playback.free()
