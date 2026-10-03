class_name ForbiddenLandsTerrain
extends RefCounted
## Native travel surface now; small, render-only detail jobs later. No scripted world
## nodes or saved cosmetic references: restoring a checkpoint rebuilds these meshes.
const CHUNK := 256
const STEP := 32
const MINIMUM := Vector2i(-2304, -2304)
const MAXIMUM := Vector2i(1792, 1792)
static var _grid := {}
static var _height_cache := {}
static var _terrain_mat: Material
static var _road_mat: StandardMaterial3D
static var _landscape_mat: StandardMaterial3D
static var _landscape_meshes := {}
const LANDSCAPE_KINDS := ["oak", "wind_tree", "pine", "dead_tree", "rock_shelf", "rock_split", "ruin_arch", "ruin_support", "ruin_parapet"]

static func _index_roads() -> void:
	if not _grid.is_empty():
		return
	for edge: Array in ForbiddenLands.road_edges():
		var a: Vector3 = edge[0]
		var b: Vector3 = edge[1]
		var low := Vector2i(floori((minf(a.x, b.x) - 80) / 80), floori((minf(a.z, b.z) - 80) / 80))
		var high := Vector2i(floori((maxf(a.x, b.x) + 80) / 80), floori((maxf(a.z, b.z) + 80) / 80))
		for z in range(low.y, high.y + 1):
			for x in range(low.x, high.x + 1):
				var key := Vector2i(x, z)
				if not _grid.has(key):
					_grid[key] = []
				_grid[key].append(edge)

static func road_distance(p: Vector2) -> float:
	_index_roads()
	var best := INF
	for edge: Array in _grid.get(Vector2i(floori(p.x / 80), floori(p.y / 80)), []):
		var a: Vector3 = edge[0]
		var b: Vector3 = edge[1]
		best = minf(best, Geometry2D.get_closest_point_to_segment(p, Vector2(a.x, a.z), Vector2(b.x, b.z)).distance_to(p))
	return best

