class_name AuthoredNature
extends RefCounted
## Visual-only authored instances. No runtime random placement or terrain resampling.
## Edit the versioned JSON, then restart or reset_cache() to apply it.
const PATH := "res://data/environment/authored_nature_layout4.json"
const CELL := 64.0
const MAX_INSTANCES := 900
static var _loaded := false
static var _by_chunk: Dictionary = {}
static var _records: Array = []

static func vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

static func transform_for(record: Dictionary) -> Transform3D:
	# Godot YXZ Euler radians and local-axis XYZ scale are part of schema v1.
	return Transform3D(Basis.from_euler(vector(record.rotation)) * Basis.from_scale(vector(record.scale)), vector(record.position))

static func validate(document: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if not document is Dictionary:
		errors.append("Placement document must be an object")
		return errors
	if document.get("schema_version") != 1 or document.get("world_layout") != 4:
		errors.append("Unsupported placement schema or world layout")
	var records = document.get("instances")
	if not records is Array:
		errors.append("instances must be an array")
		return errors
	if records.size() > MAX_INSTANCES:
		errors.append("Placement budget exceeded")
	var ids := {}
	for record in records:
		if not record is Dictionary:
			errors.append("Instance must be an object")
			continue
		var id: String = str(record.get("id", ""))
		if id.is_empty() or ids.has(id):
			errors.append("Missing or duplicate instance id: " + id)
		ids[id] = true
		if not AuthoredNatureCatalog.models().has(record.get("model_id", "")):
			errors.append("Unknown model_id for " + id)
		for field: String in ["position", "rotation", "scale"]:
			var values = record.get(field)
			if not values is Array or values.size() != 3:
				errors.append("Expected three components in " + id + "." + field)
				continue
			for value in values:
				if not (value is float or value is int):
					errors.append("Non-numeric component in " + id)
				elif not is_finite(float(value)) or (field == "scale" and float(value) <= 0):
					errors.append("Invalid component in " + id)
	return errors

static func reset_cache() -> void:
	_loaded = false
	_by_chunk.clear()
	_records.clear()

static func records() -> Array:
	_load()
	return _records.duplicate(true)

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var document = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	var errors := validate(document)
	if not errors.is_empty():
		push_error("Authored nature disabled: " + "; ".join(errors))
		return
	_records = document.instances
	for record: Dictionary in _records:
		var p := vector(record.position)
		var chunk := Vector2i(floori(p.x / 256) * 256, floori(p.z / 256) * 256)
		if not _by_chunk.has(chunk):
			_by_chunk[chunk] = []
		_by_chunk[chunk].append(record)

static func cells_for_chunk(origin: Vector2i) -> Dictionary:
	_load()
	var cells := {}
	for record: Dictionary in _by_chunk.get(origin, []):
		var xf := transform_for(record)
		var cell := Vector2i(floori(xf.origin.x / CELL), floori(xf.origin.z / CELL))
		if not cells.has(cell):
			cells[cell] = {}
		var kind: String = record.model_id
		if not cells[cell].has(kind):
			cells[cell][kind] = []
		cells[cell][kind].append(xf)
	return cells

static func append_chunk(parent: Node3D, origin: Vector2i) -> void:
	var cells := cells_for_chunk(origin)
	var profile := "balanced"
	var ancestor: Node = parent
	while ancestor:
		if ancestor.has_meta(&"environment_groundcover_profile"):
			profile = ancestor.get_meta(&"environment_groundcover_profile")
			break
		ancestor = ancestor.get_parent()
	for cell: Vector2i in cells:
		for kind: String in cells[cell]:
			var transforms: Array = cells[cell][kind]
			var anchor := Vector3((cell.x + .5) * CELL, 0, (cell.y + .5) * CELL)
			for xf: Transform3D in transforms:
				anchor.y += xf.origin.y / transforms.size()
			var mesh_bounds: AABB = AuthoredNatureCatalog.mesh_for(kind, 0).get_aabb()
			for lod in [1, 2]:
				mesh_bounds = mesh_bounds.merge(AuthoredNatureCatalog.mesh_for(kind, lod).get_aabb())
			var shared_bounds := AABB()
			for i in transforms.size():
				var local: Transform3D = transforms[i]
				local.origin -= anchor
				var bounds: AABB = local * mesh_bounds
				shared_bounds = bounds if i == 0 else shared_bounds.merge(bounds)
			for lod in 3:
				var multi := MultiMesh.new()
				multi.transform_format = MultiMesh.TRANSFORM_3D
				multi.mesh = AuthoredNatureCatalog.mesh_for(kind, lod)
				multi.custom_aabb = shared_bounds
				multi.instance_count = transforms.size()
				for i in transforms.size():
					var local: Transform3D = transforms[i]
					local.origin -= anchor
					multi.set_instance_transform(i, local)
				var batch := MultiMeshInstance3D.new()
				batch.name = "AuthoredNature_%s_%d_%d_LOD%d" % [kind, cell.x, cell.y, lod]
				batch.position = anchor
				batch.multimesh = multi
				batch.material_override = AuthoredNatureCatalog.material_for(kind)
				batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				batch.lod_bias = 100.0
				batch.set_meta(&"authored_nature_model_id", kind)
				# Existing live quality traversal recognizes these semantic aliases.
				batch.set_meta(&"groundcover_kind", "shrub_salt" if kind.begins_with("shrub_") else "grass_tuft")
				batch.set_meta(&"groundcover_lod", lod)
				batch.visibility_range_begin_margin = 0
				batch.visibility_range_end_margin = 0
				EnvironmentGroundcover.apply_quality(batch, profile)
				parent.add_child(batch)
