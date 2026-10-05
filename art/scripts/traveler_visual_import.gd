@tool
extends EditorScenePostImport
## Godot 4.6.3 ignores KHR_materials_specular on GLB import. Preserve authored
## dielectric reflectance here, once at import. No runtime material mutation.
func _post_import(scene: Node) -> Object:
	_apply(scene)
	return scene

func _apply(node: Node) -> void:
	if node is MeshInstance3D and node.mesh:
		for index in node.mesh.get_surface_count():
			var material := node.mesh.surface_get_material(index) as StandardMaterial3D
			if material:
				match material.resource_name:
					"Traveler_skin_restrained_specular": material.metallic_specular = 0.24
					"Traveler_matte_hair_fibres": material.metallic_specular = 0.16
	for child in node.get_children(): _apply(child)
