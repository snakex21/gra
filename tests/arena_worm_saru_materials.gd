extends SceneTree
## Independent material isolation + encounter reset contract (headless; no GPU claim).
const EXPECTED := {"worm": 1, "saru": 3}
var failures := 0
var report := {"arenas": {}, "legacy_layouts": [], "gpu_fps_measured": false}
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func meshes(parent: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for node: MeshInstance3D in parent.find_children("*", "MeshInstance3D", true, false): result.append(node)
	return result
func role(node: MeshInstance3D, parent: Node3D, arena: String) -> String:
	var body := node.get_parent()
	if not body is StaticBody3D or body.get_parent() != parent: return ""
	if body.name == &"Ground": return arena
	if arena == "saru" and body.name == &"ChasmFloor": return "saru_chasm"
	return ""
func coated(parent: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for node in meshes(parent):
		if node.has_meta(&"arena_ground_material"): result.append(node)
	return result
func snapshot(parent: Node3D) -> PackedByteArray:
	var rows := []
	for node in meshes(parent):
		var surfaces := []
		for i in node.mesh.get_surface_count():
			var mat := node.mesh.surface_get_material(i)
			surfaces.append([node.mesh.surface_get_arrays(i), mat.get_instance_id() if mat else 0])
		rows.append([node.get_instance_id(), node.mesh.get_instance_id(), node.transform, node.visible, node.layers, surfaces])
	for node: CollisionShape3D in parent.find_children("*", "CollisionShape3D", true, false):
		var props := []
		for prop: Dictionary in node.shape.get_property_list():
			if int(prop.usage) & PROPERTY_USAGE_STORAGE and not String(prop.name).begins_with("resource_"): props.append([prop.name, node.shape.get(prop.name)])
		rows.append([node.get_instance_id(), node.shape.get_instance_id(), node.transform, node.disabled, node.get_parent().transform, node.get_parent().collision_layer, node.get_parent().collision_mask, props])
	rows.append(parent.find_children("*", "", true, false).size())
	return var_to_bytes(rows)
func originals(parent: Node3D) -> Dictionary:
	var result := {}
	for node in meshes(parent): result[node.get_instance_id()] = [node.material_override, node.material_overlay]
	return result
func original_material_states(old: Dictionary) -> PackedByteArray:
	var rows := []
	var seen := {}
	for pair: Array in old.values():
		for material in pair:
			if material == null or seen.has(material.get_instance_id()): continue
			seen[material.get_instance_id()] = true
			var properties := []
			for prop: Dictionary in material.get_property_list():
				if not int(prop.usage) & PROPERTY_USAGE_STORAGE or String(prop.name).begins_with("resource_"): continue
				var value: Variant = material.get(prop.name)
				properties.append([prop.name, value.get_instance_id() if value is Resource else value])
			rows.append([material.get_instance_id(), properties])
	return var_to_bytes(rows)
func assert_appearance(parent: Node3D, arena: String, old: Dictionary) -> void:
	check(coated(parent).size() == EXPECTED[arena], arena + " target count")
	for node in meshes(parent):
		var target := role(node, parent, arena)
		check(node.has_meta(&"arena_ground_material") == not target.is_empty(), arena + " target role")
		if target.is_empty():
			check(node.material_override == old[node.get_instance_id()][0], arena + " excluded override changed")
			check(node.material_overlay == old[node.get_instance_id()][1], arena + " excluded overlay changed")
		else:
			check(node.material_override == ArenaGroundMaterials.material_for(target), arena + " wrong cached material")
			check(node.get_meta(&"arena_ground_material") == target, arena + " wrong metadata")
func build(arena: String, campaign := true) -> Node3D:
	var parent := Node3D.new(); parent.process_mode = Node.PROCESS_MODE_DISABLED; root.add_child(parent)
	parent.transform = Transform3D(Basis(Vector3.UP, 0.71), Vector3(641, 8, -311))
	if campaign:
		var game := GameWorld.new(); game._build_arena_ground(StringName(arena), parent); game.free()
	else:
		if arena == "worm": WormArena.build(parent)
		else: SaruArena.build(parent)
	return parent
func drain(job: ArenaArtBuild) -> void:
	var deadline := Time.get_ticks_msec() + 20000
	while not job.step(1000, 1):
		if Time.get_ticks_msec() > deadline:
			check(false, "material queue timeout"); return
		await process_frame
func audit(arena: String) -> void:
	var parent := build(arena)
	var before := snapshot(parent)
	var old := originals(parent)
	var material_before := original_material_states(old)
	var job := ArenaArt.plan(func() -> void: ArenaGroundMaterials.append(parent, arena))
	check(coated(parent).is_empty(), arena + " eager plan mutation")
	check(job.jobs.size() == (2 if arena == "worm" else 5), arena + " queue work splitting")
	await drain(job)
	assert_appearance(parent, arena, old)
	ArenaGroundMaterials.append(parent, arena)
	for profile in ["low", "balanced", "high", "low", "balanced"]: GraphicsQuality.apply(parent, profile)
	assert_appearance(parent, arena, old)
	check(snapshot(parent) == before, arena + " exact geometry/resource/physics mutation")
	check(original_material_states(old) == material_before, arena + " mutated original shared material properties")
	var second := build(arena, false)
	var second_old := originals(second)
	ArenaGroundMaterials.append(second, arena)
	assert_appearance(second, arena, second_old)
	for node in coated(second):
		var mat := node.material_override as StandardMaterial3D
		check(mat.uv1_triplanar and not mat.uv1_world_triplanar, arena + " nonlocal UVs")
		check(not mat.heightmap_enabled and mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, arena + " displacement/alpha")
		check(mat.normal_enabled and mat.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC, arena + " surface filtering")
		for slot in ["albedo", "normal", "roughness"]:
			var tex: Texture2D = mat.get(slot + "_texture")
			check(tex != null and tex.get_size() == Vector2(512, 512), arena + " texture budget")
	second.free(); parent.free()
	for midway in [false, true]:
		parent = build(arena)
		job = ArenaArt.plan(func() -> void: ArenaGroundMaterials.append(parent, arena))
		if midway:
			job.step(1000, 1); job.step(1000, 1)
			check(coated(parent).size() == 1, arena + " midway fixture")
		parent.free(); await drain(job)
		check(job.cursor == job.jobs.size(), arena + " cancellation queue incomplete")
	report.arenas[arena] = {"targets": EXPECTED[arena], "cold_queue": true, "exact_identity_geometry_physics": true, "quality_repeat_shared_resources": true, "freed_targets": true}
func audit_negative(arena: String) -> void:
	for change in ["hidden", "body_offset", "mesh_offset", "body_rotation", "shape", "nested", "same_bounds_normals"]:
		var parent := build(arena)
		var targets := []
		for mesh in meshes(parent):
			if not role(mesh, parent, arena).is_empty(): targets.append(mesh)
		for mesh: MeshInstance3D in targets:
			match change:
				"hidden": mesh.visible = false
				"body_offset": mesh.get_parent().position.x = 1.0
				"mesh_offset": mesh.position.y = 0.02
				"body_rotation": mesh.get_parent().rotation.y = 0.2
				"shape": mesh.mesh = BoxMesh.new()
				"same_bounds_normals":
					if mesh.mesh is ArrayMesh:
						var arrays := mesh.mesh.surface_get_arrays(0)
						var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
						normals[0] = -normals[0]; arrays[Mesh.ARRAY_NORMAL] = normals
						var forgery := ArrayMesh.new(); forgery.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
						mesh.mesh = forgery
					else: mesh.mesh = SphereMesh.new()
				"nested":
					var body := mesh.get_parent()
					if body.get_parent() == parent:
						var holder := Node3D.new(); parent.add_child(holder); body.reparent(holder)
		ArenaGroundMaterials.append(parent, arena)
		check(coated(parent).is_empty(), arena + " accepted invalid target: " + change)
		parent.free()
func audit_legacy() -> void:
	var game := GameWorld.new()
	for version in [1, 2, 3, 4, 5]:
		game.layout_version = version
		for arena: String in EXPECTED:
			var parent := Node3D.new(); root.add_child(parent)
			game._build_arena(StringName(arena), parent)
			check(coated(parent).size() == (EXPECTED[arena] if version == 5 else 0), "layout gate %d/%s" % [version, arena])
			parent.free()
		if version < 5: report.legacy_layouts.append(version)
	game.layout_version = 5; game.with_art = false
	for arena: String in EXPECTED:
		var parent := Node3D.new(); root.add_child(parent); game._build_arena(StringName(arena), parent)
		check(coated(parent).is_empty(), "art-off gate " + arena); parent.free()
	game.free()
func structural_bytes(parent: Node3D) -> PackedByteArray:
	var rows := []
	for node in meshes(parent):
		var arrays := []
		for i in node.mesh.get_surface_count(): arrays.append(node.mesh.surface_get_arrays(i))
		rows.append([parent.global_transform.affine_inverse() * node.global_transform, node.visible, arrays, node.material_override.resource_path if node.material_override else ""])
	return var_to_bytes(rows)
func audit_staged() -> void:
	var game := GameWorld.new(); game.layout_version = 5
	for arena: String in EXPECTED:
		var direct := Node3D.new(); var staged := Node3D.new()
		direct.process_mode = Node.PROCESS_MODE_DISABLED; staged.process_mode = Node.PROCESS_MODE_DISABLED
		root.add_child(direct); root.add_child(staged)
		game._build_arena(StringName(arena), direct)
		game.arenas[StringName(arena)] = {"root": staged, "points": {}}
		game._queue_arena(StringName(arena), staged); game._build_step()
		check(coated(staged).is_empty(), arena + " stage0 coating")
		var deadline := Time.get_ticks_msec() + 20000
		var steps := 0
		while not game.arenas_ready():
			game._build_step(); steps += 1
			if steps == 2: GraphicsQuality.apply(staged, "low")
			if steps == 7: GraphicsQuality.apply(staged, "high")
			if Time.get_ticks_msec() > deadline:
				check(false, arena + " staged timeout"); break
			await process_frame
		GraphicsQuality.apply(direct, "balanced"); GraphicsQuality.apply(staged, "balanced")
		check(structural_bytes(direct) == structural_bytes(staged), arena + " direct/staged geometry/material mismatch")
		check(coated(staged).size() == EXPECTED[arena] and game._art_jobs.is_empty(), arena + " staged final state")
		report.arenas[arena].production_staging_steps = steps
		direct.free(); staged.free()
	game.free()
func ticks(n: int) -> void:
	for i in n: await physics_frame
func audit_reset(arena: String) -> void:
	var parent := Node3D.new(); root.add_child(parent)
	parent.transform = Transform3D(Basis(Vector3.UP, 0.8), Vector3(700, 12, -550))
	var refs: Dictionary = WormArena.build_encounter(parent) if arena == "worm" else SaruArena.build_encounter(parent)
	for node in parent.find_children("*", "", true, false): node.set_physics_process(false)
	ArenaGroundMaterials.append(parent, arena)
	var old := originals(parent)
	if arena == "worm":
		var boss: Worm = refs.worm
		for plate in boss.plates:
			plate.enabled = true
			for i in plate.hits_to_break: plate.try_hit(plate.world_point(), 1.0, &"sword")
			check(plate.is_broken, "Worm break setup")
		refs.encounter.reset_encounter(); await ticks(2)
		check(boss.cycle == Worm.Cycle.LISTEN and not boss.completed.has(true), "Worm reset state")
		for plate in boss.plates:
			check(not plate.is_broken and plate.hits == 0 and not plate.shape.disabled, "Worm reset armor")
			for mesh in plate.meshes: check(mesh.visible and mesh.material_overlay == null, "Worm reset cracks")
	else:
		var bridge: SaruBridge = refs.bridge
		await ticks(2)
		var pit := parent.to_global(Vector3(0, 6.8, 0))
		var space := parent.get_world_3d().direct_space_state
		check(space.intersect_ray(PhysicsRayQueryParameters3D.create(pit, pit + Vector3.DOWN * 10, Layers.WORLD)).is_empty(), "Saru shortcut before bridge")
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(pit, pit + Vector3.DOWN * 40, Layers.WORLD))
		check(not hit.is_empty() and hit.collider.name == &"ChasmFloor" and is_equal_approx(parent.to_local(hit.position).y, -22), "Saru pit floor elevation: " + str(hit) + (" local=" + str(parent.to_local(hit.position)) if not hit.is_empty() else ""))
		for i in 2: check(bridge.stone_impact(i), "Saru impact setup")
		bridge._physics_process(3.1); await ticks(2)
		check(bridge.route_open and bridge.impacts == 2, "Saru bridge opening")
		refs.encounter.reset_encounter(); await ticks(2)
		check(not bridge.route_open and bridge.impacts == 0 and bridge.opened == [false, false], "Saru bridge reset state")
		for i in 2:
			check(bridge.spans[i].position == SaruBridge.STARTS[i] and bridge.panel_meshes[i].visible and not bridge.panels[i].disabled, "Saru bridge reset visual/collision")
	assert_appearance(parent, arena, old)
	parent.free(); await ticks(2)
	report.arenas[arena].interaction_reset_isolation = true
func run() -> void:
	InputSetup.ensure_defaults(); Sfx.enabled = false; Fx.enabled = false
	for arena: String in EXPECTED: await audit(arena)
	for arena: String in EXPECTED: audit_negative(arena)
	audit_legacy()
	await audit_staged()
	for arena: String in EXPECTED: await audit_reset(arena)
	report.failures = failures
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	var file := FileAccess.open("res://tests/output/arena_worm_saru_materials.json", FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "  ")); file.close()
	print("WORM_SARU_MATERIALS: ", JSON.stringify(report))
	quit(1 if failures else 0)
