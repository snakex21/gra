class_name Valley
## The valley between the fights: the temple where every journey starts, open ground to
## ride, and three gates at its edges, one to each colossus' arena:
##
##   Valus      south, across the open basin
##   Quadratus  north, past the lake
##   Gaius      west, through the canyon
##   Phaedra    east, up the slope
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
}
const GATE_WIDTH := 12.0
const GATE_TRIGGER := 6.0
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
static func build(parent: Node3D, open_gate: StringName, with_art := true, world := false) -> Dictionary:
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
	if world:
		for c in kit.get_children():
			if String(c.name).begins_with("DistantTerrain"):
				c.queue_free()
	# The temple floor modules have no collision of their own (the kit says the terrain
	# carries them); the flat precinct is the terrain.

	var stone := ArenaArt.material(ArenaArt.Kind.STONE) if with_art else _plain(Color(0.6, 0.58, 0.53))
	var dark := _plain(Color(0.45, 0.44, 0.41))
	var mist := StandardMaterial3D.new()
	mist.albedo_color = Color(0.85, 0.88, 0.9, 0.35)
	mist.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mist.cull_mode = BaseMaterial3D.CULL_DISABLED

	# The edge of the world: tall invisible walls (the horizon mesh shows what lies beyond).
	for w in _edge_walls(world):
		var wall := TerrainKit.box(parent, w[0], w[1], dark)
		wall.name = "WorldEdge"
		for c in wall.get_children():
			if c is MeshInstance3D:
				c.visible = false

	var gates := {}
	for c: StringName in GATES:
		var g: Dictionary = GATES[c]
		var out: Vector3 = g.out
		var pos := on_ground(g.pos)
		var side := out.cross(Vector3.UP).normalized()
		var yaw := atan2(-out.x, -out.z)
		var rot := Basis(Vector3.UP, yaw)
		var root := Node3D.new()
		root.name = "Gate_%s" % c
		parent.add_child(root)
		for s in [-1.0, 1.0]:
			var base := on_ground(pos + side * s * (GATE_WIDTH * 0.5 + 1.5))
			TerrainKit.box(root, base + Vector3(0, 6, 0), Vector3(3, 14, 3), stone, rot)
		TerrainKit.box(root, pos + Vector3(0, 12.2, 0), Vector3(GATE_WIDTH + 6, 2, 3.4), dark, rot)
		# Closed gates: a wall of mist that blocks the way (collision on the WORLD layer).
		var barrier: StaticBody3D = null
		if c != open_gate:
			barrier = TerrainKit.box(root, pos + Vector3(0, 5.5, 0), Vector3(GATE_WIDTH, 12, 1.2), mist, rot)
			barrier.name = "Mist"
		gates[c] = {"pos": pos, "out": out, "trigger": on_ground(pos + out * GATE_TRIGGER), "open": c == open_gate, "node": root}
	return {"kit": kit, "gates": gates, "spawn": on_ground(TEMPLE_SPAWN, 0.95), "spawn_yaw": TEMPLE_YAW,
		"horse": on_ground(HORSE_SPAWN), "sun": SUN_DIRECTION.normalized()}


## The edge walls ([centre, size]); in the world they leave an opening for each corridor.
static func _edge_walls(world: bool) -> Array:
	var out := []
	var e := EDGE + 2.0
	var span := EDGE + 4.0
	# Sides: [axis along the wall (x or z), fixed coordinate, sign].
	for side in [[0, -e], [0, e], [1, -e], [1, e]]:
		var along_x: bool = side[0] == 0
		var fixed: float = side[1]
		var gaps := []
		if world:
			for c: StringName in GATES:
				var g: Vector3 = GATES[c].pos
				var o: Vector3 = (GATES[c].out as Vector3).normalized()
				var to := fixed - (g.z if along_x else g.x)
				var d := o.z if along_x else o.x
				if absf(d) < 0.2 or signf(to) != signf(d):
					continue
				var hit := g + o * (to / d)
				var at := hit.x if along_x else hit.z
				# Up to the middle of the gate's pillars (they close the rest).
				var half := (GATE_WIDTH * 0.5 + 1.5) / absf(d)
				gaps.append([at - half, at + half])
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
	var out: Vector3 = gate.out
	var along := d.dot(out)
	var across := (d - out * along)
	across.y = 0.0
	return along > GATE_TRIGGER * 0.5 and across.length() < GATE_WIDTH


static func _plain(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m
