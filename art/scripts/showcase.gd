extends Node3D
## Separate art review scene. V cycles fixed composition views; no gameplay camera edits.

const EnvironmentSet = preload("res://art/scripts/environment_set.gd")
const VisualAdapter = preload("res://art/scripts/colossus_visual_adapter.gd")
const Humanoid = preload("res://src/colossus/greybox/greybox_humanoid.gd")
var camera: Camera3D
var sun: DirectionalLight3D
var world: WorldEnvironment
var env_set: Node3D
var sentinel: Node3D
var adapter: Node
var title: Label
var hint: Label
var lighting := 0
var view := 0
var _lod_debug := false
var capture_mode := false
const PRESETS := ["DAYLIGHT", "LOW SUN", "MOONLIGHT"]
const VIEW_NAMES := ["BASIN", "SENTINEL", "RUINS", "MATERIAL FIELD"]


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280,720)
	get_window().content_scale_size = Vector2i(1280,720)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	capture_mode = "--capture-art" in OS.get_cmdline_user_args()
	env_set = Node3D.new()
	env_set.set_script(EnvironmentSet)
	env_set.name = "SaltwardEnvironment"
	add_child(env_set)
	sentinel = Node3D.new()
	sentinel.set_script(Humanoid)
	sentinel.name = "Sentinel"
	sentinel.position = Vector3(7,0,-3)
	sentinel.position.y = EnvironmentSet.ground_height(7,-3)
	sentinel.debug_override = &"frozen"
	add_child(sentinel)
	adapter = Node.new()
	adapter.set_script(VisualAdapter)
	adapter.name = "VisualAdapter"
	adapter.target_path = NodePath("../Sentinel")
	add_child(adapter)
	_lighting()
	_ui()
	get_viewport().size_changed.connect(_update_ui)
	camera = Camera3D.new()
	camera.name = "ArtReviewCamera"
	camera.fov = 51.0
	camera.far = 420.0
	add_child(camera)
	camera.current = true
	set_view(0)
	set_lighting(0)
	if capture_mode:
		call_deferred("_capture")


func _lighting() -> void:
	world = WorldEnvironment.new()
	world.environment = Environment.new()
	var env := world.environment
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var sky := Sky.new()
	var material := ProceduralSkyMaterial.new()
	material.sky_curve = .18
	material.ground_curve = .16
	sky.sky_material = material
	env.sky = sky
	env.fog_enabled = true
	env.fog_density = .0011
	env.fog_sky_affect = .15
	env.fog_height = 0.0
	env.fog_height_density = .018
	add_child(world)
	sun = DirectionalLight3D.new()
	sun.name = "SingleKeyLight"
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 110
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.shadow_bias = .06
	add_child(sun)


func set_lighting(index: int) -> void:
	lighting = index
	var env := world.environment
	var sky := env.sky.sky_material as ProceduralSkyMaterial
	if index == 0:
		sun.rotation_degrees = Vector3(-41,-32,0)
		sun.light_color = Color(1.0,.94,.78)
		sun.light_energy = 1.15
		env.ambient_light_color = Color(.61,.70,.77)
		env.ambient_light_energy = .60
		env.fog_light_color = Color(.66,.70,.69)
		sky.sky_top_color = Color(.30,.45,.52)
		sky.sky_horizon_color = Color(.76,.77,.67)
		sky.ground_bottom_color = Color(.38,.39,.34)
	elif index == 1:
		sun.rotation_degrees = Vector3(-13,-61,0)
		sun.light_color = Color(1.0,.61,.31)
		sun.light_energy = 2.0
		env.ambient_light_color = Color(.45,.56,.70)
		env.ambient_light_energy = .65
		env.fog_light_color = Color(.68,.54,.38)
		sky.sky_top_color = Color(.26,.35,.47)
		sky.sky_horizon_color = Color(.85,.59,.35)
		sky.ground_bottom_color = Color(.29,.27,.26)
	else:
		sun.rotation_degrees = Vector3(-35,35,0)
		sun.light_color = Color(.56,.70,.91)
		sun.light_energy = .52
		env.ambient_light_color = Color(.33,.45,.59)
		env.ambient_light_energy = .45
		env.fog_light_color = Color(.17,.26,.36)
		sky.sky_top_color = Color(.015,.033,.064)
		sky.sky_horizon_color = Color(.19,.27,.32)
		sky.ground_bottom_color = Color(.08,.12,.16)
	sky.ground_horizon_color = sky.sky_horizon_color
	_update_ui()


