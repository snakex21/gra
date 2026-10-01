extends Node3D
## Fixed art review cameras and three static single-sun lighting presets.
## Independent of showcase.gd, gameplay scenes, controllers, and camera scripts.
const Crossing = preload("res://art/scripts/saltwind_environment.gd")
const PRESETS := ["CLEAR DAY", "LATE SUN", "BLUE HOUR"]
const VIEWS := ["SALT BASIN", "WIND GATE", "CRUST STUDY", "ERODED NEEDLES", "FAR ESCARPMENTS", "GEOLOGY + SALT", "RUINS + DRY PLANTS"]
var env_set: Node3D
var camera: Camera3D
var sun: DirectionalLight3D
var world: WorldEnvironment
var overlay: CanvasLayer
var title: Label
var subtitle: Label
var hint: Label
var lighting := 0
var view := 0
var catalogue_labels: Array[Label] = []
var _lod_debug := false
var _lod_debug_materials: Array[StandardMaterial3D] = []

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280, 720)
	get_window().content_scale_size = Vector2i(1280, 720)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	env_set = Node3D.new()
	env_set.name = "SaltwindCrossing"
	env_set.set_script(Crossing)
	env_set.include_collision = true
	env_set.include_catalogue = true
	add_child(env_set)
	_make_lighting()
	_make_overlay()
	camera = Camera3D.new()
	camera.name = "FixedArtReviewCamera"
	camera.near = .08
	camera.far = 1000
	add_child(camera)
	camera.current = true
	set_view(0)
	set_lighting(0)
	if "--capture-saltwind" in OS.get_cmdline_user_args():
		call_deferred("_capture")

func _make_lighting() -> void:
	world = WorldEnvironment.new()
	world.name = "ArtWorldEnvironment"
	world.environment = Environment.new()
	var env := world.environment
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.sdfgi_enabled = false
	env.volumetric_fog_enabled = false
	var sky := Sky.new()
	var material := ProceduralSkyMaterial.new()
	material.sky_curve = .17
	material.ground_curve = .18
	sky.sky_material = material
	env.sky = sky
	env.fog_enabled = true
	env.fog_density = .0011
	env.fog_sky_affect = .14
	env.fog_height = -8
	env.fog_height_density = .02
	add_child(world)
	sun = DirectionalLight3D.new()
	sun.name = "SingleShadowCastingSun"
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 130
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.shadow_bias = .045
	sun.shadow_normal_bias = 1.0
	add_child(sun)

func set_lighting(index: int) -> void:
	lighting = index
	var env := world.environment
	var sky := env.sky.sky_material as ProceduralSkyMaterial
	if index == 0:
		sun.rotation_degrees = Vector3(-44, -36, 0)
		sun.light_color = Color(.98,.97,.91)
		sun.light_energy = .72
		env.ambient_light_color = Color(.63, .72, .77)
		env.ambient_light_energy = .38
		env.fog_light_color = Color(.74,.73,.65)
		sky.sky_top_color = Color(.33,.43,.46)
		sky.sky_horizon_color = Color(.80,.79,.69)
		sky.ground_bottom_color = Color(.34, .37, .34)
	elif index == 1:
		sun.rotation_degrees = Vector3(-16, -62, 0)
		sun.light_color = Color(1.0,.78,.58)
		sun.light_energy = 1.0
		env.ambient_light_color = Color(.49, .58, .72)
		env.ambient_light_energy = .38
		env.fog_light_color = Color(.74, .57, .41)
		sky.sky_top_color = Color(.27, .36, .48)
		sky.sky_horizon_color = Color(.89, .65, .43)
		sky.ground_bottom_color = Color(.28, .27, .27)
	else:
		sun.rotation_degrees = Vector3(-36, 31, 0)
		sun.light_color = Color(.59, .74, .96)
		sun.light_energy = .68
		env.ambient_light_color = Color(.38, .49, .66)
		env.ambient_light_energy = .62
		env.fog_light_color = Color(.20, .30, .40)
		sky.sky_top_color = Color(.018, .04, .085)
		sky.sky_horizon_color = Color(.23, .34, .43)
		sky.ground_bottom_color = Color(.1, .15, .20)
	if view >= 5:
		sun.rotation_degrees = Vector3(-52,145,0)
		sun.light_energy = .9
		env.ambient_light_energy = .55
	sky.ground_horizon_color = sky.sky_horizon_color
	_update_overlay()

