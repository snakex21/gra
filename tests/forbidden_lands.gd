extends Node
## Geometry and real action-driven temple -> branch -> gate -> arena-rim journeys.
var failures := 0
var test_layout := 4 if OS.get_cmdline_user_args().has("--layout4") else 3
var watchdog_ticks := 0
var watchdog_began := Time.get_ticks_msec()
var report := {"geometry": [], "rides": [], "legacy_layouts": true, "checkpoints": [], "reentries": []}

func _physics_process(_delta: float) -> void:
	watchdog_ticks += 1
	if watchdog_ticks >= 600000 or Time.get_ticks_msec() - watchdog_began >= 900000:
		push_error("FORBIDDEN_LANDS global timeout: unfinished route/checkpoint test")
		get_tree().quit(1)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	_legacy()
	_geometry()
	await _surfaces()
	if not OS.get_cmdline_user_args().has("--geometry-only"):
		for kind: StringName in BossRoster.PLAYABLE:
			if OS.get_cmdline_user_args().is_empty() or OS.get_cmdline_user_args() == PackedStringArray(["--layout4"]) or OS.get_cmdline_user_args().has(String(kind)):
				await _ride(kind)
	report["failures"] = failures
	report["completed"] = true
	report["physics_ticks"] = watchdog_ticks
	report["wall_ms"] = Time.get_ticks_msec() - watchdog_began
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	var output := "forbidden_lands.json"
	if OS.get_cmdline_user_args().has("--geometry-only"):
		output = "forbidden_lands_geometry.json"
	elif not OS.get_cmdline_user_args().is_empty():
		output = "forbidden_lands_selected.json"
	if test_layout == 4:
		output = output.trim_suffix(".json") + "_layout4.json"
	report["world_layout"] = test_layout
	var file := FileAccess.open("res://tests/output/" + output, FileAccess.WRITE)
	if file == null:
		push_error("FORBIDDEN_LANDS cannot write final portable report")
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("FORBIDDEN_LANDS: %d failures; %d geometry routes; %d real Agro arrivals" % [failures, report.geometry.size(), report.rides.size()])
	get_tree().quit(1 if failures else 0)

func _legacy() -> void:
	check(WorldMap.gates(1) == Valley.GATES, "Layout 1 gates moved")
	for kind: StringName in Valley.GATES:
		var gate: Dictionary = Valley.GATES[kind]
		var expected: Vector3 = gate.pos + (gate.out as Vector3).normalized() * float(WorldMap.LEGACY_DISTANCE[kind])
		var actual := WorldMap.arena_transform(kind, 1)
		check(Vector2(actual.origin.x, actual.origin.z).distance_to(Vector2(expected.x, expected.z)) < .0001, "Layout 1 arena moved: " + String(kind))
	for kind: StringName in BossRoster.PLAYABLE:
		var angle := PI + float(WorldMap.SLOTS[kind]) * TAU / 21
		var outward := Vector3(sin(angle), 0, cos(angle))
		var old_gate := outward * (Valley.EDGE / maxf(absf(outward.x), absf(outward.z)))
		var actual: Vector3 = WorldMap.gate(kind, 2).pos
		check(actual.distance_to(old_gate) < .0001, "Layout 2 gate moved: " + String(kind))
		var centre: Vector3 = WorldMap.arena_transform(kind, 2).origin
		var expected := old_gate + outward.normalized() * 1400
		check(Vector2(centre.x, centre.z).distance_to(Vector2(expected.x, expected.z)) < .001, "Layout 2 arena moved: " + String(kind))
		check(WorldMap.arena_transform(kind, 2).basis.is_equal_approx(Basis(Vector3.UP, atan2(-outward.x, -outward.z))), "Layout 2 arena rotated: " + String(kind))

