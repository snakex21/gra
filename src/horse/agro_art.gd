class_name AgroArt
extends RefCounted
## Continuous visual-only skin on the production Skeleton3D, with rigid fallback.
const BONES := [&"body", &"neck", &"head", &"fl_up", &"fl_low", &"fl_hoof", &"fr_up", &"fr_low", &"fr_hoof", &"rl_up", &"rl_low", &"rl_hoof", &"rr_up", &"rr_low", &"rr_hoof"]
const RANGES := [0.0, 18.0, 45.0, 1800.0]
static var _meshes := {}
static var _reference_bind_poses := {}
static var _canonical_rests := {}
const SKIN_MATERIAL_ALIASES := {
	"Agro neutral anatomical clay": "agro_dark_bay",
	"Agro detail points": "agro_mane_tail_fibres",
	"Agro core black points": "agro_black_points",
	"Agro core cream star": "agro_cream_star",
	"Agro detail eye": "agro_gloss_eye",
	"Agro detail leather": "agro_worn_leather",
	"Agro detail cloth": "agro_woven_blanket",
	"Agro detail brass": "agro_aged_brass",
	"Agro detail muzzle": "agro_soft_muzzle",
}
static var _skin_palette := {}

## Reuse the established imported PBR materials, including exact texture imports.
## Shared read-only refs avoid one new image copy per skin LOD and preserve finish.
static func skin_palette() -> Dictionary:
	if not _skin_palette.is_empty(): return _skin_palette
	var palette := {}
	for bone in ["body", "head"]:
		var mesh := _mesh("res://models/agro_v3/%s_lod0.glb" % bone)
		if mesh == null: return {}
		for surface in mesh.get_surface_count():
			var mat := mesh.surface_get_material(surface)
			if mat and mat.resource_name in SKIN_MATERIAL_ALIASES.values() and not palette.has(mat.resource_name):
				palette[mat.resource_name] = mat
	if not palette.has("agro_black_points"): return {}
	var fibres := palette["agro_black_points"].duplicate() as StandardMaterial3D
	fibres.resource_name = "agro_mane_tail_fibres"
	fibres.roughness = 0.86
	fibres.metallic_specular = 0.22
	palette["agro_mane_tail_fibres"] = fibres
	for name in SKIN_MATERIAL_ALIASES.values():
		if not palette.has(name): return {}
	_skin_palette = palette
	return palette


static func dress(horse: Horse, render_layers := 1) -> void:
	if _dress_skin(horse, render_layers):
		if not horse.has_node("AgroReins"):
			var reins := AgroReins.new()
			horse.add_child(reins)
			reins.configure(horse)
		(horse.get_node("AgroReins") as AgroReins).straps.layers = render_layers
		# Core skin does not contain hooves. Keep their existing bone-local adapter.
		for bone in BONES:
			if String(bone).ends_with("hoof"):
				dress_bone(horse, bone, render_layers)
		return
	for bone in BONES:
		dress_bone(horse, bone, render_layers)


