class_name Valley
## The valley between the fights: the temple where every journey starts, open ground to
## ride, and three gates at its edges, one to each colossus' arena:
##
##   Valus      south, across the open basin
##   Quadratus  north, past the lake
##   Gaius      west, through the canyon
##   Phaedra    east, up the slope
##   Hydrus     west, over the ridge (a lake behind it)
##   Avion      south-west, a long way to a lake with towers
##
## The ground, the temple and the rocks are the Ancient Valley kit (art/scripts/
## ancient_valley.gd, CC0): its height field and low-poly collisions are the gameplay
## ground here (unlike the arenas, where art is only a skin). The valley adds what play
## needs on top: the world's edge, the gates (open only towards the next colossus),
## spawn points and the sun direction for the sword's beam.

const ValleyArt := preload("res://art/scripts/ancient_valley.gd")

## Player spawn in the temple (in front of the altar), facing the way out (south).
const TEMPLE_SPAWN := Vector3(-32, 0, 25)
const TEMPLE_YAW := 0.0
## Agro waits below the temple stairs.
const HORSE_SPAWN := Vector3(-26, 0, 8)
## The world's edge (half size): beyond it the kit has no ground.
const EDGE := 172.0
## Gate: centre of the opening on the ground, the outward direction (towards the arena),
## and the trigger distance past the opening. The gates stand in the world's edge: the
## only openings in it, each into the corridor to its arena (WorldMap).
const GATES := {
	&"valus": {"pos": Vector3(0, 0, -172), "out": Vector3(0, 0, -1)},
	&"quadratus": {"pos": Vector3(36, 0, 172), "out": Vector3(0.8, 0, 0.6)},
	&"gaius": {"pos": Vector3(-96, 0, 172), "out": Vector3(0, 0, 1)},
	&"phaedra": {"pos": Vector3(172, 0, -100), "out": Vector3(1, 0, 0)},
	&"hydrus": {"pos": Vector3(-172, 0, -120), "out": Vector3(-1, 0, 0)},
	&"avion": {"pos": Vector3(-150, 0, -172), "out": Vector3(-0.544, 0, -0.839)},
	&"cave": {"pos": Vector3(172, 0, 80), "out": Vector3(1, 0, 0)},
}
const GATE_WIDTH := 12.0
const GATE_TRIGGER := 6.0
## The kit's lake: its surface and a disc round it (the water is where the ground is lower).
const LAKE_CENTER := Vector3(40, -0.35, 42)
const LAKE_RADIUS := 38.0
## Sun (towards the light) for the beam and the shadow test; matches the region's light.
const SUN_DIRECTION := Vector3(0.35, 0.85, 0.4)


static func ground_height(x: float, z: float) -> float:
	return ValleyArt.height_at(x, z)


static func on_ground(p: Vector3, lift := 0.0) -> Vector3:
	return Vector3(p.x, ground_height(p.x, p.z) + lift, p.z)


