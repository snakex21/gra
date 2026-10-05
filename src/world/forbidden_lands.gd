class_name ForbiddenLands
extends RefCounted
## Layout 3: original, compact geography inspired by reference maps, never asset copies.
## North +Z, east +X. Stable routes are derived from position, not a saved route cursor.
const CELL := 440.0
const ROAD_HALF := 14.0
const GATE_DISTANCE := 220.0
const SAMPLE_STEP := 8.0
const COMMON := [Vector2(-32, -65), Vector2(-110, -90)]
const NORTH := [Vector2(-135, 25), Vector2(-140, 135), Vector2(-225, 220), Vector2(-235, 450), Vector2(-225, 670)]
const WEST := [Vector2(-240, -70), Vector2(-425, -135), Vector2(-625, -110), Vector2(-650, 160)]
const SOUTH := [Vector2(-130, -220), Vector2(-230, -280), Vector2(-235, -470), Vector2(-200, -650), Vector2(-175, -700)]
const EAST := [Vector2(90, -90), Vector2(190, -80), Vector2(290, -130), Vector2(410, -150), Vector2(640, -180)]
## [centre XZ, reference grid, regional profile, shared trunk, trunk points, branch].
const REGIONS := {
	&"valus": [Vector2(0, -440), "F5", "southern_cliffs", SOUTH, 1, [Vector2(-135, -265)]],
	&"quadratus": [Vector2(0, 440), "F3", "northern_canyon", NORTH, 3, [Vector2(-120, 210), Vector2(-100, 235)]],
	&"gaius": [Vector2(-440, 880), "E2", "western_highland", NORTH, 5, [Vector2(-285, 690)]],
	&"phaedra": [Vector2(440, -440), "G5", "eastern_grassland", EAST, 3, [Vector2(320, -210)]],
	&"avion": [Vector2(880, 0), "H4", "eastern_lake", EAST, 5, [Vector2(665, -235), Vector2(750, -195)]],
	&"barba": [Vector2(-880, -880), "D6", "forest_tomb", WEST, 3, [Vector2(-740, -310), Vector2(-660, -480), Vector2(-675, -640), Vector2(-675, -680)]],
	&"hydrus": [Vector2(-880, 1320), "D1", "northern_lake", NORTH, 5, [Vector2(-610, 620), Vector2(-700, 820), Vector2(-750, 990), Vector2(-690, 1180)]],
	&"kuromori": [Vector2(440, -880), "G6", "southern_ruins", SOUTH, 5, [Vector2(190, -675), Vector2(230, -735)]],
	&"basaran": [Vector2(-880, 440), "D3", "western_geysers", WEST, 4, [Vector2(-700, 240)]],
	&"dirge": [Vector2(-1760, 0), "B4", "western_cavern", WEST, 3, [Vector2(-880, -150), Vector2(-1150, -135), Vector2(-1430, -160)]],
	&"celosia_cenobia": [Vector2(-1320, 880), "C2 + shared Celosia", "western_city", NORTH, 5, [Vector2(-610, 620), Vector2(-800, 780), Vector2(-1070, 690), Vector2(-1150, 740)]],
	&"pelagia": [Vector2(440, 880), "G2", "eastern_falls", NORTH, 5, [Vector2(-20, 695), Vector2(150, 665), Vector2(290, 700)]],
	&"phalanx": [Vector2(-440, -880), "E6", "southern_desert", SOUTH, 5, [Vector2(-260, -715)]],
	&"argus": [Vector2(880, 1320), "H1", "northern_fortress", NORTH, 5, [Vector2(-20, 695), Vector2(150, 665), Vector2(210, 1080), Vector2(370, 1250), Vector2(580, 1140)]],
	&"malus": [Vector2(0, -1760), "F8", "southern_citadel", SOUTH, 5, [Vector2(-160, -1040), Vector2(-190, -1300), Vector2(-135, -1510)]],
	&"devil": [Vector2(1320, 880), "own I2 extension", "eastern_cave", EAST, 5, [Vector2(730, -280), Vector2(1090, -290), Vector2(1110, 220), Vector2(1190, 400), Vector2(1140, 630)]],
	&"phoenix": [Vector2(1320, 0), "own I4 crater", "eastern_crater", EAST, 5, [Vector2(730, -280), Vector2(980, -270), Vector2(1110, -225)]],
	&"spider": [Vector2(-1320, -440), "own C5 extension", "forest_ruins", WEST, 3, [Vector2(-880, -150), Vector2(-1060, -220), Vector2(-1080, -280)]],
	&"worm": [Vector2(-1320, -1320), "own C7 extension", "western_dunes", WEST, 3, [Vector2(-740, -310), Vector2(-660, -480), Vector2(-675, -640), Vector2(-1120, -620), Vector2(-1190, -890), Vector2(-1150, -1080)]],
	&"saru": [Vector2(0, 1320), "own F1 ruined span", "northern_bridges", NORTH, 5, [Vector2(-20, 695), Vector2(90, 880), Vector2(-100, 1040)]],
	&"dormin": [Vector2(440, 440), "own G3 chapel", "temple_annex", EAST, 2, [Vector2(240, 100), Vector2(190, 280), Vector2(250, 310)]]
}
## Layout 4 is an opt-in geography for new games. Layout 3 remains immutable for
## checkpoints/replays. Only selected crowded northern/southern clusters move.
const EXPANDED_CENTRES := {
	&"phaedra": Vector2(540, -500), &"kuromori": Vector2(610, -1050),
	&"phalanx": Vector2(-440, -1140),
	&"saru": Vector2(0, 1510), &"pelagia": Vector2(560, 980),
	&"argus": Vector2(1040, 1460)
}
static var _expanded_regions := {}

