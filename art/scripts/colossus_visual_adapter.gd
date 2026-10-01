extends Node
## One-way VISUAL adapter. Existing BodySegments own animation and collision.
## No physics process, bone writes, ClimbPatch edits, grip logic or player access.

const Asset = preload("res://art/scripts/art_asset.gd")
const ATLAS := preload("res://materials/environment/shared_atlas.tres")
const SEGMENTS := ["hips", "spine", "chest", "neck", "head", "upper_arm_l", "forearm_l", "hand_l", "upper_arm_r", "forearm_r", "hand_r", "thigh_l", "shin_l", "foot_l", "thigh_r", "shin_r", "foot_r"]
@export var target_path: NodePath
var attached_count := 0
var _original_visibility: Dictionary = {}
var _attached: Array[Node] = []


func _ready() -> void:
	call_deferred("attach_visuals")


func attach_visuals() -> void:
	if attached_count > 0:
		return
	var target := get_node_or_null(target_path)
	if target == null:
		push_error("Sentinel visual adapter requires an existing colossus target")
		return
	# Fail closed on a changed contract. Never partially replace the greybox.
	for bone in SEGMENTS:
		if target.get_node_or_null("Seg_" + bone) == null:
			push_warning("Sentinel art not attached: missing segment Seg_" + bone)
			return
	for bone in SEGMENTS:
		var segment := target.get_node("Seg_" + bone)
		for child in segment.get_children():
			if child is MeshInstance3D:
				_original_visibility[child] = child.visible
				child.visible = false
		var art := Node3D.new()
		art.name = "SaltwardVisual"
		segment.add_child(art)
		_attached.append(art)
		for level in 3:
			var mesh := MeshInstance3D.new()
			mesh.name = "LOD%d" % level
			mesh.mesh = Asset.mesh_for("sentinel_" + bone, level, "colossus")
			mesh.lod_bias = 100.0
			mesh.material_override = ATLAS
			mesh.visibility_range_begin = [0.0, 48.0, 100.0][level]
			mesh.visibility_range_end = [48.0, 100.0, 300.0][level]
			art.add_child(mesh)
		attached_count += 1
	print("ART_ADAPTER_OK: %d rigid visuals attached; physics and skeleton unchanged" % attached_count)


func _exit_tree() -> void:
	for visual in _original_visibility:
		if is_instance_valid(visual):
			visual.visible = _original_visibility[visual]
	for node in _attached:
		if is_instance_valid(node):
			node.queue_free()
