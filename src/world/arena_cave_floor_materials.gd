class_name ArenaCaveFloorMaterials
extends RefCounted
## Layout-5-only Hollowvault soil finish. The variant keeps every non-soil atlas
## texel and all material settings unchanged: this is not a whole-mesh ground
## projection. Shared kit meshes, original materials and Deeprelic stay intact.
const MATERIAL_PATH := "res://materials/arena_cave/hollowvault_floor.tres"
const SUPPORT := preload("res://materials/arena_cave/support_cutout.tres")
const KIT_PATH := "res://art/scripts/hollowvault_asset.gd"
const ORIGINAL_PATH := "res://materials/hollowvault/atlas.tres"
static var _materials := {}
static var _requests := {}

static func material_for(arena: String) -> StandardMaterial3D:
	if arena not in ["cave", "devil"]: return null
	if not _materials.has("shared"):
		_materials["shared"] = load(MATERIAL_PATH) as StandardMaterial3D
	return _materials["shared"]

static func _material_ready(_arena: String) -> bool:
	if _materials.has("shared"): return true
	if not _requests.has("shared"):
		_requests["shared"] = ResourceLoader.load_threaded_request(MATERIAL_PATH, "Material")
		if _requests["shared"] != OK:
			push_error("Cave floor atlas request failed")
			return true
		return false
	if _requests["shared"] != OK: return true
	var status := ResourceLoader.load_threaded_get_status(MATERIAL_PATH)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS: return false
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		_requests["shared"] = ERR_CANT_OPEN
		push_error("Cave floor atlas load failed")
		return true
	var material := ResourceLoader.load_threaded_get(MATERIAL_PATH) as StandardMaterial3D
	if material == null:
		_requests["shared"] = ERR_INVALID_DATA
		push_error("Invalid Cave floor atlas material")
		return true
	_materials["shared"] = material
	return true

static func _targets(parent: Node3D, _arena: String) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for node: Node in parent.get_children():
		if not node is Node3D or not node.get_script() is GDScript: continue
		if node.get_script().resource_path != KIT_PATH: continue
		if not node.visible or not node.basis.is_equal_approx(Basis.IDENTITY): continue
		var id := String(node.get("model_id"))
		var allowed: bool = id == "great_closed_dome" and node.position.is_equal_approx(Vector3.ZERO)
		if id == "vault_tunnel_12m":
			for i in 12:
				if node.position.is_equal_approx(Vector3(0, 0, 35.5 + i * 11.5)): allowed = true
		if not allowed: continue
		for level in 3:
			var mesh := node.get_node_or_null("LOD%d" % level) as MeshInstance3D
			if mesh == null or not mesh.visible or not mesh.mesh or mesh.mesh.get_surface_count() != 1: continue
			if not is_equal_approx(mesh.visibility_range_begin, [0.0,65.0,150.0][level]) or not is_equal_approx(mesh.visibility_range_end, [65.0,150.0,800.0][level]): continue
			if not mesh.transform.is_equal_approx(Transform3D.IDENTITY): continue
			# Pin the shared authored mesh and material. Future replacements fail closed.
			if mesh.mesh != node.get_script().mesh_for(id, level): continue
			if mesh.material_override == null or mesh.material_override.resource_path not in [ORIGINAL_PATH, MATERIAL_PATH]: continue
			result.append(mesh)
	return result

static func _support_target(parent: Node3D) -> MeshInstance3D:
	var body := parent.get_node_or_null("Ground") as StaticBody3D
	if body == null or not body.position.is_equal_approx(Vector3(0, -1, 0)) or not body.basis.is_equal_approx(Basis.IDENTITY): return null
	for child: Node in body.get_children():
		if not child is MeshInstance3D: continue
		var visual := child as MeshInstance3D
		if not visual.visible or not visual.transform.is_equal_approx(Transform3D.IDENTITY): continue
		var shape_ok := false
		if visual.mesh is CylinderMesh:
			var disc := visual.mesh as CylinderMesh
			shape_ok = is_equal_approx(disc.height, 2.0) and is_equal_approx(disc.top_radius, 175.0) and is_equal_approx(disc.bottom_radius, 175.0)
		elif visual.mesh is BoxMesh:
			shape_ok = (visual.mesh as BoxMesh).size.is_equal_approx(Vector3(350, 2, 350))
		if not shape_ok: continue
		if visual.material_override == SUPPORT: return visual
		var original := visual.material_override as StandardMaterial3D
		if original and original.albedo_color.is_equal_approx(Color(.18,.19,.18)) and original.albedo_texture == null and is_equal_approx(original.roughness,1.0): return visual
	return null

static func _coverage_complete(targets: Array[MeshInstance3D]) -> bool:
	if targets.size() != 39: return false
	var positions: Array[Vector3] = [Vector3.ZERO]
	for i in 12: positions.append(Vector3(0, 0, 35.5 + i * 11.5))
	for position: Vector3 in positions:
		var count := 0
		for mesh: MeshInstance3D in targets:
			if (mesh.get_parent() as Node3D).position.is_equal_approx(position): count += 1
		if count != 3: return false
	return true

static func _apply(parent: Node3D, arena: String) -> void:
	var material := _materials.get("shared") as StandardMaterial3D
	if material == null: return
	var targets := _targets(parent, arena)
	for mesh: MeshInstance3D in targets:
		mesh.material_override = material
		mesh.set_meta(&"arena_cave_floor_material", arena)
	# Fail closed if ANY expected floor module/LOD is missing or replaced. The
	# support stays opaque, so partial art loading can never expose a hole.
	if _coverage_complete(targets):
		var support := _support_target(parent)
		if support:
			if support.material_override != SUPPORT:
				support.set_meta(&"cave_support_original_material", support.material_override)
			support.material_override = SUPPORT
			support.set_meta(&"arena_cave_support_cutout", arena)
	else:
		var support := _support_target(parent)
		if support and support.has_meta(&"cave_support_original_material"):
			support.material_override = support.get_meta(&"cave_support_original_material") as Material
			support.remove_meta(&"arena_cave_support_cutout")

static func append(parent: Node3D, arena: String) -> void:
	if arena not in ["cave", "devil"]: return
	if ArenaArt._planner:
		ArenaArt._planner.jobs.append(func() -> bool: return _material_ready(arena))
		# Cave kit children are themselves queued. Resolve targets only after those
		# jobs have built all three LODs; a root can unload while its maps decode.
		var parent_ref: WeakRef = weakref(parent)
		ArenaArt._planner.add(func() -> void:
			var alive := parent_ref.get_ref() as Node3D
			if alive: _apply(alive, arena))
	else:
		material_for(arena)
		_apply(parent, arena)