static func regions(layout := 3) -> Dictionary:
	if layout != 4:
		return REGIONS
	if _expanded_regions.is_empty():
		_expanded_regions = REGIONS.duplicate(true)
		for kind: StringName in EXPANDED_CENTRES:
			var delta: Vector2 = EXPANDED_CENTRES[kind] - REGIONS[kind][0]
			_expanded_regions[kind][0] = EXPANDED_CENTRES[kind]
			# Keep shared trunks fixed. Feather the individual approach to preserve
			# its final heading/gate relationship rather than scaling the whole map.
			var branch: Array = _expanded_regions[kind][5]
			for i in branch.size():
				branch[i] += delta * float(i + 1) / branch.size()
	return _expanded_regions

static func road_half_at(x: float, z: float, layout := 3) -> float:
	if layout != 4:
		return ROAD_HALF
	# Retain existing shrine, gate and bridge envelopes. Open-country approaches
	# broaden smoothly from 28 to 36 metres, including physical collision.
	var p := Vector2(x, z)
	var blend := smoothstep(250, 350, maxf(absf(x), absf(z)))
	for data: Array in regions(layout).values():
		blend = minf(blend, smoothstep(245, 320, p.distance_to(data[0])))
	if z > 200 and z < 660:
		blend *= smoothstep(65, 115, absf(x + 230))
	return ROAD_HALF + 4.0 * blend

static var _routes := {}
static var _edges := {}

static func arena_transform(kind: StringName, layout := 3) -> Transform3D:
	var data: Array = regions(layout)[kind]
	var centre: Vector2 = data[0]
	var branch: Array = data[5]
	var back: Vector2 = (branch.back() as Vector2) - centre
	back = back.normalized()
	return Transform3D(Basis(Vector3.UP, atan2(back.x, back.y)), Vector3(centre.x, 0, centre.y))

static func gates(layout := 3) -> Dictionary:
	var result := {}
	for kind: StringName in BossRoster.PLAYABLE:
		var xf := arena_transform(kind, layout)
		var pos := xf * Vector3(0, 0, GATE_DISTANCE)
		result[kind] = {"pos": pos, "out": -xf.basis.z, "trigger": pos - xf.basis.z * Valley.GATE_TRIGGER, "layout": layout}
	return result

