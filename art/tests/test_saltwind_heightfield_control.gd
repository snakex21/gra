extends SceneTree
## Minimal flat-heightfield control, independent of Saltwind generation.
var result := {"engine":Engine.get_version_info().string,"shape":"flat 97x97 HeightMapShape3D, scale 5, zero heights","probes":49,"exact_ray_misses":[],"offset_ray_misses":[],"finite_contact_misses":[]}
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var body := StaticBody3D.new()
	world.add_child(body)
	var node := CollisionShape3D.new()
	var shape := HeightMapShape3D.new()
	shape.map_width = 97
	shape.map_depth = 97
	var heights := PackedFloat32Array()
	heights.resize(97*97)
	heights.fill(0.0)
	shape.map_data = heights
	node.shape = shape
	node.scale = Vector3(5,1,5)
	body.add_child(node)
	await physics_frame
	await physics_frame
	var state := world.get_world_3d().direct_space_state
	for x in [-239.0,-160.0,-80.0,0.0,80.0,160.0,239.0]:
		for z in [-239.0,-160.0,-80.0,0.0,80.0,160.0,239.0]:
			for mode in ["exact","offset"]:
				var dx := 0.017 if mode=="offset" else 0.0
				var dz := 0.023 if mode=="offset" else 0.0
				var ray := PhysicsRayQueryParameters3D.create(Vector3(x+dx,80,z+dz),Vector3(x+dx,-5,z+dz))
				if state.intersect_ray(ray).is_empty():
					result[mode+"_ray_misses"].append([x,z])
			var sphere := SphereShape3D.new()
			sphere.radius = .15
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = sphere
			query.transform = Transform3D(Basis.IDENTITY,Vector3(x,.04,z))
			if state.intersect_shape(query).is_empty():
				result.finite_contact_misses.append([x,z])
	FileAccess.open("res://art/reports/v4/heightfield_control.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("SALTWIND_FLAT_HEIGHTFIELD_CONTROL ",JSON.stringify(result))
	world.free()
	quit(0 if result.offset_ray_misses.is_empty() and result.finite_contact_misses.is_empty() else 1)