func set_view(index: int) -> void:
	view = index
	var positions := [Vector3(43,25,-63),Vector3(21,14,-27),Vector3(-41,13,-15),Vector3(-1,4,-31)]
	var targets := [Vector3(-2,8,7),Vector3(7,9,-3),Vector3(-17,5,15),Vector3(-13,0,-17)]
	camera.position = positions[index]
	camera.look_at(targets[index])
	_update_ui()


func _ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "ArtReviewOverlay"
	add_child(canvas)
	title = Label.new()
	title.position = Vector2(36,26)
	title.add_theme_font_size_override("font_size",30)
	title.add_theme_color_override("font_color",Color(.95,.92,.80))
	canvas.add_child(title)
	var sub := Label.new()
	sub.text = "AN ORIGINAL ANCIENT LANDSCAPE  /  REAL-TIME ART STUDY"
	sub.position = Vector2(38,65)
	sub.add_theme_font_size_override("font_size",12)
	sub.modulate = Color(.84,.86,.77)
	canvas.add_child(sub)
	hint = Label.new()
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(38, get_viewport().get_visible_rect().size.y-48)
	hint.add_theme_font_size_override("font_size",14)
	hint.add_theme_color_override("font_shadow_color",Color(.04,.05,.04,.95))
	hint.add_theme_constant_override("shadow_offset_x",1)
	hint.add_theme_constant_override("shadow_offset_y",1)
	canvas.add_child(hint)


func _update_ui() -> void:
	if title:
		title.text = "S A L T W A R D"
	if hint:
		hint.position = Vector2(38,get_viewport().get_visible_rect().size.y-40)
		hint.text = "%s  /  %s      1–3 light     V view     L LOD colours     H hide text" % [PRESETS[lighting],VIEW_NAMES[view]]


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.keycode in [KEY_1,KEY_2,KEY_3]:
		set_lighting(event.keycode-KEY_1)
	elif event.keycode == KEY_V:
		set_view((view+1)%4)
	elif event.keycode == KEY_H:
		$ArtReviewOverlay.visible = not $ArtReviewOverlay.visible
	elif event.keycode == KEY_L:
		_lod_debug = not _lod_debug
		for node in find_children("LOD*","MeshInstance3D",true,false):
			if _lod_debug:
				var debug := StandardMaterial3D.new()
				debug.albedo_color = [Color(.25,.7,.36),Color(.85,.65,.18),Color(.8,.28,.22)][int(str(node.name).trim_prefix("LOD"))]
				node.material_overlay = debug
			else:
				node.material_overlay = null


func _capture() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Art screenshots need a real rendering display, not --headless")
		get_tree().quit(2)
		return
	var out := "res://art/tests/output"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	FileAccess.open(out+"/.gdignore",FileAccess.WRITE).store_string("# Render evidence, not runtime resources.\n")
	var observations: Array = []
	for shot in [[0,0,"01_basin_day"],[0,1,"02_basin_sunset"],[0,2,"03_basin_night"],[1,0,"04_sentinel_front"],[2,0,"05_ruin_modules"],[3,0,"06_ground_vegetation"]]:
		set_view(shot[0])
		set_lighting(shot[1])
		for frame in 12:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := ProjectSettings.globalize_path(out+"/"+shot[2]+".png")
		var error := img.save_png(path)
		assert(error == OK, "Screenshot write failed")
		var row := {"view":shot[2],"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"rendered_primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"rendered_objects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)}
		observations.append(row)
		print("ART_CAPTURE ", JSON.stringify(row))
	var report := {"engine":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"vendor":RenderingServer.get_video_adapter_vendor(),"resolution":str(get_viewport().get_visible_rect().size),"texture_memory_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"buffer_memory_bytes":Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED),"note":"Rendered work counters on the actual test renderer. No target-hardware FPS claim. Screenshot capture stalls are excluded from any timing claim.","asset_instances":env_set.asset_count,"vegetation_instances":env_set.vegetation_instances,"segment_visuals":adapter.attached_count,"views":observations}
	var file := FileAccess.open(out+"/render_costs.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")+"\n")
	print("ART_CAPTURE_OK")
	get_tree().quit()
