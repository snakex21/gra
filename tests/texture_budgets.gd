extends Node3D
## Real texture imports and material resource identities, with an OpenGL render.
var failures := 0
var textures: Array[Texture2D] = []
var scenes: Array[PackedScene] = []
var texture_records: Array = []
var material_records: Array = []
var surface_materials: Array[Material] = []
var format_counts := {}
var payload_bytes := 0
var rgba8_equivalent_bytes := 0
var started_msec := 0
const EXCLUDED := ["ui", "hud", "icons", "captures", "screenshots", "output"]

func _enter_tree() -> void:
	started_msec = Time.get_ticks_msec()

func _process(_delta: float) -> void:
	if Time.get_ticks_msec() - started_msec > 120000:
		push_error("Texture budget test exceeded its 120-second wall-clock watchdog")
		get_tree().quit(1)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func pngs(folder: String) -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(folder)
	check(directory != null, "Texture folder missing: " + folder)
	if not directory: return result
	for subfolder in directory.get_directories():
		if not subfolder.to_lower() in EXCLUDED:
			result.append_array(pngs(folder.path_join(subfolder)))
	for file in directory.get_files():
		if file.ends_with(".png"): result.append(folder.path_join(file))
	result.sort()
	return result

func rgba_mips(w: int, h: int) -> int:
	var amount := 0
	while true:
		amount += w * h * 4
		if w == 1 and h == 1: return amount
		w = maxi(1, w / 2)
		h = maxi(1, h / 2)
	return amount

