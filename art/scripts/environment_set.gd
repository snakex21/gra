@tool
extends Node3D
## Deterministic modular composition. Geometry and scattering are art-owned only.

const Asset = preload("res://art/scripts/art_asset.gd")
const TERRAIN := preload("res://materials/environment/terrain.tres")
const FOLIAGE := preload("res://materials/environment/foliage_atlas.tres")
@export var include_terrain := true
@export var include_collision := true
@export var vegetation_count := 2400
var asset_count := 0
var vegetation_instances := 0


static func ground_height(x: float, z: float) -> float:
	return 0.35 * sin(x * 0.07) * cos(z * 0.09) + 1.5 * smoothstep(22.0, 68.0, absf(x))


func _ready() -> void:
	if get_child_count() == 0:
		build()


func _asset(id: String, pos: Vector3, yaw := 0.0, size := 1.0, collision := "hull") -> Node3D:
	var instance := Node3D.new()
	instance.set_script(Asset)
	instance.name = id + "_%03d" % asset_count
	instance.model_id = id
	instance.collidable = include_collision and collision != "none"
	instance.collision_kind = collision
	instance.position = pos + Vector3.UP * ground_height(pos.x, pos.z)
	instance.rotation.y = yaw
	instance.scale = Vector3.ONE * size
	if id == "cliff_buttress":
		instance.lod_distances = Vector3(50, 110, 380)
	add_child(instance)
	asset_count += 1
	return instance


func build() -> void:
	if include_terrain:
		_terrain()
	# Broad, quiet ancient basin. Ruins follow a 4 m modular grid.
	_asset("ruin_arch", Vector3(-18,0,12), 0.05, 1.45, "arch_boxes")
	for pos in [Vector3(-25,0,13), Vector3(-11,0,13), Vector3(-25,0,21), Vector3(-11,0,21)]:
		_asset("ruin_column", pos, 0, 1.45)
	for pos in [Vector3(-29,0,17), Vector3(-29,0,21), Vector3(-7,0,22)]:
		_asset("ruin_wall", pos, PI*.5, 1.05)
	_asset("ruin_stairs", Vector3(-18,0,9), 0, 1.35, "stair_ramp")
	_asset("ruin_rubble", Vector3(-24,0,6), .3, 1.4)
	_asset("ruin_rubble", Vector3(-9,0,16), 1.1, 1.1)
	# A distant interrupted colonnade suggests a larger place without a full world.
	for i in 4:
		_asset("ruin_column", Vector3(13+i*7,0,35), 0, 1.45 + i*.11)
	for i in 8:
		_asset("cliff_buttress", Vector3(-76+i*22,0,65+sin(i)*7), .2+sin(i)*.24, 1.3+sin(i*.7)*.35)
	_asset("cliff_buttress", Vector3(-63,0,7), PI*.52, 1.15)
	_asset("cliff_buttress", Vector3(60,0,27), PI*.30, 1.15)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7013
	for i in 58:
		var pos := Vector3(rng.randf_range(-53,53),0,rng.randf_range(-37,49))
		if absf(pos.x - (sin(pos.z*.027)*4-1)) < 5.5 or pos.distance_to(Vector3(7,0,-3)) < 8.0:
			continue
		var id := "rock_%02d" % (i % 5 + 1)
		_asset(id,pos,rng.randf()*TAU,rng.randf_range(.65,1.45))
	_asset("rock_05", Vector3(29,0,-10), .4, 1.6)
	_asset("rock_03", Vector3(-31,0,-12), .2, 1.7)
	_asset("tree_windward", Vector3(24,0,13), 1.0, 1.3, "trunk")
	_asset("tree_juniper", Vector3(-35,0,-4), 2.4, 1.25, "trunk")
	for i in 32:
		var pos := Vector3(rng.randf_range(-38,38),0,rng.randf_range(-28,34))
		if absf(pos.x) < 6:
			continue
		_asset("shrub_salt" if i % 2 == 0 else "plant_spear",pos,rng.randf()*TAU,rng.randf_range(.7,1.2),"none")
	# Hand-placed sparse flagstones give way to a shader-blended worn earth path.
	for i in 30:
		var z := -48.0+i*2.5
		var x := sin(z*.027)*4-1
		if i % 5 != 2:
			_asset("road_slab",Vector3(x+rng.randf_range(-.35,.35),.015,z),rng.randf_range(-.1,.1),1.1,"none")
	_scatter_grass(rng)


func _terrain() -> void:
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	const STEPS := 80
	const CELL := 2.5
	for iz in STEPS:
		for ix in STEPS:
			var x := (ix-STEPS/2)*CELL
			var z := (iz-STEPS/2)*CELL
			for corner in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,0),Vector2(1,1),Vector2(0,1)]:
				var px: float = x+corner.x*CELL
				var pz: float = z+corner.y*CELL
				builder.set_uv(Vector2(px,pz)*.2)
				builder.add_vertex(Vector3(px,ground_height(px,pz),pz))
	builder.generate_normals()
	var mesh := builder.commit()
	var terrain := MeshInstance3D.new()
	terrain.name = "Terrain_200m"
	terrain.mesh = mesh
	terrain.material_override = TERRAIN
	add_child(terrain)
	if include_collision:
		# Dedicated coarse height grid: 21x21 instead of render grid's 81x81.
		var body := StaticBody3D.new()
		body.name = "TerrainCollision_21x21"
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := HeightMapShape3D.new()
		shape.map_width = 21
		shape.map_depth = 21
		var heights := PackedFloat32Array()
		for z in 21:
			for x in 21:
				heights.append(ground_height((x-10)*10.0,(z-10)*10.0))
		shape.map_data = heights
		var col := CollisionShape3D.new()
		col.shape = shape
		col.scale = Vector3(10,1,10)
		body.add_child(col)
		add_child(body)


func _scatter_grass(rng: RandomNumberGenerator) -> void:
	var chunks: Dictionary = {}
	for i in vegetation_count:
		var p := Vector3(rng.randf_range(-48,48),0,rng.randf_range(-36,45))
		var road_x := sin(p.z*.027)*4-1
		if absf(p.x-road_x) < rng.randf_range(3.1,5.0):
			continue
		if p.distance_to(Vector3(7,0,-3)) < 5.5:
			continue
		var patch := sin(p.x*.14)*cos(p.z*.13)
		if patch < -.30 and i % 4 != 0:
			continue
		p.y = ground_height(p.x,p.z)
		var key := Vector3i(floori(p.x/16.0), floori(p.z/16.0), i%3)
		if not chunks.has(key):
			chunks[key] = []
		var xf := Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*rng.randf_range(.6,1.35)),p)
		chunks[key].append(xf)
		vegetation_instances += 1
	for key: Vector3i in chunks:
		var center := Vector3(key.x*16+8,0,key.y*16+8)
		var transforms: Array = chunks[key]
		for level in 2:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = Asset.mesh_for(["grass_tuft","grass_dry","grass_low"][key.z], level*2)
			mm.instance_count = transforms.size()
			for i in transforms.size():
				var xf: Transform3D = transforms[i]
				xf.origin -= center
				mm.set_instance_transform(i,xf)
			var node := MultiMeshInstance3D.new()
			node.name = "Grass_%s_LOD%d" % [str(key),level]
			node.multimesh = mm
			node.lod_bias = 100.0
			node.position = center
			node.material_override = FOLIAGE
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.visibility_range_begin = 0 if level == 0 else 27
			node.visibility_range_end = 27 if level == 0 else 68
			add_child(node)
