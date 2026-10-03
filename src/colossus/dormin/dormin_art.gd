class_name DorminArt
extends RefCounted
## Organic render-only silhouette over Dormin's existing BodySegments and climb patches.
const BONES := [&"hips", &"spine", &"chest", &"neck", &"head", &"upper_arm_l", &"forearm_l", &"hand_l", &"upper_arm_r", &"forearm_r", &"hand_r", &"thigh_l", &"shin_l", &"foot_l", &"thigh_r", &"shin_r", &"foot_r"]
const RANGES := [0.0, 55.0, 140.0, 1800.0]
static var _meshes := {}

static func dress(dormin: Dormin, render_layers := 1) -> void:
	for bone in BONES:
		dress_bone(dormin, bone, render_layers)

static func dress_bone(dormin: Dormin, bone: StringName, render_layers := 1) -> void:
	var segment := dormin._seg_by_bone.get(bone) as BodySegment
	if segment == null:
		push_error("DorminArt requires Dormin._ready(): missing " + String(bone))
		return
	var art := segment.get_node_or_null("DorminArtV3") as Node3D
	if art:
		for visual in art.get_children():
			visual.layers = render_layers
		return
	art = Node3D.new()
	art.name = "DorminArtV3"
	segment.add_child(art)
	for lod in 3:
		var path := "res://models/dormin_v3/%s_lod%d.glb" % [bone, lod]
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
	if art.get_child_count() == 3:
		for child in segment.get_children():
			if child is MeshInstance3D:
				child.hide()

static func _mesh(path: String) -> Mesh:
	if _meshes.has(path):
		return _meshes[path]
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("DorminArt mesh missing: " + path)
		return null
	var imported := packed.instantiate()
	var candidates := imported.find_children("*", "MeshInstance3D", true, false)
	if candidates.size() == 1:
		_meshes[path] = candidates[0].mesh
	imported.free()
	return _meshes.get(path)
