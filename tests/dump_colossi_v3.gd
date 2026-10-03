extends Node
const KINDS := ["valus", "quadratus", "gaius", "phaedra", "avion", "barba", "hydrus", "kuromori", "basaran", "dirge", "celosia_cenobia", "pelagia", "phalanx", "argus", "malus", "devil", "phoenix", "spider", "worm", "saru"]
var contracts := {}

func _ready() -> void:
	Sfx.enabled = false
	Fx.enabled = false
	for kind: String in KINDS:
		var root := Node3D.new()
		add_child(root)
		var script := load("res://src/colossus/%s/%s.gd" % [kind, kind]) as Script
		var colossus := script.new() as Colossus
		root.add_child(colossus)
		root.process_mode = Node.PROCESS_MODE_DISABLED
		_dump(colossus, kind)
		root.free()
	var file := FileAccess.open("res://assets/colossi_v3_contracts.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(contracts, "  "))
	file.close()
	print("COLLOSSI_V3_CONTRACTS ", contracts.size())
	get_tree().quit()

func _dump(c: Colossus, kind: String) -> void:
	if kind == "celosia_cenobia":
		for child in c.get_children():
			if child is PairedSentinel:
				_dump(child, "celosia" if child.index == 0 else "cenobia")
		return
	var segments := []
	for seg: BodySegment in c.segments:
		var parts := []
		var patches := []
		for child in seg.get_children():
			if child is MeshInstance3D and child.mesh is PrimitiveMesh:
				var size: Vector3 = child.mesh.get_aabb().size
				var material_kind := int(child.get_meta(&"kind", 1))
				for collision in seg.get_children():
					if collision is ClimbPatch and collision.position.distance_to(child.position) < 0.05:
						if not child.has_meta(&"guardian_placeholder") and (collision.shape.get_debug_mesh().get_aabb().size - size).length() < 0.03:
							material_kind = 0
				parts.append({"size": _v(size), "at": _v(child.position), "rotation": _v(child.rotation), "kind": material_kind, "primitive": child.mesh.get_class()})
			if child is ClimbPatch:
				patches.append({"size": _v(child.shape.get_debug_mesh().get_aabb().size), "at": _v(child.position), "disabled": child.disabled})
		var pose := c.skeleton.get_bone_global_pose(seg.bone_idx)
		segments.append({"bone": String(seg.bone_name), "at": _v(pose.origin), "basis": [_v(pose.basis.x), _v(pose.basis.y), _v(pose.basis.z)], "parts": parts, "patches": patches})
	contracts[kind] = {"segments": segments}

func _v(v: Vector3) -> Array:
	return [v.x, v.y, v.z]
