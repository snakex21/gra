extends Node
## Layout 4 geometry, physical lanes and immutable layout 3 regression contract.
const BEFORE := {"valus": [0.0, -440.0, 334.286375954747], "quadratus": [0.0, 440.0, 628.975278198719], "gaius": [-440.0, 880.0, 1033.18643379211], "phaedra": [440.0, -440.0, 681.373422145844], "avion": [880.0, 0.0, 1072.74781554937], "barba": [-880.0, -880.0, 1360.96907043457], "hydrus": [-880.0, 1320.0, 1926.08341145515], "kuromori": [440.0, -880.0, 1293.09520888329], "basaran": [-880.0, 440.0, 1093.5976164341], "dirge": [-1760.0, 0.0, 1642.27736520767], "celosia_cenobia": [-1320.0, 880.0, 1941.17712598201], "pelagia": [440.0, 880.0, 1476.39601695538], "phalanx": [-440.0, -880.0, 929.594723343849], "argus": [880.0, 1320.0, 2313.54063010216], "malus": [0.0, -1760.0, 1707.67341399193], "devil": [1320.0, 880.0, 2416.41715788841], "phoenix": [1320.0, 0.0, 1514.58544659615], "spider": [-1320.0, -440.0, 1267.51524114609], "worm": [-1320.0, -1320.0, 2227.13698172569], "saru": [0.0, 1320.0, 1671.04952478409], "dormin": [440.0, 440.0, 890.019980549812]}
const BEFORE_HEIGHTS := [[0.0,0.0,-0.05,-0.0500000007450581],[170.0,-790.0,-0.217688626133824,-0.0668445811606944],[390.0,-770.0,-3.73870859669672,-5.47759580332786],[-740.0,-870.0,-21.4094131005462,-21.3376648426056],[300.0,1250.0,-0.1,-0.100000001490116],[-230.0,400.0,-34.0,-32.6349999904633],[-2200.0,-2200.0,-45.0,-45.0],[1500.0,1400.0,-45.0,-45.0],[850.0,-150.0,-0.1,-1.19495624070987],[-1000.0,-1000.0,-35.0,-29.2474613189697]]
var failures := 0
var began := Time.get_ticks_msec()
var report := {"routes": [], "arena_pairs": [], "errors": [], "missing_floor_samples": [], "legacy_height_samples": [], "completed": false}

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		report.errors.append(message)
		push_error(message)

func _process(_delta: float) -> void:
	if Time.get_ticks_msec() - began > 180000:
		check(false, "Terrain layout watchdog exceeded 180 seconds")
		_finish()

func _ready() -> void:
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	_geometry()
	await _surfaces()
	report.completed = true
	_finish()