static func height_at(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var natural := 4.0 + sin(x * .006) * cos(z * .005) * 9.0
	for hill: Vector4 in [Vector4(-470, 370, 230, 110), Vector4(720, 500, 220, 94), Vector4(-910, -450, 200, 76), Vector4(280, -1310, 250, 65), Vector4(-1620, -730, 200, 82)]:
		natural += hill.w * exp(-p.distance_squared_to(Vector2(hill.x, hill.y)) / (hill.z * hill.z))
	var coastline := Vector2((x + 220) / 1950, (z + 150) / 2000).length()
	natural = lerpf(natural, -45, smoothstep(.94, 1.10, coastline))
	var nearest_arena := INF
	for kind: StringName in ForbiddenLands.REGIONS:
		nearest_arena = minf(nearest_arena, p.distance_to(ForbiddenLands.REGIONS[kind][0]))
	if nearest_arena < WorldMap.GROUND_RADIUS + 50:
		natural = lerpf(-35, natural, smoothstep(WorldMap.GROUND_RADIUS + 2, WorldMap.GROUND_RADIUS + 50, nearest_arena))
	var road := road_distance(p)
	# The northern span is a real bridge above a recessed canyon, not land painted blue.
	var bridge := absf(x + 230) < 75 and z > 240 and z < 620
	if bridge:
		natural = minf(natural, -34 + absf(x + 230) * .14)
	elif road < 125:
		# Coarse terrain vertices bordering a road also stay below its ribbon; a
		# diagonal chunk triangle must never protrude through the drivable surface.
		natural = lerpf(ForbiddenLands.road_height(x, z) - .10, natural, smoothstep(62, 125, road))
	if maxf(absf(x), absf(z)) <= WorldMap.VALLEY_HALF:
		return Valley.ground_height(x, z) - .05
	return natural

static func biome_color(x: float, z: float, known_height: float = NAN) -> Color:
	var variation := .035 * sin(x * .023 + z * .018)
	var color := Color(.30, .36, .25)
	if x < -650 and z > -300 or z > 750:
		color = Color(.42, .40, .30)
	if x < -350 and z < -300 and z > -1050:
		color = Color(.19, .27, .20)
	if z < -1050 or x < -1100 and z < -950:
		color = Color(.42, .34, .27)
	if x > 700:
		color = Color(.29, .36, .35)
	if x > 1100 and absf(z) < 300:
		color = Color(.35, .28, .24)
	# Chunk vertices already have a cached height; avoid repeating road/arena
	# searches for every copy of a triangle corner during world construction.
	var height := height_at(x, z) if is_nan(known_height) else known_height
	if height > 38:
		color = Color(.34, .35, .33)
	return color + Color(variation, variation, variation, 0)

static func _materials() -> void:
	if _terrain_mat:
		return
	# One atlas sample adds local grain while retaining the authored biome colours.
	_terrain_mat = load("res://materials/landscape_v5/terrain.tres")
	_road_mat = StandardMaterial3D.new()
	_road_mat.albedo_color = Color(.43, .43, .37)
	_road_mat.roughness = 1
	_road_mat.disable_receive_shadows = true
	_road_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_road_mat.albedo_texture = load("res://textures/environment/rock_albedo.png")
	_road_mat.uv1_scale = Vector3(.2, .2, .2)

static func build(parent: Node3D, with_art := true) -> void:
	_materials()
	_index_roads()
	var root := Node3D.new()
	root.name = "ForbiddenLandsTerrain"
	parent.add_child(root)
	var job := ArenaArtBuild.new()
	if with_art:
		# One asset (three small geometry-only files) per bounded cache warmup job.
		# The 256 chunk jobs remain independent; no all-world batch is assembled.
		for kind: String in LANDSCAPE_KINDS:
			job.add(func() -> void: _prime_landscape(kind))
		job.add(func() -> void: _bridge_art(root))
	for z in range(MINIMUM.y, MAXIMUM.y, CHUNK):
		for x in range(MINIMUM.x, MAXIMUM.x, CHUNK):
			var origin := Vector2i(x, z)
			_build_chunk(root, origin)
			if with_art:
				job.add(func() -> void: _detail_chunk(root, origin))
	_build_roads(root)
	_bridge_details(root)
	if with_art:
		var ocean := MeshInstance3D.new()
		ocean.name = "OuterSea_NoCollision"
		var plane := PlaneMesh.new()
		plane.size = Vector2(11000, 11000)
		ocean.mesh = plane
		ocean.position.y = -42
		var water := StandardMaterial3D.new()
		water.albedo_color = Color(.19, .31, .34)
		water.roughness = .4
		ocean.material_override = water
		root.add_child(ocean)
		root.set_meta(&"detail_job", job)
		# Existing bounded queue, native controller node; no simulation script to serialize.
		var pump := func() -> void:
			if is_instance_valid(root):
				job.step(1800, 1)
		parent.get_tree().process_frame.connect(pump)
		root.tree_exiting.connect(func() -> void:
			if parent.get_tree() and parent.get_tree().process_frame.is_connected(pump):
				parent.get_tree().process_frame.disconnect(pump))
	for side: Array in [[Vector3(-2320, 20, -256), Vector3(20, 120, 4160)], [Vector3(1808, 20, -256), Vector3(20, 120, 4160)], [Vector3(-256, 20, -2320), Vector3(4160, 120, 20)], [Vector3(-256, 20, 1808), Vector3(4160, 120, 20)]]:
		var border := TerrainKit.box(root, side[0], side[1], null)
		border.name = "OuterBoundary"
		for node in border.get_children():
			if node is MeshInstance3D:
				node.visible = false

static func finish_art(parent: Node) -> void:
	var root := parent.get_node_or_null("ForbiddenLandsTerrain")
	if root and root.has_meta(&"detail_job"):
		var job: ArenaArtBuild = root.get_meta(&"detail_job")
		while not job.step(1800, 1):
			pass

static func _point(x: int, z: int) -> Vector3:
	var key := Vector2i(x, z)
	if not _height_cache.has(key):
		_height_cache[key] = height_at(x, z)
	return Vector3(x, _height_cache[key], z)

static func surface_height(x: float, z: float) -> float:
	# Decorations stand on the actual coarse triangles, rather than floating at
	# the analytic hill height between their vertices.
	var x0 := floori(x / STEP) * STEP
	var z0 := floori(z / STEP) * STEP
	var u := (x - x0) / STEP
	var v := (z - z0) / STEP
	var h00 := _point(x0, z0).y
	var h10 := _point(x0 + STEP, z0).y
	var h01 := _point(x0, z0 + STEP).y
	var h11 := _point(x0 + STEP, z0 + STEP).y
	return (1 - u) * h00 + (u - v) * h10 + v * h11 if u >= v else (1 - v) * h00 + (v - u) * h01 + u * h11

static func _build_chunk(root: Node3D, origin: Vector2i) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vertices := 0
	for z in range(origin.y, origin.y + CHUNK, STEP):
		for x in range(origin.x, origin.x + CHUNK, STEP):
			if x >= -WorldMap.VALLEY_HALF and x + STEP <= WorldMap.VALLEY_HALF and z >= -WorldMap.VALLEY_HALF and z + STEP <= WorldMap.VALLEY_HALF:
				continue
			for corner: Vector2i in [Vector2i(0, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1)]:
				var point := _point(x + corner.x * STEP, z + corner.y * STEP)
				st.set_uv(Vector2(point.x, point.z))
				st.set_color(biome_color(point.x, point.z, point.y))
				st.add_vertex(point)
				vertices += 1
	if vertices == 0:
		return
	st.generate_normals()
	_surface(root, st.commit(), "Land_%d_%d" % [origin.x, origin.y], _terrain_mat)

static func _surface(parent: Node3D, mesh: ArrayMesh, label: String, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.name = label
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.add_to_group(&"walkable_terrain")
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	(shape.shape as ConcavePolygonShape3D).backface_collision = true
	body.add_child(shape)
	if label == "BranchRoads":
		parent.add_child(body)
		_road_visual_chunks(body, mesh, mat)
		return
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = mat
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Centred chunk origins make native distance culling genuinely spatial.
	var centre := mesh.get_aabb().get_center()
	visual.position = centre
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for index in vertices.size():
		vertices[index] -= centre
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var local_mesh := ArrayMesh.new()
	local_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	visual.mesh = local_mesh
	visual.visibility_range_end = 1100 if label.begins_with("Land_") else 0
	body.add_child(visual)
	parent.add_child(body)

static func _road_visual_chunks(body: StaticBody3D, mesh: ArrayMesh, mat: Material) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var cells := {}
	for index in range(0, vertices.size(), 3):
		var centre := (vertices[index] + vertices[index + 1] + vertices[index + 2]) / 3
		var cell := Vector2i(floori(centre.x / CHUNK), floori(centre.z / CHUNK))
		if not cells.has(cell):
			cells[cell] = []
		cells[cell].append(index)
	for cell: Vector2i in cells:
		var origin := Vector3((cell.x + .5) * CHUNK, 0, (cell.y + .5) * CHUNK)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for triangle: int in cells[cell]:
			for corner in 3:
				st.set_normal(Vector3.UP)
				st.set_uv(uv[triangle + corner])
				st.add_vertex(vertices[triangle + corner] - origin)
		var visual := MeshInstance3D.new()
		visual.name = "RoadVisual_%d_%d" % [cell.x, cell.y]
		visual.position = origin
		visual.mesh = st.commit()
		visual.material_override = mat
		visual.visibility_range_end = 1100
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(visual)

static func _build_roads(root: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for edge: Array in ForbiddenLands.road_edges():
		var a: Vector3 = edge[0]
		var b: Vector3 = edge[1]
		# Tiny overlaps seal concave-triangle seams at the sampled curve vertices.
		var forward := (Vector3(b.x, 0, b.z) - Vector3(a.x, 0, a.z)).normalized() * .25
		a -= forward
		b += forward
		var side := (b - a).cross(Vector3.UP).normalized() * ForbiddenLands.ROAD_HALF
		var apron := maxf(maxf(absf(a.x), absf(a.z)), maxf(absf(b.x), absf(b.z))) < 280
		var lanes := 14 if apron else 1
		var along := maxi(1, ceili(a.distance_to(b) / 2.0)) if apron else 1
		for segment in along:
			var begin := a.lerp(b, float(segment) / along)
			var end := a.lerp(b, float(segment + 1) / along)
			for lane in lanes:
				var left := side * lerpf(-1, 1, float(lane) / lanes)
				var right := side * lerpf(-1, 1, float(lane + 1) / lanes)
				for point: Vector3 in [begin + left, end + right, begin + right, begin + left, end + left, end + right]:
					point.y = ForbiddenLands.road_height(point.x, point.z)
					st.set_uv(Vector2(point.x, point.z))
					st.set_normal(Vector3.UP)
					st.add_vertex(point)
	_surface(root, st.commit(), "BranchRoads", _road_mat)

static func _bridge_details(root: Node3D) -> void:
	var stone := ArenaArt.material(ArenaArt.Kind.STONE)
	for z in range(280, 600, 64):
		for side: float in [-1.0, 1.0]:
			# Supports below the deck and side parapets keep the 28m lane clear.
			var pier := TerrainKit.box(root, Vector3(-233 + side * 17, -17, z), Vector3(4, 34, 5), stone)
			pier.set_meta(&"landscape_bridge_part", &"pier")
			var parapet := TerrainKit.box(root, Vector3(-233 + side * 17, 1.2, z), Vector3(2, 2.4, 52), stone)
			parapet.set_meta(&"landscape_bridge_part", &"parapet")

static func _prime_landscape(kind: String) -> void:
	if _landscape_meshes.has(kind):
		return
	if not _landscape_mat:
		_landscape_mat = load("res://materials/landscape_v5/atlas.tres")
	var meshes: Array[Mesh] = []
	for lod in 3:
		var scene: PackedScene = load("res://models/landscape_v5/%s_lod%d.glb" % [kind, lod])
		if not scene:
			push_error("Landscape model missing: " + kind)
			return
		var instance := scene.instantiate()
		var visual := instance as MeshInstance3D
		if not visual:
			visual = instance.find_child("*", true, false) as MeshInstance3D
		if not visual or not visual.mesh:
			push_error("Landscape model has no mesh: " + kind)
			instance.free()
			return
		meshes.append(visual.mesh)
		instance.free()
	_landscape_meshes[kind] = meshes

static func _landscape_batch(parent: Node3D, kind: String, origin: Vector3, transforms: Array[Transform3D]) -> void:
	if transforms.is_empty():
		return
	_prime_landscape(kind)
	if not _landscape_meshes.has(kind):
		return
	for lod in 3:
		var batch := MultiMeshInstance3D.new()
		batch.name = "%s_LOD%d" % [kind, lod]
		batch.position = origin
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = _landscape_meshes[kind][lod]
		multi.instance_count = transforms.size()
		for index in transforms.size():
			var local := transforms[index]
			local.origin -= origin
			multi.set_instance_transform(index, local)
		batch.multimesh = multi
		batch.material_override = _landscape_mat
		batch.visibility_range_begin = [0.0, 110.0, 230.0][lod]
		batch.visibility_range_end = [110.0, 230.0, 550.0][lod]
		batch.visibility_range_begin_margin = 8
		batch.visibility_range_end_margin = 8
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(batch)

static func _bridge_art(root: Node3D) -> void:
	if not is_instance_valid(root):
		return
	var cells := {}
	for body: Node3D in root.get_children():
		if not body.has_meta(&"landscape_bridge_part"):
			continue
		# Only replace the render child. The original solid bridge collider stays
		# exactly where it was; the crafted masonry covers the same dimensions.
		for child in body.get_children():
			if child is MeshInstance3D:
				child.visible = false
		# A long bridge uses tighter 64m batches, so near parapets do not select the
		# LOD of a centre hundreds of metres farther down the span.
		var cell := Vector2i(floori(body.position.x / 64), floori(body.position.z / 64))
		if not cells.has(cell):
			cells[cell] = {"ruin_support": [], "ruin_parapet": []}
		if body.get_meta(&"landscape_bridge_part") == &"pier":
			var xf := Transform3D(Basis.IDENTITY.scaled(Vector3(4.0 / 3.5, 34.0 / 6.26, 5.0 / 3.1)), body.position - Vector3(0, 17, 0))
			cells[cell]["ruin_support"].append(xf)
		else:
			for segment in 13:
				var xf := Transform3D(Basis.IDENTITY.scaled(Vector3(2.0 / 2.13, 2.4 / 2.26, 1)), body.position + Vector3(0, -1.2, -24 + segment * 4))
				cells[cell]["ruin_parapet"].append(xf)
	for cell: Vector2i in cells:
		var details := Node3D.new()
		details.name = "BridgeArt_%d_%d" % [cell.x, cell.y]
		root.add_child(details)
		for kind: String in cells[cell]:
			var transforms: Array[Transform3D] = []
			transforms.assign(cells[cell][kind])
			_landscape_batch(details, kind, Vector3((cell.x + .5) * 64, 0, (cell.y + .5) * 64), transforms)

static func _detail_chunk(root: Node3D, origin: Vector2i) -> void:
	if not is_instance_valid(root):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 330721 + origin.x * 13 + origin.y * 29
	var forest := origin.x < -350 and origin.y < -300 and origin.y > -1100
	var count := 24 if forest else 4
	var details := Node3D.new()
	details.name = "BiomeDetail_%d_%d" % [origin.x, origin.y]
	root.add_child(details)
	var groups := {}
	for i in count:
		var p := Vector3(origin.x + rng.randf_range(0, CHUNK), 0, origin.y + rng.randf_range(0, CHUNK))
		if maxf(absf(p.x), absf(p.z)) < 210 or road_distance(Vector2(p.x, p.z)) < 34:
			continue
		var close := false
		for kind: StringName in ForbiddenLands.REGIONS:
			close = close or Vector2(p.x, p.z).distance_to(ForbiddenLands.REGIONS[kind][0]) < 210
		if close:
			continue
		p.y = surface_height(p.x, p.z)
		if p.y < -8:
			continue
		var kind: String = ["oak", "wind_tree", "pine", "dead_tree"][rng.randi_range(0, 3)] if forest else ["rock_shelf", "rock_split"][rng.randi_range(0, 1)]
		var size := rng.randf_range(.8, 1.3) if forest else rng.randf_range(1.3, 2.7)
		if not groups.has(kind):
			groups[kind] = []
		groups[kind].append(Transform3D(Basis(Vector3.UP, rng.randf_range(-PI, PI)).scaled(Vector3.ONE * size), p - Vector3.UP * .08))
	# Three deliberate remnants beside the old forest route. The empty grassland
	# stays empty; these are visual landmarks, without colliders or map markers.
	for ruin: Vector3 in [Vector3(-780, 0, -345), Vector3(-706, 0, -545), Vector3(-1110, 0, -370)]:
		if floori(ruin.x / CHUNK) * CHUNK != origin.x or floori(ruin.z / CHUNK) * CHUNK != origin.y:
			continue
		if not groups.has("ruin_arch"):
			groups["ruin_arch"] = []
		ruin.y = surface_height(ruin.x, ruin.z) - .15
		groups["ruin_arch"].append(Transform3D(Basis(Vector3.UP, .6), ruin))
	for kind: String in groups:
		var transforms: Array[Transform3D] = []
		transforms.assign(groups[kind])
		_landscape_batch(details, kind, Vector3(origin.x + CHUNK * .5, 0, origin.y + CHUNK * .5), transforms)