## Fail closed: missing/malformed skin never removes the established rigid horse.
## Only native Skeleton3D rendering drives this mesh; no new pose/process loop.
static func _dress_skin(horse: Horse, render_layers: int) -> bool:
	var existing := horse.skeleton.get_node_or_null("AgroSkin")
	if existing:
		for visual in existing.get_children():
			if visual is MeshInstance3D: visual.layers = render_layers
		return true
	var root := Node3D.new()
	root.name = "AgroSkin"
	for lod in 3:
		var path := "res://models/agro_skin/agro_lod%d.glb" % lod
		if not ResourceLoader.exists(path): break
		var packed := load(path) as PackedScene
		if packed == null: break
		var imported := packed.instantiate()
		var meshes := imported.find_children("*", "MeshInstance3D", true, false)
		var visual: MeshInstance3D
		if meshes.size() == 1:
			var source := meshes[0] as MeshInstance3D
			var source_rig := source.get_node_or_null(source.skeleton) as Skeleton3D
			var skin := _mapped_skin(source, source_rig, horse.skeleton)
			var palette := skin_palette()
			var materials: Array[Material] = []
			if skin and not palette.is_empty():
				for surface in source.mesh.get_surface_count():
					var authored := source.mesh.surface_get_material(surface)
					if authored == null or not SKIN_MATERIAL_ALIASES.has(authored.resource_name): break
					materials.append(palette[SKIN_MATERIAL_ALIASES[authored.resource_name]])
			if skin and materials.size() == source.mesh.get_surface_count():
				visual = MeshInstance3D.new()
				visual.name = "LOD%d" % lod
				visual.mesh = source.mesh
				for surface in materials.size(): visual.set_surface_override_material(surface, materials[surface])
				visual.skin = skin
				visual.layers = render_layers
				visual.lod_bias = 100.0
				visual.visibility_range_begin = RANGES[lod]
				visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		imported.free()
		if visual == null: break
		root.add_child(visual)
	if root.get_child_count() != 3:
		root.free()
		return false
	horse.skeleton.add_child(root)
	for lod in root.get_child_count():
		var visual := root.get_child(lod) as MeshInstance3D
		visual.skeleton = visual.get_path_to(horse.skeleton)
		# All three validated authored LODs are required before hiding legacy art.
		visual.visibility_range_end = RANGES[lod + 1] if lod + 1 < root.get_child_count() else RANGES[3]
	for bone in BONES:
		if String(bone).ends_with("hoof"): continue
		var frame := horse.get_node_or_null("Vis_" + String(bone)) as Node3D
		if frame: frame.hide()
	return true


## Fixed authored bind pose, never inferred from the horse's current animation pose.
## Geometry is authored in this recorded neutral production pose. Runtime canonical
## bone rests remain unchanged; native skinning uses currentGlobal * inverseNeutral.
static func bind_reference() -> Dictionary:
	if not _reference_bind_poses.is_empty(): return _reference_bind_poses
	var path := "res://assets/agro_skin_neutral_reference.json"
	if not FileAccess.file_exists(path): return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or not data.get("global_pose") is Dictionary or not data.get("canonical_rest") is Dictionary: return {}
	var poses := {}
	var canonical := {}
	for bone in BONES:
		var origin = data.canonical_rest.get(String(bone))
		if not origin is Array or origin.size() != 3: return {}
		for number in origin:
			if not (number is float or number is int) or not is_finite(float(number)): return {}
		canonical[bone] = Transform3D(Basis.IDENTITY, Vector3(origin[0], origin[1], origin[2]))
		var columns = data.global_pose.get(String(bone))
		if not columns is Array or columns.size() != 4: return {}
		var vectors: Array[Vector3] = []
		for column in columns:
			if not column is Array or column.size() != 3: return {}
			for number in column:
				if not (number is float or number is int): return {}
			var vector := Vector3(float(column[0]), float(column[1]), float(column[2]))
			if not vector.is_finite(): return {}
			vectors.append(vector)
		var basis := Basis(vectors[0], vectors[1], vectors[2])
		if not basis.is_equal_approx(basis.orthonormalized()) or not is_equal_approx(basis.determinant(), 1.0): return {}
		poses[bone] = Transform3D(basis, vectors[3])
	_canonical_rests = canonical
	_reference_bind_poses = poses
	return _reference_bind_poses


