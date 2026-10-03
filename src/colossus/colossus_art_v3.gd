class_name ColossusArtV3
extends Node3D
## Render-only sculptures on existing rigid segments. No collision or bone writes.
## Invoke after older art: ColossusArtV3.dress(c, &"valus"). Returns attached segments.
const ATLAS := preload("res://materials/colossi_v3/atlas.tres")
const Asset = preload("res://art/scripts/art_asset.gd")
static var _manifest := {}
static var _entries := {}
var _gates: Array[Dictionary] = []

static func dress(c: Colossus, kind: StringName) -> int:
	if c == null:
		return 0
	if kind == &"celosia_cenobia":
		var count := 0
		for child in c.get_children():
			if child is PairedSentinel:
				count += dress(child, &"celosia" if child.index == 0 else &"cenobia")
		return count
	if c.get_node_or_null("ColossiV3Render") != null:
		return 0
	_load_manifest()
	if not _manifest.profiles.has(String(kind)):
		return 0
	# Fail closed: an changed gameplay skeleton must keep its existing visual.
	for seg: BodySegment in c.segments:
		if not _entries.has(_id(kind, seg.bone_name)):
			push_warning("Colossi V3 has no matching sculpture: %s/%s" % [kind, seg.bone_name])
			return 0
	var render := ColossusArtV3.new()
	render.name = "ColossiV3Render"
	c.add_child(render)
	var count := 0
	for seg: BodySegment in c.segments:
		var id := _id(kind, seg.bone_name)
		for child in seg.get_children():
			if child is MeshInstance3D and child.mesh is PrimitiveMesh:
				child.visible = false
			elif child is Node3D and (String(child.name) in ["ArtVisual", "SentinelV2Visual", "GuardianVisual", "GuardianArt"]):
				child.visible = false
		var art := Node3D.new()
		art.name = "ColossiV3Visual"
		seg.add_child(art)
		_add_lods(art, id, seg)
		count += 1
		if _entries.has(id + "_grip"):
			var wool := Node3D.new()
			wool.name = "UnlockedWool"
			art.add_child(wool)
			_add_lods(wool, id + "_grip", seg)
			var patches: Array[ClimbPatch] = []
			for spec: Dictionary in _entries[id + "_grip"].patches:
				var at := Vector3(spec.at[0], spec.at[1], spec.at[2])
				for child in seg.get_children():
					if child is ClimbPatch and child.position.distance_to(at) < 0.03:
						patches.append(child)
			render._gates.append({"visual": wool, "patches": patches})
	render._process(0)
	render.set_process(not render._gates.is_empty())
	c.set_meta(&"colossi_v3_profile", kind)
	c.set_meta(&"colossi_v3_triangles", _manifest.profiles[String(kind)].lod_triangles)
	return count

static func _load_manifest() -> void:
	if not _manifest.is_empty():
		return
	_manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/colossi_v3_manifest.json"))
	for entry: Dictionary in _manifest.assets:
		_entries[entry.id] = entry

static func _id(kind: StringName, bone: StringName) -> String:
	return "%s_%s" % [kind, String(bone).replace("-", "m")]

static func _add_lods(root: Node3D, id: String, seg: BodySegment) -> void:
	var layer := 1
	for child in seg.get_children():
		if child is MeshInstance3D:
			layer = child.layers
			break
	for level in 3:
		var mesh := MeshInstance3D.new()
		mesh.name = "LOD%d" % level
		mesh.mesh = Asset.mesh_for(id, level, "colossi_v3")
		mesh.material_override = ATLAS
		mesh.layers = layer
		mesh.lod_bias = 100
		mesh.visibility_range_begin = [0.0, 55.0, 125.0][level]
		mesh.visibility_range_end = [55.0, 125.0, 0.0][level]
		root.add_child(mesh)

func _process(_delta: float) -> void:
	for gate: Dictionary in _gates:
		var open: bool = not gate.patches.is_empty()
		for patch: ClimbPatch in gate.patches:
			open = open and is_instance_valid(patch) and not patch.disabled
		(gate.visual as Node3D).visible = open
