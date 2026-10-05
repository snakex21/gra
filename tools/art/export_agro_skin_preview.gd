extends SceneTree
## CPU evidence from actual loaded production Horse meshes and Skin binds.
## godot --headless --path . --script tools/art/export_agro_skin_preview.gd -- OUT
## Pose-only snapshots: fixed speed body path + production gait planner and _pose;
## not a live controller, GPU render, animation clip, or movement-quality benchmark.
var output: String
var world: Node3D
var grey: StandardMaterial3D
var records: Array = []
var allow_rigid_baseline := false
var mode_failed := false
var keep_materials := false
var include_rider := false
var selected_lod := 0
var extra_sources := {}
var export_materials := {}

func _initialize() -> void:
	call_deferred("run")

func vec(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func xf(t: Transform3D) -> Array:
	return [vec(t.basis.x), vec(t.basis.y), vec(t.basis.z), vec(t.origin)]

func digest(value: Variant) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(value))
	return hash.finish().hex_encode()

func track(path: String) -> void:
	path = path.get_slice("::", 0)
	if path.begins_with("res://") and FileAccess.file_exists(path):
		extra_sources[path.trim_prefix("res://")] = FileAccess.get_sha256(path)

func export_material(material: Material) -> Material:
	var key := material.get_instance_id()
	if not export_materials.has(key):
		var private_copy := material.duplicate() as Material
		private_copy.resource_name = "%s__e%03d" % [material.resource_name, export_materials.size()]
		export_materials[key] = private_copy
	return export_materials[key]

func material_info(mat: Material) -> Dictionary:
	assert(mat is StandardMaterial3D, "Expected production StandardMaterial3D")
	var m := mat as StandardMaterial3D
	track(m.resource_path)
	var result := {"name": m.resource_name, "export_name": export_material(m).resource_name, "source": m.resource_path, "albedo": [m.albedo_color.r,m.albedo_color.g,m.albedo_color.b,m.albedo_color.a], "metallic_specular": m.metallic_specular, "roughness": m.roughness, "metallic": m.metallic, "normal_enabled": m.normal_enabled, "normal_scale": m.normal_scale, "cull_mode": m.cull_mode, "transparency": m.transparency, "textures": {}}
	for channel in [BaseMaterial3D.TEXTURE_ALBEDO,BaseMaterial3D.TEXTURE_NORMAL,BaseMaterial3D.TEXTURE_ROUGHNESS,BaseMaterial3D.TEXTURE_METALLIC]:
		var texture := m.get_texture(channel)
		if texture:
			track(texture.resource_path)
			var image := texture.get_image()
			assert(image != null and not image.is_empty(), "Texture pixels unavailable")
			result.textures[str(channel)] = {"source": texture.resource_path, "width": image.get_width(), "height": image.get_height(), "format": image.get_format(), "pixels_sha256": digest(image.get_data())}
	return result

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func baked_mesh(original: MeshInstance3D, skeleton: Skeleton3D) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var matrices: Array[Transform3D] = []
	var binds: Array = []
	for i in original.skin.get_bind_count():
		var name := original.skin.get_bind_name(i)
		var index := skeleton.find_bone(name)
		assert(index >= 0, "Unmapped skin bind")
		var reference_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/agro_skin_neutral_reference.json"))
		var columns: Array = reference_data.global_pose[String(name)]
		var v: Array[Vector3] = []
		for column in columns: v.append(Vector3(column[0], column[1], column[2]))
		var reference := Transform3D(Basis(v[0], v[1], v[2]), v[3])
		assert((reference * original.skin.get_bind_pose(i)).is_equal_approx(Transform3D.IDENTITY), "Fixed neutral bind must be identity")
		matrices.append(skeleton.get_bone_global_pose(index) * original.skin.get_bind_pose(i))
		binds.append({"bind": i, "bone": str(name), "target_index": index, "inverse_bind": xf(original.skin.get_bind_pose(i)), "global_pose": xf(skeleton.get_bone_global_pose(index)), "fixed_reference_global_pose": xf(reference), "deform": xf(matrices[i])})
	var surfaces: Array = []
	for surface in original.mesh.get_surface_count():
		var arrays := original.mesh.surface_get_arrays(surface).duplicate(true)
		var source_digest := digest(arrays)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var tangents = arrays[Mesh.ARRAY_TANGENT]
		var joints = arrays[Mesh.ARRAY_BONES]
		var weights = arrays[Mesh.ARRAY_WEIGHTS]
		var count: int = weights.size() / vertices.size()
		for vertex in vertices.size():
			var position := Vector3.ZERO
			var normal := Vector3.ZERO
			var tangent := Vector3.ZERO
			var input_tangent := Vector3.ZERO
			if tangents != null and tangents.size() > 0:
				input_tangent = Vector3(tangents[vertex * 4], tangents[vertex * 4 + 1], tangents[vertex * 4 + 2])
			for influence in count:
				var offset: int = vertex * count + influence
				var weight: float = weights[offset]
				if weight == 0.0: continue
				var matrix: Transform3D = matrices[joints[offset]]
				position += (matrix * vertices[vertex]) * weight
				if not normals.is_empty(): normal += (matrix.basis * normals[vertex]) * weight
				tangent += (matrix.basis * input_tangent) * weight
			vertices[vertex] = position
			if not normals.is_empty(): normals[vertex] = normal.normalized()
			if tangents != null and tangents.size() > 0:
				tangent = tangent.normalized()
				tangents[vertex * 4] = tangent.x
				tangents[vertex * 4 + 1] = tangent.y
				tangents[vertex * 4 + 2] = tangent.z
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TANGENT] = tangents
		arrays[Mesh.ARRAY_BONES] = null
		arrays[Mesh.ARRAY_WEIGHTS] = null
		mesh.add_surface_from_arrays(original.mesh.surface_get_primitive_type(surface), arrays)
		mesh.surface_set_material(surface, export_material(original.get_active_material(surface)) if keep_materials else grey)
		surfaces.append({"vertices": vertices.size(), "source_arrays_sha256": source_digest, "baked_arrays_sha256": digest(arrays), "material": material_info(original.get_active_material(surface))})
	records.append({"source_mesh": original.mesh.resource_path, "source_transform": xf(original.global_transform), "binds": binds, "surfaces": surfaces})
	return mesh

