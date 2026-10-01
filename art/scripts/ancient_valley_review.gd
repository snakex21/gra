extends "res://art/scripts/showcase.gd"
const Valley=preload("res://art/scripts/ancient_valley.gd")
func _ready() -> void:
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	get_window().size=Vector2i(1280,720)
	get_window().content_scale_size=Vector2i(1280,720)
	get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	env_set=Node3D.new();env_set.set_script(Valley);env_set.name="AncientValley_360m";add_child(env_set)
	_lighting();_ui()
	camera=Camera3D.new();camera.fov=52;camera.far=680;add_child(camera);camera.current=true
	set_view(0);set_lighting(0)
	if "--capture-valley" in OS.get_cmdline_user_args():call_deferred("_capture_valley")
func _update_ui() -> void:
	if title:title.text="A N C I E N T   V A L L E Y"
	if hint:hint.text="V2 / ORIGINAL ART     360 m landscape     1-3 light    V view    H hide text"
func set_view(index: int) -> void:
	view=index
	camera.position=[Vector3(104,58,-122),Vector3(-56,12,-2),Vector3(83,10,1),Vector3(-121,36,23),Vector3(-13,2.9,-30)][index]
	if index==4:camera.position.y=Valley.height_at(camera.position.x,camera.position.z)+1.7
	camera.look_at([Vector3(-13,11,32),Vector3(-31,4,29),Vector3(37,1,43),Vector3(-83,18,85),Vector3(-30,7,27)][index])
	_update_ui()
func _capture_valley() -> void:
	var out := "res://art/reports/v2"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var shots := "res://art/screenshots/v2"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shots))
	var observations: Array=[]
	for shot in [[0,0,"valley_day"],[0,1,"valley_sunset"],[0,2,"valley_night"],[1,0,"temple"],[2,0,"shore"],[3,0,"canyon"],[4,0,"ground_path"]]:
		set_view(shot[0]);set_lighting(shot[1])
		for frame in 15:await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var error:=get_viewport().get_texture().get_image().save_png(shots+"/"+shot[2]+".png")
		assert(error==OK)
		observations.append({"view":shot[2],"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"objects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)})
	var result: Dictionary={"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info().string,"terrain_triangles":env_set.terrain_triangles,"asset_instances":env_set.asset_count,"vegetation_instances":env_set.vegetation_instances,"scatter_fingerprint":env_set.scatter_fingerprint,"texture_memory_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"views":observations,"note":"Actual render workload, not a target-hardware FPS benchmark. No gameplay implementation changed."}
	FileAccess.open(out+"/render_costs.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("VALLEY_CAPTURE_OK ",JSON.stringify(result));get_tree().quit()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and not event.is_echo() and event.keycode==KEY_V:set_view((view+1)%5)
	else:super._unhandled_key_input(event)
