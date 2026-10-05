extends Node3D
## Imported-material and actor lifecycle regression contract. Kept outside the frozen 197-test registry.
## Run: godot --headless --fixed-fps 60 res://tests/character_material_finish.tscn
## CPU checks only: no claim about GPU cost, mip appearance or visual quality.
var failures := 0
var checks := 0
var report := {"scope": "CPU imported resources, native attachments, LOD ownership, respawn/despawn and untouched Devil shadow/weak-point contracts", "gpu_fps_measured": false, "traveler_lods": [], "agro_lods": [], "spawn_cycles": 0, "lod_transitions": 0}
var held_meshes := {}
var held_materials := {}
var traveler_mesh_ids := {}
var traveler_scene_ids := {}
var agro_mesh_ids := {}
var agro_skin_mesh_ids := {}
var agro_skin_scenes := {}
var agro_palette_ids := {}
var agro_live_signatures := {}
var deadline := Time.get_ticks_msec() + 120000

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _process(_delta: float) -> void:
	if Time.get_ticks_msec() > deadline:
		push_error("Character material contract timed out or stopped after a runtime error")
		get_tree().quit(1)

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func digest(value: Variant) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(value))
	return hash.finish().hex_encode()

func value_signature(value: Variant) -> Variant:
	if value is Texture2D:
		return [value.get_class(), value.get_instance_id(), value.resource_path, value.get_size()]
	if value is Resource:
		return [value.get_class(), value.get_instance_id(), value.resource_path]
	return value

func material_signature(material: Material) -> String:
	var rows := []
	for property: Dictionary in material.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_STORAGE:
			rows.append([property.name, value_signature(material.get(property.name))])
	return digest(rows)

func mesh_signature(mesh: Mesh) -> String:
	var rows := []
	for surface in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface)
		rows.append([mesh.surface_get_arrays(surface), material.get_instance_id() if material else 0])
	return digest(rows)

func remember_mesh(mesh: Mesh, expected_size: Vector2i, label: String) -> void:
	check(mesh != null and mesh.get_surface_count() > 0, label + " has no material-bearing mesh")
	if mesh == null: return
	var id := mesh.get_instance_id()
	if not held_meshes.has(id): held_meshes[id] = {"resource": mesh, "signature": mesh_signature(mesh)}
	for surface in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface) as StandardMaterial3D
		check(material != null, label + " lost its imported PBR material")
		if material == null: continue
		check(not material.resource_local_to_scene, label + " unexpectedly duplicates materials per instance")
		var material_id := material.get_instance_id()
		if not held_materials.has(material_id): held_materials[material_id] = {"resource": material, "signature": material_signature(material)}
		for slot in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_ROUGHNESS, BaseMaterial3D.TEXTURE_METALLIC, BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION]:
			var texture := material.get_texture(slot)
			if texture != null and expected_size != Vector2i.ZERO:
				check(Vector2i(texture.get_size()) == expected_size, label + " texture resolution changed: " + str(texture.get_size()))

func check_resources(label: String) -> void:
	for record: Dictionary in held_meshes.values():
		check(mesh_signature(record.resource) == record.signature, label + " mutated shared geometry/material binding")
	for record: Dictionary in held_materials.values():
		check(material_signature(record.resource) == record.signature, label + " mutated shared material/texture state")

func render_meshes(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D: result.append(node)
	for child: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false): result.append(child)
	return result

func ids(meshes: Array[MeshInstance3D]) -> Array:
	var result := []
	for node in meshes:
		check(node.material_override == null, "Texture-only actor unexpectedly uses a whole-mesh override")
		for surface in node.mesh.get_surface_count():
			check(node.get_surface_override_material(surface) == null, "Texture-only actor unexpectedly uses a surface override")
		result.append(node.mesh.get_instance_id())
	result.sort()
	return result

func triangles(mesh: Mesh) -> int:
	var total := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		total += int((indices.size() if not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()) / 3)
	return total

func physics_signature(node: Node) -> String:
	var rows := []
	for child: CollisionShape3D in node.find_children("*", "CollisionShape3D", true, false):
		rows.append([child.get_instance_id(), child.get_parent().get_instance_id(), child.transform, child.shape.get_instance_id(), child.shape.get_rid(), child.disabled])
	for body: CollisionObject3D in node.find_children("*", "CollisionObject3D", true, false):
		rows.append([body.get_instance_id(), body.collision_layer, body.collision_mask])
	return digest(rows)

func fixture() -> Node3D:
	var world := Node3D.new()
	world.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(world)
	return world

