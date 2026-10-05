extends SceneTree
const CATALOG = preload("res://src/world/nature_variety_catalog.gd")
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var models := CATALOG.models()
	check(models.size() == 12, "Expected twelve Nature Variety models")
	var unique_meshes := {}
	var unique_materials := {}
	var unique_textures := {}
	var totals := [0, 0, 0]
	for model_id: String in models:
		var data: Dictionary = models[model_id]
		check(model_id.begins_with("rock_") or model_id.begins_with("ruin_") or model_id.begins_with("plant_"), "Source asset prefix changed")
		var material := CATALOG.material_for(model_id) as StandardMaterial3D
		check(material != null, "Missing shared palette material: " + model_id)
		if material == null:
			continue
		check(material == CATALOG.material_for(model_id), "Material cache miss")
		unique_materials[material.get_instance_id()] = true
		check(material.albedo_texture != null, "Missing external palette")
		if material.albedo_texture:
			unique_textures[material.albedo_texture.get_instance_id()] = true
			check(material.albedo_texture.get_width() == 64 and material.albedo_texture.get_height() == 64, "Palette dimensions changed")
		check(material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "Opaque palette was changed")
		check(material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, "Palette filtering changed")
		var previous_count := 2147483647
		for lod in 3:
			var mesh: Mesh = CATALOG.mesh_for(model_id, lod)
			check(mesh != null, "Missing GLB mesh: %s LOD%d" % [model_id, lod])
			if mesh == null:
				continue
			check(mesh == CATALOG.mesh_for(model_id, lod), "Mesh cache miss")
			unique_meshes[mesh.get_instance_id()] = true
			check(mesh.get_surface_count() == 1, "Expected single shared-material surface")
			for surface in mesh.get_surface_count():
				check(mesh.surface_get_material(surface) == null, "Embedded runtime material remains")
			var count := mesh.get_faces().size() / 3
			check(count == int(data.triangles[lod]), "Runtime triangles changed")
			check(count < previous_count, "Artist LOD triangle count does not decrease")
			previous_count = count
			totals[lod] += count
			check(CATALOG.bounds_for(model_id).grow(.005).encloses(mesh.get_aabb()), "Combined bounds clip artist LOD")
			check(CATALOG.bounds_for(model_id, lod).grow(.005).encloses(mesh.get_aabb()), "Per-LOD bounds clip mesh")
			check(mesh.get_aabb().grow(.005).encloses(CATALOG.bounds_for(model_id, lod)), "Imported mesh bounds differ from source")
	check(unique_meshes.size() == 36, "Expected 36 distinct cached artist meshes")
	check(unique_materials.size() == 1, "Models do not reuse the shared palette material")
	check(unique_textures.size() == 1, "Models do not reuse the shared palette texture")
	check(totals == [10186, 6402, 2576], "Unexpected catalog geometry budget")
	print("NATURE_VARIETY_CATALOG: ", JSON.stringify({"failures": failures, "models": models.size(), "shared_meshes": unique_meshes.size(), "shared_materials": unique_materials.size(), "shared_textures": unique_textures.size(), "triangles_by_lod": totals}))
	quit(1 if failures else 0)
