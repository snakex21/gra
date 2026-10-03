class_name GuardianVisuals
extends RefCounted
## Independent bone visuals, static shared Mesh cache, no collision.
static var _meshes := {}
static func dress(c: WingedGuardian, kind: String) -> void:
	for bone in [&"body", &"wing_l", &"wing_r"]:
		var segment: BodySegment = c._seg_by_bone[bone]
		for child in segment.get_children():
			if child is MeshInstance3D and child.has_meta(&"guardian_placeholder"):
				child.visible = false
		if segment.has_node("GuardianArt"):
			continue
		var root := Node3D.new()
		root.name = "GuardianArt"
		segment.add_child(root)
		for lod in 3:
			var key := "%s/%s/%d" % [kind, bone, lod]
			if not _meshes.has(key):
				var packed := load("res://models/%s/%s_lod%d.glb" % [kind, bone, lod]) as PackedScene
				if packed == null:
					continue
				var imported := packed.instantiate()
				var meshes := imported.find_children("*", "MeshInstance3D", true, false)
				if meshes.size() == 1:
					_meshes[key] = meshes[0].mesh
					if bone != &"body":
						# Thin membranes still cast onto the cave, but receiving their own
						# spot-light shadow creates bands on the near-coincident faces.
						var wing_mesh: Mesh = _meshes[key]
						for surface in wing_mesh.get_surface_count():
							var material := wing_mesh.surface_get_material(surface) as StandardMaterial3D
							if material:
								var copy := material.duplicate() as StandardMaterial3D
								copy.disable_receive_shadows = true
								wing_mesh.surface_set_material(surface, copy)
				imported.free()
			if not _meshes.has(key):
				continue
			var visual := MeshInstance3D.new()
			visual.name = "LOD%d" % lod
			visual.mesh = _meshes[key]
			visual.layers = 2 if kind == "devil" else 1
			visual.lod_bias = 100
			visual.visibility_range_begin = [0, 45, 100][lod]
			visual.visibility_range_end = [45, 100, 800][lod]
			visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(visual)