func flatten(node: Node, target: Node3D, horse: Horse) -> void:
	if node is Node3D and not node.is_visible_in_tree(): return
	if node is MeshInstance3D:
		var original := node as MeshInstance3D
		if original.mesh == null: return
		if String(original.name).begins_with("LOD") and original.name != StringName("LOD%d" % selected_lod): return
		var clone := MeshInstance3D.new()
		clone.name = "Mesh_%03d" % target.get_child_count()
		if original.skin:
			assert(original.get_node(original.skeleton) == horse.skeleton)
			clone.mesh = baked_mesh(original, horse.skeleton)
			clone.transform = horse.global_transform.affine_inverse() * horse.skeleton.global_transform
		else:
			clone.mesh = original.mesh
			clone.transform = horse.global_transform.affine_inverse() * original.global_transform
			records.append({"rigid_source_mesh": original.mesh.resource_path, "source_transform": xf(original.global_transform), "export_transform": xf(clone.transform)})
		if not keep_materials:
			clone.material_override = grey
		elif not original.skin:
			var surfaces := []
			for surface in original.mesh.get_surface_count():
				var material := original.get_active_material(surface)
				clone.set_surface_override_material(surface, export_material(material))
				surfaces.append({"material": material_info(material)})
			records[-1]["surfaces"] = surfaces
		target.add_child(clone)
		clone.owner = target
	for child in node.get_children(): flatten(child, target, horse)