func _geometry() -> void:
	var lengths := []
	var min_clearance := INF
	for kind: StringName in BossRoster.PLAYABLE:
		var xf := WorldMap.arena_transform(kind, test_layout)
		var centre := Vector2(xf.origin.x, xf.origin.z)
		var square_nearest := Vector2(clampf(centre.x, -180, 180), clampf(centre.y, -180, 180))
		check(centre.distance_to(square_nearest) > WorldMap.GROUND_RADIUS + 5, "Arena overlaps temple valley: " + String(kind))
		for other: StringName in BossRoster.PLAYABLE:
			if other != kind:
				var other_centre: Vector2 = ForbiddenLands.regions(test_layout)[other][0]
				check(centre.distance_to(other_centre) > WorldMap.GROUND_RADIUS * 2 + 15, "Arena discs overlap: %s/%s" % [kind, other])
		var points := ForbiddenLands.route_points(kind, test_layout)
		var clearance := INF
		var bends := 0
		for i in range(1, points.size()):
			var a := Vector2(points[i - 1].x, points[i - 1].z)
			var b := Vector2(points[i].x, points[i].z)
			if i > 1:
				var previous := Vector2(points[i - 2].x, points[i - 2].z)
				bends += 1 if absf((a - previous).angle_to(b - a)) > .025 else 0
			for other: StringName in BossRoster.PLAYABLE:
				if other == kind:
					continue
				var other_centre: Vector2 = ForbiddenLands.regions(test_layout)[other][0]
				var distance := Geometry2D.get_closest_point_to_segment(other_centre, a, b).distance_to(other_centre) - WorldMap.GROUND_RADIUS
				clearance = minf(clearance, distance)
				check(distance > ForbiddenLands.ROAD_HALF + 2, "Route enters another arena or its rim: %s/%s %.1fm" % [kind, other, distance])
		var end: Vector3 = xf.affine_inverse() * points[points.size() - 1]
		check(absf(end.x) < .001 and absf(end.z - 145) < .001, "Route does not reach original +Z approach: " + String(kind))
		var gate: Vector3 = xf.affine_inverse() * WorldMap.gate(kind, test_layout).pos
		check(absf(gate.x) < .001 and absf(gate.z - 220) < .001, "Gate not on final straight approach: " + String(kind))
		var length := ForbiddenLands.route_length(kind, test_layout)
		lengths.append(snappedf(length, .1))
		min_clearance = minf(min_clearance, clearance)
		report.geometry.append({"kind": String(kind), "grid": ForbiddenLands.regions(test_layout)[kind][1], "centre": [centre.x, centre.y], "length_m": length, "samples": points.size(), "bends": bends, "other_arena_clearance_m": clearance})
	lengths.sort()
	check(lengths.back() - lengths.front() > 1000, "Routes retained equal spoke lengths")
	report["minimum_road_clearance_m"] = min_clearance

func _surfaces() -> void:
	var world := Node3D.new()
	add_child(world)
	ForbiddenLands.build_valley(world, &"valus", false, test_layout)
	WorldMap.build(world, func(kind: StringName, root: Node3D) -> Dictionary:
		if kind in [&"valus", &"gaius"]:
			return ValusArena.build(root)
		var arena: Script = load("res://src/world/%s_arena.gd" % kind)
		return arena.call(&"build", root), false, test_layout)
	for i in 3:
		await get_tree().physics_frame
	var hits := 0
	var missing := []
	for kind: StringName in BossRoster.PLAYABLE:
		var points := ForbiddenLands.route_points(kind, test_layout)
		for i in range(1, points.size(), 3):
			var direction := (points[i] - points[i - 1]).normalized()
			var side := direction.cross(Vector3.UP).normalized()
			for lane: float in [-5.0, 0.0, 5.0]:
				var p := points[i] + side * lane
				p.y = ForbiddenLands.road_height(p.x, p.z)
				var ray := PhysicsRayQueryParameters3D.create(p + Vector3.UP * .5, p - Vector3.UP * .8, Layers.WORLD)
				ray.hit_back_faces = false # same query contract as Agro/ClimbQuery
				var hit := world.get_world_3d().direct_space_state.intersect_ray(ray)
				if hit.is_empty():
					missing.append([String(kind), i, lane, str(p)])
				else:
					hits += 1
	check(missing.is_empty(), "Missing physical road/apron samples: " + str(missing.slice(0, 12)))
	report["physical_lane_samples"] = hits
	report["missing_floor_samples"] = missing
	world.free()
	await get_tree().physics_frame

func _ride(kind: StringName) -> void:
	var game := GameWorld.new()
	game.layout_version = test_layout
	game.with_input = false
	game.with_art = false
	game.save_path = ""
	add_child(game)
	var previous := []
	for other: StringName in BossRoster.PLAYABLE:
		if other == kind:
			break
		previous.append(String(other))
	game.start_from({"version": 2, "defeated": previous})
	var bot := GameBot.new()
	add_child(bot)
	bot.setup(game)
	var arrived := false
	var elapsed := 0.0
	var furthest := 0.0
	var stationary := 0.0
	var previous_position := game.player().global_position
	var checkpoint_done := false
	for i in 60 * 460:
		await get_tree().physics_frame
		elapsed = (i + 1) / 60.0
		furthest = maxf(furthest, game.player().global_position.distance_to(Valley.on_ground(Valley.TEMPLE_SPAWN)))
		stationary = stationary + 1.0 / 60 if bot.phase == GameBot.Phase.RIDE and game.player().global_position.distance_to(previous_position) < .005 else 0.0
		previous_position = game.player().global_position
		if kind == &"hydrus" and not checkpoint_done and furthest > 500 and game.region_kind == GameWorld.VALLEY:
			await _branch_checkpoint(game, bot)
			checkpoint_done = true
		if game.region_kind == kind:
			var local: Vector3 = game.arenas[kind].xf.affine_inverse() * game.player().global_position
			if local.z < WorldMap.RIM - 5 and absf(local.x) < 10:
				arrived = true
				break
		if game.player().dead or game.state.deaths > 0 or not bot.result.is_empty():
			break
		if stationary > 15:
			break
	var horse := game.refs.horse as Horse
	var diagnostic := {"position": str(horse.global_position), "obstacle": horse.controller.obstacle, "obstacle_distance": horse.controller.obstacle_distance, "stop_distance": horse.controller.stop_distance, "probe_hits": str(horse.controller.probe_hits), "colliders": [], "terrain_count": horse.controller.terrain_rids.size()}
	for index in horse.get_slide_collision_count():
		diagnostic.colliders.append(str(horse.get_slide_collision(index).get_collider().get_path()))
	check(arrived and game.player().is_riding() and game.state.deaths == 0, "Agro did not physically arrive: %s, %s %.1fs position%s events%s" % [kind, game.region_kind, elapsed, game.player().global_position, bot.events.slice(-8)])
	report.rides.append({"kind": String(kind), "arrived": arrived, "riding": game.player().is_riding(), "time_s": elapsed, "deaths": game.state.deaths, "furthest_from_temple_m": furthest, "horse_speed": horse.controller.speed, "diagnostic": diagnostic, "stalls": bot.stats.stalls.duplicate(), "events": bot.events.slice(-8)})
	bot.free()
	if kind == &"valus" and arrived:
		await _reentry(game, kind)
	game.free()
	for i in 2:
		await get_tree().physics_frame