func _finish() -> void:
	report["failures"] = failures
	report["wall_ms"] = Time.get_ticks_msec() - began
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	var file := FileAccess.open("res://tests/output/terrain_layout.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	else:
		push_error("Cannot save terrain_layout.json")
		failures += 1
	print("TERRAIN_LAYOUT: %d failures; %d routes; %d physical lanes; complete=%s" % [failures, report.routes.size(), report.get("physical_lane_samples", 0), report.completed])
	get_tree().quit(1 if failures else 0)

func _geometry() -> void:
	check(ForbiddenLands.regions(4).size() == 21, "Layout 4 lost encounter regions")
	var old_routes := {}
	for kind: StringName in BossRoster.PLAYABLE:
		old_routes[kind] = ForbiddenLands.route_points(kind, 3).duplicate()
	var old_edges := ForbiddenLands.road_edges(3).duplicate(true)
	var min_gap := INF
	var min_clearance := INF
	for kind: StringName in BossRoster.PLAYABLE:
		var base: Array = BEFORE[String(kind)]
		var old_xf := ForbiddenLands.arena_transform(kind, 3)
		check(old_xf.origin.distance_to(Vector3(base[0], 0, base[1])) < .001, "Layout 3 centre changed: " + String(kind))
		check(absf(ForbiddenLands.route_length(kind, 3) - float(base[2])) < .001, "Layout 3 route length changed: " + String(kind))
		var xf := WorldMap.arena_transform(kind, 4)
		check(xf.is_equal_approx(ForbiddenLands.arena_transform(kind, 4)), "Arena API mismatch: " + String(kind))
		var center := Vector2(xf.origin.x, xf.origin.z)
		var near_valley := Vector2(clampf(center.x,-180,180),clampf(center.y,-180,180))
		check(center.distance_to(near_valley) > WorldMap.GROUND_RADIUS + 5, "Arena overlaps valley: " + String(kind))
		var gate := WorldMap.gate(kind, 4)
		var local_gate: Vector3 = xf.affine_inverse() * (gate.pos as Vector3)
		check(local_gate.distance_to(Vector3(0,0,ForbiddenLands.GATE_DISTANCE)) < .001, "Gate transform mismatch: " + String(kind))
		check((gate.out as Vector3).distance_to(-xf.basis.z) < .001, "Gate heading mismatch: " + String(kind))
		check((gate.trigger as Vector3).distance_to((gate.pos as Vector3) - xf.basis.z * Valley.GATE_TRIGGER) < .001, "Gate trigger mismatch: " + String(kind))
		check(WorldMap.rim_entry(kind,4).distance_to(xf * Vector3(0,0,WorldMap.RIM)) < .001, "Rim transform mismatch: " + String(kind))
		var points := ForbiddenLands.route_points(kind, 4)
		check((xf.affine_inverse() * points[points.size()-1]).distance_to(Vector3(0,0,145)) < .001, "Route endpoint mismatch: " + String(kind))
		var clearance := INF
		for other: StringName in BossRoster.PLAYABLE:
			if other == kind: continue
			var other_center: Vector2 = ForbiddenLands.regions(4)[other][0]
			var gap := center.distance_to(other_center) - 2 * WorldMap.GROUND_RADIUS
			min_gap = minf(min_gap,gap)
			if String(kind) < String(other):
				var old_other: Array = BEFORE[String(other)]
				var old_gap := Vector2(base[0],base[1]).distance_to(Vector2(old_other[0],old_other[1])) - 2*WorldMap.GROUND_RADIUS
				report.arena_pairs.append({"a":String(kind),"b":String(other),"before_ground_edge_gap_m":old_gap,"after_ground_edge_gap_m":gap})
			check(gap > 15, "Arena ground overlap: %s/%s %.3f" % [kind,other,gap])
			for i in range(1,points.size()):
				var a := Vector2(points[i-1].x,points[i-1].z)
				var b := Vector2(points[i].x,points[i].z)
				var nearest := Geometry2D.get_closest_point_to_segment(other_center,a,b)
				var distance := nearest.distance_to(other_center) - WorldMap.GROUND_RADIUS
				clearance = minf(clearance,distance)
				check(distance > ForbiddenLands.road_half_at(nearest.x,nearest.y,4) + 2, "Road enters other arena: %s/%s segment%d %.3f" % [kind,other,i,distance])
		min_clearance = minf(min_clearance,clearance)
		var length := ForbiddenLands.route_length(kind,4)
		report.routes.append({"kind":String(kind),"before_length_m":base[2],"after_length_m":length,"before_center_xz":[base[0],base[1]],"after_center_xz":[center.x,center.y],"before_foot_s":float(base[2])/5.5,"after_foot_s":length/5.5,"before_horse_gallop_s":float(base[2])/9.5,"after_horse_gallop_s":length/9.5,"after_horse_walk_s":length/1.7,"after_horse_trot_s":length/4.2,"nearest_other_arena_route_clearance_m":clearance})
	ForbiddenLands.road_edges(4)
	check(ForbiddenLands.road_edges(3) == old_edges, "Layout 4 contaminated layout 3 edge cache")
	for kind: StringName in BossRoster.PLAYABLE:
		check(ForbiddenLands.route_points(kind,3) == old_routes[kind], "Layout 4 contaminated layout 3 route cache: " + String(kind))
		check(ForbiddenLands.route_points(kind) == old_routes[kind], "Default route layout no longer 3: " + String(kind))
	for sample: Array in BEFORE_HEIGHTS:
		var h3 := ForbiddenLandsTerrain.height_at(sample[0],sample[1],3)
		var s3 := ForbiddenLandsTerrain.surface_height(sample[0],sample[1],3)
		var h4 := ForbiddenLandsTerrain.height_at(sample[0],sample[1],4)
		var s4 := ForbiddenLandsTerrain.surface_height(sample[0],sample[1],4)
		check(absf(h3-float(sample[2])) < .0001 and absf(s3-float(sample[3])) < .0001, "Layout 3 terrain changed at " + str(sample.slice(0,2)))
		check(ForbiddenLandsTerrain.height_at(sample[0],sample[1],3) == h3 and ForbiddenLandsTerrain.surface_height(sample[0],sample[1],3) == s3, "Terrain cache contamination at " + str(sample.slice(0,2)))
		report.legacy_height_samples.append({"xz":sample.slice(0,2),"before_height":sample[2],"layout3_height":h3,"layout4_height":h4,"before_surface":sample[3],"layout3_surface":s3,"layout4_surface":s4})
	check(min_gap >= 90.0 - .001, "Expanded layout reduced global minimum arena edge gap")
	var old_samples := PackedFloat64Array()
	var interleaved_samples := PackedFloat64Array()
	for x in range(-2200,1701,137):
		for z in range(-2200,1701,149):
			old_samples.append(ForbiddenLandsTerrain.surface_height(x,z,3))
	for x in range(-2200,1701,137):
		for z in range(-2200,1701,149):
			ForbiddenLandsTerrain.surface_height(x,z,4)
			interleaved_samples.append(ForbiddenLandsTerrain.surface_height(x,z,3))
	check(old_samples.to_byte_array() == interleaved_samples.to_byte_array(), "Layout 3 sampled terrain bytes changed after interleaved layout 4 calls")
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(old_samples.to_byte_array())
	report["layout3_terrain_sample_sha256"] = digest.finish().hex_encode()
	report["layout3_terrain_hash_sample_count"] = old_samples.size()
	report["layout3_interleaved_byte_identity"] = old_samples.to_byte_array() == interleaved_samples.to_byte_array()
	report["before_nearest_ground_edge_gap_m"] = 90.0
	report["after_nearest_ground_edge_gap_m"] = min_gap
	report["minimum_other_arena_route_clearance_m"] = min_clearance

func _surfaces() -> void:
	var world := Node3D.new()
	add_child(world)
	var valley := ForbiddenLands.build_valley(world, &"valus", false, 4)
	check((valley.spawn as Vector3).distance_to(Valley.on_ground(Valley.TEMPLE_SPAWN,.95)) < .001, "Layout 4 temple spawn changed")
	var arenas := WorldMap.build(world, func(kind: StringName, root: Node3D) -> Dictionary:
		if kind in [&"valus", &"gaius"]: return ValusArena.build(root)
		var arena: Script = load("res://src/world/%s_arena.gd" % kind)
		return arena.call(&"build", root), false, 4)
	for kind: StringName in BossRoster.PLAYABLE:
		check((arenas[kind].xf as Transform3D).is_equal_approx(WorldMap.arena_transform(kind,4)), "Built arena transform mismatch: " + String(kind))
		check((valley.gates[kind].pos as Vector3).distance_to(WorldMap.gate(kind,4).pos) < .001, "Built gate mismatch: " + String(kind))
		check((arenas[kind].root as Node3D).global_transform.is_equal_approx(WorldMap.arena_transform(kind,4)), "Built arena root mismatch: " + String(kind))
	for i in 3: await get_tree().physics_frame
	var spawn_samples := []
	for kind: StringName in BossRoster.PLAYABLE:
		var starts := GameWorld.arena_starts(kind)
		var xf := WorldMap.arena_transform(kind,4)
		for index in 2:
			var local: Vector3 = starts[index]
			var p := xf * local
			check((arenas[kind].root as Node3D).to_global(local).distance_to(p) < .001, "Spawn world transform mismatch: " + String(kind))
			var ray := PhysicsRayQueryParameters3D.create(p+Vector3.UP*2,p-Vector3.UP*4,Layers.WORLD)
			ray.hit_back_faces = false
			var hit := world.get_world_3d().direct_space_state.intersect_ray(ray)
			check(not hit.is_empty(), "Missing spawn floor: %s actor%d" % [kind,index])
			spawn_samples.append({"kind":String(kind),"actor":"player" if index == 0 else "horse","world":[p.x,p.y,p.z],"floor_hit":not hit.is_empty()})
	report["spawn_samples"] = spawn_samples
	var hits := 0
	var widened := 0
	for kind: StringName in BossRoster.PLAYABLE:
		var points := ForbiddenLands.route_points(kind,4)
		for i in range(1,points.size(),3):
			var side := (points[i]-points[i-1]).normalized().cross(Vector3.UP).normalized()
			var lanes := [-5.0,0.0,5.0]
			if ForbiddenLands.road_half_at(points[i].x,points[i].z,4) >= 17.5:
				lanes.append_array([-16.0,16.0])
			for lane: float in lanes:
				var p := points[i]+side*lane
				p.y = ForbiddenLands.road_height(p.x,p.z)
				var ray := PhysicsRayQueryParameters3D.create(p+Vector3.UP*.5,p-Vector3.UP*.8,Layers.WORLD)
				ray.hit_back_faces = false
				var hit := world.get_world_3d().direct_space_state.intersect_ray(ray)
				if hit.is_empty(): report.missing_floor_samples.append({"kind":String(kind),"sample":i,"lane":lane,"position":[p.x,p.y,p.z]})
				else: hits += 1
				if absf(lane)>15: widened += 1
	check(report.missing_floor_samples.is_empty(), "Missing physical lane floors: " + str(report.missing_floor_samples.slice(0,12)))
	check(widened > 100, "Too few widened lane samples")
	report["physical_lane_samples"] = hits
	report["widened_lane_samples"] = widened
	world.free()
	await get_tree().physics_frame
