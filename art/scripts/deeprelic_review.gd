extends Node3D
const Cavern = preload("res://art/scripts/deeprelic_environment.gd")
const Asset = preload("res://art/scripts/deeprelic_asset.gd")
const NAMES := ["01_processional_ruins","02_abandoned_camp","03_shrine_and_crossing","04_gate_detail","05_catalogue_gates_bridges","06_catalogue_pillars_stairs","07_catalogue_altars_storage","08_catalogue_camp"]
var camera: Camera3D
var cave: Node3D
var catalogue: Node3D
var title: Label
var view := 0
func _ready() -> void:
	get_window().size = Vector2i(1280,720)
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(.009,.013,.018)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(.40,.49,.58)
	env.ambient_light_energy = 1.15
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.8
	world.environment = env
	add_child(world)
	cave = Node3D.new(); cave.set_script(Cavern); cave.include_collision=true; add_child(cave)
	for p in [Vector3(7,4,12),Vector3(0,5,5),Vector3(-4,5,14),Vector3(5,7,-8),Vector3(-5,5,-23),Vector3(1,5,-35),Vector3(0,6,-52),Vector3(-12,11,0),Vector3(8,17,5)]:
		var lamp := OmniLight3D.new()
		lamp.position=p; lamp.omni_range=29; lamp.light_energy=3.5
		lamp.light_color=Color(.94,.71,.44) if p.z<0 else Color(.53,.72,.89)
		lamp.shadow_enabled=false
		add_child(lamp)
	catalogue = Node3D.new(); add_child(catalogue)
	var ids: Array = Asset.records().keys()
	for i in ids.size():
		var obj := Node3D.new(); obj.set_script(Asset); obj.model_id=ids[i]
		obj.lod_distances=Vector3(900,1000,1100)
		var record: Dictionary = Asset.records()[ids[i]]
		var size: Array = record.nominal_size
		var factor: float = 11.0/maxf(float(size[0]),maxf(float(size[1]),float(size[2])))
		obj.scale=Vector3.ONE*factor
		obj.position=Vector3(200+(i%4)*18,0,(i%7)/4*20)
		obj.set_meta("page",i/7)
		catalogue.add_child(obj)
		var label := Label3D.new(); label.text=ids[i].replace("_"," ")
		label.font_size=26; label.pixel_size=.06; label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test=true
		label.position=obj.position+Vector3(0,-1,8); label.set_meta("page",i/7); catalogue.add_child(label)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-45,-25,0); sun.light_energy=2.0
	# Catalogue light is layer-isolated; it cannot fake sunlight through cave ceiling.
	sun.light_cull_mask=2; add_child(sun)
	for item in catalogue.get_children():
		for child in item.get_children():
			if child is MeshInstance3D: child.layers=2
	camera=Camera3D.new(); camera.near=.08; camera.far=500; add_child(camera);camera.current=true
	var canvas := CanvasLayer.new(); add_child(canvas)
	title=Label.new(); title.position=Vector2(28,22); title.add_theme_font_size_override("font_size",24);canvas.add_child(title)
	set_view(0)
	if "--capture-deeprelic" in OS.get_cmdline_user_args(): call_deferred("capture")
func set_view(index: int) -> void:
	view=index; cave.visible=index<4;catalogue.visible=index>=4
	camera.projection=Camera3D.PROJECTION_PERSPECTIVE if index<4 else Camera3D.PROJECTION_ORTHOGONAL
	camera.fov=68;camera.size=64
	var positions := [Vector3(3,4,21),Vector3(-1,3.6,19),Vector3(-2,4,7),Vector3(4,3,-10)]
	var targets := [Vector3(0,6,-13),Vector3(6,1.2,9),Vector3(-10,3,-6),Vector3(0,5.4,-17)]
	if index<4:
		camera.position=positions[index];camera.look_at(targets[index])
	else:
		camera.position=Vector3(226,46,66);camera.look_at(Vector3(226,3,9))
		for item in catalogue.get_children():item.visible=int(item.get_meta("page"))==index-4
	title.text="DEEPRELIC  /  " + NAMES[index].substr(3).replace("_"," ").to_upper()+"\nV: next view · original underground props / 1 metre units"
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode==KEY_V:set_view((view+1)%NAMES.size())
func capture() -> void:
	DirAccess.make_dir_recursive_absolute("res://art/screenshots/v7")
	var reports: Array=[]
	for i in NAMES.size():
		set_view(i)
		for frame in 12: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://art/screenshots/v7/"+NAMES[i]+".png")
		reports.append({"view":NAMES[i],"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)})
	var f:=FileAccess.open("res://art/reports/v7/render_costs.json",FileAccess.WRITE);f.store_string(JSON.stringify({"views":reports,"note":"llvmpipe viewport evidence; no FPS claim"},"\t"));f.close()
	print("DEEPRELIC_CAPTURE_OK views=8");get_tree().quit()
