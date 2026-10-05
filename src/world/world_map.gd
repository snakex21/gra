class_name WorldMap
## One continuous world: the valley in the middle, and behind each gate a straight
## corridor to that colossus' arena. The arenas keep their own layout (colossus at the
## local origin, the way in along local +Z); here they get a place in the world:
##
##   arena transform  origin = gate + out * DISTANCE (at the corridor's ground height),
##                    local +Z pointing back along the corridor to the gate
##   corridor         gate -> arena rim: the valley's height field inside the valley,
##                    a flat floor from the valley's edge on; walls on both sides
##   arena rim        an invisible ring at RIM (the art's cliffs stand just inside it),
##                    open only where the corridor comes in
##
## Arenas are discs of GROUND_RADIUS that never overlap the valley or each other (the
## test checks it). The horizon outside is a coarse mesh without collision that sinks
## under the arenas and corridors and rises to ridges between them.

## Gate -> arena centre (along the gate's outward direction).
const LEGACY_DISTANCE := {&"valus": 193.0, &"quadratus": 280.0, &"gaius": 183.0, &"phaedra": 193.0, &"hydrus": 193.0, &"avion": 373.0, &"cave": 550.0}
const DISTANCE := {&"valus": 1400.0, &"quadratus": 1400.0, &"gaius": 1400.0, &"phaedra": 1400.0, &"avion": 1400.0, &"barba": 1400.0, &"hydrus": 1400.0, &"kuromori": 1400.0, &"basaran": 1400.0, &"dirge": 1400.0, &"celosia_cenobia": 1400.0, &"pelagia": 1400.0, &"phalanx": 1400.0, &"argus": 1400.0, &"malus": 1400.0, &"devil": 1400.0, &"phoenix": 1400.0, &"spider": 1400.0, &"worm": 1400.0, &"saru": 1400.0, &"dormin": 1400.0}
## Space reserved for 21 arenas; enabling another fight never moves an earlier one.
const SLOTS := {&"valus": 0, &"avion": 2, &"hydrus": 5, &"gaius": 10, &"quadratus": 14, &"phaedra": 16,
	&"barba": 1, &"kuromori": 3, &"basaran": 4, &"dirge": 6, &"celosia_cenobia": 7, &"pelagia": 8,
	&"phalanx": 9, &"argus": 11, &"malus": 12, &"devil": 13, &"phoenix": 15, &"spider": 17,
	&"worm": 18, &"saru": 19, &"dormin": 20}
const GROUND_RADIUS := 175.0
## The invisible rim of an arena (local radius).
const RIM := 170.0
## Inner width of a corridor.
const CORRIDOR_WIDTH := 16.0
## Low enough for the sun to reach most of the corridor floor (the beam needs it).
const WALL_HEIGHT := 7.0
## Half size of the valley's height field (its collision ends there).
const VALLEY_HALF := 180.0


static func gates(layout := 2) -> Dictionary:
	if layout >= 3:
		return ForbiddenLands.gates(layout)
	if layout == 1:
		return Valley.GATES
	var result := {}
	for kind: StringName in BossRoster.PLAYABLE:
		var angle := PI + float(SLOTS[kind]) * TAU / 21.0
		var outward := Vector3(sin(angle), 0, cos(angle))
		result[kind] = {"pos": outward * (Valley.EDGE / maxf(absf(outward.x), absf(outward.z))), "out": outward}
	return result

static func gate(kind: StringName, layout := 2) -> Dictionary:
	return gates(layout)[kind]


static func out_dir(kind: StringName, layout := 2) -> Vector3:
	return (gate(kind, layout).out as Vector3).normalized()


## Where the corridor leaves the valley's height field (XZ, y = valley ground there).
static func valley_exit(kind: StringName, layout := 2) -> Vector3:
	if layout >= 3:
		for point: Vector3 in ForbiddenLands.route_points(kind, layout):
			if maxf(absf(point.x), absf(point.z)) >= VALLEY_HALF:
				return point
	var g: Vector3 = gate(kind, layout).pos
	var o := out_dir(kind, layout)
	var t := INF
	if absf(o.x) > 1e-4:
		t = minf(t, ((VALLEY_HALF if o.x > 0.0 else -VALLEY_HALF) - g.x) / o.x)
	if absf(o.z) > 1e-4:
		t = minf(t, ((VALLEY_HALF if o.z > 0.0 else -VALLEY_HALF) - g.z) / o.z)
	return Valley.on_ground(g + o * t)


