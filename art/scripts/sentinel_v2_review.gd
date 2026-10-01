extends "res://art/scripts/ancient_valley_review.gd"
const SentinelAdapter=preload("res://art/scripts/sentinel_v2_adapter.gd")
func _ready() -> void:
	super._ready()
	sentinel=Node3D.new();sentinel.set_script(Humanoid);sentinel.name="SentinelV2"
	sentinel.position=Vector3(7,Valley.height_at(7,-3),-3);sentinel.debug_override=&"frozen"
	add_child(sentinel)
	adapter=Node.new();adapter.set_script(SentinelAdapter);adapter.target_path=NodePath("../SentinelV2");add_child(adapter)
	call_deferred("_sentinel_view",0)
	if "--capture-sentinel-v2" in OS.get_cmdline_user_args():call_deferred("_capture_sentinel")
func _sentinel_view(index: int) -> void:
	camera.position=[Vector3(22,12,-29),Vector3(7,7,-30),Vector3(-12,12,22),Vector3(15,16,-16)][index]
	camera.look_at([Vector3(7,9,-3),Vector3(7,9,-3),Vector3(7,9,-3),Vector3(7,14,-3)][index])
	title.text="S E N T I N E L   /   V 2"
	hint.text="17 m original humanoid  /  17 rigid visual segments  /  gameplay rig unchanged"
func _capture_sentinel() -> void:
	var out := "res://art/screenshots/sentinel_v2";DirAccess.make_dir_recursive_absolute(out)
	var observations: Array=[]
	for i in 4:
		set_lighting(0);sun.rotation_degrees=Vector3(-35,145,0);world.environment.ambient_light_energy=.72;_sentinel_view(i)
		for frame in 15:await get_tree().process_frame
		await RenderingServer.frame_post_draw
		assert(get_viewport().get_texture().get_image().save_png(out+"/"+["three_quarter","front","back","joint_detail"][i]+".png")==OK)
		observations.append({"view":i,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)})
	var result := {"adapter":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"attached_segments":adapter.attached_count,"views":observations,"note":"Actual Godot viewport workload; not target-hardware FPS. Rigid visual adapter only."}
	FileAccess.open("res://art/reports/v2/sentinel_render_costs.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("SENTINEL_V2_CAPTURE_OK ",JSON.stringify(result));get_tree().quit()

func _update_ui() -> void:
	if title:title.text="S E N T I N E L   /   V 2"
	if hint:hint.text="Original 17 m humanoid / fur grip readability / unchanged gameplay rig"