static func route_points(kind: StringName, layout := 3) -> PackedVector3Array:
	var key := "%d:%s" % [layout, kind]
	if _routes.has(key):
		return _routes[key]
	var data: Array = regions(layout)[kind]
	var points: Array[Vector2] = []
	for point: Vector2 in COMMON:
		points.append(point)
	var trunk: Array = data[3]
	for index in int(data[4]):
		points.append(trunk[index])
	for point: Vector2 in data[5]:
		points.append(point)
	var xf := arena_transform(kind, layout)
	# Exactly straight for the existing arena-approach bot, from gate to local Z=145.
	for distance in [GATE_DISTANCE, WorldMap.RIM, 145.0]:
		var p := xf * Vector3(0, 0, distance)
		points.append(Vector2(p.x, p.z))
	var dense := PackedVector3Array()
	var last: Vector2 = points[0]
	dense.append(_road_point(last))
	for i in range(1, points.size() - 1):
		var b := points[i]
		var before := b - points[i - 1]
		var after := points[i + 1] - b
		var radius := minf(28.0, minf(before.length(), after.length()) * 0.22)
		if i >= points.size() - 3:
			radius = 0.0
		var start := b - before.normalized() * radius
		var end := b + after.normalized() * radius
		_line(dense, last, start)
		if radius > 0.01:
			for step in 8:
				var t := float(step + 1) / 8.0
				dense.append(_road_point(start.lerp(b, t).lerp(b.lerp(end, t), t)))
		last = end
	_line(dense, last, points.back())
	_routes[key] = dense
	return dense

static func _line(points: PackedVector3Array, a: Vector2, b: Vector2) -> void:
	var steps := maxi(1, ceili(a.distance_to(b) / SAMPLE_STEP))
	for i in steps:
		points.append(_road_point(a.lerp(b, float(i + 1) / steps)))

static func _road_point(p: Vector2) -> Vector3:
	return Vector3(p.x, road_height(p.x, p.y), p.y)

static func road_height(x: float, z: float) -> float:
	var edge := maxf(absf(x), absf(z))
	if edge >= 300:
		return 0.0
	var px := clampf(x, -WorldMap.VALLEY_HALF, WorldMap.VALLEY_HALF)
	var pz := clampf(z, -WorldMap.VALLEY_HALF, WorldMap.VALLEY_HALF)
	var native := maxf(Valley.ground_height(px, pz), WorldMap._valley_collision_height(px, pz))
	# Keep the original height-field boundary intact. Lowering the apron before
	# the edge leaves a two-metre drop where Agro quite correctly refuses to go.
	return (native + .035) * (1.0 - smoothstep(180.0, 300.0, edge))

static func route_length(kind: StringName, layout := 3) -> float:
	var points := route_points(kind, layout)
	var length := 0.0
	for i in range(1, points.size()):
		length += points[i - 1].distance_to(points[i])
	return length

static func _nearest(kind: StringName, p: Vector3, layout := 3) -> Dictionary:
	var points := route_points(kind, layout)
	var query := Vector2(p.x, p.z)
	var best := INF
	var index := 0
	var fraction := 0.0
	for i in range(1, points.size()):
		var a := Vector2(points[i - 1].x, points[i - 1].z)
		var b := Vector2(points[i].x, points[i].z)
		var on := Geometry2D.get_closest_point_to_segment(query, a, b)
		var distance := query.distance_squared_to(on)
		if distance < best:
			best = distance
			index = i - 1
			fraction = a.distance_to(on) / maxf(0.001, a.distance_to(b))
	return {"index": index, "fraction": fraction, "distance": sqrt(best)}

static func guide_target(kind: StringName, p: Vector3, layout := 3) -> Vector3:
	var points := route_points(kind, layout)
	var near := _nearest(kind, p, layout)
	var i: int = near.index
	var on := points[i].lerp(points[i + 1], near.fraction)
	# Off a road, first return to the actual road instead of cutting through ridges.
	if near.distance > ROAD_HALF * 0.7:
		return on
	var left := 28.0
	for j in range(i + 1, points.size()):
		var distance := on.distance_to(points[j])
		if distance >= left:
			return on.lerp(points[j], left / maxf(distance, 0.001))
		left -= distance
		on = points[j]
	return points[points.size() - 1]

