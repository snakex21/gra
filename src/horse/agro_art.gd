class_name AgroArt
extends RefCounted
## Bone-local Blender art. The horse's existing Vis_* nodes keep driving every pose.
const BONES := [&"body", &"neck", &"head", &"fl_up", &"fl_low", &"fl_hoof", &"fr_up", &"fr_low", &"fr_hoof", &"rl_up", &"rl_low", &"rl_hoof", &"rr_up", &"rr_low", &"rr_hoof"]
const RANGES := [0.0, 18.0, 45.0, 1800.0]
static var _meshes := {}

static func dress(horse: Horse, render_layers := 1) -> void:
	for bone in BONES:
		dress_bone(horse, bone, render_layers)

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