func audit_imports() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/travelers_v3_manifest.json"))
	for item: Dictionary in manifest.assets:
		if item.id != "traveler": continue
		for record: Dictionary in item.lods:
			var level := int(record.lod)
			var packed := TravelerArt._scene("traveler", level)
			check(packed != null and packed == load("res://" + record.runtime), "Traveler cache is not the imported scene")
			if not packed: continue
			traveler_scene_ids[level] = packed.get_instance_id()
			var imported := packed.instantiate()
			var count := 0
			for mesh in render_meshes(imported):
				remember_mesh(mesh.mesh, Vector2i(1024, 1024), "Traveler LOD%d" % level)
				count += triangles(mesh.mesh)
			traveler_mesh_ids[level] = ids(render_meshes(imported))
			check(count == int(record.triangles), "Traveler LOD%d topology changed" % level)
			check(imported.find_children("*", "CollisionObject3D", true, false).is_empty() and imported.find_children("*", "CollisionShape3D", true, false).is_empty(), "Traveler GLB added collision")
			report.traveler_lods.append({"lod": level, "triangles": count, "meshes": traveler_mesh_ids[level].size()})
			imported.free()
	check(traveler_mesh_ids.size() == 3, "Traveler must expose exactly three verified LODs")
	manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/agro_dormin_v3_manifest.json"))
	for item: Dictionary in manifest.items:
		if item.actor != "agro": continue
		for level in 3:
			var path: String = item.model_paths[level]
			var mesh := AgroArt._mesh(path)
			check(mesh != null, "Agro GLB missing: " + path)
			if mesh == null: continue
			remember_mesh(mesh, Vector2i(256, 256), path)
			agro_mesh_ids[path] = mesh.get_instance_id()
			check(triangles(mesh) == int(item.triangle_counts[level]), "Agro topology changed: " + path)
			var expected: Dictionary = item.aabb_per_lod[level]
			var bounds := mesh.get_aabb()
			check(bounds.position.distance_to(Vector3(expected.min[0], expected.min[1], expected.min[2])) < .001 and bounds.end.distance_to(Vector3(expected.max[0], expected.max[1], expected.max[2])) < .001, "Agro bounds or units changed: " + path)
			report.agro_lods.append({"bone": item.bone, "lod": level, "triangles": triangles(mesh)})
	check(agro_mesh_ids.size() == 45, "All fifteen original Agro bone assets must retain all three LODs")
	# Keep the complete rigid-source immutability audit above. Runtime core now
	# uses three weighted meshes, while four hoof adapters still use those assets.
	var skin_manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/agro_skin_manifest.json"))
	for level in 3:
		var path := "res://models/agro_skin/agro_lod%d.glb" % level
		var packed := load(path) as PackedScene
		check(packed != null, "Agro skin source missing: " + path)
		if packed == null: continue
		agro_skin_scenes[level] = packed
		var imported := packed.instantiate()
		var meshes := render_meshes(imported)
		check(meshes.size() == 1, "Agro skin source must have one weighted mesh per LOD")
		if meshes.size() == 1:
			var mesh := meshes[0].mesh
			remember_mesh(mesh, Vector2i.ZERO, "Agro authored skin LOD%d" % level)
			agro_skin_mesh_ids[level] = mesh.get_instance_id()
			check(meshes[0].skin != null and triangles(mesh) == int(skin_manifest.skin_triangle_counts[level]), "Agro skin topology/binds changed")
			report.agro_lods.append({"bone": "continuous_skin", "lod": level, "triangles": triangles(mesh)})
		imported.free()
	check(agro_skin_mesh_ids.size() == 3, "Agro must expose exactly three verified core skins")
	for name in AgroArt.skin_palette():
		var material := AgroArt.skin_palette()[name] as StandardMaterial3D
		check(material != null and not material.resource_local_to_scene, "Agro palette must use shared PBR resources")
		if material == null: continue
		var id := material.get_instance_id()
		agro_palette_ids[name] = id
		if not held_materials.has(id): held_materials[id] = {"resource": material, "signature": material_signature(material)}
		for slot in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_ROUGHNESS, BaseMaterial3D.TEXTURE_METALLIC, BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION]:
			var texture := material.get_texture(slot)
			if texture != null: check(Vector2i(texture.get_size()) == Vector2i(256, 256), "Agro palette texture resolution changed")
	var points := AgroArt.skin_palette()["agro_black_points"] as StandardMaterial3D
	var hair := AgroArt.skin_palette()["agro_mane_tail_fibres"] as StandardMaterial3D
	check(hair != points and is_equal_approx(hair.roughness, .86) and is_equal_approx(hair.metallic_specular, .22), "Agro hair-only matte palette contract changed")
	for slot in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_ROUGHNESS, BaseMaterial3D.TEXTURE_METALLIC, BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION]:
		check(hair.get_texture(slot) == points.get_texture(slot), "Agro hair clone duplicated or replaced a source texture")