## The arena's ground height (= the valley's ground where the corridor leaves it).
static func arena_height(kind: StringName, layout := 2) -> float:
	if layout >= 3:
		return 0.0
	return valley_exit(kind, layout).y


static func arena_transform(kind: StringName, layout := 2) -> Transform3D:
	if layout >= 3:
		return ForbiddenLands.arena_transform(kind, layout)
	var g: Vector3 = gate(kind, layout).pos
	var o := out_dir(kind, layout)
	var c := g + o * float((LEGACY_DISTANCE if layout == 1 else DISTANCE)[kind])
	c.y = arena_height(kind, layout)
	# Local +Z = back towards the gate (-out).
	return Transform3D(Basis(Vector3.UP, atan2(-o.x, -o.z)), c)


## Where the corridor meets the arena's rim (world).
static func rim_entry(kind: StringName, layout := 2) -> Vector3:
	return arena_transform(kind, layout) * Vector3(0, 0, RIM)


## True when ``p`` is inside the arena's disc (XZ).
static func in_arena(kind: StringName, p: Vector3, layout := 2) -> bool:
	var c := arena_transform(kind, layout).origin
	return Vector2(p.x - c.x, p.z - c.z).length() < GROUND_RADIUS


## Builds corridors, rims, arena roots and the horizon under ``parent``. The arenas'
## geometry is made by ``build_arena`` (a Callable(kind, root) -> Dictionary).
## Returns {kind: {"root": Node3D, "xf": Transform3D, "points": Dictionary}}.
static func build(parent: Node3D, build_arena: Callable, with_art := true, layout := 2) -> Dictionary:
	if layout >= 3:
		return ForbiddenLands.build(parent, build_arena, with_art, layout)
	var arenas := {}
	var stone := ArenaArt.material(ArenaArt.Kind.STONE) if with_art else _plain(Color(0.55, 0.53, 0.48))
	for kind: StringName in gates(layout):
		var root := Node3D.new()
		root.name = "Arena_%s" % kind
		root.transform = arena_transform(kind, layout)
		parent.add_child(root)
		var points: Dictionary = build_arena.call(kind, root)
		_rim(root)
		_corridor(parent, kind, stone, layout)
		arenas[kind] = {"root": root, "xf": root.transform, "points": points}
	if with_art:
		_horizon(parent, layout)
	return arenas


## The invisible ring round an arena with the gap for the corridor (local +Z).
static func _rim(root: Node3D) -> void:
	var n := 36
	var seg := TAU * RIM / n + 1.0
	var gap := (CORRIDOR_WIDTH * 0.5 + 2.0) / RIM
	for i in n:
		var a := (i + 0.5) * TAU / n
		# Angle measured from local +Z (the corridor).
		if absf(angle_difference(a, 0.0)) < gap + PI / n:
			continue
		var dir := Vector3(sin(a), 0, cos(a))
		var wall := TerrainKit.box(root, dir * (RIM + 1.0) + Vector3.UP * 10.0, Vector3(seg, 40.0, 2.0), null, Basis(Vector3.UP, a))
		wall.name = "ArenaRim"
		for c in wall.get_children():
			if c is MeshInstance3D:
				c.visible = false


