extends RefCounted
## Export-only CPU snapshot of Godot 4.6's loaded 3D skin deformation.
## Never changes the source mesh, its Skin, Skeleton3D, or shared materials.
## Renderer reference: godotengine/godot 4.6.3-stable,
## drivers/gles3/shaders/skeleton.glsl:224-246 (also renderer_rd/shaders/skeleton.glsl).
## Directions use normalize(sum(weight * deformation.basis * direction)), exactly
## like the renderer, including nonuniform scale. This is deliberately NOT an
## inverse-transpose correction or the built-in CPU bake's orthonormalized basis.

static func digest(value: Variant) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(var_to_bytes(value))
	return hashing.finish().hex_encode()

static func _vec(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

static func _xf(t: Transform3D) -> Array:
	return [_vec(t.basis.x), _vec(t.basis.y), _vec(t.basis.z), _vec(t.origin)]

static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}

static func _has_array(arrays: Array, slot: int) -> bool:
	return arrays[slot] != null and arrays[slot].size() > 0

static func _geometry(arrays: Array) -> Array:
	return [arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_NORMAL], arrays[Mesh.ARRAY_TANGENT]]

static func _has_modifier(node: Node) -> bool:
	for child in node.get_children():
		if child is SkeletonModifier3D or _has_modifier(child): return true
	return false

