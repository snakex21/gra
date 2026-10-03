extends Control
const Asset = preload("res://art/scripts/art_asset.gd")
const ATLAS = preload("res://materials/colossi_v3/atlas.tres")
const PAGES := [
	["01_humanoids", ["valus", "gaius", "barba", "argus"]],
	["02_tower_and_saru", ["malus", "saru"]],
	["03_quadrupeds", ["quadratus", "phaedra", "basaran", "pelagia"]],
	["04_pair", ["celosia", "cenobia"]],
	["05_serpents", ["hydrus", "dirge", "phalanx", "kuromori"]],
	["06_birds", ["avion", "devil", "phoenix"]],
	["07_spider_worm", ["spider", "worm"]]
]
var contracts := {}
var manifest := {}

func _ready() -> void:
	contracts = JSON.parse_string(FileAccess.get_file_as_string("res://assets/colossi_v3_contracts.json"))
	manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/colossi_v3_manifest.json"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://art/screenshots/colossi_v3"))
	for page in PAGES:
		for child in get_children():
			child.free()
		var back := ColorRect.new()
		back.color = Color(0.075, 0.095, 0.1)
		back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(back)
		_label("KOLOSY  /  RZEŹBIONE FORMY V3", Vector2(30, 18), 30)
		_label("Oryginalne modele z Blendera  ·  sztywne segmenty istniejącego rigu  ·  3 LOD", Vector2(30, 62), 20)
		for index in page[1].size():
			_card(String(page[1][index]), index)
		for i in 12:
			await get_tree().process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var path := "res://art/screenshots/colossi_v3/%s.png" % page[0]
			get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
			print("V3 capture ", path)
	get_tree().quit()

func _label(text: String, at: Vector2, font_size: int) -> void:
	var label := Label.new()
	label.position = at
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.88, 0.88, 0.79))
	add_child(label)

func _card(kind: String, index: int) -> void:
	var at := Vector2(30 + (index % 2) * 790, 108 + (index / 2) * 437)
	var profile: Dictionary = manifest.profiles[kind]
	_label(kind.to_upper() + "  /  " + String(profile.mask), at, 23)
	var container := SubViewportContainer.new()
	container.position = at + Vector2(0, 34)
	container.size = Vector2(760, 345)
	add_child(container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(760, 345)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.19, 0.19)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.87, 0.89)
	env.environment.ambient_light_energy = 0.5
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -25, 0)
	sun.light_color = Color(1, 0.91, 0.78)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	world.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-35, 145, 0)
	rim.light_color = Color(0.53, 0.71, 0.8)
	rim.light_energy = 0.8
	world.add_child(rim)
	var bounds := AABB()
	var first := true
	for spec: Dictionary in contracts[kind].segments:
		if spec.parts.is_empty():
			continue
		var pose := Transform3D(Basis(_v(spec.basis[0]), _v(spec.basis[1]), _v(spec.basis[2])), _v(spec.at))
		var mesh := MeshInstance3D.new()
		mesh.mesh = Asset.mesh_for(kind + "_" + String(spec.bone).replace("-", "m"), 0, "colossi_v3")
		mesh.material_override = ATLAS
		mesh.transform = pose
		world.add_child(mesh)
		var box := pose * mesh.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * bounds.size.length() * 2
	floor.mesh = plane
	floor.position = Vector3(bounds.get_center().x, bounds.position.y - 0.04, bounds.get_center().z)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.18, 0.21, 0.2)
	floor.material_override = material
	world.add_child(floor)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = maxf(bounds.size.y * 1.35, maxf(bounds.size.x, bounds.size.z) * 0.67)
	camera.position = bounds.get_center() + Vector3(1.1, 0.45, -1.6) * bounds.size.length()
	world.add_child(camera)
	camera.look_at(bounds.get_center())
	camera.current = true
	_label("LOD: %d / %d / %d trójkątów   ·   fizyka i sigile bez zmian" % profile.lod_triangles, at + Vector2(0, 387), 17)

func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])