func digest(data: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(data)
	return context.finish().hex_encode()

func image_record(texture: Texture2D) -> Dictionary:
	var image := texture.get_image()
	if image == null: return {"missing_image": true}
	return {"resource_path": texture.resource_path, "instance_id": texture.get_instance_id(),
		"rid": texture.get_rid().get_id(), "width": image.get_width(), "height": image.get_height(),
		"format": image.get_format(), "compressed": image.is_compressed(), "mipmaps": image.has_mipmaps(),
		"data_bytes": image.get_data().size(), "data_sha256": digest(image.get_data())}

func inspect_texture(path: String) -> void:
	var config := ConfigFile.new()
	check(config.load(path + ".import") == OK, "Texture import options missing: " + path)
	check(config.get_value("params", "compress/mode", -1) == 2, "Texture is not configured for VRAM compression: " + path)
	check(config.get_value("params", "mipmaps/generate", false), "Texture mipmaps are disabled: " + path)
	check(not config.get_value("params", "compress/high_quality", true), "Texture needs unsupported high-quality compression: " + path)
	var normal := path.get_file().get_basename().ends_with("_normal")
	if normal: check(config.get_value("params", "compress/normal_map", -1) == 1, "Normal map is not explicitly RGTC: " + path)
	var texture := load(path) as Texture2D
	check(texture != null, "Texture2D import failed: " + path)
	if not texture: return
	textures.append(texture)
	var image := texture.get_image()
	check(image != null, "Imported texture has no image: " + path)
	if not image: return
	var record := image_record(texture)
	record["path"] = path
	texture_records.append(record)
	check(image.is_compressed(), "Runtime texture is not block-compressed: " + path)
	check(image.has_mipmaps(), "Runtime texture lost mipmaps: " + path)
	if normal: check(image.get_format() in [Image.FORMAT_RGTC_RG, Image.FORMAT_DXT5], "Normal map has unexpected GPU encoding: " + path)
	format_counts[str(image.get_format())] = int(format_counts.get(str(image.get_format()), 0)) + 1
	payload_bytes += image.get_data().size()
	rgba8_equivalent_bytes += rgba_mips(image.get_width(), image.get_height())
	# Compare authored channels after decompression. This catches normal swizzles
	# and destructive ORM/roughness channel changes, without assuming exact pixels.
	if normal or path.contains("_orm") or path.contains("_roughness"):
		var decoded := image.duplicate() as Image
		check(decoded.decompress() == OK, "Cannot decode compressed texture: " + path)
		var source := Image.load_from_file(ProjectSettings.globalize_path(path))
		if source == null: check(false, "Source pixels missing: " + path); return
		var error := Vector3.ZERO
		for y in 8:
			for x in 8:
				var px := int((x + .5) * source.get_width() / 8)
				var py := int((y + .5) * source.get_height() / 8)
				var expected := source.get_pixel(px, py)
				var actual := decoded.get_pixel(px, py)
				error += Vector3(absf(actual.r - expected.r), absf(actual.g - expected.g), absf(actual.b - expected.b)) / 64.0
		check(error.x < .08 and error.y < .08 and (normal or error.z < .08), "Material channels changed excessively: %s %s" % [path, error])
		record["sample_mean_absolute_channel_error"] = [error.x, error.y, error.z]

func inspect_scene(path: String) -> void:
	var packed := load(path) as PackedScene
	check(packed != null, "Actual model material import failed: " + path)
	if not packed: return
	scenes.append(packed)
	var root := packed.instantiate() as Node3D
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if not mesh.mesh: continue
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if not material: continue
			surface_materials.append(material)
			for slot in ["albedo_texture", "normal_texture", "roughness_texture", "metallic_texture", "ao_texture"]:
				var texture := material.get(slot) as Texture2D
				if not texture: continue
				var record := image_record(texture)
				check(record.get("compressed", false) and record.get("mipmaps", false), "Real GLB material texture lost compression/mipmaps: " + texture.resource_path)
				record.merge({"scene": path, "mesh": mesh.name, "surface": surface, "slot": slot, "material": material.resource_name})
				material_records.append(record)
	root.free()

func add_material_preview(material: Material, index: int) -> void:
	var node := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = .36
	sphere.height = .72
	sphere.radial_segments = 24
	sphere.rings = 12
	node.mesh = sphere
	node.material_override = material
	node.position = Vector3((index % 10) * .85, (index / 10) * .85, 0)
	add_child(node)

func _ready() -> void:
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output")) == OK, "Test output directory cannot be created")
	var method := RenderingServer.get_current_rendering_method()
	check(method == "gl_compatibility", "Texture budget test requires the Compatibility renderer")
	var before := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)
	for folder in ["res://textures", "res://models"]:
		for path in pngs(folder): inspect_texture(path)
	for lod in 3:
		for id in ["sword", "bow", "quiver"]: inspect_scene("res://models/weapons_v4/%s_lod%d.glb" % [id, lod])
		inspect_scene("res://models/characters/travelers_v3/traveler_lod%d.glb" % lod)
		inspect_scene("res://models/agro_v3/body_lod%d.glb" % lod)
		inspect_scene("res://models/dormin_v3/chest_lod%d.glb" % lod)
	# These are the real campaign atlas/terrain materials, not synthetic samplers.
	for path in ["res://materials/colossi_v3/atlas.tres", "res://materials/environment/rock.tres", "res://materials/environment/terrain.tres"]:
		var material := load(path) as Material
		check(material != null, "Real arena material failed: " + path)
		if material: surface_materials.append(material)
	var unique_materials := {}
	var index := 0
	for material in surface_materials:
		if unique_materials.has(material.get_instance_id()): continue
		unique_materials[material.get_instance_id()] = true
		add_material_preview(material, index)
		index += 1
	var camera := Camera3D.new()
	add_child(camera)
	var center_y := (ceilf(index / 10.0) - 1) * .85 * .5
	camera.position = Vector3(3.8, center_y, 14)
	camera.look_at(Vector3(3.8, center_y, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = maxf(9.5, ceilf(index / 10.0) * .85 + 1)
	camera.current = true
	var light := DirectionalLight3D.new()
	add_child(light)
	light.rotation_degrees = Vector3(-32, -25, 0)
	light.light_energy = 2
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(.12, .14, .16)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(.6, .66, .72)
	environment.environment.ambient_light_energy = .5
	add_child(environment)
	for i in 6: await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(get_viewport().get_texture().get_image().save_png("res://tests/output/texture_budgets.png") == OK, "Real material render capture failed")
	var groups := {}
	for record in material_records:
		var key := str(record.get("data_sha256", "missing"))
		if not groups.has(key): groups[key] = []
		groups[key].append(record)
	var duplicate_records: Array = []
	for records: Array in groups.values():
		var rids := {}
		for record in records: rids[str(record.get("rid", -1))] = true
		if rids.size() > 1:
			duplicate_records.append({"identical_payload_sha256": records[0].data_sha256, "distinct_gpu_texture_rids": rids.size(), "payload_bytes_per_rid": records[0].data_bytes, "references": records})
	var report := {"renderer": method, "display_server": DisplayServer.get_name(), "failures": failures,
		"authored_textures_count": texture_records.size(), "compressed_image_payload_bytes": payload_bytes,
		"rgba8_full_mipmap_comparison_bytes": rgba8_equivalent_bytes, "image_formats": format_counts,
		"rendered_material_count": index, "texture_memory_counter_before": before,
		"texture_memory_counter_after": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED),
		"scope": "Loaded test resources only; payload sums exclude allocator overhead and are not an FPS promise or full campaign peak",
		"authored_textures": texture_records, "actual_glb_material_textures": material_records,
		"identical_glb_payloads_with_different_texture_rids": duplicate_records}
	var file := FileAccess.open("res://tests/output/texture_budgets.json", FileAccess.WRITE)
	check(file != null, "Runtime texture budget report cannot be written")
	if file: file.store_string(JSON.stringify(report, "\t") + "\n")
	print("TEXTURE_BUDGETS failures=%d renderer=%s textures=%d payload=%d rgba8_mips=%d duplicate_payload_groups=%d rendered_materials=%d" % [failures, method, texture_records.size(), payload_bytes, rgba8_equivalent_bytes, duplicate_records.size(), index])
	get_tree().quit(1 if failures else 0)