func set_view(index: int) -> void:
	view = index
	var is_catalogue := index >= 5
	env_set.show_catalogue(is_catalogue)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL if is_catalogue else Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 53.0
	camera.size = 93
	var positions := [Vector3(32,12,92),Vector3(-19,5,-31),Vector3(-8,3,35),Vector3(-35,8,5),Vector3(74,47,135),Vector3(0,130,695),Vector3(0,130,695)]
	var targets := [Vector3(0,8,-63),Vector3(4,9,-65),Vector3(-13,.25,21),Vector3(-66,17,-53),Vector3(-4,17,-129),Vector3(0,0,800),Vector3(0,0,800)]
	camera.position = positions[index]
	camera.look_at(targets[index])
	world.environment.fog_enabled = not is_catalogue
	for label in catalogue_labels:
		label.queue_free()
	catalogue_labels.clear()
	if is_catalogue:
		for node in env_set.catalogue.get_children():
			if not node.has_meta("catalogue_page"):
				continue
			node.visible = node.get_meta("catalogue_page") == index-5
			if not node.visible:
				continue
			var label := Label.new()
			label.text = node.model_id.replace("_"," ").to_upper()
			label.set_meta("world_anchor",env_set.catalogue.position+node.get_meta("label_anchor"))
			label.add_theme_font_size_override("font_size",12)
			label.add_theme_color_override("font_color",Color(.96,.94,.82))
			label.add_theme_color_override("font_shadow_color",Color(.02,.03,.03))
			label.add_theme_constant_override("shadow_offset_x",1)
			label.add_theme_constant_override("shadow_offset_y",1)
			label.size = Vector2(260,20)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.position = camera.unproject_position(env_set.catalogue.position+node.get_meta("label_anchor"))-Vector2(130,0)
			overlay.add_child(label)
			catalogue_labels.append(label)
	_update_overlay()

func _process(_delta: float) -> void:
	for label in catalogue_labels:
		label.position = camera.unproject_position(label.get_meta("world_anchor"))-Vector2(130,0)

func _make_overlay() -> void:
	overlay = CanvasLayer.new()
	overlay.name = "ArtReviewOverlay"
	add_child(overlay)
	title = Label.new()
	title.position = Vector2(31, 24)
	title.add_theme_font_size_override("font_size", 27)
	title.add_theme_color_override("font_color", Color(.94, .93, .83))
	title.add_theme_color_override("font_shadow_color", Color(.025, .06, .075, .7))
	title.add_theme_constant_override("shadow_offset_x", 1)
	title.add_theme_constant_override("shadow_offset_y", 2)
	overlay.add_child(title)
	subtitle = Label.new()
	subtitle.position = Vector2(33, 62)
	subtitle.add_theme_font_size_override("font_size", 11)
	subtitle.modulate = Color(.88, .9, .83)
	overlay.add_child(subtitle)
	hint = Label.new()
	hint.position = Vector2(33, 678)
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(.92, .93, .86))
	hint.add_theme_color_override("font_shadow_color", Color(.02, .04, .05, .9))
	hint.add_theme_constant_override("shadow_offset_x", 1)
	hint.add_theme_constant_override("shadow_offset_y", 1)
	overlay.add_child(hint)

func _update_overlay() -> void:
	if title == null:
		return
	title.text = "S A L T W I N D   E X P A N S E"
	subtitle.text = "ORIGINAL ENVIRONMENT ART   /   SALT DESERT + BURIED RUINS   /   32 NEW MODULES"
	hint.text = "%s  /  %s     1–3 lighting   V views   L LOD colours   H hide text" % [VIEWS[view], PRESETS[lighting]]
	if view >= 5:
		subtitle.text = "16 ASSETS PER PAGE   /   SCALED TO FIT   /   3 AUTHORED LODS EACH   /   ORIGINAL 1K ATLAS"

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.keycode in [KEY_1, KEY_2, KEY_3]:
		set_lighting(event.keycode - KEY_1)
	elif event.keycode == KEY_V:
		set_view((view + 1) % VIEWS.size())
	elif event.keycode == KEY_L:
		_set_lod_debug(not _lod_debug)
	elif event.keycode == KEY_H:
		overlay.visible = not overlay.visible

