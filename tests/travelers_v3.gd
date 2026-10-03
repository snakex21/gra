extends Node3D
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func ticks(n: int) -> void:
	for i in n: await get_tree().physics_frame
func _ready() -> void:
	InputSetup.ensure_defaults()
	Sfx.enabled = false
	Fx.enabled = false
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/travelers_v3_manifest.json"))
	for record in manifest.assets:
		for lod in record.lods:
			var packed := load("res://" + lod.runtime) as PackedScene
			check(packed != null, "Traveler/Mono GLB import failed: " + lod.runtime)
			if not packed: continue
			var instance := packed.instantiate() as Node3D
			add_child(instance)
			var metric := measure(instance)
			check(metric.triangles == lod.triangles and metric.collisions == 0 and metric.materials > 0, "Traveler/Mono import changed topology/materials or added colliders: %s %s" % [lod.runtime, metric])
			if record.id == "traveler":
				var a0 := instance.find_child("Arm_0*", true, false) as Node3D
				var a1 := instance.find_child("Arm_1*", true, false) as Node3D
				check(a0 != null and a1 != null, "Traveler shoulder joints missing at LOD%d" % lod.lod)
				if a0 and a1:
					check(a0.global_position.distance_to(Vector3(-.3,.4,0)) < .001 and a1.global_position.distance_to(Vector3(.3,.4,0)) < .001, "Traveler arm origin no longer matches PlayerVisual")
				for i in 2:
					var wrist := instance.find_child("Wrist_%d*" % i, true, false) as Node3D
					var grip := instance.find_child("HandGrip_%d*" % i, true, false) as Node3D
					var hand := instance.find_child("Traveler_Hand_%d*" % i, true, false) as MeshInstance3D
					check(wrist != null and grip != null and hand != null, "Traveler wrist, grip or independent hand missing at LOD%d" % lod.lod)
					if wrist and grip and hand:
						check(wrist.position.distance_to(Vector3(0,-.276,0)) < .001 and grip.get_parent() == wrist and hand.get_parent() == wrist and grip.position.distance_to(Vector3(0,-.050,-.037)) < .001, "Traveler wrist/grip contract changed at LOD%d" % lod.lod)
						check(grip.global_position.distance_to(Vector3(-.3 if i == 0 else .3, -.211, -.037)) < .001 and grip.basis.is_equal_approx(Basis.IDENTITY), "Traveler weapon socket no longer matches its metre-scale pose")
			instance.free()
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(.16,.19,.20)
	TerrainKit.box(self, Vector3(0,-.06,0), Vector3(10,.1,10), floor_mat)
	var p := PlayerCharacter.new()
	p.name = "TravelerAdapterTest"
	add_child(p)
	p.global_position = Vector3(0,.9,0)
	p.spawn_transform = p.global_transform
	var original_shape_count: int = measure(p).collisions
	var blade_parent := p.visual._blade.get_parent()
	var original_actions := p.actions
	var art := TravelerArt.attach(p.visual, p)
	art.auto_lod = false
	await ticks(3)
	for level in 3:
		art.set_lod(level)
		await ticks(2)
		check(art.current_lod == level and art._arms.size() == 2 and art._legs.size() == 2, "Traveler rigid hierarchy/LOD adapter failed")
		for i in 2:
			check(art._arms[i].get_parent() == p.visual._arms[i] and art._arms[i].transform.is_equal_approx(Transform3D.IDENTITY), "Traveler arm reparent changed joint origin")
	check(measure(p).collisions == original_shape_count and p.actions == original_actions and p.visual._blade.get_parent() == blade_parent, "Traveler adapter modified gameplay collider/actions or sword attachment")
	art.set_lod(0)
	p.actions.view_basis = Basis.IDENTITY
	p.actions.move = Vector2(0,1)
	await ticks(60)
	check(p.global_position.z < -3.5 and p.state == PlayerCharacter.State.GROUND, "Traveler render adapter interfered with action-driven walking")
	p.actions.clear()
	p.set_physics_process(false)
	art.set_process(false)
	var gear := p.visual.get_node_or_null("WeaponArt") as Node3D
	if gear:
		gear.set_process(false)
		gear.visible = false
	var fixed_position := p.global_position
	art.pose_preview(&"ride", .4)
	check(art._legs[0].rotation.x > 1.0 and art._knees[0].rotation.x < -1.0, "Traveler riding pose does not bend legs around saddle")
	art.pose_preview(&"climb", .4)
	check(p.visual._arms[0].rotation.x > 2.9 and absf(art._forearms[0].rotation.x) < .1, "Traveler climbing hands do not follow existing raised pivots")
	check(p.global_position == fixed_position and p.actions == original_actions, "Traveler pose preview changed gameplay state")
	if DisplayServer.get_name() != "headless":
		p.global_position = Vector3(-.65,.895,0)
		p.visual.transform = Transform3D.IDENTITY
		art.pose_preview(&"idle")
		setup_studio()
		TravelerArt.create_mono(self, Vector3(.55,.62,0))
		var cam := Camera3D.new()
		add_child(cam)
		cam.fov = 40
		cam.global_position = Vector3(2.7,2.25,-4.4)
		cam.look_at(Vector3(.02,.91,0))
		cam.current = true
		for i in 5: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := ProjectSettings.globalize_path("res://data/captures/travelers_v3_godot.png")
		var err := get_viewport().get_texture().get_image().save_png(path)
		check(err == OK, "Travelers runtime capture save failed")
		print("Saved ", path)
		cam.global_position = Vector3(-.10,1.82,-1.35)
		cam.look_at(Vector3(-.65,1.65,0))
		cam.fov = 32
		for i in 3: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		path = ProjectSettings.globalize_path("res://data/captures/traveler_v3_face.png")
		get_viewport().get_texture().get_image().save_png(path)
		print("Saved ", path)
		cam.global_position = Vector3(.35,1.69,-.12)
		cam.look_at(Vector3(-.65,1.66,0))
		cam.fov = 28
		for i in 3: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		path = ProjectSettings.globalize_path("res://data/captures/traveler_v3_profile.png")
		check(get_viewport().get_texture().get_image().save_png(path) == OK, "Traveler profile capture save failed")
		print("Saved ", path)
		cam.global_position = Vector3(.25,.82,-.55)
		cam.look_at(Vector3(-.35,.68,-.025))
		cam.fov = 24
		for i in 3: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		path = ProjectSettings.globalize_path("res://data/captures/traveler_v3_grip.png")
		check(get_viewport().get_texture().get_image().save_png(path) == OK, "Traveler grip capture save failed")
		print("Saved ", path)
		# Render the most demanding rigid shoulder/wrist pose, then the saddle
		# pose, so exposed seams can be reviewed without changing player state.
		cam.fov = 42
		cam.global_position = Vector3(.35,1.60,-2.75)
		cam.look_at(Vector3(-.65,1.30,0))
		art.pose_preview(&"climb", .4)
		for i in 3: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		path = ProjectSettings.globalize_path("res://data/captures/traveler_v3_climb.png")
		check(get_viewport().get_texture().get_image().save_png(path) == OK, "Traveler climb capture save failed")
		print("Saved ", path)
		cam.look_at(Vector3(-.65,1.05,0))
		art.pose_preview(&"ride", .4)
		for i in 3: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		path = ProjectSettings.globalize_path("res://data/captures/traveler_v3_ride.png")
		check(get_viewport().get_texture().get_image().save_png(path) == OK, "Traveler ride capture save failed")
		print("Saved ", path)
	print("Travelers v3: %d failure(s); six GLBs, all LODs/materials, rigid attachment origins, walk/ride/climb and unchanged gameplay" % failures)
	get_tree().quit(1 if failures else 0)
func measure(root: Node) -> Dictionary:
	var out := {"triangles": 0, "materials": 0, "collisions": 0}
	if root is CollisionShape3D: out.collisions += 1
	if root is MeshInstance3D and root.mesh:
		for i in root.mesh.get_surface_count():
			var arrays: Array = root.mesh.surface_get_arrays(i)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			out.triangles += indices.size() / 3 if not indices.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			if root.mesh.surface_get_material(i): out.materials += 1
	for child in root.get_children():
		var m := measure(child)
		for key in out: out[key] += m[key]
	return out
func setup_studio() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.10,.14,.16)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(.72,.78,.81)
	env.environment.ambient_light_energy = .65
	add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50,-30,0)
	key.light_color = Color(1,.89,.76)
	key.light_energy = 1.5
	key.shadow_enabled = true
	add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-3,2,-1)
	fill.omni_range = 8
	fill.light_color = Color(.72,.84,1)
	fill.light_energy = 2
	add_child(fill)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(.30,.33,.31)
	TerrainKit.box(self, Vector3(.55,.29,0), Vector3(.78,.56,2.05), stone)
	TerrainKit.box(self, Vector3(.55,.59,0), Vector3(.91,.06,2.13), stone)
