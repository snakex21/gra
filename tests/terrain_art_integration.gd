extends SceneTree
## Integrated layout-4 build: source geometry + both visual foliage layers.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var failures := 0
	var layout := 4 if OS.get_cmdline_user_args().has("--layout4") else 5
	var world := Node3D.new()
	root.add_child(world)
	GraphicsQuality.apply(world, "balanced")
	var began := Time.get_ticks_usec()
	ForbiddenLandsTerrain.build(world, true, layout)
	var synchronous_build_usec := Time.get_ticks_usec() - began
	var terrain := world.get_node("ForbiddenLandsTerrain")
	var job: ArenaArtBuild = terrain.get_meta(&"detail_job")
	var timings := []
	var initial_jobs := job.jobs.size()
	var step_count := 0
	var queue_usec := 0
	# Time actual queue steps, including resumable meadow work appended while
	# earlier chunk jobs execute. Wrapping only the initial jobs misses it.
	while job.cursor < job.jobs.size():
		var index := job.cursor
		var start := Time.get_ticks_usec()
		ForbiddenLandsTerrain.step_details(job, layout)
		var elapsed := Time.get_ticks_usec() - start
		queue_usec += elapsed
		timings.append({"job_index": index, "step_index": step_count, "dynamic_job": index >= initial_jobs,
			"completed": job.cursor > index, "usec": elapsed})
		step_count += 1
	timings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.usec > b.usec)
	var batches := terrain.find_children("*", "MultiMeshInstance3D", true, false)
	var authored_instances := 0
	var authored_batches := 0
	var groundcover_instances := 0
	var mesh_ids := {}
	for batch: MultiMeshInstance3D in batches:
		mesh_ids[batch.multimesh.mesh.get_instance_id()] = true
		if batch.has_meta(&"authored_nature_model_id"):
			authored_batches += 1
			if batch.get_meta(&"groundcover_lod") == 0:
				authored_instances += batch.multimesh.instance_count
			if batch.multimesh.visible_instance_count != (batch.multimesh.instance_count if batch.get_meta(&"authored_landmark", false) else maxi(1, ceili(batch.multimesh.instance_count * .65))):
				failures += 1
		elif batch.has_meta(&"groundcover_kind") and batch.get_meta(&"groundcover_lod") == 0:
			groundcover_instances += batch.multimesh.instance_count
	if authored_instances != AuthoredNature.records().size() or authored_instances != 864:
		failures += 1
	if authored_batches > 600 or batches.size() > (10000 if layout == 5 else 4600) or groundcover_instances > (75000 if layout == 5 else 8840):
		failures += 1
	var report := {"failures": failures, "layout": layout, "authored_instances": authored_instances, "authored_batches": authored_batches, "procedural_groundcover_instances": groundcover_instances, "all_world_batches": batches.size(), "shared_meshes": mesh_ids.size(), "jobs": job.jobs.size(), "initial_jobs": initial_jobs, "queue_steps": step_count, "queue_total_usec": queue_usec, "synchronous_build_usec": synchronous_build_usec, "queue_budget_usec": [1000,3000] if layout == 5 else [1800], "queue_max_units": 16 if layout == 5 else 1, "max_detail_job_usec": job.max_step_usec, "headless_build_dress_usec": Time.get_ticks_usec() - began, "gpu_fps_measured": false, "slowest_jobs": timings.slice(0, 5)}
	print("TERRAIN_ART_INTEGRATION: ", JSON.stringify(report))
	var out := FileAccess.open("res://tests/output/terrain_art_integration.json", FileAccess.WRITE)
	out.store_string(JSON.stringify(report, "  "))
	out.close()
	world.free()
	quit(1 if failures else 0)