## Builds the valley under ``parent``. ``open_gate``: the colossus whose gate lets you
## through (&"" = none). Without art the kit still builds its ground and collisions, only
## the grass is left out (tests). ``world``: the valley is part of the continuous world
## (WorldMap): the world's edge has openings where the corridors leave, and the kit's
## own horizon gives way to the world's.
static func build(parent: Node3D, open_gate: StringName, with_art := true, world := false, layout := 2) -> Dictionary:
	if layout >= 3:
		return ForbiddenLands.build_valley(parent, open_gate, with_art, layout)
	var kit := Node3D.new()
	kit.name = "AncientValley"
	kit.set_script(ValleyArt)
	kit.set(&"include_collision", true)
	if not with_art:
		kit.set(&"vegetation_candidates", 0)
	parent.add_child(kit)
	# The height field is open ground: the horse's obstacle casts ignore it (it still
	# stands on it and sees drops).
	var terrain := kit.get_node_or_null("ArtTerrainCollision_91x91")
	if terrain:
		terrain.add_to_group(&"walkable_terrain")
	# The lake (the kit draws its surface): deep enough in the middle to swim.
	var lake := WaterBody.new()
	lake.name = "Lake"
	lake.radius = LAKE_RADIUS
	lake.show_surface = false
	lake.position = LAKE_CENTER
	parent.add_child(lake)
	if world and layout >= 2:
		# Authored edge cliffs must leave the new gate approaches open. Remove whole
		# decorative props, including their collision, rather than a hidden passage.
		for prop in kit.get_children():
			if not prop is Node3D or prop.find_children("*", "CollisionObject3D", true, false).is_empty():
				continue
			for kind: StringName in WorldMap.gates(layout):
				var gate_data := WorldMap.gate(kind, layout)
				var dir: Vector3 = gate_data.out
				var off: Vector3 = (prop as Node3D).position - (gate_data.pos as Vector3)
				var along := off.dot(dir)
				var across := off - dir * along
				across.y = 0.0
				if along > -30.0 and along < 35.0 and across.length() < 24.0:
					kit.remove_child(prop)
					prop.free()
					break
	if world:
		for c in kit.get_children():
			if String(c.name).begins_with("DistantTerrain"):
				c.queue_free()
	# The temple floor modules have no collision of their own (the kit says the terrain
	# carries them); the flat precinct is the terrain. The stairs' collision in the kit
	# rises away from the temple and ends in a 2.6 m drop (a step nobody can take at the
	# middle of the way out); the terrain under them is already the gentle way down, so
	# the stairs are only seen.
	for c in kit.get_children():
		if c is Node3D and String(c.name).begins_with("floor_"):
			# These render-only tiles have a .192m cap above their authored origin.
			(c as Node3D).position.y -= 0.207 # Keep the cap .005m above the terrain.
		if String(c.name).begins_with("stairs"):
			for b in c.find_children("*", "CollisionObject3D", true, false):
				(b as CollisionObject3D).collision_layer = 0
				(b as CollisionObject3D).collision_mask = 0
	if with_art:
		for prop in kit.get_children():
			if prop is Node3D and String(prop.name).begins_with("altar_"):
				# The altar is 2.7m along X; her head points along its long axis.
				TravelerArt.create_mono(prop, Vector3(0, 1.64, 0), PI * 0.5)
				break

	var stone := ArenaArt.material(ArenaArt.Kind.STONE) if with_art else _plain(Color(0.6, 0.58, 0.53))
	var dark := _plain(Color(0.45, 0.44, 0.41))
	var mist := StandardMaterial3D.new()
	mist.albedo_color = Color(0.85, 0.88, 0.9, 0.35)
	mist.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mist.cull_mode = BaseMaterial3D.CULL_DISABLED

	# The edge of the world: tall invisible walls (the horizon mesh shows what lies beyond).
	for w in _edge_walls(world, layout):
		var wall := TerrainKit.box(parent, w[0], w[1], dark)
		wall.name = "WorldEdge"
		for c in wall.get_children():
			if c is MeshInstance3D:
				c.visible = false

	var gates := {}
	for c: StringName in WorldMap.gates(layout):
		var g: Dictionary = WorldMap.gate(c, layout)
		var out: Vector3 = (g.out as Vector3).normalized()
		var pos := on_ground(g.pos)
		var root := Node3D.new()
		root.name = "Gate_%s" % c
		parent.add_child(root)
		# The opening is where the corridor's walls meet the edge: pillars there, the lintel
		# and (closed) the mist between them, along the edge line (also for a gate at an
		# angle to the edge).
		var ends := gate_opening(c, EDGE, layout)
		var a: Vector3 = ends[0]
		var b: Vector3 = ends[1]
		var mid := on_ground((a + b) * 0.5)
		var across := (b - a)
		across.y = 0.0
		var rot := Basis(Vector3.UP, atan2(-across.z, across.x))
		for e: Vector3 in ends:
			TerrainKit.box(root, on_ground(e) + Vector3(0, 6, 0), Vector3(3, 14, 3), stone, rot)
		var top := maxf(on_ground(a).y, on_ground(b).y)
		TerrainKit.box(root, Vector3(mid.x, top + 12.2, mid.z), Vector3(across.length() + 3.0, 2, 3.4), dark, rot)
		# Closed gates: a wall of mist that blocks the way (collision on the WORLD layer).
		var barrier: StaticBody3D = null
		if c != open_gate:
			barrier = TerrainKit.box(root, mid + Vector3(0, 5.5, 0), Vector3(across.length(), 14, 1.2), mist, rot)
			barrier.name = "Mist"
		gates[c] = {"pos": pos, "out": out, "trigger": on_ground(pos + out * GATE_TRIGGER), "open": c == open_gate, "node": root}
	return {"kit": kit, "gates": gates, "spawn": on_ground(TEMPLE_SPAWN, 0.95), "spawn_yaw": TEMPLE_YAW,
		"horse": on_ground(HORSE_SPAWN), "sun": SUN_DIRECTION.normalized()}


