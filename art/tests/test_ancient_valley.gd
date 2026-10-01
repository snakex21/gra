extends SceneTree
const Valley=preload("res://art/scripts/ancient_valley.gd")
const Asset=preload("res://art/scripts/valley_asset.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var a := Node3D.new();a.set_script(Valley);root.add_child(a)
	assert(a.terrain_triangles==28800)
	assert(a.asset_count>90 and a.vegetation_instances>300)
	assert(Valley.height_at(40,42)<-2.9)
	assert(absf(Valley.height_at(-32,28)-1.4)<.001)
	var b := Node3D.new();b.set_script(Valley);b.include_collision=false;root.add_child(b)
	assert(a.scatter_fingerprint==b.scatter_fingerprint)
	assert(a.vegetation_instances==b.vegetation_instances)
	for id in ["arch","door","rock_arch"]:
		for level in 3:assert(Asset.mesh_for(id,level)!=null)
	var world_shapes := a.find_children("*","CollisionShape3D",true,false)
	assert(world_shapes.size()>80)
	var result := {"asset_instances":a.asset_count,"vegetation_instances":a.vegetation_instances,"terrain_triangles":a.terrain_triangles,"collision_shapes":world_shapes.size(),"scatter_fingerprint":a.scatter_fingerprint,"determinism":"same seed equal","scene":"res://art/tests/ancient_valley.tscn"}
	DirAccess.make_dir_recursive_absolute("res://art/reports/v2")
	FileAccess.open("res://art/reports/v2/runtime_tests.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("VALLEY_RUNTIME_OK ",JSON.stringify(result))
	a.queue_free();b.queue_free();await process_frame;quit()
