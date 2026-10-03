extends Control
## Real-rendered catalogue and import contract check for independent art props.
const PROP := preload("res://art/scripts/encounter_prop.gd")
const ITEMS := [
	["barba_shelter", "BARBA / kamienna osłona"],
	["basaran_vent_ring", "BASARAN / krąg gejzeru"],
	["kuromori_gallery_fragment", "KUROMORI / zniszczona galeria"],
	["dirge_porous_rock", "DIRGE / skała pustynna"],
	["cave_relic_lamp", "JASKINIA / lampa reliktowa"],
	["cave_offering_marker", "JASKINIA / znak ofiarny"],
	["pelagia_shrine_cap", "PELAGIA / cokół świątyni"],
]
var _failures := 0

func _ready() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.085, 0.105, 0.11)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	_label("REKWIZYTY AREN  /  ORYGINALNY ZESTAW Z BLENDERA", Vector2(28, 18), 27, Color(0.9, 0.88, 0.79))
	_label("7 modeli  •  3 LOD  •  metry  •  bez kolizji  •  źródło .blend", Vector2(28, 57), 18, Color(0.66, 0.72, 0.69))
	for index in ITEMS.size():
		_make_card(index)
	var note_at := Vector2(558, 868)
	_label("EDYTOWALNE ŹRÓDŁO", note_at, 22, Color(0.84, 0.83, 0.73))
	_label("art/source/encounter_props.blend\n\nWspólny atlas kamienia i patyny.\nOtwór gejzeru pozostaje wolny.\nLampa ma wyłącznie poświatę materiału.\nGameplay zachowuje własne kolizje.", note_at + Vector2(0, 40), 18, Color(0.67, 0.73, 0.71))
	for i in 12:
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var path := ProjectSettings.globalize_path("res://tests/output/encounter_props_catalogue.png")
		get_viewport().get_texture().get_image().save_png(path)
		print("Saved ", path)
	print("Encounter Props: ", ITEMS.size(), " imports / 21 LOD; ", _failures, " failures")
	get_tree().quit(0 if _failures == 0 else 1)

func _label(text: String, at: Vector2, size: int, colour: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	add_child(label)

func _check(valid: bool, message: String) -> void:
	if valid:
		return
	_failures += 1
	push_error(message)

func _make_card(index: int) -> void:
	var id: String = ITEMS[index][0]
	var at := Vector2(28 + (index % 3) * 532, 108 + (index / 3) * 370)
	var title: String = ITEMS[index][1]
	_label(title, at, 20, Color(0.89, 0.88, 0.8))
	var container := SubViewportContainer.new()
	container.position = at + Vector2(0, 35)
	container.size = Vector2(508, 278)
	add_child(container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(508, 278)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var sky := WorldEnvironment.new()
	sky.environment = Environment.new()
	sky.environment.background_mode = Environment.BG_COLOR
	sky.environment.background_color = Color(0.155, 0.18, 0.18)
	sky.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	sky.environment.ambient_light_color = Color(0.77, 0.85, 0.88)
	sky.environment.ambient_light_energy = 0.35
	world.add_child(sky)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -45, 0)
	sun.light_color = Color(1.0, 0.91, 0.77)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	world.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-30, 140, 0)
	rim.light_color = Color(0.5, 0.69, 0.74)
	rim.light_energy = 0.5
	world.add_child(rim)
	var prop := Node3D.new()
	prop.set_script(PROP)
	prop.model_id = id
	world.add_child(prop)
	_check(prop.get_child_count() == 3, id + ": expected 3 LOD")
	_check(prop.find_children("*", "CollisionObject3D", true, false).is_empty(), id + ": must be render-only")
	_check(prop.find_children("*", "CollisionShape3D", true, false).is_empty(), id + ": must not include physics shapes")
	var record: Dictionary = PROP.records()[id]
	var last_triangles := 100000000
	for level in 3:
		var mesh: Mesh = prop.get_child(level).mesh
		_check(mesh == PROP.mesh_for(id, level), id + ": cache must reuse the Mesh resource")
		var triangles := 0
		for surface in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(surface)
			triangles += arrays[Mesh.ARRAY_INDEX].size() / 3
		_check(triangles == int(record.triangle_counts[level]), id + ": triangle count mismatch at LOD" + str(level))
		_check(triangles > 0 and triangles < last_triangles, id + ": LOD triangle budget must decrease")
		last_triangles = triangles
		if id == "basaran_vent_ring":
			var radius := _minimum_radial_distance(mesh)
			_check(radius >= 3.0, "Basaran ring must preserve a 3m open jet radius at every LOD")
			print("Vent LOD", level, " clear radius: ", snappedf(radius, 0.001), " m")
	var bounds: AABB = prop.get_child(0).mesh.get_aabb()
	var recorded_min := Vector3(record.aabb.min[0], record.aabb.min[1], record.aabb.min[2])
	var recorded_max := Vector3(record.aabb.max[0], record.aabb.max[1], record.aabb.max[2])
	_check(bounds.position.distance_to(recorded_min) < 0.03 and bounds.end.distance_to(recorded_max) < 0.03, id + ": GLB axis or AABB mismatch")
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z)) * 2.5
	floor.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.20, 0.23, 0.22)
	floor.material_override = floor_material
	floor.position.y = bounds.position.y - 0.015
	world.add_child(floor)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = maxf(bounds.size.y * 1.45, maxf(bounds.size.x, bounds.size.z) * 0.97)
	camera.position = bounds.get_center() + Vector3(1.12, 0.72, 1.38) * maxf(bounds.size.length(), 2.0)
	world.add_child(camera)
	camera.look_at(bounds.get_center())
	camera.current = true
	_label("LOD: %d / %d / %d trójkątów" % record.triangle_counts, at + Vector2(0, 322), 16, Color(0.64, 0.71, 0.68))

func _minimum_radial_distance(mesh: Mesh) -> float:
	var result := INF
	for surface in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for start in range(0, indices.size(), 3):
			var points: Array[Vector2] = []
			for offset in 3:
				var v := vertices[indices[start + offset]]
				points.append(Vector2(v.x, v.z))
			for edge in 3:
				var a := points[edge]
				var b := points[(edge + 1) % 3]
				var along := clampf(-a.dot(b - a) / maxf((b - a).length_squared(), 0.000001), 0.0, 1.0)
				result = minf(result, (a + (b - a) * along).length())
	return result