static func route_heading(kind: StringName, p: Vector3, layout := 3) -> Vector3:
	var direction := guide_target(kind, p, layout) - p
	direction.y = 0
	return direction.normalized() if direction.length() > 0.1 else -arena_transform(kind, layout).basis.z

static func road_edges(layout := 3) -> Array[Array]:
	if _edges.has(layout):
		return _edges[layout]
	var edges: Array[Array] = []
	var used := {}
	for kind: StringName in BossRoster.PLAYABLE:
		var points := route_points(kind, layout)
		for i in range(1, points.size()):
			var a := points[i - 1]
			var b := points[i]
			var key := str(a.snapped(Vector3.ONE * 0.01)) + ":" + str(b.snapped(Vector3.ONE * 0.01))
			if not used.has(key) and a.distance_to(b) > 0.01:
				used[key] = true
				edges.append([a, b])
	_edges[layout] = edges
	return edges

static func build_valley(parent: Node3D, open_gate: StringName, with_art := true, layout := 3) -> Dictionary:
	# Reuse our existing original temple/actors; legacy layouts retain their own build.
	var result := Valley.build(parent, &"", with_art, true, 1)
	for node in parent.get_children():
		# All direct static bodies from this legacy build are its square edge walls.
		# Godot renames repeated WorldEdge siblings with generated @ names.
		if node is StaticBody3D or String(node.name).begins_with("Gate_"):
			parent.remove_child(node)
			node.free()
	var kit: Node3D = result.kit
	for prop in kit.get_children():
		if not prop is Node3D or not (String(prop.name).begins_with("cliff") or String(prop.name).begins_with("rock")):
			continue
		if _distance_to_roads(Vector2(prop.position.x, prop.position.z), layout) < 30:
			kit.remove_child(prop)
			prop.free()
	var actual := {}
	for kind: StringName in gates(layout):
		var gate_data: Dictionary = gates(layout)[kind].duplicate()
		var gate_root := Node3D.new()
		gate_root.name = "Gate_%s" % kind
		gate_root.transform = Transform3D(arena_transform(kind, layout).basis, gate_data.pos)
		parent.add_child(gate_root)
		var stone := ArenaArt.material(ArenaArt.Kind.STONE)
		for side: float in [-1.0, 1.0]:
			TerrainKit.box(gate_root, Vector3(side * 13, 5.5, 0), Vector3(3, 11, 3), stone)
		TerrainKit.box(gate_root, Vector3(0, 11.4, 0), Vector3(29, 1.8, 3.5), stone)
		if kind != open_gate:
			var mist := StandardMaterial3D.new()
			mist.albedo_color = Color(.65, .74, .77, .30)
			mist.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mist.cull_mode = BaseMaterial3D.CULL_DISABLED
			TerrainKit.box(gate_root, Vector3(0, 5, 0), Vector3(23, 11, 1), mist).name = "Mist"
		gate_data["open"] = kind == open_gate
		gate_data["node"] = gate_root
		actual[kind] = gate_data
	result.gates = actual
	result["layout"] = layout
	return result

static func build(parent: Node3D, build_arena: Callable, with_art := true, layout := 3) -> Dictionary:
	var arenas := {}
	for kind: StringName in BossRoster.PLAYABLE:
		var root := Node3D.new()
		root.name = "Arena_%s" % kind
		root.transform = arena_transform(kind, layout)
		parent.add_child(root)
		var points: Dictionary = build_arena.call(kind, root)
		WorldMap._rim(root)
		arenas[kind] = {"root": root, "xf": root.transform, "points": points, "route": route_points(kind, layout), "biome": regions(layout)[kind][2]}
	ForbiddenLandsTerrain.build(parent, with_art, layout)
	return arenas

static func _distance_to_roads(p: Vector2, layout := 3) -> float:
	var best := INF
	for edge: Array in road_edges(layout):
		var a: Vector3 = edge[0]
		var b: Vector3 = edge[1]
		best = minf(best, Geometry2D.get_closest_point_to_segment(p, Vector2(a.x, a.z), Vector2(b.x, b.z)).distance_to(p))
	return best