func check_traveler(player: PlayerCharacter, level: int) -> void:
	var art := player.visual.get_node("TravelerArt") as TravelerArt
	check(art.current_lod == level and art._arms.size() == 2 and art._legs.size() == 2, "Traveler adapter lost its LOD/rig")
	var actual := render_meshes(art.model)
	for i in 2:
		check(art._arms[i].get_parent() == player.visual._arms[i] and art._arms[i].transform.is_equal_approx(Transform3D.IDENTITY), "Traveler shoulder ownership/origin changed")
		check(art._grips[i].get_parent() == art._wrists[i] and art._grips[i].position.distance_to(Vector3(0, -.050, -.037)) < .001, "Traveler weapon socket contract changed")
		actual.append_array(render_meshes(art._arms[i]))
	check(ids(actual) == traveler_mesh_ids[level], "Traveler spawned duplicate or missing render resources at LOD%d" % level)
	check(art.find_children("*", "CollisionShape3D", true, false).is_empty(), "Traveler adapter owns a gameplay collider")
	check(TravelerArt._scene("traveler", level).get_instance_id() == traveler_scene_ids[level], "Traveler scene cache was replaced")

func check_agro(horse: Horse, layer: int) -> void:
	var root := horse.skeleton.get_node_or_null("AgroSkin") as Node3D
	check(root != null and root.get_child_count() == 3, "Agro continuous skin missing or duplicated")
	if root == null: return
	check(root.visible and root.transform == Transform3D.IDENTITY, "Agro core root hidden or transformed")
	check(root.find_children("*", "CollisionObject3D", true, false).is_empty() and root.find_children("*", "CollisionShape3D", true, false).is_empty(), "Agro core owns gameplay collision")
	var signature := [root.get_instance_id()]
	for level in 3:
		var node := root.get_node_or_null("LOD%d" % level) as MeshInstance3D
		check(node != null and node.mesh != null and node.skin != null, "Agro core lost weighted LOD%d" % level)
		if node == null or node.mesh == null or node.skin == null: continue
		check(node.mesh.get_instance_id() == agro_skin_mesh_ids[level], "Agro core cloned or replaced imported mesh")
		check(node.visible and node.transform == Transform3D.IDENTITY and node.get_node_or_null(node.skeleton) == horse.skeleton, "Agro core detached from original rig")
		check(node.layers == layer and node.lod_bias == 100.0 and node.visibility_range_begin == AgroArt.RANGES[level] and node.visibility_range_end == AgroArt.RANGES[level + 1], "Agro core layer/LOD contract changed")
		check(node.cast_shadow == (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if level == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF), "Agro core shadow contract changed")
		check(node.material_override == null, "Agro core acquired whole-mesh override")
		for surface in node.mesh.get_surface_count():
			var source := node.mesh.surface_get_material(surface)
			var alias: String = AgroArt.SKIN_MATERIAL_ALIASES.get(source.resource_name, "")
			var active := node.get_surface_override_material(surface)
			check(agro_palette_ids.has(alias) and active != null, "Agro core missing exact runtime palette override")
			if active != null and agro_palette_ids.has(alias):
				check(active.get_instance_id() == agro_palette_ids[alias] and active == AgroArt.skin_palette()[alias] and node.get_active_material(surface) == active, "Agro core duplicated or replaced shared palette material")
		var binds := []
		check(node.skin.get_bind_count() == AgroArt.BONES.size(), "Agro core lost named binds")
		for bind in node.skin.get_bind_count():
			var name := node.skin.get_bind_name(bind)
			check(horse.skeleton.find_bone(name) == node.skin.get_bind_bone(bind), "Agro core bind no longer targets original bone")
			binds.append([name, node.skin.get_bind_bone(bind), node.skin.get_bind_pose(bind)])
		signature.append([node.get_instance_id(), node.mesh.get_instance_id(), node.skin.get_instance_id(), binds])
	var key := horse.get_instance_id()
	if agro_live_signatures.has(key): check(agro_live_signatures[key] == signature, "Agro repeat dress/respawn replaced core nodes, meshes or binds")
	else: agro_live_signatures[key] = signature
	check(AgroArt.skin_palette().size() == agro_palette_ids.size(), "Agro palette cache expanded during lifecycle")
	for bone in AgroArt.BONES:
		var frame := horse.get_node("Vis_" + String(bone)) as Node3D
		check(frame.visible == String(bone).ends_with("hoof"), "Agro native attachment visibility changed")
		if not String(bone).ends_with("hoof"): continue
		var art := frame.get_node_or_null("AgroArtV3")
		check(art != null and art.get_child_count() == 3, "Agro repeated dressing duplicated or lost LODs: " + String(bone))
		if art == null: continue
		for level in 3:
			var node := art.get_node("LOD%d" % level) as MeshInstance3D
			var path := "res://models/agro_v3/%s_lod%d.glb" % [bone, level]
			check(node.mesh.get_instance_id() == agro_mesh_ids[path] and node.mesh == AgroArt._mesh(path), "Agro cloned cached mesh/material: " + path)
			check(node.transform.is_equal_approx(Transform3D.IDENTITY) and node.layers == layer and node.lod_bias == 100.0, "Agro bone-local placement/layer/LOD bias changed")
			check(node.visibility_range_begin == AgroArt.RANGES[level] and node.visibility_range_end == AgroArt.RANGES[level + 1], "Agro LOD ranges changed")
			check(node.cast_shadow == (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if level == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF), "Agro shadow LOD contract changed")
			check(node.material_override == null, "Agro acquired a per-instance material override")
			for surface in node.mesh.get_surface_count():
				check(node.get_surface_override_material(surface) == null, "Agro hoof acquired per-instance surface material")
		check(art.find_children("*", "CollisionShape3D", true, false).is_empty(), "Agro render adapter added collision")

