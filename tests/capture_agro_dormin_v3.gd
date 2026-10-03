extends Node3D
## Import/rig contract and actual runtime actors; all captures use the game renderer.
var failures := 0
var world: Node3D
var camera: Camera3D
var horse: Horse
var dormin: Dormin
var player: PlayerCharacter

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func ticks(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func _ready() -> void:
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	validate_imports()
	if "--validate" in OS.get_cmdline_user_args():
		await validate_fight()
	else:
		await capture_actors()
	print("Agro/Dormin V3: ", failures, " failure(s); 96 GLB imports, units, 3LOD, rig bindings, sigil clearance and unchanged physics")
	get_tree().quit(0 if failures == 0 else 1)

func validate_imports() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/agro_dormin_v3_manifest.json"))
	check(data.items.size() == 32, "Expected fifteen horse and seventeen Dormin bone pieces")
	for item: Dictionary in data.items:
		var previous := 100000
		for lod in 3:
			var packed := load(item.model_paths[lod]) as PackedScene
			check(packed != null, "Missing GLB: " + str(item.model_paths[lod]))
			if not packed:
				continue
			var imported := packed.instantiate()
			var visuals := imported.find_children("*", "MeshInstance3D", true, false)
			check(visuals.size() == 1 and physics_count(imported) == 0, "GLB must contain one render mesh and no physics")
			if visuals.size() != 1:
				imported.free()
				continue
			var mesh: Mesh = visuals[0].mesh
			var count := triangle_count(mesh)
			check(count == int(item.triangle_counts[lod]) and count < previous, "Triangle count/LOD reduction mismatch for " + str(item.model_paths[lod]))
			previous = count
			var aabb := mesh.get_aabb()
			var expected: Dictionary = item.aabb_per_lod[lod]
			var p0 := Vector3(expected.min[0], expected.min[1], expected.min[2])
			var p1 := Vector3(expected.max[0], expected.max[1], expected.max[2])
			check(aabb.position.distance_to(p0) < .001 and aabb.end.distance_to(p1) < .001, "Imported metres/axis/bounds mismatch for " + str(item.model_paths[lod]))
			if item.actor == "dormin" and item.bone in ["head", "spine", "chest"]:
				validate_sigil_clearance(mesh, item.bone)
			imported.free()

func validate_sigil_clearance(mesh: Mesh, bone: String) -> void:
	var crown_max := -INF
	var back_max := -INF
	var chest_max := -INF
	for surface in mesh.get_surface_count():
		var vertices: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for p in vertices:
			if bone == "head" and Vector2(p.x, p.z - .2).length() < .85:
				crown_max = maxf(crown_max, p.y)
			if bone == "spine" and Vector2(p.x, p.y - 1.8).length() < .85:
				back_max = maxf(back_max, p.z)
			if bone == "chest" and Vector2(p.x, p.y + .4).length() < .84:
				chest_max = maxf(chest_max, p.z)
	check(crown_max <= 2.461, "Head art covers the crown sigil: %.4f" % crown_max)
	check(back_max <= 1.221, "Back art covers the spine sigil: %.4f" % back_max)
	check(chest_max <= 1.152, "Neighbouring chest art covers the spine sigil: %.4f" % chest_max)

func triangle_count(mesh: Mesh) -> int:
	var total := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		total += int((indices.size() if not indices.is_empty() else vertices.size()) / 3)
	return total

func physics_count(n: Node) -> int:
	var count := 1 if n is CollisionObject3D or n is CollisionShape3D else 0
	for child in n.get_children():
		count += physics_count(child)
	return count

func scene_world() -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(37, 3, -21)
	root.rotation.y = .31
	add_child(root)
	return root

func dress_checked(h: Horse, c: Dormin) -> void:
	var before := physics_count(world)
	var saddle := h.saddle_transform()
	AgroArt.dress(h)
	DorminArt.dress(c)
	AgroArt.dress(h)
	DorminArt.dress(c)
	check(physics_count(world) == before and saddle.is_equal_approx(h.saddle_transform()), "Render adapter changed physics or saddle anchor")
	for bone in AgroArt.BONES:
		var frame := h.get_node("Vis_" + String(bone)) as Node3D
		var art := frame.get_node_or_null("AgroArtV3")
		check(art != null and art.get_child_count() == 3, "Horse art missing or duplicated: " + String(bone))
	for bone in DorminArt.BONES:
		var segment: BodySegment = c._seg_by_bone[bone]
		var art := segment.get_node_or_null("DorminArtV3")
		check(art != null and art.get_child_count() == 3, "Dormin art missing or duplicated: " + String(bone))
	check(c.back_sigil.visible and c.weak_point.visible, "Adapter hid gameplay sigils")

func validate_fight() -> void:
	world = scene_world()
	var refs := DorminArena.build_encounter(world)
	dress_checked(refs.horse, refs.dormin)
	var bot := DorminBot.new()
	world.add_child(bot)
	bot.setup(refs.player, refs.dormin, refs.encounter)
	for i in 60 * 120:
		await ticks(1)
		if refs.dormin.is_defeated():
			break
	check(refs.dormin.is_defeated() and not refs.player.dead and refs.dormin.stats.weak_point_hits >= 5, "V3 rendered Dormin is no longer winnable via PlayerActions")
	print("PASS rendered Dormin three-lock climb and two-sigil victory, living Wander")

func capture_actors() -> void:
	world = scene_world()
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(.15, .18, .18)
	TerrainKit.box(world, Vector3(0, -1, 0), Vector3(180, 2, 180), ground_mat)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.11, .15, .17)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(.38, .44, .46)
	env.environment.ambient_light_energy = .65
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-43, -32, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	world.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-18, 148, 0)
	rim.light_color = Color(.47, .62, .69)
	rim.light_energy = .55
	world.add_child(rim)
	horse = Horse.new()
	world.add_child(horse)
	horse.teleport(world.global_transform * Vector3(5, 0, 1), world.global_rotation.y)
	dormin = Dormin.new()
	dormin.position = Vector3(-9, 0, -11)
	world.add_child(dormin)
	dormin.reset_encounter(dormin.global_transform, true)
	dormin.debug_override = &"frozen"
	# A neutral review pose; the --validate branch runs the full live encounter.
	dormin.set_physics_process(false)
	player = PlayerCharacter.new()
	world.add_child(player)
	player.global_position = horse.global_position + world.global_basis.x * 1.3 + Vector3.UP * .95
	player.spawn_transform = player.global_transform
	dress_checked(horse, dormin)
	camera = Camera3D.new()
	world.add_child(camera)
	camera.current = true
	camera.far = 1000
	await ticks(160)
	for bone in AgroArt.BONES:
		var frame := horse.get_node("Vis_" + String(bone)) as Node3D
		var idx: int = horse._bone[bone]
		var expected := horse.skeleton.global_transform * horse.skeleton.get_bone_global_pose(idx)
		check(frame.global_transform.is_equal_approx(expected), "V3 attachment diverged from animated horse bone " + String(bone))
	camera.fov = 47
	camera.global_position = horse.global_position + world.global_basis * Vector3(3.2, 1.9, -3.4)
	camera.look_at(horse.global_position + Vector3.UP * 1.32)
	await shot("agro_v3_full")
	camera.fov = 35
	camera.global_position = horse.global_position + world.global_basis * Vector3(1.7, 2.2, -3.0)
	camera.look_at((horse.get_node("Vis_head") as Node3D).global_position + world.global_basis * Vector3(0, .05, -.3))
	await shot("agro_v3_face")
	player.actions.press_interact()
	await ticks(110)
	check(player.is_riding(), "Real player could not mount the unchanged V3 saddle")
	player.actions.view_basis = world.global_basis
	player.actions.move = Vector2(0, 1)
	player.actions.press_jump()
	await ticks(40)
	player.actions.press_jump()
	await ticks(120)
	camera.fov = 46
	camera.global_position = horse.global_position + world.global_basis * Vector3(3.8, 2.05, -3.9)
	camera.look_at(horse.global_position + Vector3.UP * 1.6)
	await shot("agro_v3_riding")
	check(horse.get_speed() > 2, "V3 horse failed to animate while being ridden")
	player.actions.clear()
	player.actions.grab_held = true
	await ticks(150)
	dormin.set_physics_process(false)
	dormin.weak_point.set_protected(false)
	dormin.back_sigil.set_protected(false)
	camera.fov = 46
	camera.global_position = world.global_transform * Vector3(10, 10.5, -36)
	camera.look_at(world.global_transform * Vector3(-9, 10, -11))
	await shot("dormin_v3_front")
	camera.fov = 48
	camera.global_position = world.global_transform * Vector3(-23, 13, 11)
	camera.look_at(world.global_transform * Vector3(-9, 10.8, -11))
	await shot("dormin_v3_back")
	camera.fov = 42
	var crown := dormin.weak_point.world_point()
	camera.global_position = crown + world.global_basis * Vector3(5, 5, 4.7)
	camera.look_at(crown - Vector3.UP * .8)
	await shot("dormin_v3_crown")

func shot(name: String) -> void:
	await ticks(2)
	await RenderingServer.frame_post_draw
	var path := PortablePaths.prepare("res://data/captures/" + name + ".png")
	check(get_viewport().get_texture().get_image().save_png(path) == OK, "Failed to save " + name)
	print("CAPTURE ", path)
