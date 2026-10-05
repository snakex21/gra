extends SceneTree
## Headless contract test; never edits production poses or source assets.
func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	if not condition:
		push_error(label)
		quit(1)
		assert(condition, label)

func same_mechanics(skinned: Horse, rigid: Horse) -> void:
	check(skinned.global_transform == rigid.global_transform, "Visual adapter preserves horse transform exactly")
	check(skinned.saddle_transform() == rigid.saddle_transform(), "Visual adapter preserves saddle exactly")
	for i in skinned.skeleton.get_bone_count():
		check(skinned.skeleton.get_bone_global_pose(i) == rigid.skeleton.get_bone_global_pose(i), "Visual adapter preserves every bone exactly")
	for i in 4:
		check(skinned.sole_world(i) == rigid.sole_world(i), "Visual adapter preserves all sole positions exactly")

func compare_mechanics(skinned: Horse) -> void:
	var rigid := Horse.new()
	root.add_child(rigid)
	rigid.set_physics_process(false)
	# Established rigid baseline visuals, same unmodified production Horse class.
	var core := rigid.skeleton.get_node("AgroSkin")
	core.free()
	for bone in AgroArt.BONES:
		rigid.get_node("Vis_" + String(bone)).show()
		AgroArt.dress_bone(rigid, bone)
	var dt := 1.0 / 120.0
	for gait in 4:
		for h in [skinned, rigid]:
			h.controller.gait = gait
			h.controller.gait_level = gait
			h.controller.speed = HorseController.GAIT_SPEED[gait]
		for tick in 240:
			for h in [skinned, rigid]:
				# Prescribed turn extremes are evidence inputs, not gameplay changes.
				h.controller.yaw_rate = 0.6 if tick < 120 else -0.6
				h.controller.yaw += h.controller.yaw_rate * dt
				h.controller.steer_dir = h.controller.forward().rotated(Vector3.UP, 1.0 if tick < 120 else -1.0)
				h.controller.position += h.controller.forward() * h.controller.speed * dt
				h.global_transform = Transform3D(h.controller.body_basis(), h.controller.position)
				h.gait_planner.update(h.controller, dt, h.get_world_3d().direct_space_state)
				h._pose(dt)
			same_mechanics(skinned, rigid)
	# Synthetic sloped contacts exercise production pitch/roll without editing bones.
	for h in [skinned, rigid]:
		for i in 4:
			h.gait_planner.legs[i].foot_pos.y += [0.12, 0.04, -0.06, -0.1][i]
	for tick in 120:
		for h in [skinned, rigid]: h._pose(dt)
		same_mechanics(skinned, rigid)
	for h in [skinned, rigid]: h.teleport(Vector3(3, 0, -2), 0.8)
	same_mechanics(skinned, rigid)
	rigid.free()
	print("AGRO_SKIN_MECHANICS_PARITY_OK exact_bones_soles_saddle 960_gait_turn_ticks 120_slope_ticks teleport")