static func bake(original: MeshInstance3D) -> Dictionary:
	if original == null or original.mesh == null:
		return _failure("Missing source MeshInstance3D or mesh")
	var source := original.mesh
	var morphs: Array = []
	for index in original.get_blend_shape_count():
		var weight := original.get_blend_shape_value(index)
		if not is_finite(weight) or weight != 0.0:
			return _failure("Nonzero blend shapes are unsupported; refusing a rest-pose snapshot: " + str(original.name))
		morphs.append({"name": str((source as ArrayMesh).get_blend_shape_name(index)), "weight": weight})
	if source.get_surface_count() == 0:
		return _failure("Source mesh has no surfaces: " + str(original.name))
	var skinned := false
	var source_arrays: Array[Array] = []
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		if arrays.size() != Mesh.ARRAY_MAX:
			return _failure("Malformed source surface array: %s/%d" % [original.name, surface])
		var has_bones := _has_array(arrays, Mesh.ARRAY_BONES)
		var has_weights := _has_array(arrays, Mesh.ARRAY_WEIGHTS)
		if has_bones != has_weights:
			return _failure("Unpaired bone/weight arrays: %s/%d" % [original.name, surface])
		skinned = skinned or has_bones
		source_arrays.append(arrays)

	if skinned and not morphs.is_empty():
		return _failure("Combined skin and blend-shape meshes are unsupported")
	var rebuild := skinned or not morphs.is_empty()
	var proof := {"method": "unskinned_duplicate" if morphs.is_empty() else "verified_zero_weight_blend_shape_snapshot", "skinned": skinned, "source_mesh": source.resource_path, "blend_shapes": morphs, "surfaces": []}
	var transforms: Array[Transform3D] = []
	if skinned:
		if not source is ArrayMesh or not original.is_inside_tree():
			return _failure("Skinned snapshot requires an in-tree ArrayMesh instance")
		var skeleton := original.get_node_or_null(original.skeleton) as Skeleton3D
		if skeleton == null or skeleton.get_bone_count() == 0:
			return _failure("Missing or empty Skeleton3D: " + str(original.name))
		if _has_modifier(skeleton):
			return _failure("SkeletonModifier3D pose restoration is unsupported; refusing potentially stale pose")
		var skin_reference := original.get_skin_reference()
		if skin_reference == null:
			return _failure("Skin is not registered with the source Skeleton3D")
		var skin := skin_reference.get_skin()
		if skin == null or skin.get_bind_count() == 0:
			return _failure("Missing or empty registered Skin")
		if original.skin != null and skin != original.skin:
			return _failure("Registered Skin differs from the explicit mesh Skin")
		var bindings: Array = []
		for bind_index in skin.get_bind_count():
			var bind_name := skin.get_bind_name(bind_index)
			var bone_index := skeleton.find_bone(bind_name) if not bind_name.is_empty() else skin.get_bind_bone(bind_index)
			if bone_index < 0 or bone_index >= skeleton.get_bone_count():
				return _failure("Unresolvable Skin binding %d (%s); refusing Godot's bone-zero fallback" % [bind_index, bind_name])
			var pose := skeleton.get_bone_global_pose(bone_index)
			var inverse_bind := skin.get_bind_pose(bind_index)
			var deformation := pose * inverse_bind
			if not pose.is_finite() or not inverse_bind.is_finite() or not deformation.is_finite():
				return _failure("Nonfinite bone transform in binding %d" % bind_index)
			if absf(deformation.basis.determinant()) < 0.00000001:
				return _failure("Singular bone deformation in binding %d" % bind_index)
			transforms.append(deformation)
			bindings.append({"bind_index": bind_index, "bind_name": str(bind_name), "bind_bone_index": skin.get_bind_bone(bind_index), "resolved_bone_index": bone_index, "resolved_bone_name": str(skeleton.get_bone_name(bone_index)), "bone_parent_index": skeleton.get_bone_parent(bone_index), "bone_enabled": skeleton.is_bone_enabled(bone_index), "bone_global_rest": _xf(skeleton.get_bone_global_rest(bone_index)), "bone_global_pose": _xf(pose), "inverse_bind": _xf(inverse_bind), "deformation": _xf(deformation)})
		proof.merge({"method": "godot_4_6_renderer_linear_blend_skinning_cpu", "direction_method": "normalized_weighted_deformation_basis; tangent_handedness_preserved", "coordinate_contract": "mesh-local skin arrays; clone retains original MeshInstance3D global transform", "shader_reference": "https://github.com/godotengine/godot/blob/4.6.3-stable/drivers/gles3/shaders/skeleton.glsl#L224-L246", "skin_source": skin.resource_path, "skin_name": skin.resource_name, "skin_origin": "explicit" if original.skin != null else "registered_implicit_rest_skin", "skin_bind_count": skin.get_bind_count(), "skeleton_path": str(original.skeleton), "skeleton_node_path": str(skeleton.get_path()), "skeleton_global_transform": _xf(skeleton.global_transform), "bindings": bindings, "bindings_sha256": digest(bindings)}, true)

	var baked: Mesh = ArrayMesh.new() if rebuild else source.duplicate(false)
	for surface in source_arrays.size():
		var arrays: Array = source_arrays[surface]
		var original_hash := digest(arrays)
		var posed_arrays := arrays.duplicate(true)
		var surface_skinned := _has_array(arrays, Mesh.ARRAY_BONES)
		if surface_skinned:
			var result := _bake_arrays(arrays, transforms, (source as ArrayMesh).surface_get_format(surface))
			if not result.ok: return _failure("%s/%d: %s" % [original.name, surface, result.error])
			posed_arrays = result.arrays
		if rebuild:
			# Keep custom-attribute formats and primitive type. Remove skin flags and
			# lossy attribute compression: skinning is already applied to these arrays.
			var format := (source as ArrayMesh).surface_get_format(surface)
			format &= ~(Mesh.ARRAY_FORMAT_BONES | Mesh.ARRAY_FORMAT_WEIGHTS | Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS | Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
			(baked as ArrayMesh).add_surface_from_arrays((source as ArrayMesh).surface_get_primitive_type(surface), posed_arrays, [], {}, format)
			if baked.get_surface_count() != surface + 1:
				return _failure("Godot rejected the baked surface")
			(baked as ArrayMesh).surface_set_name(surface, (source as ArrayMesh).surface_get_name(surface))
		var material := original.get_active_material(surface)
		if material != null:
			# Export may inspect/change material metadata; give it a private copy.
			# Texture resources remain shared read-only to avoid duplicating the atlas.
			baked.surface_set_material(surface, material.duplicate(false))
		var uploaded_arrays := baked.surface_get_arrays(surface)
		if digest(source.surface_get_arrays(surface)) != original_hash:
			return _failure("Source arrays mutated during skin baking")
		proof.surfaces.append({"surface": surface, "skinned": surface_skinned, "source_array_sha256": original_hash, "baked_array_sha256": digest(uploaded_arrays), "source_geometry_sha256": digest(_geometry(arrays)), "baked_geometry_sha256": digest(_geometry(uploaded_arrays)), "cpu_pose_geometry_sha256": digest(_geometry(posed_arrays)), "source_bones_sha256": digest(arrays[Mesh.ARRAY_BONES]), "source_weights_sha256": digest(arrays[Mesh.ARRAY_WEIGHTS]), "source_vertices": arrays[Mesh.ARRAY_VERTEX].size(), "baked_vertices": uploaded_arrays[Mesh.ARRAY_VERTEX].size(), "skin_arrays_removed": not _has_array(uploaded_arrays, Mesh.ARRAY_BONES) and not _has_array(uploaded_arrays, Mesh.ARRAY_WEIGHTS), "source_unchanged": true})
	return {"ok": true, "mesh": baked, "proof": proof}

static func _bake_arrays(arrays: Array, transforms: Array[Transform3D], format: int) -> Dictionary:
	if not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
		return _failure("Only 3D vertex arrays are supported")
	if not arrays[Mesh.ARRAY_BONES] is PackedInt32Array or not arrays[Mesh.ARRAY_WEIGHTS] is PackedFloat32Array:
		return _failure("Unsupported bone/weight array types")
	if arrays[Mesh.ARRAY_NORMAL] != null and not arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array:
		return _failure("Unsupported normal array type")
	if arrays[Mesh.ARRAY_TANGENT] != null and not arrays[Mesh.ARRAY_TANGENT] is PackedFloat32Array:
		return _failure("Unsupported tangent array type")
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals := PackedVector3Array() if arrays[Mesh.ARRAY_NORMAL] == null else arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
	var tangents := PackedFloat32Array() if arrays[Mesh.ARRAY_TANGENT] == null else arrays[Mesh.ARRAY_TANGENT] as PackedFloat32Array
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var count := vertices.size()
	var influence_count := 8 if format & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS else 4
	if count == 0 or bones.size() != count * influence_count or weights.size() != bones.size():
		return _failure("Malformed skin array lengths")
	if normals.size() not in [0, count] or tangents.size() not in [0, count * 4]:
		return _failure("Malformed normal/tangent array lengths")
	var positions_out := vertices.duplicate()
	var normals_out := normals.duplicate()
	var tangents_out := tangents.duplicate()
	for vertex_index in count:
		var position := Vector3.ZERO
		var normal := Vector3.ZERO
		var tangent := Vector3.ZERO
		var source_tangent := Vector3.ZERO
		if not tangents.is_empty():
			source_tangent = Vector3(tangents[vertex_index * 4], tangents[vertex_index * 4 + 1], tangents[vertex_index * 4 + 2])
			if not is_finite(tangents[vertex_index * 4 + 3]) or absf(absf(tangents[vertex_index * 4 + 3]) - 1.0) > 0.0001:
				return _failure("Malformed tangent handedness")
		var total_weight := 0.0
		for influence in influence_count:
			var slot := vertex_index * influence_count + influence
			var bind_index := bones[slot]
			var weight := weights[slot]
			# Validate all indices, even zero-weight slots: GPU shaders fetch them too.
			if bind_index < 0 or bind_index >= transforms.size() or not is_finite(weight) or weight < 0.0 or weight > 1.0001:
				return _failure("Invalid skin bind index or weight at vertex %d" % vertex_index)
			total_weight += weight
			var deformation: Transform3D = transforms[bind_index]
			position += (deformation * vertices[vertex_index]) * weight
			if not normals.is_empty(): normal += (deformation.basis * normals[vertex_index]) * weight
			if not tangents.is_empty(): tangent += (deformation.basis * source_tangent) * weight
		# Loaded 16-bit weight quantization is allowed; never silently renormalize.
		if absf(total_weight - 1.0) > 0.001:
			return _failure("Unnormalized or zero skin weights at vertex %d" % vertex_index)
		if not position.is_finite(): return _failure("Nonfinite posed vertex")
		positions_out[vertex_index] = position
		if not normals.is_empty():
			if not normal.is_finite() or normal.length_squared() < 0.000000000001: return _failure("Degenerate posed normal")
			normals_out[vertex_index] = normal.normalized()
		if not tangents.is_empty():
			if not tangent.is_finite() or tangent.length_squared() < 0.000000000001: return _failure("Degenerate posed tangent")
			tangent = tangent.normalized()
			tangents_out[vertex_index * 4] = tangent.x
			tangents_out[vertex_index * 4 + 1] = tangent.y
			tangents_out[vertex_index * 4 + 2] = tangent.z
	var result := arrays.duplicate(true)
	result[Mesh.ARRAY_VERTEX] = positions_out
	if not normals.is_empty(): result[Mesh.ARRAY_NORMAL] = normals_out
	if not tangents.is_empty(): result[Mesh.ARRAY_TANGENT] = tangents_out
	result[Mesh.ARRAY_BONES] = null
	result[Mesh.ARRAY_WEIGHTS] = null
	return {"ok": true, "arrays": result}
