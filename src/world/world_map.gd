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
const DISTANCE := {&"valus": 193.0, &"quadratus": 280.0, &"gaius": 183.0, &"phaedra": 193.0, &"hydrus": 193.0}
const GROUND_RADIUS := 175.0
## The invisible rim of an arena (local radius).
const RIM := 170.0
## Inner width of a corridor.
const CORRIDOR_WIDTH := 16.0
## Low enough for the sun to reach most of the corridor floor (the beam needs it).
const WALL_HEIGHT := 7.0
## Half size of the valley's height field (its collision ends there).
const VALLEY_HALF := 180.0


static func gate(kind: StringName) -> Dictionary:
	return Valley.GATES[kind]


static func out_dir(kind: StringName) -> Vector3:
	return (gate(kind).out as Vector3).normalized()


## Where the corridor leaves the valley's height field (XZ, y = valley ground there).
static func valley_exit(kind: StringName) -> Vector3:
	var g: Vector3 = gate(kind).pos
	var o := out_dir(kind)
	var t := INF
	if absf(o.x) > 1e-4:
		t = minf(t, ((VALLEY_HALF if o.x > 0.0 else -VALLEY_HALF) - g.x) / o.x)
	if absf(o.z) > 1e-4:
		t = minf(t, ((VALLEY_HALF if o.z > 0.0 else -VALLEY_HALF) - g.z) / o.z)
	return Valley.on_ground(g + o * t)


## The arena's ground height (= the valley's ground where the corridor leaves it).
static func arena_height(kind: StringName) -> float:
	return valley_exit(kind).y


static func arena_transform(kind: StringName) -> Transform3D:
	var g: Vector3 = gate(kind).pos
	var o := out_dir(kind)
	var c := g + o * float(DISTANCE[kind])
	c.y = arena_height(kind)
	# Local +Z = back towards the gate (-out).
	return Transform3D(Basis(Vector3.UP, atan2(-o.x, -o.z)), c)


## Where the corridor meets the arena's rim (world).
static func rim_entry(kind: StringName) -> Vector3:
	return arena_transform(kind) * Vector3(0, 0, RIM)


## True when ``p`` is inside the arena's disc (XZ).
static func in_arena(kind: StringName, p: Vector3) -> bool:
	var c := arena_transform(kind).origin
	return Vector2(p.x - c.x, p.z - c.z).length() < GROUND_RADIUS


## Builds corridors, rims, arena roots and the horizon under ``parent``. The arenas'
## geometry is made by ``build_arena`` (a Callable(kind, root) -> Dictionary).
## Returns {kind: {"root": Node3D, "xf": Transform3D, "points": Dictionary}}.
static func build(parent: Node3D, build_arena: Callable, with_art := true) -> Dictionary:
	var arenas := {}
	var stone := ArenaArt.material(ArenaArt.Kind.STONE) if with_art else _plain(Color(0.55, 0.53, 0.48))
	for kind: StringName in Valley.GATES:
		var root := Node3D.new()
		root.name = "Arena_%s" % kind
		root.transform = arena_transform(kind)
		parent.add_child(root)
		var points: Dictionary = build_arena.call(kind, root)
		_rim(root)
		_corridor(parent, kind, stone)
		arenas[kind] = {"root": root, "xf": root.transform, "points": points}
	if with_art:
		_horizon(parent)
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
static func _corridor(parent: Node3D, kind: StringName, stone: Material) -> void:
	var o := out_dir(kind)
	var side := o.cross(Vector3.UP).normalized()
	var yaw := atan2(o.x, o.z)
	var rot := Basis(Vector3.UP, yaw)
	var exit := valley_exit(kind)
	var y := exit.y
	var rim := rim_entry(kind)
	var starts := Valley.gate_opening(kind, Valley.EDGE)
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
	fc.y = y - 1.0
	var floor := TerrainKit.box(parent, fc, Vector3(CORRIDOR_WIDTH + 4.0, 2.0, floor_len), stone, rot)
	floor.name = "CorridorFloor_%s" % kind


## A coarse, non-colliding landscape round everything playable: it meets the valley's
## height field at its edge, sinks under the arenas and corridors, and rises to ridges
## in between (so the arenas sit in basins and nothing is cut off at the horizon).
static func _horizon(parent: Node3D) -> void:
	const HALF := 760
	const CELL := 20
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hcache := {}
	for z in range(-HALF, HALF, CELL):
		for x in range(-HALF, HALF, CELL):
			if x >= -VALLEY_HALF and x < VALLEY_HALF and z >= -VALLEY_HALF and z < VALLEY_HALF:
				continue
			for c in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var px: int = x + c.x * CELL
				var pz: int = z + c.y * CELL
				var key := Vector2i(px, pz)
				if not hcache.has(key):
					hcache[key] = horizon_height(px, pz)
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


static func horizon_height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	# Inside an arena or a corridor beyond the valley: below its floor.
	var near := INF
	var floor_y := 0.0
	for kind: StringName in Valley.GATES:
		var xf := arena_transform(kind)
		var c := Vector2(xf.origin.x, xf.origin.z)
		var d_arena := p.distance_to(c) - GROUND_RADIUS
		var a := Vector2(valley_exit(kind).x, valley_exit(kind).z)
		var r := rim_entry(kind)
		var d_corr := Geometry2D.get_closest_point_to_segment(p, a, Vector2(r.x, r.z)).distance_to(p) - CORRIDOR_WIDTH * 0.5 - 6.0
		var d := minf(d_arena, d_corr)
		if d < near:
			near = d
			floor_y = xf.origin.y
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