func _branch_checkpoint(game: GameWorld, bot: GameBot) -> void:
	bot.set_physics_process(false)
	game.set_physics_process(false)
	var before := game.player().global_position
	var horse_before := (game.refs.horse as Horse).global_position
	var heading := ForbiddenLands.route_heading(&"hydrus", before, test_layout)
	var data := WorldSnapshot.capture(game)
	var bytes := var_to_bytes(data)
	var file := FileAccess.open("res://tests/output/forbidden_lands_branch.bin", FileAccess.WRITE)
	if file == null:
		check(false, "Cannot write portable branch checkpoint")
		game.set_physics_process(true)
		bot.set_physics_process(true)
		return
	file.store_buffer(bytes)
	file.close()
	file = FileAccess.open("res://tests/output/forbidden_lands_branch.bin", FileAccess.READ)
	if file == null:
		check(false, "Cannot read portable branch checkpoint")
		game.set_physics_process(true)
		bot.set_physics_process(true)
		return
	var decoded: Dictionary = bytes_to_var(file.get_buffer(file.get_length()))
	file.close()
	check(WorldSnapshot.restore(game, decoded), "Layout 3 branch binary checkpoint failed")
	check(game.layout_version == test_layout and game.region_kind == GameWorld.VALLEY, "Checkpoint forgot layout or travel region")
	check(game.player().global_position.distance_to(before) < .001 and (game.refs.horse as Horse).global_position.distance_to(horse_before) < .001, "Checkpoint restarted travelled branch")
	check(game.player().is_riding(), "Checkpoint lost live Agro rider reference")
	check(ForbiddenLands.route_heading(&"hydrus", game.player().global_position, test_layout).distance_to(heading) < .001, "Checkpoint changed position-derived route heading")
	for object: Dictionary in decoded.objects:
		check(not String(object.get("script", "")).contains("forbidden_lands"), "Render/terrain builder leaked into checkpoint")
	report.checkpoints.append({"kind": "hydrus", "bytes": bytes.size(), "position": str(before), "restored": game.player().global_position.distance_to(before) < .001, "riding": game.player().is_riding()})
	game.set_physics_process(true)
	bot.set_physics_process(true)
	await get_tree().physics_frame

func _reentry(game: GameWorld, kind: StringName) -> void:
	var xf: Transform3D = game.arenas[kind].xf
	var left := false
	var returned := false
	for i in 60 * 65:
		await get_tree().physics_frame
		var player := game.player()
		var local: Vector3 = xf.affine_inverse() * player.global_position
		if not left and game.region_kind == GameWorld.VALLEY:
			left = true
			var at := player.global_position
			check(at.distance_to(Valley.on_ground(Valley.TEMPLE_SPAWN)) > 200, "Leaving arena teleported to temple")
		if left and game.region_kind == kind and local.z < 165:
			returned = true
			break
		var target: Vector3 = xf * Vector3(0, 0, 245 if not left else 145)
		var direction := target - player.global_position
		direction.y = 0
		player.actions.view_basis = Basis.looking_at(direction.normalized())
		player.riding.steer_relative = false
		player.actions.move = Vector2(0, 1)
		if i % 50 == 0:
			player.actions.press_jump()
	check(left and returned and game.player().is_riding() and game.state.deaths == 0, "Arena exit and physical reentry failed")
	report.reentries.append({"kind": String(kind), "left": left, "returned": returned, "deaths": game.state.deaths})
