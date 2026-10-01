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
	var material_ids: Dictionary={}
	var configured_shadow_geometry := 0
	var multimesh_batches := 0
	var geometries := a.find_children("*","GeometryInstance3D",true,false)
	for g: GeometryInstance3D in geometries:
		if g.material_override:material_ids[g.material_override.get_instance_id()]=true
		if g.cast_shadow!=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:configured_shadow_geometry+=1
		if g is MultiMeshInstance3D:multimesh_batches+=1
	assert(material_ids.size()<=6)
	var result := {"unique_override_material_resources":material_ids.size(),"configured_geometry_nodes_all_lods":geometries.size(),"configured_shadow_geometry_all_lods":configured_shadow_geometry,"multimesh_batches_all_lods":multimesh_batches,"shadow_max_distance_metres":110,"foliage_lod_bands_metres":[[0,32],[32,62],[62,95]],"solid_lod_boundaries_metres":[45,105,340],"cliff_lod_boundaries_metres":[90,190,580],"counter_note":"Configured geometry/shadow counts include every LOD resource, not simultaneously rendered draws. Actual view workload is in render_costs.json.","asset_instances":a.asset_count,"vegetation_instances":a.vegetation_instances,"terrain_triangles":a.terrain_triangles,"collision_shapes":world_shapes.size(),"scatter_fingerprint":a.scatter_fingerprint,"determinism":"same seed equal","scene":"res://art/tests/ancient_valley.tscn"}
	DirAccess.make_dir_recursive_absolute("res://art/reports/v2")
	FileAccess.open("res://art/reports/v2/runtime_tests.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("VALLEY_RUNTIME_OK ",JSON.stringify(result))
	a.queue_free();b.queue_free();await process_frame;quit()
