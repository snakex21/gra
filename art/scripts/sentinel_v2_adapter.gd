extends Node
## One-way VISUAL adapter. Existing BodySegments own animation and collision.
## No physics process, bone writes, ClimbPatch edits, grip logic or player access.

const Asset = preload("res://art/scripts/art_asset.gd")
const ATLAS := preload("res://materials/sentinel_v2/atlas.tres")
const SEGMENTS := ["hips", "spine", "chest", "neck", "head", "upper_arm_l", "forearm_l", "hand_l", "upper_arm_r", "forearm_r", "hand_r", "thigh_l", "shin_l", "foot_l", "thigh_r", "shin_r", "foot_r"]
@export var target_path: NodePath
var attached_count := 0
var selected_foot_variant := "baseline_2_8m"
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
	var extended_feet := false
	var constants: Dictionary=target.get_script().get_script_constant_map()
	for part in constants.get("PARTS",[]):
		if str(part[0])=="foot_l" and part[2] is Vector3:
			extended_feet=is_equal_approx(part[2].z,3.6) and is_equal_approx(part[3].z,-.85)
	selected_foot_variant="extended_3_6m" if extended_feet else "baseline_2_8m"
	for bone in SEGMENTS:
		var segment := target.get_node("Seg_" + bone)
		for child in segment.get_children():
			if child is MeshInstance3D:
				_original_visibility[child] = child.visible
				child.visible = false
		var art := Node3D.new()
		art.name = "SentinelV2Visual"
		segment.add_child(art)
		_attached.append(art)
		for level in 3:
			var mesh := MeshInstance3D.new()
			mesh.name = "LOD%d" % level
			var model_id: String="sentinel_"+bone
			if extended_feet and bone in ["foot_l","foot_r"]:model_id+="_extended"
			mesh.mesh = Asset.mesh_for(model_id, level, "sentinel_v2")
			mesh.lod_bias = 100.0
			mesh.material_override = ATLAS
			mesh.visibility_range_begin = [0.0, 48.0, 100.0][level]
			mesh.visibility_range_end = [48.0, 100.0, 300.0][level]
			art.add_child(mesh)
		attached_count += 1
	print("SENTINEL_V2_ADAPTER_OK: %d rigid visuals attached; physics and skeleton unchanged" % attached_count)


func _exit_tree() -> void:
	for visual in _original_visibility:
		if is_instance_valid(visual):
			visual.visible = _original_visibility[visual]
	for node in _attached:
		if is_instance_valid(node):
			node.queue_free()
