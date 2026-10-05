extends SceneTree
## Independent CPU-only contract for the layout-5 Cave/Devil floor-only finish.
## Run: godot --headless --path . --script tests/arena_cave_floor_materials.gd
## Expected targets are transcribed from CaveArena, not the production selector.
const META := &"arena_cave_floor_material"
const SUPPORT_META := &"arena_cave_support_cutout"
const KINDS := ["cave", "devil"]
const HOLLOW := preload("res://art/scripts/hollowvault_asset.gd")
const ORIGINAL := preload("res://materials/hollowvault/atlas.tres")
var failures := 0
var checks := 0
var report := {"arenas":{}, "legacy_layouts":[], "gpu_fps_measured":false,
	"scope":"CPU headless: exact authored instance/LOD mapping, unchanged geometry, physics, light and shared resource identity, deferred queue interruption and isolated atlas reuse. No GPU/FPS or mip-render quality claim."}

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func digest(value: Variant) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(value))
	return hash.finish().hex_encode()

func meshes(parent: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for node: MeshInstance3D in parent.find_children("*","MeshInstance3D",true,false):
		result.append(node)
	return result

func coated(parent: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for node in meshes(parent):
		if node.has_meta(META): result.append(node)
	return result

func supports(parent: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for mesh in meshes(parent):
		if mesh.has_meta(SUPPORT_META): result.append(mesh)
	return result

func support_mesh(parent: Node3D) -> MeshInstance3D:
	var ground := parent.get_node_or_null("Ground") as StaticBody3D
	if ground == null: return null
	for child in ground.get_children():
		if child is MeshInstance3D: return child as MeshInstance3D
	return null

func value_signature(value: Variant, depth := 0) -> Variant:
	if value is Texture2D:
		return [value.get_class(),value.resource_path,value.get_size()]
	if value is Resource:
		if depth >= 4: return [value.get_class(),value.resource_path]
		var rows := []
		for property: Dictionary in value.get_property_list():
			if int(property.usage) & PROPERTY_USAGE_STORAGE and not String(property.name).begins_with("resource_"):
				rows.append([property.name,value_signature(value.get(property.name),depth+1)])
		return [value.get_class(),value.resource_path,rows]
	if value is Array:
		var rows := []
		for item: Variant in value: rows.append(value_signature(item,depth+1))
		return rows
	return value

func geometry_bytes(parent: Node3D) -> PackedByteArray:
	var rows := []
	for node in meshes(parent):
		var surfaces := []
		for surface in node.mesh.get_surface_count():
			var primitive: int = node.mesh.surface_get_primitive_type(surface) if node.mesh is ArrayMesh else Mesh.PRIMITIVE_TRIANGLES
			surfaces.append([node.mesh.get_class(),primitive,node.mesh.surface_get_arrays(surface)])
		rows.append([parent.global_transform.affine_inverse()*node.global_transform,node.visible,node.layers,node.cast_shadow,node.lod_bias,node.visibility_range_begin,node.visibility_range_end,node.visibility_range_fade_mode,surfaces])
	return var_to_bytes(rows)

func physics_bytes(parent: Node3D) -> PackedByteArray:
	var rows := []
	for node: CollisionShape3D in parent.find_children("*","CollisionShape3D",true,false):
		rows.append([parent.global_transform.affine_inverse()*node.global_transform,node.disabled,node.get_parent().collision_layer,node.get_parent().collision_mask,value_signature(node.shape)])
	return var_to_bytes(rows)

func identity_bytes(parent: Node3D) -> PackedByteArray:
	var rows := []
	for node: Node in parent.find_children("*","",true,false):
		rows.append([node.get_instance_id(),node.get_parent().get_instance_id(),node.get_class()])
		if node is Node3D: rows.append(node.transform)
		if node is MeshInstance3D:
			var surfaces := []
			for surface in node.mesh.get_surface_count():
				var material: Material = node.mesh.surface_get_material(surface)
				var override: Material = node.get_surface_override_material(surface)
				surfaces.append([material.get_instance_id() if material else 0,override.get_instance_id() if override else 0])
			rows.append([node.mesh.get_instance_id(),node.mesh.get_rid(),surfaces])
		if node is CollisionShape3D: rows.append([node.shape.get_instance_id(),node.shape.get_rid()])
	return var_to_bytes(rows)

func appearance_bytes(parent: Node3D) -> PackedByteArray:
	var rows := []
	for node in meshes(parent):
		rows.append([value_signature(node.material_override),node.get_meta(META,""),node.get_meta(SUPPORT_META,"")])
	return var_to_bytes(rows)

func snapshot(parent: Node3D) -> Dictionary:
	check(not meshes(parent).is_empty(),"Geometry snapshot fixture must contain meshes")
	var geometry := geometry_bytes(parent)
	check(geometry.size()>100,"Geometry snapshot is empty or incomplete")
	return {"geometry":geometry,"physics":physics_bytes(parent),"identity":identity_bytes(parent),"nodes":parent.find_children("*","",true,false).size(),"colliders":parent.find_children("*","CollisionShape3D",true,false).size(),"mesh_count":meshes(parent).size(),"root_transform":parent.transform}

func check_unchanged(parent: Node3D, before: Dictionary, label: String) -> void:
	check(geometry_bytes(parent)==before.geometry,"Geometry arrays/transforms/visibility changed: "+label)
	check(physics_bytes(parent)==before.physics,"Collider shapes/transforms/layers changed: "+label)
	check(identity_bytes(parent)==before.identity,"Tree identity, transforms, mesh/shape objects or surface materials changed: "+label)
	check(parent.find_children("*","",true,false).size()==before.nodes,"Nodes added or removed: "+label)
	check(parent.transform==before.root_transform,"Arena placement changed: "+label)

func light_bytes(parent: Node3D) -> PackedByteArray:
	var rows := []
	for node: Node in parent.find_children("*", "", true, false):
		if node is Light3D:
			var props := []
			for property: Dictionary in node.get_property_list():
				var key := String(property.name)
				if key.begins_with("light_") or key.begins_with("shadow_") or key.begins_with("spot_") or key.begins_with("omni_"):
					props.append([key, value_signature(node.get(key))])
			rows.append([node.get_class(), node.transform, props])
		elif node is WorldEnvironment:
			rows.append([value_signature(node.environment), value_signature(node.camera_attributes)])
	return var_to_bytes(rows)

func make_root() -> Node3D:
	var parent := Node3D.new()
	parent.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(parent)
	return parent

func expected_targets(parent: Node3D) -> Dictionary:
	var result := {}
	var expected := [["great_closed_dome", Vector3.ZERO]]
	for i in 12: expected.append(["vault_tunnel_12m", Vector3(0, 0, 35.5 + i * 11.5)])
	for spec: Array in expected:
		var found := []
		for child: Node in parent.get_children():
			if child.get_script() == HOLLOW and child.get("model_id") == spec[0] and child.transform.is_equal_approx(Transform3D(Basis.IDENTITY, spec[1])):
				found.append(child)
		check(found.size() == 1, "Missing/duplicate authored Hollowvault instance: " + str(spec))
		if found.size() != 1: continue
		var kit: Node3D = found[0]
		check(not bool(kit.get("collidable")), "Render kit unexpectedly collidable")
		for lod in 3:
			var mesh := kit.get_node_or_null("LOD%d" % lod) as MeshInstance3D
			check(mesh != null, "Missing authored LOD: " + str(spec) + "/" + str(lod))
			if mesh:
				check(mesh.mesh == HOLLOW.mesh_for(spec[0], lod), "Authored LOD mesh identity mismatch")
				result[mesh.get_instance_id()] = {"mesh":mesh, "model":spec[0], "lod":lod, "position":str(kit.position)}
	check(result.size() == 39, "Independent authored target count must be 39")
	return result

func check_assignment(parent: Node3D, kind: String, expected: Dictionary, previous: Dictionary) -> void:
	var material := ArenaCaveFloorMaterials.material_for(kind)
	check(material != null and material != ORIGINAL, "No separate floor variant: " + kind)
	var support := support_mesh(parent)
	check(support != null and support.mesh is CylinderMesh, "Independent support fixture absent")
	var cutout := load("res://materials/arena_cave/support_cutout.tres") as ShaderMaterial
	check(cutout != null and support.material_override == cutout, "Wrong support material assignment: " + kind)
	check(supports(parent).size() == 1 and support.has_meta(SUPPORT_META), "Expected exactly one support cutout: " + kind)
	var per_lod := [0, 0, 0]
	for mesh in meshes(parent):
		var id := mesh.get_instance_id()
		check(mesh.has_meta(META) == expected.has(id), "Coating escaped authored target list: " + kind + "/" + str(mesh.get_path()))
		if expected.has(id):
			per_lod[expected[id].lod] += 1
			check(mesh.material_override == material, "Wrong atlas variant on target: " + kind)
			check(String(mesh.get_meta(META, "")) == kind, "Wrong arena metadata: " + kind)
		elif previous.has(id) and mesh != support:
			check(mesh.material_override == previous[id], "Unrelated material identity changed: " + kind)
	check(per_lod == [13,13,13], "Not all 13 authored instances have all three LODs: " + kind)
	check(coated(parent).size() == 39, "Wrong total coating count: " + kind)

func baseline_script() -> GDScript:
	var source := FileAccess.get_file_as_string("res://src/game/game_world.gd")
	var hook := "\t\tArenaCaveFloorMaterials.append(root, String(kind))\n"
	check(source.count(hook) == 1, "Campaign floor hook must occur exactly once")
	source = source.replace("class_name GameWorld\n", "").replace(hook, "")
	var script := GDScript.new()
	script.source_code = source
	check(script.reload() == OK, "Baseline no-hook campaign fixture does not compile")
	return script

func previous_materials(parent: Node3D) -> Dictionary:
	var result := {}
	for mesh in meshes(parent): result[mesh.get_instance_id()] = mesh.material_override
	return result

func drain(job: ArenaArtBuild, label: String) -> int:
	var steps := 0
	var deadline := Time.get_ticks_msec() + 20000
	while not job.step(1000, 1):
		steps += 1
		if Time.get_ticks_msec() > deadline:
			check(false, "Queue timed out: " + label)
			return steps
		await process_frame
	check(job.cursor == job.jobs.size(), "Drained queue retains work: " + label)
	return steps + 1

func audit_append() -> void:
	var baseline: Node3D = baseline_script().new()
	baseline.layout_version = 5
	var first := make_root()
	var second := make_root()
	var discarded := make_root()
	first.transform = Transform3D(Basis(Vector3.UP, .71), Vector3(641, 8, -311))
	baseline._build_arena(&"cave", first)
	baseline._build_arena(&"devil", second)
	baseline._build_arena(&"cave", discarded)
	var expected_first := expected_targets(first)
	var expected_second := expected_targets(second)
	var before_first := snapshot(first)
	var before_second := snapshot(second)
	var light_first := light_bytes(first)
	var light_second := light_bytes(second)
	var materials_first := previous_materials(first)
	var materials_second := previous_materials(second)
	var original_resource := var_to_bytes(value_signature(ORIGINAL))
	var first_appearance := appearance_bytes(first)
	var cancelled := ArenaArt.plan(func() -> void: ArenaCaveFloorMaterials.append(discarded, "cave"))
	var discarded_ref: WeakRef = weakref(discarded)
	discarded.free()
	check(discarded_ref.get_ref() == null, "Queued floor pass retains unloaded root")
	var first_job := ArenaArt.plan(func() -> void: ArenaCaveFloorMaterials.append(first, "cave"))
	var second_job := ArenaArt.plan(func() -> void: ArenaCaveFloorMaterials.append(second, "devil"))
	check(coated(first).is_empty() and coated(second).is_empty(), "Planning eagerly assigned floor materials")
	check(appearance_bytes(first) == first_appearance, "Planning changed appearance")
	var max_steps := 0
	var deadline := Time.get_ticks_msec() + 20000
	var done_first := false
	var done_second := false
	var done_cancelled := false
	while not (done_first and done_second and done_cancelled):
		if not done_first: done_first = first_job.step(1000, 1)
		if not done_second: done_second = second_job.step(1000, 1)
		if not done_cancelled: done_cancelled = cancelled.step(1000, 1)
		max_steps += 1
		if Time.get_ticks_msec() > deadline:
			check(false, "Concurrent cold Cave/Devil/cancelled queues timed out")
			break
		await process_frame
	check_assignment(first, "cave", expected_first, materials_first)
	check_assignment(second, "devil", expected_second, materials_second)
	check_unchanged(first, before_first, "cave")
	check_unchanged(second, before_second, "devil")
	check(light_bytes(first) == light_first and light_bytes(second) == light_second, "Floor pass changed lighting")
	check(var_to_bytes(value_signature(ORIGINAL)) == original_resource, "Shared original Hollowvault/Deeprelic atlas mutated")
	var shared := ArenaCaveFloorMaterials.material_for("cave")
	check(shared == ArenaCaveFloorMaterials.material_for("devil"), "Cave/Devil duplicate shared material")
	var warm_began := Time.get_ticks_usec()
	ArenaCaveFloorMaterials.append(first, "cave")
	var warm_usec := Time.get_ticks_usec() - warm_began
	check_unchanged(first, before_first, "idempotent cave")
	for profile in ["low", "balanced", "high", "low", "balanced"]:
		GraphicsQuality.apply(first, profile)
		check_assignment(first, "cave", expected_first, materials_first)
	for kind in KINDS:
		var parent: Node3D = first if kind == "cave" else second
		var before: Dictionary = before_first if kind == "cave" else before_second
		report.arenas[kind] = {"targets":39, "support_cutouts":1, "total_material_assignments":40, "lod_counts":[13,13,13], "total_meshes":meshes(parent).size(), "colliders":before.colliders,
			"geometry_sha256":digest(before.geometry), "physics_sha256":digest(before.physics), "concurrent_cold_steps":max_steps,
			"max_cpu_step_usec":maxi(first_job.max_step_usec, second_job.max_step_usec), "warm_assignment_usec":warm_usec,
			"shared_mesh_shape_and_surface_identity_preserved":true, "lighting_unchanged":true, "added_nodes":0}
	check(ArenaCaveFloorMaterials.material_for("unknown") == null, "Unsupported kind acquired variant")
	first.free()
	second.free()
	baseline.free()

func audit_campaign() -> void:
	var current := GameWorld.new()
	var baseline: Node3D = baseline_script().new()
	for layout in [1,2,3,4,5]:
		current.layout_version = layout
		baseline.layout_version = layout
		for kind in KINDS:
			var first := make_root()
			var other := make_root()
			current._build_arena(StringName(kind), first)
			baseline._build_arena(StringName(kind), other)
			check(coated(first).size() == (39 if layout == 5 else 0), "Wrong campaign layout count: %d/%s" % [layout, kind])
			check(coated(other).is_empty() and supports(other).is_empty(), "No-hook fixture unexpectedly coated")
			check(supports(first).size() == (1 if layout == 5 else 0), "Wrong support campaign layout count")
			check(geometry_bytes(first) == geometry_bytes(other), "Campaign geometry changed: %d/%s" % [layout,kind])
			check(physics_bytes(first) == physics_bytes(other), "Campaign physics changed: %d/%s" % [layout,kind])
			check(light_bytes(first) == light_bytes(other), "Campaign lighting changed: %d/%s" % [layout,kind])
			if layout < 5:
				check(appearance_bytes(first) == appearance_bytes(other), "Legacy appearance changed: %d/%s" % [layout,kind])
			else:
				var a := meshes(first)
				var b := meshes(other)
				for i in mini(a.size(), b.size()):
					if not a[i].has_meta(META) and not a[i].has_meta(SUPPORT_META):
						check(var_to_bytes(value_signature(a[i].material_override)) == var_to_bytes(value_signature(b[i].material_override)), "Campaign changed decoration/greybox: " + kind)
			first.free()
			other.free()
		if layout < 5: report.legacy_layouts.append(layout)
	current.layout_version = 5
	current.with_art = false
	for kind in KINDS:
		var artless := make_root()
		current._build_arena(StringName(kind), artless)
		check(coated(artless).is_empty() and supports(artless).is_empty(), "with_art=false acquired finish: " + kind)
		artless.free()
	current.free()
	baseline.free()
	report.with_art_false_unchanged = true

func audit_deferred_and_stop() -> void:
	var metrics := {}
	for kind in KINDS:
		var game := GameWorld.new()
		game.layout_version = 5
		var direct := make_root()
		var staged := make_root()
		game._build_arena(StringName(kind), direct)
		game.arenas[StringName(kind)] = {"root":staged, "points":{}}
		game._queue_arena(StringName(kind), staged)
		game._build_step()
		check(coated(staged).is_empty(), "Stage zero already coated: " + kind)
		var steps := 0
		var max_usec := 0
		var deadline := Time.get_ticks_msec() + 20000
		while not game.arenas_ready():
			var began := Time.get_ticks_usec()
			game._build_step()
			max_usec = maxi(max_usec, Time.get_ticks_usec() - began)
			steps += 1
			if steps == 2: GraphicsQuality.apply(staged, "low")
			if steps == 7: GraphicsQuality.apply(staged, "high")
			if Time.get_ticks_msec() > deadline:
				check(false, "Production staging timed out: " + kind)
				break
			await process_frame
		check(game._art_jobs.is_empty(), "Completed production queue retains art jobs")
		GraphicsQuality.apply(direct, "balanced")
		GraphicsQuality.apply(staged, "balanced")
		check(coated(staged).size() == 39, "Deferred selector missed art created later: " + kind)
		check(appearance_bytes(direct) == appearance_bytes(staged), "Staged/direct material mismatch: " + kind)
		check(geometry_bytes(direct) == geometry_bytes(staged), "Staged/direct geometry mismatch: " + kind)
		check(physics_bytes(direct) == physics_bytes(staged), "Staged/direct physics mismatch: " + kind)
		check(light_bytes(direct) == light_bytes(staged), "Staged/direct lighting mismatch: " + kind)
		metrics[kind] = {"steps":steps, "max_cpu_stage_usec":max_usec, "quality_switched_during_build":true, "direct_equals_staged":true}
		direct.free()
		staged.free()
		game.free()
		for midway in [false,true]:
			game = GameWorld.new()
			game.layout_version = 5
			game.with_input = false
			game.save_path = ""
			root.add_child(game)
			game.region = Node3D.new()
			game.add_child(game.region)
			var parent := Node3D.new()
			game.region.add_child(parent)
			var parent_ref: WeakRef = weakref(parent)
			game.arenas[StringName(kind)] = {"root":parent, "points":{}}
			game._queue_arena(StringName(kind), parent)
			game._build_step()
			if midway: game._build_step()
			game.stop()
			check(game._pending.is_empty() and game._art_jobs.is_empty(), "Stop retains queued jobs: " + kind)
			check(game.region == null and game.arenas.is_empty() and parent_ref.get_ref() == null, "Stop retains region/root: " + kind)
			check(ArenaCaveFloorMaterials.material_for(kind) == ArenaCaveFloorMaterials.material_for("cave"), "Stop discarded reusable variant")
			game.free()
	report.production_staging = metrics
	report.production_stop_before_and_during_art = true

func audit_partial_cancel() -> void:
	var baseline: Node3D = baseline_script().new()
	baseline.layout_version = 5
	for kind in KINDS:
		var parent := make_root()
		baseline._build_arena(StringName(kind), parent)
		var sentinel := {"called":false}
		var job := ArenaArt.plan(func() -> void:
			ArenaCaveFloorMaterials.append(parent, kind)
			ArenaArt._planner.add(func() -> void: sentinel.called = true))
		var attempts := 0
		while coated(parent).is_empty() and attempts < 100:
			job.step(1000, 1)
			attempts += 1
			await process_frame
		check(coated(parent).size() == 39, "Expected atomic application before trailing queue cancellation")
		check(not sentinel.called and job.cursor < job.jobs.size(), "Queue tail executed before cancellation checkpoint")
		var parent_ref: WeakRef = weakref(parent)
		parent.free()
		check(parent_ref.get_ref() == null, "Partially applied queue retains dead root")
		await drain(job, "after atomic apply unload " + kind)
		check(sentinel.called, "Pending queue tail did not drain safely after root unload")
	baseline.free()
	report.cold_and_after_atomic_apply_cancel_drained = true

func audit_standalone_and_reuse() -> void:
	for kind in KINDS:
		var parent := make_root()
		if kind == "cave": CaveArena.build_encounter(parent, false, true)
		else: DevilArena.build_encounter(parent, false, 109, true)
		check(coated(parent).is_empty() and supports(parent).is_empty(), "Standalone encounter received campaign-only finish: " + kind)
		var expected := expected_targets(parent)
		for data: Dictionary in expected.values(): check(data.mesh.material_override == ORIGINAL, "Standalone shell uses a campaign atlas")
		parent.free()
	var outside := make_root()
	for model in ["great_closed_dome", "vault_tunnel_12m", "stalagmite_great"]:
		var kit := Node3D.new()
		kit.set_script(HOLLOW)
		kit.model_id = model
		outside.add_child(kit)
		for mesh in meshes(kit): check(mesh.material_override == ORIGINAL, "New globally reused kit inherited campaign floor variant")
	var before := appearance_bytes(outside)
	ArenaCaveFloorMaterials.append(outside, "unknown")
	check(appearance_bytes(outside) == before, "Unsupported arena changed materials")
	outside.free()
	report.standalone_and_reused_kits_keep_original = true

func audit_selector_fail_closed() -> void:
	var baseline: Node3D = baseline_script().new()
	baseline.layout_version = 5
	var cases := ["kit_rotation", "kit_scale", "kit_position", "mesh_transform", "mesh_resource", "material_resource", "lod_name", "nested_asset", "kit_visibility", "mesh_visibility", "lod_range"]
	for mutation in cases:
		var parent := make_root()
		baseline._build_arena(&"cave", parent)
		var allowed := expected_targets(parent)
		var kit := parent.get_node("CaveArt_great_closed_dome") as Node3D
		var mesh := kit.get_node("LOD0") as MeshInstance3D
		var rejected: Array[MeshInstance3D] = []
		if mutation in ["kit_rotation", "kit_scale", "kit_position", "nested_asset", "kit_visibility"]:
			for child in meshes(kit): rejected.append(child)
		else: rejected.append(mesh)
		match mutation:
			"kit_rotation": kit.rotation.y = .1
			"kit_scale": kit.scale = Vector3.ONE * 1.1
			"kit_position": kit.position.x += 1
			"mesh_transform": mesh.position.x += 1
			"mesh_resource": mesh.mesh = mesh.mesh.duplicate()
			"material_resource": mesh.material_override = ORIGINAL.duplicate()
			"lod_name": mesh.name = "NotLOD0"
			"kit_visibility": kit.visible = false
			"mesh_visibility": mesh.visible = false
			"lod_range": mesh.visibility_range_end = 60.0
			"nested_asset":
				var container := Node3D.new()
				parent.add_child(container)
				kit.reparent(container)
		for excluded in rejected: allowed.erase(excluded.get_instance_id())
		var before := snapshot(parent)
		var previous := previous_materials(parent)
		ArenaCaveFloorMaterials.append(parent, "cave")
		check(coated(parent).size() == allowed.size(), "Fail-closed rejection count differs: " + mutation)
		check(supports(parent).is_empty(), "Cutout exposed incomplete/altered floor coverage: " + mutation)
		var support := support_mesh(parent)
		check(support.material_override == previous[support.get_instance_id()], "Incomplete footprint altered support material: " + mutation)
		for candidate in meshes(parent):
			check(candidate.has_meta(META) == allowed.has(candidate.get_instance_id()), "Fail-closed mapping violated: " + mutation)
		for excluded in rejected:
			check(excluded.material_override == previous[excluded.get_instance_id()], "Mutated unrelated replacement: " + mutation)
		check_unchanged(parent, before, mutation)
		parent.free()
	baseline.free()
	report.selector_fail_closed = cases

func audit_support_fail_closed() -> void:
	var baseline: Node3D = baseline_script().new()
	baseline.layout_version = 5
	var cases := ["wrong_height", "wrong_radius", "ground_position", "ground_rotation", "mesh_position", "support_material", "support_visibility", "wrong_mesh_type"]
	for mutation in cases:
		var parent := make_root()
		baseline._build_arena(&"cave", parent)
		var support := support_mesh(parent)
		match mutation:
			"wrong_height": support.mesh.height = 3
			"wrong_radius": support.mesh.top_radius = 150
			"ground_position": support.get_parent().position.y = -1.2
			"ground_rotation": support.get_parent().rotation.y = .2
			"mesh_position": support.position.x = .1
			"support_material":
				var replacement := StandardMaterial3D.new()
				replacement.albedo_color = Color.RED
				support.material_override = replacement
			"support_visibility": support.visible = false
			"wrong_mesh_type": support.mesh = SphereMesh.new()
		var before := snapshot(parent)
		var previous := support.material_override
		ArenaCaveFloorMaterials.append(parent, "cave")
		check(coated(parent).size() == 39, "Invalid support affected valid floor atlas: " + mutation)
		check(supports(parent).is_empty() and support.material_override == previous, "Support selector failed closed: " + mutation)
		check_unchanged(parent, before, "support " + mutation)
		parent.free()
	# Preserve the total of 39 LODs while replacing one placement with a duplicate
	# of another; a count-only safety gate would expose an uncovered corridor.
	var parent := make_root()
	baseline._build_arena(&"cave", parent)
	var tunnel_nodes := []
	for child: Node in parent.get_children():
		if child.get_script() == HOLLOW and child.get("model_id") == "vault_tunnel_12m": tunnel_nodes.append(child)
	check(tunnel_nodes.size() == 12, "Duplicate coverage fixture missing tunnels")
	var removed: Node = tunnel_nodes.pop_back()
	removed.free()
	var duplicate: Node = tunnel_nodes[0].duplicate()
	parent.add_child(duplicate)
	var support := support_mesh(parent)
	var previous := support.material_override
	var before := snapshot(parent)
	ArenaCaveFloorMaterials.append(parent, "cave")
	check(supports(parent).is_empty() and support.material_override == previous, "Duplicate module count exposed missing tunnel footprint")
	check_unchanged(parent, before, "duplicate coverage")
	parent.free()
	baseline.free()
	# Invalidate then restore coverage after a successful application. A repeated
	# append must restore the exact old support material rather than keep a hole.
	baseline = baseline_script().new()
	baseline.layout_version = 5
	parent = make_root()
	baseline._build_arena(&"cave", parent)
	support = support_mesh(parent)
	previous = support.material_override
	ArenaCaveFloorMaterials.append(parent, "cave")
	check(supports(parent).size() == 1, "Restoration fixture never applied cutout")
	var changed := parent.get_node("CaveArt_great_closed_dome") as Node3D
	changed.visible = false
	ArenaCaveFloorMaterials.append(parent, "cave")
	check(supports(parent).is_empty() and support.material_override == previous, "Reapplying incomplete coverage did not restore exact original support material")
	changed.visible = true
	ArenaCaveFloorMaterials.append(parent, "cave")
	check(supports(parent).size() == 1 and support.material_override == load("res://materials/arena_cave/support_cutout.tres"), "Restored full coverage did not reuse cutout material")
	parent.free()
	baseline.free()
	report.support_fail_closed = cases + ["duplicate_module_missing_footprint", "invalidate_restore_reapply"]

func audit_support_shader_source() -> void:
	var support := load("res://materials/arena_cave/support_cutout.tres") as ShaderMaterial
	check(support != null and support.shader != null, "Support shader resource did not load")
	if support == null or support.shader == null: return
	var code := support.shader.code
	check(code.contains("render_mode cull_back, depth_draw_opaque"), "Support shader changed opaque/backface pipeline")
	check(code.contains("support_local = VERTEX;"), "Support footprint lost original local coordinates")
	check(code.contains("dot(normalize(NORMAL), normalize(-VERTEX)) > 0.001"), "Support lost grazing-angle fallback guard")
	check(code.contains("if (clear_floor_angle && length(VERTEX) < 740.0 && abs(support_local.y - 1.0) < 0.01 && (chamber || tunnel))"), "Support discard not bounded to safe distance, top and footprint")
	check(code.contains("vec2(22.0, 28.0)") and code.contains("abs(p.x) < 5.5 && p.y > 29.55 && p.y < 167.95"), "Support mask bounds changed without coverage review")
	check(code.contains("base_color : source_color = vec4(0.18, 0.19, 0.18, 1.0)") and code.contains("ROUGHNESS = 1.0;") and code.contains("SPECULAR = 0.5;"), "Outside-mask original support shading settings changed")
	var displaced := RegEx.new()
	displaced.compile("\\b(?:VERTEX|POSITION|DEPTH|ALPHA)\\s*=")
	check(displaced.search(code) == null, "Support shader added displacement/depth/alpha writes")
	report.support_shader = {"source_guards_checked":true, "distance_limit_m":740.0, "minimum_view_normal_dot":0.001,
		"top_only":true, "resource_loaded":true, "actual_shader_draw_verified":false,
		"draw_probe_blocker":"No active X11/Wayland display; installed Xorg dummy cannot create Unix/local listening sockets. Godot headless only offers dummy rendering."}

func audit_actual_atlas() -> void:
	var material := ArenaCaveFloorMaterials.material_for("cave")
	check(material.resource_path == "res://materials/arena_cave/hollowvault_floor.tres", "Wrong shared variant provenance")
	for property: Dictionary in ORIGINAL.get_property_list():
		var name := String(property.name)
		if not int(property.usage) & PROPERTY_USAGE_STORAGE or name.begins_with("resource_") or name == "albedo_texture": continue
		check(var_to_bytes(value_signature(material.get(name))) == var_to_bytes(value_signature(ORIGINAL.get(name))), "Non-albedo material setting changed: " + name)
	check(not material.normal_enabled and not material.heightmap_enabled and not material.emission_enabled, "Floor finish changes wall normal/displacement/emission shading")
	var texture := material.albedo_texture
	check(texture != null and texture.resource_path == "res://textures/arena_cave/hollowvault_floor_atlas.png", "Wrong floor variant texture")
	check(texture.get_size() == Vector2(1024,1024), "Floor atlas source budget changed")
	check(texture == ArenaCaveFloorMaterials.material_for("devil").albedo_texture, "Arenas duplicate the variant atlas")
	var source := Image.load_from_file(ProjectSettings.globalize_path(ORIGINAL.albedo_texture.resource_path))
	var variant := Image.load_from_file(ProjectSettings.globalize_path(texture.resource_path))
	check(source != null and variant != null, "Could not read actual source PNGs")
	if source == null or variant == null: return
	source.convert(Image.FORMAT_RGBA8)
	variant.convert(Image.FORMAT_RGBA8)
	check(source.get_size() == variant.get_size(), "Atlas resolution changed")
	var original_bytes := source.get_data()
	var changed_bytes := variant.get_data()
	check(original_bytes != changed_bytes, "Floor variant has no actual source pixel change")
	# PNG-space soil is tile x=0..255,y=512..767 after Blender image export.
	for y in 1024:
		var start := y * 1024 * 4
		var allowed := y >= 512 and y < 768
		var offset := 256 * 4 if allowed else 0
		check(original_bytes.slice(start + offset, start + 4096) == changed_bytes.slice(start + offset, start + 4096), "Non-soil source atlas texels changed at row " + str(y))
	check(source.generate_mipmaps() == OK and variant.generate_mipmaps() == OK, "Native Godot source mip generation failed")
	var source_mips := source.get_data()
	var variant_mips := variant.get_data()
	var native_mips := []
	for level in range(4, source.get_mipmap_count() + 1):
		var start := source.get_mipmap_offset(level)
		var end := source.get_mipmap_offset(level + 1) if level < source.get_mipmap_count() else source_mips.size()
		var exact := source_mips.slice(start, end) == variant_mips.slice(start, end)
		check(exact, "Native Godot source mip changed: " + str(level))
		native_mips.append({"level":level, "all_bytes_equal":exact})
	var config := ConfigFile.new()
	check(config.load(texture.resource_path + ".import") == OK, "Missing new atlas import settings")
	check(config.get_value("params", "compress/mode", -1) == 2 and config.get_value("params", "mipmaps/generate", false), "New atlas compression/mipmap configuration invalid")
	var imported := texture.get_image()
	var old_imported := ORIGINAL.albedo_texture.get_image()
	check(imported != null and old_imported != null, "Imported texture unavailable to CPU audit")
	if imported == null or old_imported == null: return
	check(imported.is_compressed() and imported.has_mipmaps(), "Actual floor import lost compression/mips")
	check(imported.get_format() == old_imported.get_format(), "Atlas import encoding changed")
	check(imported.get_mipmap_count() == old_imported.get_mipmap_count(), "Atlas mip count changed")
	var imported_bytes := imported.get_data()
	var old_bytes := old_imported.get_data()
	check(imported_bytes.size() == old_bytes.size(), "Imported atlas payload size grew")
	check(imported_bytes != old_bytes, "Imported variant has no actual visible pixel change")
	var block_bytes := int(imported.get_mipmap_offset(1) / (256 * 256))
	check(block_bytes in [8,16], "Unexpected compressed block size")
	var imported_mips := []
	for level in range(imported.get_mipmap_count() + 1):
		var start := imported.get_mipmap_offset(level)
		var end := imported.get_mipmap_offset(level + 1) if level < imported.get_mipmap_count() else imported_bytes.size()
		var exact := imported_bytes.slice(start, end) == old_bytes.slice(start, end)
		if level >= 4: check(exact, "Actual compressed mip4+ changed: " + str(level))
		else:
			var blocks := 256 >> level
			var soil_first := 128 >> level
			var soil_end := 192 >> level
			var soil_width := 64 >> level
			for row in blocks:
				var begin := start + row * blocks * block_bytes
				var skip := soil_width * block_bytes if row >= soil_first and row < soil_end else 0
				check(imported_bytes.slice(begin + skip, begin + blocks * block_bytes) == old_bytes.slice(begin + skip, begin + blocks * block_bytes), "Imported non-soil compressed block changed at mip %d row %d" % [level, row])
		imported_mips.append({"level":level, "all_bytes_equal":exact})
	report.atlas = {"source_png_bytes":FileAccess.get_file_as_bytes(texture.resource_path).size(), "imported_cpu_payload_bytes":imported_bytes.size(),
		"additional_unique_texture_count":1, "nonsoil_source_and_imported_blocks_identical":true, "native_source_mips":native_mips,
		"actual_compressed_mips":imported_mips, "all_material_settings_except_albedo_identical":true, "gpu_residency_measured":false}

func run() -> void:
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	var began := Time.get_ticks_usec()
	await audit_append()
	audit_actual_atlas()
	audit_support_shader_source()
	audit_campaign()
	await audit_deferred_and_stop()
	await audit_partial_cancel()
	audit_standalone_and_reuse()
	audit_selector_fail_closed()
	audit_support_fail_closed()
	report.checks = checks
	report.failures = failures
	report.elapsed_usec = Time.get_ticks_usec() - began
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	var file := FileAccess.open("res://tests/output/arena_cave_floor_materials.json", FileAccess.WRITE)
	check(file != null, "Cannot write floor material QA report")
	if file:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	print("ARENA_CAVE_FLOOR_MATERIALS: ", JSON.stringify(report))
	quit(1 if failures else 0)
