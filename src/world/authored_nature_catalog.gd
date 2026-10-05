class_name AuthoredNatureCatalog
extends RefCounted
## Shared mesh assets are independent of the editable placement document.
const PATH := "res://data/environment/nature_catalog.json"
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
		push_error("Invalid Nature Craft catalog lookup: " + model_id)
		return null
	var mesh: Mesh = ASSET.mesh_for(model_id, lod, models()[model_id].category)
	# Runtime GLBs are geometry-only. Keep cached surfaces material-free even
	# if an editor import supplies a default; all batches use one external atlas.
	if mesh:
		for surface in mesh.get_surface_count():
			mesh.surface_set_material(surface, null)
	return mesh

static func material_for(model_id: String) -> Material:
	var path: String = models()[model_id].material
	if not _materials.has(path):
		_materials[path] = load(path) as Material
	return _materials[path]