func audit_lifecycle() -> void:
	var scene_cache_count := TravelerArt._scenes.size()
	var mesh_cache_count := AgroArt._meshes.size()
	for cycle in 4:
		var world := fixture()
		var player := PlayerCharacter.new()
		var peer := PlayerCharacter.new()
		var horse := Horse.new()
		var second_horse := Horse.new()
		world.add_child(player)
		world.add_child(peer)
		world.add_child(horse)
		world.add_child(second_horse)
		var art := player.visual.get_node("TravelerArt") as TravelerArt
		var peer_art := peer.visual.get_node("TravelerArt") as TravelerArt
		art.auto_lod = false
		peer_art.auto_lod = false
		var physics := physics_signature(world)
		var actions := player.actions
		var blade := player.visual._blade
		var blade_parent := blade.get_parent()
		var beam := player.visual._beam
		var gear := player.visual.get_node("WeaponArt") as WeaponArt
		var gear_id := gear.get_instance_id()
		var saddle := horse.saddle_transform()
		var shape := player._shape
		for requested in [0, 0, 1, 1, 2, 2, 0, 2, 1, -1, 5, 0]:
			var level := clampi(requested, 0, 2)
			art.set_lod(requested)
			peer_art.set_lod(requested)
			await settle()
			check_traveler(player, level)
			check_traveler(peer, level)
			var model_id := art.model.get_instance_id()
			art.set_lod(requested)
			check(art.model.get_instance_id() == model_id, "Repeated set_lod replaced the current model")
			check(TravelerArt.attach(player.visual, player) == art, "Repeated Traveler attach replaced its adapter")
			check(player.visual.find_children("TravelerModelLOD*", "Node3D", true, false).size() == 1, "Traveler LOD transition leaked obsolete models")
			check(player.actions == actions and player._shape == shape and player.visual._blade == blade and blade.get_parent() == blade_parent and player.visual._beam == beam and gear.get_instance_id() == gear_id, "Traveler LOD replaced native actions, collision or weapon/light attachments")
			check(physics_signature(world) == physics, "Cosmetic LOD changed physics ownership, collision or layer")
			report.lod_transitions += 1
		for layer in [1, 2, 1, 1]:
			AgroArt.dress(horse, layer)
			AgroArt.dress(second_horse, layer)
			check_agro(horse, layer)
			check_agro(second_horse, layer)
			check(horse.saddle_transform().is_equal_approx(saddle) and physics_signature(world) == physics, "Agro dress moved the saddle or changed native collision")
		for repeat in 3:
			player.respawn()
			horse.teleport(Vector3.ZERO, 0.0)
			AgroArt.dress(horse)
			check_traveler(player, 0)
			check_agro(horse, 1)
			check(physics_signature(world) == physics, "Respawn changed collider resources/ownership")
		check(TravelerArt._scenes.size() == scene_cache_count and AgroArt._meshes.size() == mesh_cache_count, "Actor lifecycle expanded an already warm resource cache")
		check_resources("spawn cycle %d" % cycle)
		var stale_model: WeakRef = weakref(art.model)
		var stale_arm: WeakRef = weakref(art._arms[0])
		var stale_agro: Array[WeakRef] = []
		for actor in [horse, second_horse]:
			stale_agro.append(weakref(actor.skeleton.get_node("AgroSkin")))
			for mesh in render_meshes(actor.skeleton.get_node("AgroSkin")): stale_agro.append(weakref(mesh))
			for bone in AgroArt.BONES:
				if String(bone).ends_with("hoof"):
					for mesh in render_meshes(actor.get_node("Vis_%s/AgroArtV3" % bone)): stale_agro.append(weakref(mesh))
		world.queue_free()
		await settle()
		check(stale_model.get_ref() == null and stale_arm.get_ref() == null, "Despawn leaked a model or externally parented arm")
		for stale in stale_agro: check(stale.get_ref() == null, "Agro despawn leaked a core/hoof render node")
		agro_live_signatures.clear()
		check_resources("despawn cycle %d" % cycle)
		report.spawn_cycles += 1