## Where the two walls of ``c``'s corridor cross the edge line at ``at`` (|x| or |z|):
## the ends of the gate's opening (XZ, y = 0).
static func gate_opening(c: StringName, at: float, layout := 2) -> Array[Vector3]:
	var g: Dictionary = WorldMap.gate(c, layout)
	var pos: Vector3 = g.pos
	var out: Vector3 = (g.out as Vector3).normalized()
	var side := out.cross(Vector3.UP).normalized()
	var on_z := absf(absf(pos.z) - EDGE) < 0.5
	var fixed := signf(pos.z if on_z else pos.x) * at
	var ends: Array[Vector3] = []
	for s: float in [-1.0, 1.0]:
		var q := pos + side * s * (WorldMap.CORRIDOR_WIDTH * 0.5 + 1.0)
		var d := out.z if on_z else out.x
		var t := (fixed - (q.z if on_z else q.x)) / d
		var e := q + out * t
		ends.append(Vector3(e.x, 0, e.z))
	return ends


## The edge walls ([centre, size]); in the world they leave an opening for each corridor.
static func _edge_walls(world: bool, layout := 2) -> Array:
	var out := []
	var e := EDGE + 2.0
	var span := EDGE + 4.0
	# Sides: [axis along the wall (x or z), fixed coordinate, sign].
	for side in [[0, -e], [0, e], [1, -e], [1, e]]:
		var along_x: bool = side[0] == 0
		var fixed: float = side[1]
		var gaps := []
		if world:
			for c: StringName in WorldMap.gates(layout):
				var g: Vector3 = WorldMap.gate(c, layout).pos
				var on_z := absf(absf(g.z) - EDGE) < 0.5
				if on_z != along_x or signf(g.z if on_z else g.x) != signf(fixed):
					continue
				# Between the corridor's walls where they cross this wall's middle.
				var ends := gate_opening(c, absf(fixed), layout)
				var u0: float = ends[0].x if along_x else ends[0].z
				var u1: float = ends[1].x if along_x else ends[1].z
				gaps.append([minf(u0, u1), maxf(u0, u1)])
		gaps.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var from := -span
		for gp in gaps + [[span, span]]:
			var to_: float = minf(gp[0], span)
			if to_ - from > 0.5:
				var mid := (from + to_) * 0.5
				var length := to_ - from
				out.append([Vector3(mid, 30, fixed) if along_x else Vector3(fixed, 30, mid), Vector3(length, 80, 4) if along_x else Vector3(4, 80, length)])
			from = maxf(from, gp[1])
	return out


## True when ``p`` has gone through the open gate ``gate`` (a gates entry of build()).
static func passed_gate(gate: Dictionary, p: Vector3) -> bool:
	if not gate.open:
		return false
	var d: Vector3 = p - (gate.pos as Vector3)
	var out: Vector3 = (gate.out as Vector3).normalized()
	var along := d.dot(out)
	var across := (d - out * along)
	across.y = 0.0
	# Through the opening and out of the valley (a gate at an angle to the edge leaves
	# valley ground beside it that is "ahead" of the gate too).
	var outside := int(gate.get("layout", 2)) >= 3 or maxf(absf(p.x), absf(p.z)) > EDGE
	return along > GATE_TRIGGER * 0.5 and across.length() < GATE_WIDTH * 0.5 + 1.0 and outside


static func _plain(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m
