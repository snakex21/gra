extends SceneTree
## Art-only structural/import/physics checks, no gameplay dependencies.
const Asset = preload("res://art/scripts/hollowvault_asset.gd")
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
	check(default_item.model_id == "great_closed_dome", "valid default module")
	check(default_item.get_child_count() == 3, "default module builds three LODs")
	default_item.free()
	var records := Asset.records()
	check(records.size() == 28, "28 distinct assets")
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
	print("HOLLOWVAULT_RUNTIME_OK checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