## Walls from the valley's edge (where they close the gate's opening) to the rim, and
## the floor from the valley's edge to the rim.
static func _corridor(parent: Node3D, kind: StringName, stone: Material, layout := 2) -> void:
	var o := out_dir(kind, layout)
	var side := o.cross(Vector3.UP).normalized()
	var yaw := atan2(o.x, o.z)
	var rot := Basis(Vector3.UP, yaw)
	var exit := valley_exit(kind, layout)
	var y := exit.y
	var rim := rim_entry(kind, layout)
	var starts := Valley.gate_opening(kind, Valley.EDGE, layout)
	var i := 0
	for s: float in [-1.0, 1.0]:
		var a: Vector3 = starts[i] - o * 1.0
		var b := rim + side * s * (CORRIDOR_WIDTH * 0.5 + 1.0) + o * 1.0
		i += 1
		var length := Vector2(b.x - a.x, b.z - a.z).length()
		var ground_a := Valley.ground_height(a.x, a.z)
		var low := minf(ground_a, y) - 6.0
		var high := maxf(ground_a, y) + WALL_HEIGHT
		var c := (a + b) * 0.5
		c.y = (low + high) * 0.5
		var wall := TerrainKit.box(parent, c, Vector3(2.0, high - low, length), stone, rot)
		wall.name = "CorridorWall_%s" % kind
	var floor_start := exit
	var floor_len := Vector2(rim.x - floor_start.x, rim.z - floor_start.z).length() + 6.0
	var fc := floor_start + o * (floor_len * 0.5 - 2.0)
	if layout >= 2:
		floor_len = Vector2(rim.x - floor_start.x, rim.z - floor_start.z).length() + 0.1
		fc = floor_start + o * (floor_len * 0.5 - 0.02)
	fc.y = y - 1.0
	var floor := TerrainKit.box(parent, fc, Vector3(CORRIDOR_WIDTH + 4.0, 2.0, floor_len), stone, rot)
	floor.name = "CorridorFloor_%s" % kind
	if layout >= 2:
		_corridor_apron(parent, kind, stone, layout)


## Blend the entire entrance width into the flat corridor. A diagonal gate crosses
## the height field edge at a different point and height for each lateral lane.
static func _corridor_apron(parent: Node3D, kind: StringName, stone: Material, layout: int) -> void:
	var outward := out_dir(kind, layout)
	var side := outward.cross(Vector3.UP).normalized()
	var exit := valley_exit(kind, layout)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for along in range(-24, 24):
		for across in range(-10, 10):
			for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]:
				var point := exit + outward * (float(along) + corner.x) + side * (float(across) + corner.y)
				point.y = _apron_height(point, outward, exit.y)
				st.set_uv(Vector2(float(across) + corner.y, float(along) + corner.x) * 0.2)
				st.add_vertex(point)
	st.generate_normals()
	var mesh := st.commit()
	var body := StaticBody3D.new()
	body.name = "CorridorApron_%s" % kind
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.add_to_group(&"walkable_terrain")
	var collision := CollisionShape3D.new()
	collision.shape = mesh.create_trimesh_shape()
	body.add_child(collision)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = stone
	body.add_child(visual)
	parent.add_child(body)


static func _apron_height(point: Vector3, outward: Vector3, floor_y: float) -> float:
	# Signed distance along the route to the square height field's boundary.
	var to_edge := INF
	if absf(outward.x) > 0.0001:
		to_edge = minf(to_edge, ((VALLEY_HALF if outward.x > 0.0 else -VALLEY_HALF) - point.x) / outward.x)
	if absf(outward.z) > 0.0001:
		to_edge = minf(to_edge, ((VALLEY_HALF if outward.z > 0.0 else -VALLEY_HALF) - point.z) / outward.z)
	var edge := point + outward * to_edge
	var edge_y := _valley_collision_height(edge.x, edge.z)
	if to_edge >= 0.0:
		var natural := maxf(Valley.ground_height(point.x, point.z), _valley_collision_height(point.x, point.z))
		return lerpf(natural, maxf(natural, floor_y), 1.0 - smoothstep(0.0, 12.0, to_edge)) + 0.015
	return lerpf(maxf(edge_y, floor_y), floor_y, smoothstep(0.0, 12.0, -to_edge)) + 0.015


