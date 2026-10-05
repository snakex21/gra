extends SceneTree
const BAKE = preload("res://tools/art/bake_nature_placements.gd")
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var document = JSON.parse_string(FileAccess.get_file_as_string(AuthoredNature.PATH))
	check(AuthoredNature.validate(document).is_empty(), "Invalid authored placement document")
	var records := AuthoredNature.records()
	check(records.size() >= 400 and records.size() <= 900, "Placement count outside agreed budget")
	check(JSON.stringify(records) == JSON.stringify(document.instances), "Runtime records differ from JSON")
	check(JSON.stringify(BAKE.generate_document()) == JSON.stringify(BAKE.generate_document()), "Offline generation is nondeterministic")
	# Edited files need not match regenerated positions. The checked-in first pass does.
	if not OS.get_cmdline_user_args().has("--edited"):
		check(FileAccess.get_file_as_string(AuthoredNature.PATH) == JSON.stringify(BAKE.generate_document(), "  ") + "\n", "Baked placements stale after terrain edit; regenerate or test edited data with --edited")
	AuthoredNature.reset_cache()
	check(JSON.stringify(records) == JSON.stringify(AuthoredNature.records()), "JSON reload changes records")
	# Editing a detached record changes reconstruction exactly, never cache data.
	var edited: Dictionary = records[0].duplicate(true)
	edited.position = [123.25, 17.5, -456.75]
	edited.rotation = [.1, .7, -.2]
	edited.scale = [.9, 1.2, 1.1]
	var edited_xf := AuthoredNature.transform_for(edited)
	check(edited_xf.origin == Vector3(123.25, 17.5, -456.75), "Edited position ignored")
	check(edited_xf.basis.is_equal_approx(Basis.from_euler(Vector3(.1, .7, -.2)) * Basis.from_scale(Vector3(.9, 1.2, 1.1))), "Edited rotation/local scale ignored")
	check(JSON.stringify(AuthoredNature.records()) == JSON.stringify(records), "Editing detached records mutated the cached document")
	var chunks := {}
	var kinds := {}
	for record: Dictionary in records:
		var xf := AuthoredNature.transform_for(record)
		var p := xf.origin
		check(BAKE.allowed(Vector2(p.x, p.z)), "Clearance/slope violation: " + record.id)
		check(absf(p.y - ForbiddenLandsTerrain.surface_height(p.x, p.z, 4)) < .001, "Instance is not on actual triangle: " + record.id)
		var reconstructed := Transform3D(Basis.from_euler(AuthoredNature.vector(record.rotation)) * Basis.from_scale(AuthoredNature.vector(record.scale)), AuthoredNature.vector(record.position))
		check(xf == reconstructed, "Transform did not preserve authored fields")
		chunks[Vector2i(floori(p.x / 256) * 256, floori(p.z / 256) * 256)] = true
		kinds[record.model_id] = true
	if not OS.get_cmdline_user_args().has("--edited"):
		check(kinds.size() == 12, "Expected twelve selected plant models")
	var fixture := Node3D.new()
	root.add_child(fixture)
	GraphicsQuality.apply(fixture, "low")
	var sample_count := 0
	var maximum_cell_instances := 0
	for chunk: Vector2i in chunks:
		var samples := AuthoredNature.cells_for_chunk(chunk)
		check(var_to_bytes(samples) == var_to_bytes(AuthoredNature.cells_for_chunk(chunk)), "Runtime reconstruction is unstable")
		for cell: Vector2i in samples:
			var cell_instances := 0
			for kind: String in samples[cell]:
				sample_count += samples[cell][kind].size()
				cell_instances += samples[cell][kind].size()
			maximum_cell_instances = maxi(maximum_cell_instances, cell_instances)
		AuthoredNature.append_chunk(fixture, chunk)
	check(sample_count == records.size(), "Chunk index lost or duplicated placements")
	var batches := fixture.find_children("*", "MultiMeshInstance3D", true, false)
	check(batches.size() <= 600, "Authored batches exceed 600 world budget")
	check(fixture.find_children("*", "CollisionObject3D", true, false).is_empty(), "Visual nature adds physics bodies")
	check(fixture.find_children("*", "CollisionShape3D", true, false).is_empty(), "Visual nature adds collision shapes")
	var meshes := {}
	var allocated := 0
	var triangles_by_lod := [0, 0, 0]
	for batch: MultiMeshInstance3D in batches:
		allocated += batch.multimesh.instance_count
		meshes[batch.multimesh.mesh.get_instance_id()] = true
		check(batch.multimesh.mesh.get_surface_count() == 1, "Nature mesh must have one surface")
		check(batch.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Nature adds shadow cost")
		check(batch.multimesh.visible_instance_count == maxi(1, ceili(batch.multimesh.instance_count * .35)), "Incremental low quality ignored")
		var material := batch.material_override as StandardMaterial3D
		check(material != null and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "Nature material is not opaque")
		var lod: int = batch.get_meta(&"groundcover_lod")
		triangles_by_lod[lod] += batch.multimesh.mesh.get_faces().size() / 3 * batch.multimesh.instance_count
		if lod == 0:
			for next in [1, 2]:
				var peer := fixture.get_node(String(batch.name).replace("LOD0", "LOD%d" % next)) as MultiMeshInstance3D
				check(peer.multimesh.custom_aabb == batch.multimesh.custom_aabb and peer.position == batch.position, "LOD culling centers mismatch")
				check(peer.multimesh.instance_count == batch.multimesh.instance_count, "LOD population mismatch")
				check(peer.multimesh.mesh != batch.multimesh.mesh, "LOD did not use separate artist geometry")
			var kind: String = batch.get_meta(&"authored_nature_model_id")
			var cell := Vector2i(floori(batch.position.x / 64), floori(batch.position.z / 64))
			var chunk := Vector2i(floori(batch.position.x / 256) * 256, floori(batch.position.z / 256) * 256)
			var transforms: Array = AuthoredNature.cells_for_chunk(chunk)[cell][kind]
			for index in transforms.size():
				var local: Transform3D = transforms[index]
				local.origin -= batch.position
				for level in 3:
					check(batch.multimesh.custom_aabb.grow(.001).encloses(local * AuthoredNatureCatalog.mesh_for(kind, level).get_aabb()), "Common AABB clips nature")
				# Dummy headless rendering does not retain GPU transform buffers.
				if DisplayServer.get_name() != "headless":
					check(batch.multimesh.get_instance_transform(index).is_equal_approx(local), "GPU transform differs from authored record")
	check(allocated == records.size() * 3, "Exactly three LOD copies required")
	check(meshes.size() == kinds.size() * 3, "Meshes not shared across cells")
	check(triangles_by_lod[0] <= 2000000, "Full-world LOD0 exceeds two-million triangle budget")
	var populations := {}
	for profile: String in ["low", "balanced", "high"]:
		GraphicsQuality.apply(fixture, profile)
		var total := 0
		for batch: MultiMeshInstance3D in batches:
			if batch.get_meta(&"groundcover_lod") == 0:
				total += batch.multimesh.visible_instance_count
			check(batch.visibility_range_end > batch.visibility_range_begin and batch.visibility_range_end <= 140, "Invalid quality cull distance")
		populations[profile] = total
	check(populations.low < populations.balanced and populations.balanced < populations.high, "Live quality fails to reduce population")
	var bad: Dictionary = document.duplicate(true)
	bad.instances[0].model_id = "missing_model"
	check(not AuthoredNature.validate(bad).is_empty(), "Unknown model accepted")
	bad = document.duplicate(true)
	bad.instances[0].scale = [0, 1, 1]
	check(not AuthoredNature.validate(bad).is_empty(), "Zero scale accepted")
	bad = document.duplicate(true)
	bad.instances[1].id = bad.instances[0].id
	check(not AuthoredNature.validate(bad).is_empty(), "Duplicate id accepted")
	print("AUTHORED_NATURE: ", JSON.stringify({"failures": failures, "placements": records.size(), "batches": batches.size(), "unique_meshes": meshes.size(), "allocated_lod_instances": allocated, "full_world_triangles_by_lod": triangles_by_lod, "maximum_cell_placements": maximum_cell_instances, "quality_visible_placements": populations}))
	fixture.free()
	quit(1 if failures else 0)