func snapshot(horse: Horse, gait: int, phase: float, ticks: int, label := "") -> void:
	var target := Node3D.new()
	target.name = "AgroProductionPose"
	root.add_child(target)
	records = []
	extra_sources = {}
	export_materials = {}
	if horse.has_node("AgroReins"): horse.get_node("AgroReins").update_reins(1.0)
	flatten(horse, target, horse)
	var player: PlayerCharacter
	if include_rider:
		player = PlayerCharacter.new()
		world.add_child(player)
		freeze(player)
		player.riding.mount_now(horse)
		var traveler := player.visual.get_node("TravelerArt") as TravelerArt
		traveler.auto_lod = false
		traveler.set_lod(selected_lod)
		traveler.pose_preview(&"ride", 0.7)
		var equipment := player.visual.get_node("WeaponArt") as WeaponArt
		equipment.auto_lod = false
		equipment.set_lod(selected_lod)
		equipment.update_equipment(0.0)
		flatten(player.visual, target, horse)
	assert(target.get_child_count() > 0)
	var id := "agro_skin_%s_phase%03d" % [HorseController.GAIT_NAMES[gait].to_lower(), roundi(phase * 100)]
	if label != "": id = "agro_skin_" + label
	if include_rider: id += "_rider"
	if selected_lod > 0: id += "_lod%d" % selected_lod
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	assert(doc.append_from_scene(target, state) == OK)
	assert(doc.write_to_filesystem(state, output.path_join(id + ".glb")) == OK)
	var hashes := {}
	for path in ["src/horse/horse.gd", "src/horse/agro_art.gd", "src/horse/quadruped_gait.gd", "src/horse/horse_controller.gd", "src/locomotion/two_bone_ik.gd", "models/agro_skin/agro_lod0.glb", "assets/agro_skin_neutral_reference.json", "tools/art/export_agro_skin_preview.gd"]:
		if FileAccess.file_exists("res://" + path): hashes[path] = FileAccess.get_sha256("res://" + path)
	hashes.merge(extra_sources)
	var bone_poses := {}
	for index in horse.skeleton.get_bone_count():
		bone_poses[str(horse.skeleton.get_bone_name(index))] = xf(horse.skeleton.get_bone_global_pose(index))
	var feet := []
	for i in 4: feet.append({"sole_world": vec(horse.sole_world(i)), "planned_world": vec(horse.gait_planner.legs[i].foot_pos), "phase": horse.gait_planner.legs[i].phase})
	var file := FileAccess.open(output.path_join(id + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"id": id, "project": ProjectSettings.globalize_path("res://"), "fixed_dt": 1.0 / 120.0, "ticks": ticks, "requested_phase": phase, "actual_phase": horse.gait_planner.clock, "speed": horse.controller.speed, "gait": gait, "source_sha256s": hashes, "exporter_sha256": FileAccess.get_sha256(get_script().resource_path), "meshes": records, "feet": feet, "horse_transform": xf(horse.global_transform), "saddle_transform": xf(horse.saddle_transform()), "bone_global_poses": bone_poses, "skin_active": horse.skeleton.has_node("AgroSkin"), "explicit_rigid_baseline_mode": allow_rigid_baseline, "material_mode": "production" if keep_materials else "neutral_grey", "rider_mounted": player.is_riding() if player else false, "lod": selected_lod, "prescribed_pose_label": label, "note": "Material mode recorded explicitly; neutral override only in neutral_grey mode. Optional labeled steering uses prescribed yaw rate +/-0.6 radians/sec; slope uses explicitly synthetic contact elevation inputs. Exact loaded production mesh skin baked with named bind mapping: bone global pose multiplied by inverse bind; normalized blended normals and tangents, original tangent handedness. Fixed recorded neutral-bind deformation asserted identity; canonical production skeleton rests remain unchanged. Rigid hooves preserve production transforms. Translation recentered to horse root for matched cameras. Fixed prescribed controller speeds/body trajectory with actual QuadrupedGait.update and Horse._pose, not live controller movement or GPU validation."}, "\t"))
	file.close()
	print("AGRO_SKIN_EXPORT_OK ", id)
	target.free()
	if player: player.free()

