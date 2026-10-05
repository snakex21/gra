class_name NatureVarietyCatalog
extends RefCounted
## Shared Nature Variety meshes/material, independent of arena placement data.
## The immutable source pack has one identity-transformed mesh per artist LOD.
const PATH := "res://data/environment/nature_variety_catalog.json"
const ASSET = preload("res://art/scripts/art_asset.gd")
static var _models: Dictionary = {}
static var _materials: Dictionary = {}

static func models() -> Dictionary:
	if _models.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary and parsed.get("schema_version") == 1:
			_models = parsed.get("models", {})
	return _models

static func mesh_for(model_id: String, lod: int) -> Mesh:
	if not models().has(model_id) or lod < 0 or lod > 2:
		push_error("Invalid Nature Variety catalog lookup: " + model_id)
		return null
	var mesh: Mesh = ASSET.mesh_for(model_id, lod, models()[model_id].category)
	# Shared geometry-only surfaces; batches supply the single external palette.
	if mesh:
		for surface in mesh.get_surface_count():
			mesh.surface_set_material(surface, null)
	return mesh

static func material_for(model_id: String) -> Material:
	if not models().has(model_id):
		push_error("Invalid Nature Variety material lookup: " + model_id)
		return null
	var path: String = models()[model_id].material
	if not _materials.has(path):
		_materials[path] = load(path) as Material
	return _materials[path]

static func bounds_for(model_id: String, lod := -1) -> AABB:
	if not models().has(model_id) or lod < -1 or lod > 2:
		push_error("Invalid Nature Variety bounds lookup: " + model_id)
		return AABB()
	var model: Dictionary = models()[model_id]
	var bounds: Dictionary = model if lod == -1 else model.lod_bounds[lod]
	var low: Array = bounds.bounds_min
	var high: Array = bounds.bounds_max
	var minimum := Vector3(low[0], low[1], low[2])
	var maximum := Vector3(high[0], high[1], high[2])
	return AABB(minimum, maximum - minimum)
