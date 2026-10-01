extends Node3D
## Opt-in integration wrapper. Instantiates the unmodified gameplay sandbox.
## Only replaces its ground material and colossus render meshes; modular art is
## outside the central test area. It adds no new interaction or AI behavior.

const BaseSandbox := preload("res://scenes/sandbox.tscn")
const Adapter = preload("res://art/scripts/colossus_visual_adapter.gd")
const Asset = preload("res://art/scripts/art_asset.gd")
const Terrain := preload("res://materials/environment/terrain.tres")


func _ready() -> void:
	get_window().content_scale_size = Vector2i(1280,720)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	var sandbox := BaseSandbox.instantiate()
	sandbox.name = "OriginalSandbox"
	add_child(sandbox)
	(sandbox.get_node("Ground/Mesh") as MeshInstance3D).material_override = Terrain
	var adapter := Node.new()
	adapter.set_script(Adapter)
	adapter.name = "SentinelVisualAdapter"
	adapter.target_path = NodePath("../OriginalSandbox/Colossus")
	add_child(adapter)
	for item in [
		["cliff_buttress",Vector3(-55,0,-65),0.1,1.5,"hull"],
		["cliff_buttress",Vector3(10,0,-72),0.0,1.7,"hull"],
		["ruin_arch",Vector3(-33,0,-29),.15,1.25,"arch_boxes"],
		["ruin_column",Vector3(-42,0,-18),0.0,1.2,"hull"],
		["ruin_rubble",Vector3(-39,0,-23),0.5,1.0,"hull"],
		["rock_04",Vector3(30,0,-35),0.7,1.0,"hull"],
		["tree_windward",Vector3(34,0,18),1.2,1.1,"trunk"],
		["grass_dry",Vector3(28,0,14),0.0,1.0,"none"]
	]:
		var prop := Node3D.new()
		prop.set_script(Asset)
		prop.model_id = item[0]
		prop.position = item[1]
		prop.rotation.y = item[2]
		prop.scale = Vector3.ONE*item[3]
		prop.collidable = item[4] != "none"
		prop.collision_kind = item[4]
		add_child(prop)
	print("ART_SANDBOX_OK: original sandbox instantiated, visual replacement only inside arena")
	if "--capture-art-wrapper" in OS.get_cmdline_user_args():
		call_deferred("_capture")


func _capture() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	for frame in 75:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://art/tests/output/07_sandbox_integration.png")
	assert(image.save_png(path) == OK)
	print("ART_WRAPPER_CAPTURE_OK")
	get_tree().quit()