func run() -> void:
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	var horse := Horse.new()
	root.add_child(horse)
	horse.set_physics_process(false)
	var art := horse.skeleton.get_node_or_null("AgroSkin")
	check(art != null, "Prototype skin must be active")
	check(art.get_child_count() == 3, "All three authored LODs must be present")
	var visual := art.get_child(0) as MeshInstance3D
	check(visual.get_node(visual.skeleton) == horse.skeleton, "Skin uses original production skeleton")
	check(visual.transform == Transform3D.IDENTITY and art.transform == Transform3D.IDENTITY, "No double transform")
	for bone in AgroArt.BONES:
		var frame := horse.get_node("Vis_" + String(bone)) as Node3D
		check(frame.visible == String(bone).ends_with("hoof"), "Only core legacy frames are hidden")
	var palette := AgroArt.skin_palette()
	for lod in 3:
		var layer := art.get_child(lod) as MeshInstance3D
		check(layer.visibility_range_begin == AgroArt.RANGES[lod] and layer.visibility_range_end == AgroArt.RANGES[lod+1], "Exact existing LOD ranges")
		for surface in layer.mesh.get_surface_count():
			var authored := layer.mesh.surface_get_material(surface)
			var active := layer.get_active_material(surface)
			check(active == palette[AgroArt.SKIN_MATERIAL_ALIASES[authored.resource_name]], "Read-only palette shared across LODs")
			var arrays := layer.mesh.surface_get_arrays(surface)
			check(arrays[Mesh.ARRAY_TEX_UV].size() > 0 and arrays[Mesh.ARRAY_TANGENT].size() > 0, "Normal-map UV/tangent arrays loaded")
	var points := palette["agro_black_points"] as StandardMaterial3D
	var fibres := palette["agro_mane_tail_fibres"] as StandardMaterial3D
	check(is_equal_approx(points.roughness,0.72) and is_equal_approx(points.metallic_specular,0.5), "Original black-points material unchanged")
	check(is_equal_approx(fibres.roughness,0.86) and is_equal_approx(fibres.metallic_specular,0.22), "Hair-only matte finish")
	check(fibres.albedo_texture == points.albedo_texture and fibres.normal_texture == points.normal_texture, "Hair shares original texture resources exactly")
	var before := horse.saddle_transform()
	AgroArt.dress(horse, 3)
	check((horse.get_node("AgroReins") as AgroReins).straps.layers == 3, "Reins follow requested render layers")
	check(art.get_child(0) == visual, "Repeated dressing is idempotent")
	check(visual.layers == 3, "Repeated dressing updates layers")
	check(horse.saddle_transform().is_equal_approx(before), "Dressing preserves saddle transform")
	var max_rest_error := 0.0
	var weighted_vertices := 0
	for surface in visual.mesh.get_surface_count():
		var arrays := visual.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var weights = arrays[Mesh.ARRAY_WEIGHTS]
		var bones = arrays[Mesh.ARRAY_BONES]
		var count: int = weights.size() / vertices.size()
		for vertex in vertices.size():
			var rest := Vector3.ZERO
			var nonzero := 0
			for influence in count:
				var offset: int = vertex * count + influence
				var bind: int = bones[offset]
				var index := horse.skeleton.find_bone(visual.skin.get_bind_name(bind))
				check(index >= 0, "Bind is name-resolved")
				var reference: Transform3D = AgroArt.bind_reference()[visual.skin.get_bind_name(bind)]
				var matrix := reference * visual.skin.get_bind_pose(bind)
				rest += (matrix * vertices[vertex]) * weights[offset]
				if weights[offset] > 0.00001: nonzero += 1
			if nonzero > 1: weighted_vertices += 1
			max_rest_error = maxf(max_rest_error, rest.distance_to(vertices[vertex]))
	check(max_rest_error < 0.002, "Fixed neutral-bind weighted mesh must be identity within weight quantization")
	check(weighted_vertices > 0, "Prototype has genuinely blended vertices")
	var scene := (load("res://models/agro_skin/agro_lod0.glb") as PackedScene).instantiate()
	var source := scene.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var source_rig := source.get_node(source.skeleton) as Skeleton3D
	var original_skin := source.skin
	source.skin = source.skin.duplicate()
	source.skin.set_bind_name(0, &"INVALID_BIND_SENTINEL")
	check(AgroArt._mapped_skin(source, source_rig, horse.skeleton) == null, "Malformed name fails closed")
	source.skin = original_skin.duplicate()
	source.skin.set_bind_pose(0, Transform3D(Basis.IDENTITY, Vector3(99,99,99)))
	check(AgroArt._mapped_skin(source, source_rig, horse.skeleton) == null, "Incorrect inverse bind fails closed")
	source.skin = original_skin
	source.scale = Vector3(2,2,2)
	check(AgroArt._mapped_skin(source, source_rig, horse.skeleton) == null, "Unexpected mesh scale fails closed")
	# Corrupt only the process-local cached imported resource, then immediately restore.
	# This exercises dress() fallback end-to-end without changing any asset file.
	var saved_name := original_skin.get_bind_name(0)
	original_skin.set_bind_name(0, &"INVALID_FALLBACK_SENTINEL")
	var fallback := Horse.new()
	root.add_child(fallback)
	fallback.set_physics_process(false)
	original_skin.set_bind_name(0, saved_name)
	check(not fallback.skeleton.has_node("AgroSkin"), "Invalid skin creates no incomplete replacement")
	for bone in AgroArt.BONES:
		var frame := fallback.get_node("Vis_" + String(bone)) as Node3D
		check(frame.visible, "Fallback keeps legacy attachment visible")
		check(frame.has_node("AgroArtV3"), "Fallback retains rigid production art")
	fallback.free()
	scene.free()
	print("AGRO_SKIN_CONTRACT_OK neutral_bind_max_error=", max_rest_error, " blended_vertices=", weighted_vertices, " bind_count=", visual.skin.get_bind_count())
	compare_mechanics(horse)
	horse.free()
	quit(0)
