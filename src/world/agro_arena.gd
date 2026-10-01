class_name AgroArena
## Greybox test ground for Agro (not a final world). Built by scenes/agro_test.tscn and the
## horse tests. Returns named start points: {name: [position, yaw]} (yaw 0 = facing -Z).
##
##   course   (40, 0, 10)   TerrainKit course: flat, 10 deg ramp, bumps, 0.8 m step
##   rocks    (0, 0, 10)    scattered rocks 1-2 m tall to weave between
##   passage  (-30, 0, 10)  two walls with a 3 m gap
##   wall     (10, 0, -5)   a 5 m wall at z -60, 50 m wide: impassable
##   cliff    (-60, 4, -46) a 4 m high plateau reached by a ramp, ending in a drop
##   log      (18, 0, 10)   a 0.3 m log across the way: stepped over, not avoided


static func build(parent: Node3D) -> Dictionary:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.55, 0.53, 0.5)
	var dirt := StandardMaterial3D.new()
	dirt.albedo_color = Color(0.5, 0.46, 0.36)
	TerrainKit.build_course(parent, Vector3(40, 0, 0))
	# Rocks.
	var rocks := [[Vector3(0.3, 0, -8), Vector3(1.2, 1.6, 1.2)], [Vector3(-3, 0, -16), Vector3(2.0, 1.4, 1.6)],
		[Vector3(3, 0, -22), Vector3(1.4, 2.0, 1.4)], [Vector3(-1, 0, -30), Vector3(1.6, 1.2, 1.8)],
		[Vector3(4, 0, -36), Vector3(1.2, 1.8, 1.2)], [Vector3(-4, 0, -40), Vector3(1.8, 1.5, 1.4)]]
	for i in rocks.size():
		var r: Array = rocks[i]
		TerrainKit.box(parent, (r[0] as Vector3) + Vector3(0, (r[1] as Vector3).y * 0.5, 0), r[1], stone, Basis(Vector3.UP, 0.5 * i))
	# Narrow passage: walls along Z with a 3 m gap at x = -30.
	TerrainKit.box(parent, Vector3(-31.5 - 0.5, 1.5, -12), Vector3(1.0, 3.0, 14.0), stone)
	TerrainKit.box(parent, Vector3(-28.5 + 0.5, 1.5, -12), Vector3(1.0, 3.0, 14.0), stone)
	# Funnel walls leading into the passage.
	TerrainKit.box(parent, Vector3(-36.0, 1.5, -4.0), Vector3(8.0, 3.0, 1.0), stone)
	TerrainKit.box(parent, Vector3(-24.0, 1.5, -4.0), Vector3(8.0, 3.0, 1.0), stone)
	# A low log across the way (small enough to step over).
	TerrainKit.box(parent, Vector3(18, 0.15, -2), Vector3(8.0, 0.3, 0.45), dirt)
	# Impassable wall.
	TerrainKit.box(parent, Vector3(0, 2.5, -60), Vector3(50.0, 5.0, 1.0), stone)
	# Cliff: a ramp up to a 4 m plateau whose far edge drops back to the ground.
	TerrainKit.ramp(parent, Vector3(-60, 0, -20), 22.7, 10.0, 12.0, dirt)
	TerrainKit.box(parent, Vector3(-60, 2.0, -57.7), Vector3(12.0, 4.0, 30.0), dirt)
	return {
		"course": [Vector3(40, 0, 10), 0.0],
		"rocks": [Vector3(0, 0, 10), 0.0],
		"passage": [Vector3(-30, 0, 10), 0.0],
		"wall": [Vector3(10, 0, -5), 0.0],
		"cliff": [Vector3(-60, 4.0, -46), 0.0],
		"log": [Vector3(18, 0, 10), 0.0],
		"flat": [Vector3(120, 0, 150), 0.0],
	}