static func _mapped_skin(source: MeshInstance3D, source_rig: Skeleton3D, target: Skeleton3D) -> Skin:
	if source.mesh == null or source.skin == null or source_rig == null: return null
	if source.mesh.get_surface_count() == 0: return null
	# This asset contract deliberately excludes mesh-space scale/rotation adapters.
	var relative := source_rig.transform.affine_inverse() * source.transform if source.get_parent() == source_rig.get_parent() else source.transform
	if source.get_parent() != source_rig and source.get_parent() != source_rig.get_parent(): return null
	if not relative.is_equal_approx(Transform3D.IDENTITY): return null
	var reference := bind_reference()
	if reference.is_empty(): return null
	var result := Skin.new()
	var names := {}
	for bind in source.skin.get_bind_count():
		var bone_name := source.skin.get_bind_name(bind)
		if bone_name == &"":
			var source_index := source.skin.get_bind_bone(bind)
			if source_index < 0 or source_index >= source_rig.get_bone_count(): return null
			bone_name = source_rig.get_bone_name(source_index)
		var index := target.find_bone(bone_name)
		if index < 0 or names.has(bone_name): return null
		if not _canonical_rests.has(bone_name) or not target.get_bone_global_rest(index).is_equal_approx(_canonical_rests[bone_name]): return null
		var inverse_bind := source.skin.get_bind_pose(bind)
		var source_index := source_rig.find_bone(bone_name)
		if source_index < 0 or not reference.has(bone_name): return null
		if not (source_rig.get_bone_global_rest(source_index) * inverse_bind).is_equal_approx(Transform3D.IDENTITY): return null
		if not ((reference[bone_name] as Transform3D) * inverse_bind).is_equal_approx(Transform3D.IDENTITY): return null
		result.add_named_bind(bone_name, inverse_bind)
		result.set_bind_bone(bind, index)
		names[bone_name] = true
	for bone in BONES:
		if not names.has(bone): return null
	# Require actual normalized weighted vertices, not a mesh merely carrying a Skin.
	for surface in source.mesh.get_surface_count():
		var arrays := source.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var weights = arrays[Mesh.ARRAY_WEIGHTS]
		var joints = arrays[Mesh.ARRAY_BONES]
		if vertices.is_empty() or weights == null or joints == null: return null
		var count: int = weights.size() / vertices.size()
		if count not in [4, 8] or joints.size() != weights.size() or weights.size() != vertices.size() * count: return null
		for vertex in vertices.size():
			var total := 0.0
			for influence in count:
				var offset: int = vertex * count + influence
				if joints[offset] < 0 or joints[offset] >= result.get_bind_count() or not is_finite(weights[offset]) or weights[offset] < 0: return null
				total += weights[offset]
			if absf(total - 1.0) > 0.002: return null
	return result


static func dress_bone(horse: Horse, bone: StringName, render_layers := 1) -> void:
	var frame := horse.get_node_or_null("Vis_" + String(bone)) as Node3D
	if frame == null:
		push_error("AgroArt requires Horse._ready(): missing " + String(bone))
		return
	var art := frame.get_node_or_null("AgroArtV3") as Node3D
	if art:
		for visual in art.get_children():
			visual.layers = render_layers
		return
	art = Node3D.new()
	art.name = "AgroArtV3"
	frame.add_child(art)
	for lod in 3:
		var path := "res://models/agro_v3/%s_lod%d.glb" % [bone, lod]
		var mesh := _mesh(path)
		if mesh == null:
			continue
		var visual := MeshInstance3D.new()
		visual.name = "LOD%d" % lod
		visual.mesh = mesh
		visual.layers = render_layers
		visual.lod_bias = 100.0
		visual.visibility_range_begin = RANGES[lod]
		visual.visibility_range_end = RANGES[lod + 1]
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		art.add_child(visual)
	# Only legacy visual meshes are hidden. Vis_* attachment nodes and all physics live on.
	if art.get_child_count() == 3:
		for child in frame.get_children():
			if child is MeshInstance3D:
				child.hide()

static func _mesh(path: String) -> Mesh:
	if _meshes.has(path):
		return _meshes[path]
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("AgroArt mesh missing: " + path)
		return null
	var imported := packed.instantiate()
	var candidates := imported.find_children("*", "MeshInstance3D", true, false)
	if candidates.size() == 1:
		_meshes[path] = candidates[0].mesh
	imported.free()
	return _meshes.get(path)