func capture(gait: int) -> void:
	var horse := Horse.new()
	world.add_child(horse)
	freeze(horse)
	if not validate_mode(horse):
		horse.free()
		return
	var dt := 1.0 / 120.0
	for frame in 360: horse._pose(dt)
	if gait == 0:
		snapshot(horse, gait, 0.0, 360)
		horse.free()
		return
	horse.controller.gait = gait
	horse.controller.gait_level = gait
	horse.controller.speed = HorseController.GAIT_SPEED[gait]
	horse._prev_speed = horse.controller.speed
	var targets := [0.0, 0.25, 0.5, 0.75]
	var captured := 0
	var ticks := 0
	while captured < targets.size() and ticks < 2400:
		var previous := horse.gait_planner.clock
		horse.controller.position += horse.controller.forward() * horse.controller.speed * dt
		horse.global_transform = Transform3D(horse.controller.body_basis(), horse.controller.position)
		horse.gait_planner.update(horse.controller, dt, world.get_world_3d().direct_space_state)
		horse._pose(dt)
		ticks += 1
		if ticks < 360: continue
		var current := horse.gait_planner.clock
		var phase: float = targets[captured]
		if (phase == 0.0 and current < previous) or (phase > 0.0 and previous < phase and current >= phase):
			snapshot(horse, gait, phase, ticks)
			captured += 1
	assert(captured == targets.size())
	horse.free()

func validate_mode(horse: Horse) -> bool:
	var active := horse.skeleton.has_node("AgroSkin")
	if active == allow_rigid_baseline:
		mode_failed = true
		push_error("Explicit rigid baseline unexpectedly contains skin" if active else "Skin prototype did not load; refusing mislabeled rigid evidence")
		return false
	return true

func capture_extreme(label: String, turn: float, slope: bool) -> void:
	var horse := Horse.new()
	world.add_child(horse)
	freeze(horse)
	if not validate_mode(horse):
		horse.free()
		return
	var dt := 1.0 / 120.0
	for tick in 360: horse._pose(dt)
	if slope:
		# Fixed synthetic contact elevations test production body pitch and roll.
		for i in 4: horse.gait_planner.legs[i].foot_pos.y += [0.12, 0.04, -0.06, -0.10][i]
		for tick in 120: horse._pose(dt)
	else:
		horse.controller.gait = HorseController.Gait.TROT
		horse.controller.gait_level = HorseController.Gait.TROT
		horse.controller.speed = HorseController.GAIT_SPEED[HorseController.Gait.TROT]
		horse._prev_speed = horse.controller.speed
		for tick in 480:
			horse.controller.yaw_rate = turn
			horse.controller.yaw += turn * dt
			horse.controller.steer_dir = horse.controller.forward().rotated(Vector3.UP, signf(turn))
			horse.controller.position += horse.controller.forward() * horse.controller.speed * dt
			horse.global_transform = Transform3D(horse.controller.body_basis(), horse.controller.position)
			horse.gait_planner.update(horse.controller, dt, world.get_world_3d().direct_space_state)
			horse._pose(dt)
	snapshot(horse, horse.controller.gait, horse.gait_planner.clock, 480 if slope else 840, label)
	horse.free()

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Expected OUT [--allow-rigid-baseline] [--materials] [--lod=0|1|2]")
		quit(2)
		return
	output = args[0]
	for arg in args.slice(1):
		if arg == "--allow-rigid-baseline": allow_rigid_baseline = true
		elif arg == "--materials": keep_materials = true
		elif arg == "--rider": include_rider = true
		elif arg.begins_with("--lod=") and arg.trim_prefix("--lod=") in ["0", "1", "2"]: selected_lod = int(arg.trim_prefix("--lod="))
		else:
			push_error("Unknown export option: " + arg)
			quit(2)
			return
	DirAccess.make_dir_recursive_absolute(output)
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	grey = StandardMaterial3D.new()
	grey.resource_name = "Neutral grey shape evidence"
	grey.albedo_color = Color(0.42, 0.42, 0.42)
	grey.roughness = 0.8
	world = Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	ground.collision_layer = Layers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1000, 0.2, 1000)
	shape.shape = box
	shape.position.y = -0.1
	ground.add_child(shape)
	world.add_child(ground)
	await physics_frame
	await physics_frame
	if include_rider:
		capture(0)
	else:
		for gait in 4: capture(gait)
		capture_extreme("steer_left_060", 0.6, false)
		capture_extreme("steer_right_060", -0.6, false)
		capture_extreme("slope_pitch_roll", 0.0, true)
	world.free()
	quit(2 if mode_failed else 0)
