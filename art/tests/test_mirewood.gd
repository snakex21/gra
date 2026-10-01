extends SceneTree
## Art-only structural/import/physics checks, no gameplay dependencies.
const Asset = preload("res://art/scripts/mirewood_asset.gd")
var checks := 0
var failures: Array[String] = []
var exact_edge_ray_misses := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var default_item := Node3D.new()
	default_item.set_script(Asset)
	world.add_child(default_item)
	check(default_item.model_id == "root_island", "valid default module")
	check(default_item.get_child_count() == 3, "default module builds three LODs")
	default_item.free()
	var records := Asset.records()
	check(records.size() == 31, "31 distinct assets")
	var index := 0
	for id in records:
		var item := Node3D.new()
		item.set_script(Asset)
		item.model_id = id
		item.collidable = true
		item.position = Vector3(index * 80, 0, 0)
		world.add_child(item)
		var record: Dictionary = records[id]
		check(item.get_child_count() == (4 if not record.collision_shapes.is_empty() else 3), id + " three visual LODs and optional proxy")
		for level in 3:
			var visual := item.get_node("LOD%d" % level) as MeshInstance3D
			check(visual.mesh != null and visual.mesh.get_surface_count() == 1, id + " one imported surface")
			check(visual.material_override == Asset.ATLAS, id + " shared atlas identity")
			check(visual.visibility_range_end == item.lod_distances[level], id + " LOD end")
			check(visual.visibility_range_begin == (0.0 if level == 0 else item.lod_distances[level-1]), id + " contiguous LOD start")
			check(visual.mesh == Asset.mesh_for(id,level), id + " mesh cache identity")
		if not record.collision_shapes.is_empty():
			var proxy := item.get_node("AuthoredStaticProxy") as StaticBody3D
			check(proxy.get_child_count() == record.collision_shapes.size(), id + " recipe count")
			check(proxy.collision_layer == 1 and proxy.collision_mask == 0, id + " passive static layer")
			for shape in proxy.get_children():
				check(shape.shape != null and not shape.disabled, id + " valid shape")
		item.build()
		check(item.get_child_count() == (4 if not record.collision_shapes.is_empty() else 3), id + " idempotent build")
		var decorative := Node3D.new()
		decorative.set_script(Asset)
		decorative.model_id = id
		world.add_child(decorative)
		check(decorative.get_child_count() == 3, id + " collision opt-in")
		decorative.free()
		await physics_frame
		await physics_frame
		var origin: Vector3 = item.position
		for probe in record.get("passage_probes", []):
			var ray := PhysicsRayQueryParameters3D.create(origin+Asset.vector(probe["from"]),origin+Asset.vector(probe["to"]))
			var hit := not world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
			check(hit == (probe.expect == "hit"), id + " collision probe " + str(probe.get("name", probe.expect)))
		index += 1
	world.free()
	var environment_script = load("res://art/scripts/mirewood_environment.gd")
	var environment := Node3D.new()
	environment.set_script(environment_script)
	environment.include_catalogue = true
	root.add_child(environment)
	check(environment.catalogue_count == 31,"31 catalogue entries")
	check(environment.terrain_triangles == 18432,"nine continuous terrain chunks")
	check(environment.asset_count > 25,"landscape contains meaningful placements")
	# Actual render-mesh edges: every interior edge must have two neighbours,
	# including the near/far transition. Only the outer 1200m perimeter is open.
	var edges: Dictionary = {}
	var perimeter: Dictionary = {}
	for mesh_node in environment.landscape.get_children():
		if not mesh_node is MeshInstance3D or not (str(mesh_node.name).begins_with("PeatBasin_") or str(mesh_node.name).begins_with("StitchedDistant")):
			continue
		var arrays: Array = mesh_node.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for triangle in range(0,vertices.size(),3):
			for edge in 3:
				var a: Vector3 = vertices[triangle+edge]
				var b: Vector3 = vertices[triangle+(edge+1)%3]
				var aa := str(a)
				var bb := str(b)
				var key := aa+"|"+bb if aa<bb else bb+"|"+aa
				edges[key] = int(edges.get(key,0))+1
				perimeter[key] = (absf(a.x)==600 and a.x==b.x) or (absf(a.z)==600 and a.z==b.z)
	var open_interior_edges := 0
	var nonmanifold_edges := 0
	for edge in edges:
		if edges[edge]==1 and not perimeter[edge]:
			open_interior_edges += 1
		if edges[edge]>2:
			nonmanifold_edges += 1
	check(open_interior_edges==0,"no render terrain holes or near/far cracks")
	check(nonmanifold_edges==0,"no duplicated overlapping terrain triangles")
	var count := environment.get_child_count()
	environment.build()
	check(environment.get_child_count() == count,"environment build idempotent")
	await physics_frame
	await physics_frame
	for x in [-239.0,-160.0,-80.0,0.0,80.0,160.0,239.0]:
		for z in [-239.0,-160.0,-80.0,0.0,80.0,160.0,239.0]:
			# Godot's heightfield ray tracer can miss exact triangle/grid boundaries.
			# Record this explicitly; verify a nearby ray AND a finite contact shape.
			var edge_ray := PhysicsRayQueryParameters3D.create(Vector3(x,80,z),Vector3(x,-5,z))
			if environment.get_world_3d().direct_space_state.intersect_ray(edge_ray).is_empty():
				exact_edge_ray_misses += 1
			var sphere := SphereShape3D.new()
			sphere.radius = .15
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = sphere
			query.transform = Transform3D(Basis.IDENTITY,Vector3(x,environment.height_at(x,z)+.04,z))
			check(not environment.get_world_3d().direct_space_state.intersect_shape(query).is_empty(),"finite floor contact at grid boundary")
			var ray := PhysicsRayQueryParameters3D.create(Vector3(x+.017,80,z+.023),Vector3(x+.017,-5,z+.023))
			var result_hit := environment.get_world_3d().direct_space_state.intersect_ray(ray)
			check(not result_hit.is_empty(),"terrain ray present %s/%s" % [x,z])
			if not result_hit.is_empty() and result_hit.collider.name=="PeatBasinHeightfield":
				check(absf(result_hit.position.y-environment.height_at(x+.017,z+.023))<.15,"heightfield matches render samples")
	var signature: String = environment.scatter_signature
	var vegetation_count: int = environment.vegetation_instances
	environment.free()
	var second := Node3D.new()
	second.set_script(environment_script)
	second.include_collision = false
	root.add_child(second)
	check(second.scatter_signature==signature,"deterministic scatter positions")
	check(second.vegetation_instances==vegetation_count,"deterministic foliage count")
	second.free()
	var result := {"checks":checks,"failures":failures,"exact_heightfield_boundary_ray_misses":exact_edge_ray_misses,"ray_caveat":"Exact grid/triangle boundary point rays may miss in this Godot build; paired offset rays and finite sphere contacts are asserted. Not a claim that point-ray edge behavior passes.","engine":Engine.get_version_info().string,"scope":"Only Mirewood imported geometry, shared materials, LOD settings and independent static collision; no gameplay assertions"}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://art/reports/v5"))
	FileAccess.open("res://art/reports/v5/runtime_tests.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("MIREWOOD_RUNTIME_TESTS ", JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