func audit_devil() -> void:
	var world := fixture()
	var devil := Devil.new()
	world.add_child(devil)
	await settle()
	var before := physics_signature(devil)
	var weak_point := devil.weak_point
	var sigil_parent := weak_point.get_parent()
	var sigil_mesh := weak_point._mesh
	GuardianVisuals.dress(devil, "devil")
	var cache_count := GuardianVisuals._meshes.size()
	var original_nodes := devil.find_children("*", "Node", true, false).size()
	var ownership := []
	for bone in [&"body", &"wing_l", &"wing_r"]:
		var segment: BodySegment = devil._seg_by_bone[bone]
		var art := segment.get_node("GuardianArt")
		check(art.get_child_count() == 3 and art.find_children("*", "CollisionShape3D", true, false).is_empty(), "Devil render-only LOD contract changed")
		for level in 3:
			var mesh := art.get_node("LOD%d" % level) as MeshInstance3D
			ownership.append([mesh.get_instance_id(), mesh.mesh.get_instance_id()])
			check(mesh.layers == 2 and mesh.cast_shadow == (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if level == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF), "Devil cave layer/shadow casting changed")
			remember_mesh(mesh.mesh, Vector2i.ZERO, "untouched Devil")
			if bone != &"body":
				for surface in mesh.mesh.get_surface_count():
					var material := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
					check(material.disable_receive_shadows, "Devil wing self-shadow protection was lost")
	for repeat in 4:
		GuardianVisuals.dress(devil, "devil")
		devil.reset_encounter()
		await settle()
		check(physics_signature(devil) == before, "Untouched Devil dress/reset changed colliders")
		check(devil.weak_point == weak_point and weak_point.get_parent() == sigil_parent and weak_point._mesh == sigil_mesh and weak_point.health == 120 and weak_point.state == WeakPoint.State.PROTECTED and not devil._patch_open and devil._grip_patch.disabled, "Devil weak-point/climb lock/reset invariant changed")
		check(devil.phase == Devil.Phase.HANGING and devil.find_children("*", "Node", true, false).size() == original_nodes and GuardianVisuals._meshes.size() == cache_count, "Devil reset leaked nodes/resources or failed to restore hanging state")
		var actual := []
		for bone in [&"body", &"wing_l", &"wing_r"]:
			for level in 3:
				var mesh := devil._seg_by_bone[bone].get_node("GuardianArt/LOD%d" % level) as MeshInstance3D
				actual.append([mesh.get_instance_id(), mesh.mesh.get_instance_id()])
		check(actual == ownership, "Devil reset/dress replaced cached meshes")
		check_resources("untouched Devil reset")
	world.queue_free()
	await settle()
	report["devil_lods_checked"] = 9
	report["devil_resets"] = 4

func _ready() -> void:
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	audit_imports()
	await audit_lifecycle()
	await audit_devil()
	report["failures"] = failures
	report["checks"] = checks
	report["held_meshes"] = held_meshes.size()
	report["held_materials"] = held_materials.size()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	var file := FileAccess.open("res://tests/output/character_material_finish.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("CHARACTER_MATERIAL_FINISH: %d failures; %d checks; 3 Traveler LODs, 45 original Agro assets + 3 active core skins/12 hoof LODs, 4 paired actor spawn/despawns, 48 LOD transitions, 12 respawns, 9 Devil LODs/4 resets" % [failures, checks])
	get_tree().quit(1 if failures else 0)
