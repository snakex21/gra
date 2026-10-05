extends SceneTree
## Sliced generation preserves exact placement/order and reads current settings.
## Never reads transforms from headless dummy-renderer MultiMeshes.
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func batch_records(parent: Node3D) -> Array:
	var records := []
	for batch: MultiMeshInstance3D in parent.get_children():
		records.append([String(batch.name), batch.position, batch.multimesh.mesh.resource_path,
			batch.multimesh.instance_count, batch.multimesh.visible_instance_count,
			batch.multimesh.custom_aabb, batch.visibility_range_begin, batch.visibility_range_end,
			batch.get_meta(&"route_meadow", false), batch.get_meta(&"groundcover_kind"), batch.get_meta(&"groundcover_lod")])
	return records

func check_mid_lod_profile_switch(origin: Vector2i, samples: Dictionary) -> bool:
	# Force the supported yield boundary after LOD0 so timing cannot make this
	# regression check accidentally switch only between complete spatial groups.
	for cell: Vector2i in samples:
		for kind: String in samples[cell]:
			var transforms: Array = samples[cell][kind]
			var streamed := Node3D.new()
			root.add_child(streamed)
			streamed.set_meta(&"environment_groundcover_profile", "low")
			var state := EnvironmentGroundcover._route_state(origin, 5)
			state.row = EnvironmentGroundcover.ROUTE_ROWS
			state.shuffled = true
			state.batches = [[cell, kind, transforms]]
			state.prepared = EnvironmentGroundcover._prepare_cell_kind(cell, kind, transforms)
			state.batch_lod = 1
			EnvironmentGroundcover._append_cell_lod(streamed, cell, kind, transforms, "low", true, state.prepared, 0)
			check(streamed.get_child_count() == 1, "Mid-LOD fixture did not stop after LOD0")
			GraphicsQuality.apply(streamed, "high")
			while not EnvironmentGroundcover._append_route_step(streamed, state):
				pass
			var synchronous := Node3D.new()
			root.add_child(synchronous)
			EnvironmentGroundcover._append_cell_kind(synchronous, cell, kind, transforms, "high", true)
			check(var_to_bytes(batch_records(streamed)) == var_to_bytes(batch_records(synchronous)), "Quality switch between LOD uploads left mixed density/ranges")
			check(state.size() == 1 and state.get("done", false), "Completed mid-LOD job retained CPU sampler arrays")
			streamed.free()
			synchronous.free()
			return true
	return false

