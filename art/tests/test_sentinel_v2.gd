extends Node
## Art-owned contract tests. Original gameplay tests remain untouched.

const Asset = preload("res://art/scripts/art_asset.gd")
const Adapter = preload("res://art/scripts/sentinel_v2_adapter.gd")
const Humanoid = preload("res://src/colossus/greybox/greybox_humanoid.gd")
var failures: Array[String] = []
var checks := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/sentinel_v2_manifest.json"))
	check(manifest.assets.size() == 17, "17 v2 visual segments in manifest")
	for asset: Dictionary in manifest.assets:
		var category := "sentinel_v2" if asset.category == "colossus" else "environment"
		var previous := 1000000
		for level in 3:
			var mesh := Asset.mesh_for(asset.id, level, category)
			check(mesh != null, "%s LOD%d imported" % [asset.id,level])
			if mesh == null:
				continue
			var faces := mesh.get_faces()
			check(faces.size() > 0, "%s LOD%d nonempty" % [asset.id,level])
			check(faces.size()/3 <= previous, "%s LOD%d reduces geometry" % [asset.id,level])
			previous = faces.size()/3
			check(mesh.get_surface_count() == 1, "%s shares a single atlas surface" % asset.id)
			var finite := true
			for v in faces:
				finite = finite and v.is_finite()
			check(finite, "%s finite vertices" % asset.id)
			var box := mesh.get_aabb()
			check(box.size.length() < 100, "%s dimensions in metres" % asset.id)
		if category == "environment":
			var prefab := load("res://environment/prefabs/%s.tscn" % asset.id) as PackedScene
			var instance := prefab.instantiate()
			add_child(instance)
			check(instance.get_node_or_null("LOD0") != null,"%s prefab ready" % asset.id)
			check(instance.get_node("LOD0").visibility_range_end == instance.get_node("LOD1").visibility_range_begin,"%s LOD ranges meet" % asset.id)
			instance.free()
	for filename in ["saltward_atlas_albedo", "grass_albedo", "grass_normal", "soil_albedo", "soil_normal", "rock_albedo", "rock_normal", "sand_albedo", "sand_normal", "path_albedo", "path_normal", "ruin_stone_albedo", "ruin_stone_normal"]:
		var texture := load("res://textures/environment/%s.png" % filename) as Texture2D
		check(texture != null and texture.get_width() <= 1024 and texture.get_height() <= 1024,"Texture budget: " + filename)
	var colossus := Node3D.new()
	colossus.set_script(Humanoid)
	colossus.name = "ContractColossus"
	colossus.debug_override = &"walk"
	add_child(colossus)
	var collision_snapshot: Dictionary = {}
	var originals: Array = []
	for segment in colossus.segments:
		for node in segment.get_children():
			if node is CollisionShape3D:
				collision_snapshot[node] = [node.shape,node.transform,node.disabled]
			if node is MeshInstance3D:
				originals.append(node)
	var skeleton_id: int = colossus.skeleton.get_instance_id()
	var visual := Node.new()
	visual.set_script(Adapter)
	visual.target_path = NodePath("../ContractColossus")
	add_child(visual)
	await get_tree().process_frame
	check(visual.attached_count == 17,"Adapter attaches to 17 existing segments")
	var extended_expected: bool=is_equal_approx(Humanoid.PARTS[-1][2].z,3.6)
	check(visual.selected_foot_variant == ("extended_3_6m" if extended_expected else "baseline_2_8m"),"Foot visual variant matches actual gameplay constant")
	check(colossus.skeleton.get_instance_id() == skeleton_id,"Adapter preserves original skeleton identity")
	check(colossus.skeleton.get_bone_count() == 17,"Original 17-bone contract")
	for original in originals:
		check(not original.visible,"Greybox render mesh hidden by adapter")
	for node in collision_snapshot:
		check(node.shape == collision_snapshot[node][0] and node.transform == collision_snapshot[node][1] and node.disabled == collision_snapshot[node][2],"Physics shape unchanged: " + str(node.get_path()))
	for frame in 30:
		await get_tree().physics_frame
	for segment in colossus.segments:
		var art := segment.get_node("SentinelV2Visual") as Node3D
		check(art.transform.is_equal_approx(Transform3D.IDENTITY),"Rigid art is in segment-local coordinates")
		check(art.global_transform.is_equal_approx(segment.global_transform),"Art follows animated segment without independent pose logic")
	visual.free()
	await get_tree().process_frame
	for original in originals:
		check(original.visible,"Removing adapter restores greybox")
	colossus.free()
	if failures.is_empty():
		print("SENTINEL_V2_TESTS_OK: %d checks passed" % checks)
	else:
		print("SENTINEL_V2_TESTS_FAILED: %d / %d\n%s" % [failures.size(),checks,"\n".join(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