## The native height field samples every four metres. Its edge is interpolated
## between samples, so the analytic terrain function alone can leave a lip there.
static func _valley_collision_height(x: float, z: float) -> float:
	var x0 := clampf(floorf(x / 4.0) * 4.0, -VALLEY_HALF, VALLEY_HALF - 4.0)
	var z0 := clampf(floorf(z / 4.0) * 4.0, -VALLEY_HALF, VALLEY_HALF - 4.0)
	var u := clampf((x - x0) / 4.0, 0.0, 1.0)
	var v := clampf((z - z0) / 4.0, 0.0, 1.0)
	var h00 := Valley.ground_height(x0, z0)
	var h10 := Valley.ground_height(x0 + 4.0, z0)
	var h01 := Valley.ground_height(x0, z0 + 4.0)
	var h11 := Valley.ground_height(x0 + 4.0, z0 + 4.0)
	var diagonal_a := (1.0 - u) * h00 + (u - v) * h10 + v * h11 if u >= v else (1.0 - v) * h00 + (v - u) * h01 + u * h11
	var diagonal_b := (1.0 - u - v) * h00 + u * h10 + v * h01 if u + v <= 1.0 else (1.0 - v) * h10 + (1.0 - u) * h01 + (u + v - 1.0) * h11
	return maxf(diagonal_a, diagonal_b)


## A coarse, non-colliding landscape round everything playable: it meets the valley's
## height field at its edge, sinks under the arenas and corridors, and rises to ridges
## in between (so the arenas sit in basins and nothing is cut off at the horizon).
static func _horizon(parent: Node3D, layout := 2) -> void:
	var half := 940 if layout == 1 else 1880
	var cell := 20 if layout == 1 else 40
	var regions := _horizon_regions(layout)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hcache := {}
	for z in range(-half, half, cell):
		for x in range(-half, half, cell):
			if x >= -VALLEY_HALF and x < VALLEY_HALF and z >= -VALLEY_HALF and z < VALLEY_HALF:
				continue
			for c in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var px: int = x + c.x * cell
				var pz: int = z + c.y * cell
				var key := Vector2i(px, pz)
				if not hcache.has(key):
					hcache[key] = horizon_height(px, pz, layout, regions)
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(px, pz) * 0.2)
				st.add_vertex(Vector3(px, hcache[key], pz))
	st.generate_normals()
	var n := MeshInstance3D.new()
	n.name = "WorldHorizon_NoCollision"
	n.mesh = st.commit()
	n.material_override = load("res://materials/ancient_valley/terrain.tres")
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(n)


static func _horizon_regions(layout: int) -> Array:
	var result := []
	for kind: StringName in gates(layout):
		var xf := arena_transform(kind, layout)
		var exit := valley_exit(kind, layout)
		var rim := rim_entry(kind, layout)
		result.append([Vector2(xf.origin.x, xf.origin.z), Vector2(exit.x, exit.z), Vector2(rim.x, rim.z), xf.origin.y])
	return result

static func horizon_height(x: float, z: float, layout := 2, regions := []) -> float:
	var p := Vector2(x, z)
	# Inside an arena or a corridor beyond the valley: below its floor.
	var near := INF
	var floor_y := 0.0
	for area: Array in _horizon_regions(layout) if regions.is_empty() else regions:
		var c: Vector2 = area[0]
		var d_arena := p.distance_to(c) - GROUND_RADIUS
		var a: Vector2 = area[1]
		var r: Vector2 = area[2]
		var d_corr := Geometry2D.get_closest_point_to_segment(p, a, r).distance_to(p) - CORRIDOR_WIDTH * 0.5 - 6.0
		var d := minf(d_arena, d_corr)
		if d < near:
			near = d
			floor_y = float(area[3])
	var edge := maxf(absf(x), absf(z)) - VALLEY_HALF
	var ridge := 26.0 + 10.0 * sin(x * 0.021) + 8.0 * cos(z * 0.027)
	var natural := Valley.ground_height(clampf(x, -VALLEY_HALF, VALLEY_HALF), clampf(z, -VALLEY_HALF, VALLEY_HALF))
	natural += ridge * smoothstep(0.0, 70.0, edge)
	if near <= 0.0:
		return floor_y - 4.0
	# Rising from the basin's floor to the ridges.
	return lerpf(floor_y - 2.0, natural, smoothstep(0.0, 45.0, near))


static func _plain(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m