func run() -> void:
	var began := Time.get_ticks_usec()
	# Same independent cache warmup used by production; timing below excludes IO.
	for kind: String in ["grass_meadow_soft", "grass_meadow_straw", "shrub_meadow", "rock_02"]:
		for lod in 3:
			EnvironmentGroundcover.ASSET.mesh_for(kind, lod)
	var sample_hashes := []
	var steps := 0
	var maximum_step := 0
	var durations := []
	var all_batches := 0
	var mid_lod_switch_checked := false
	var four_candidate_steps := 0
	for z in range(-768, 256, 256):
		for x in range(0, 768, 256):
			var origin := Vector2i(x, z)
			var expected := EnvironmentGroundcover.sample_chunk(origin, {}, 5)
			var state := EnvironmentGroundcover._route_state(origin, 5)
			var slice := 0
			while int(state.row) < EnvironmentGroundcover.ROUTE_ROWS:
				EnvironmentGroundcover._sample_route_rows(state, [1, 7, 3, 2][slice % 4])
				slice += 1
			EnvironmentGroundcover._shuffle_route_cells(state.cells, state.rng)
			check(var_to_bytes(expected) == var_to_bytes(state.cells), "Sliced meadow changed deterministic transforms/order: " + str(origin))
			# Production streams four candidates, not full rows; exercise the column
			# cursor and the same incremental group-shuffle branch before any upload.
			var atomic := EnvironmentGroundcover._route_state(origin, 5)
			while int(atomic.row) < EnvironmentGroundcover.ROUTE_ROWS:
				var prior := int(atomic.row) * EnvironmentGroundcover.ROUTE_ROWS + int(atomic.get("column", 0))
				EnvironmentGroundcover._sample_route_rows(atomic, 1, 4)
				var next := int(atomic.row) * EnvironmentGroundcover.ROUTE_ROWS + int(atomic.get("column", 0))
				check(next > prior and next - prior <= 4, "Four-candidate sampler lost its bounded cursor")
				four_candidate_steps += 1
			var shuffle_parent := Node3D.new()
			root.add_child(shuffle_parent)
			while not atomic.shuffled:
				EnvironmentGroundcover._append_route_step(shuffle_parent, atomic)
			check(shuffle_parent.get_child_count() == 0, "Shuffle stage unexpectedly uploaded LOD geometry")
			check(var_to_bytes(expected) == var_to_bytes(atomic.cells), "Four-candidate sampling/incremental shuffle changed exact transform bytes: " + str(origin))
			check(state.rng.state == atomic.rng.state, "Incremental shuffle changed RNG consumption: " + str(origin))
			shuffle_parent.free()
			if not mid_lod_switch_checked:
				mid_lod_switch_checked = check_mid_lod_profile_switch(origin, expected)
			sample_hashes.append({"chunk": [x, z], "sha256": var_to_bytes(expected).hex_encode().sha256_text()})
			var streamed := Node3D.new()
			root.add_child(streamed)
			var queue := ArenaArtBuild.new()
			streamed.set_meta(&"detail_job", queue)
			streamed.set_meta(&"environment_groundcover_profile", "high")
			EnvironmentGroundcover.append_chunk(streamed, origin, {}, 5)
			check(queue.jobs.size() == 1 and streamed.get_child_count() == 0, "Runtime route append did not defer work")
			# The queued job must use the quality selected after enqueue, rather
			# than capture the earlier profile in its closure.
			streamed.set_meta(&"environment_groundcover_profile", "low")
			while queue.cursor < queue.jobs.size():
				var start := Time.get_ticks_usec()
				queue.step(1800, 1)
				var duration := Time.get_ticks_usec() - start
				durations.append(duration)
				maximum_step = maxi(maximum_step, duration)
				steps += 1
			var synchronous := Node3D.new()
			root.add_child(synchronous)
			synchronous.set_meta(&"environment_groundcover_profile", "low")
			EnvironmentGroundcover.append_chunk(synchronous, origin, {}, 5)
			check(var_to_bytes(batch_records(streamed)) == var_to_bytes(batch_records(synchronous)), "Streamed batch metadata/AABBs/quality differ from direct append: " + str(origin))
			for batch: MultiMeshInstance3D in streamed.get_children():
				check(batch.get_meta(&"route_meadow", false), "Route batch lost extended-distance metadata")
				check(batch.multimesh.visible_instance_count == maxi(1, ceili(batch.multimesh.instance_count * .35)), "Pending job ignored current quality profile")
			all_batches += streamed.get_child_count()
			streamed.free()
			synchronous.free()
	# Cancellation must complete without accessing a destroyed parent or retaining
	# the generated CPU arrays in the long-lived queue callable.
	var cancelled := EnvironmentGroundcover._route_state(Vector2i(256, -256), 5)
	check(EnvironmentGroundcover._append_route_step(null, cancelled) and cancelled.get("done", false), "Cancelled route job did not finish safely")
	check(cancelled.size() == 1, "Cancelled route job retained sampler state")
	check(mid_lod_switch_checked, "No populated route group exercised the mid-LOD settings switch")
	durations.sort()
	var p95: int = durations[mini(durations.size() - 1, floori(durations.size() * .95))] if not durations.is_empty() else 0
	# CPU scheduling/load can affect max latency. Report max and p95 rather than
	# claiming a wall-clock guarantee on every machine; inspect serial validation.
	var report := {"failures": failures, "chunks": sample_hashes, "streamed_batches": all_batches,
		"four_candidate_steps": four_candidate_steps, "mid_lod_profile_switch_checked": mid_lod_switch_checked,
		"streamed_steps": steps, "max_streamed_step_usec": maximum_step, "p95_streamed_step_usec": p95,
		"soft_budget_usec": 1250, "atomic_unit": "four candidates, one batch preparation, or one LOD upload",
		"elapsed_usec": Time.get_ticks_usec() - began, "gpu_fps_measured": false}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	var file := FileAccess.open("res://tests/output/route_meadow_streaming.json", FileAccess.WRITE)
	check(file != null, "Could not write meadow streaming report")
	if file:
		report.failures = failures
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	print("ROUTE_MEADOW_STREAMING: ", JSON.stringify(report))
	quit(1 if failures else 0)