func _set_lod_debug(enabled: bool) -> void:
	_lod_debug = enabled
	if _lod_debug_materials.is_empty():
		for colour in [Color(.23, .72, .36), Color(.95, .63, .16), Color(.81, .22, .23)]:
			var material := StandardMaterial3D.new()
			material.resource_name = "LOD_Debug_%d" % _lod_debug_materials.size()
			material.albedo_color = colour
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_lod_debug_materials.append(material)
	for node in env_set.find_children("LOD*", "MeshInstance3D", true, false):
		var level := int(str(node.name).trim_prefix("LOD"))
		node.material_overlay = _lod_debug_materials[level] if enabled else null

func _material_key(material: Material) -> String:
	if material == null:
		return "default"
	if not material.resource_path.is_empty():
		return material.resource_path
	return "%s#%d" % [material.resource_name, material.get_instance_id()]

func _scene_inventory() -> Dictionary:
	var materials: Dictionary = {}
	var branch_materials: Dictionary = {}
	var mesh_nodes := 0
	var branch_mesh_nodes := 0
	var shadow_mesh_nodes := 0
	var branch_shadow_mesh_nodes := 0
	var range_mesh_nodes := 0
	var lod_nodes := {"LOD0": 0, "LOD1": 0, "LOD2": 0}
	var branch_lod_in_range := {"LOD0": 0, "LOD1": 0, "LOD2": 0}
	var multimesh_nodes := 0
	var multimesh_instances := 0
	for node in env_set.find_children("*", "GeometryInstance3D", true, false):
		var visible_branch: bool = node.is_visible_in_tree()
		var dist: float = node.global_position.distance_to(camera.global_position)
		var in_range: bool = visible_branch and (node.visibility_range_begin <= 0 or dist >= node.visibility_range_begin) and (node.visibility_range_end <= 0 or dist < node.visibility_range_end)
		var mats: Array[Material] = []
		if node is MeshInstance3D:
			mesh_nodes += 1
			if visible_branch:
				branch_mesh_nodes += 1
			if in_range:
				range_mesh_nodes += 1
			if node.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				shadow_mesh_nodes += 1
				if in_range:
					branch_shadow_mesh_nodes += 1
			if lod_nodes.has(str(node.name)):
				lod_nodes[str(node.name)] += 1
				if in_range:
					branch_lod_in_range[str(node.name)] += 1
			if node.material_override != null:
				mats.append(node.material_override)
			elif node.mesh != null:
				for surface in node.mesh.get_surface_count():
					mats.append(node.get_active_material(surface))
		elif node is MultiMeshInstance3D:
			multimesh_nodes += 1
			if node.multimesh != null:
				multimesh_instances += node.multimesh.instance_count
			mats.append(node.material_override)
		for material in mats:
			materials[_material_key(material)] = true
			if in_range:
				branch_materials[_material_key(material)] = true
	return {
		"loaded_mesh_nodes_including_all_lods_and_hidden_catalogue": mesh_nodes,
		"visible_branch_mesh_nodes_before_range_and_frustum_culling": branch_mesh_nodes,
		"visible_branch_mesh_nodes_approximately_in_lod_range": range_mesh_nodes,
		"loaded_material_resources": materials.size(),
		"visible_branch_material_resources_approximately_in_range": branch_materials.size(),
		"loaded_material_keys": materials.keys(),
		"loaded_shadow_enabled_mesh_nodes": shadow_mesh_nodes,
		"visible_branch_shadow_enabled_mesh_nodes_approximately_in_range": branch_shadow_mesh_nodes,
		"loaded_authored_lod_mesh_nodes": lod_nodes,
		"visible_branch_authored_lods_approximately_in_range": branch_lod_in_range,
		"multimesh_nodes": multimesh_nodes,
		"multimesh_instances": multimesh_instances,
		"inventory_caveat": "Structural counts are not render submissions. Approximate LOD inventory uses node-origin camera distance and does not test the frustum or shadow-caster volume; actual submission counters are above."
	}

func _capture() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Saltwind capture needs a rendering display; headless images are not evidence")
		get_tree().quit(2)
		return
	_set_lod_debug(false)
	var shots := "res://art/screenshots/v4"
	var reports := "res://art/reports/v4"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shots))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(reports))
	var observations: Array[Dictionary] = []
	var sequence := [
		[0,0,"01_salt_basin_day"],[0,1,"02_salt_basin_sunset"],[0,2,"03_salt_basin_blue_hour"],
		[1,0,"04_wind_gate"],[2,0,"05_salt_crust_detail"],[3,0,"06_eroded_needles"],
		[4,0,"07_distant_escarpments"],[5,0,"08_geology_salt_catalogue"],[6,0,"09_ruins_plants_catalogue"]
	]
	for shot in sequence:
		set_view(shot[0])
		set_lighting(shot[1])
		for frame in 18:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		# Read counters before PNG readback; they are actual Godot rendered work.
		var row: Dictionary = {
			"view": shot[2],
			"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			"rendered_objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			"texture_memory_bytes": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),
			"buffer_memory_bytes": Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED),
			"video_memory_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
			"camera_position": [camera.position.x, camera.position.y, camera.position.z],
			"preset": PRESETS[lighting],
			"scene_inventory": _scene_inventory()
		}
		var image := get_viewport().get_texture().get_image()
		var result := image.save_png(shots + "/" + shot[2] + ".png")
		if result != OK:
			push_error("Viewport PNG write failed: " + str(result))
			get_tree().quit(3)
			return
		observations.append(row)
		print("SALTWIND_VIEW ", JSON.stringify(row))
	var report: Dictionary = {
		"engine": Engine.get_version_info().string,
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"vendor": RenderingServer.get_video_adapter_vendor(),
		"display_server": DisplayServer.get_name(),
		"viewport_pixels": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
		"saltwind_landscape_asset_instances": env_set.asset_count,
		"saltwind_catalogue_asset_instances": env_set.catalogue_count,
		"distant_terrain_triangles": env_set.distant_triangles,
		"vegetation_instances": env_set.vegetation_instances,
		"near_terrain_triangles": env_set.terrain_triangles,
		"new_unique_asset_ids": Crossing.SaltAsset.records().keys(),
		"configured_shadows": {"directional_shadow_lights": 1, "local_shadow_lights": 0, "directional_mode": "2 parallel splits", "max_distance_metres": sun.directional_shadow_max_distance, "configured_shadow_atlas_size": ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size", 2048)},
		"configured_lod_ranges_metres": {"saltwind": [55,145,800], "catalogue_lod0_inspection": [900,1100,1500], "vegetation_cells": [38,78,140]},
		"expensive_features": {"ssao": false, "ssil": false, "sdfgi": false, "volumetric_fog": false, "water_reflection_passes": 0, "water_refraction_passes": 0, "animated_light_nodes": 0},
		"views": observations,
		"measurement_notes": [
			"Actual rendered frame counters from Godot Performance, after 18 settling frames and frame_post_draw; not source triangle totals.",
			"Draw calls, primitives and objects may include shadow passes and UI. Scene inventories describe configured nodes/materials separately.",
			"Memory counters are renderer-reported allocations including render targets, sky, fonts, textures, and buffers. They are not source PNG sizes, resident per-asset VRAM, or peak device memory.",
			"Software renderer results are workload evidence only, not target GPU FPS benchmarks. PNG readback time is excluded from any performance claim.",
			"All shots use fixed art-only cameras, one shadow light and static presets. Gameplay scenes/scripts are not loaded."
		]
	}
	var file := FileAccess.open(reports + "/render_costs.json", FileAccess.WRITE)
	if file == null:
		push_error("Cannot write Saltwind render report")
		get_tree().quit(4)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	print("SALTWIND_CAPTURE_OK views=", observations.size())
	get_tree().quit()
