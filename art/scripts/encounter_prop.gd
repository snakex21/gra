@tool
extends Node3D
## Render-only authored props. Physics and gameplay markers belong to the arena.
@export var model_id := "cave_relic_lamp"
@export var collidable := false
@export var lod_distances := Vector3(55.0, 125.0, 800.0)
@export var cast_shadows := true
@export_flags_3d_render var render_layers := 1
const ATLAS := preload("res://materials/encounter_props/atlas.tres")
static var _records: Dictionary = {}
static var _meshes: Dictionary = {}

static func records() -> Dictionary:
	if _records.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://assets/encounter_props_manifest.json"))
		if not parsed is Dictionary or not parsed.has("assets"):
			push_error("Invalid Encounter Props manifest")
			return {}
		for record in parsed.assets:
			_records[record.id] = record
	return _records

static func mesh_for(id: String, level: int) -> Mesh:
	var key := "%s:%d" % [id, level]
	if not _meshes.has(key):
		var inventory := records()
		if not inventory.has(id) or level < 0 or level > 2:
			push_error("Unknown Encounter Prop or LOD: " + key)
			return null
		var path := "res://" + str(inventory[id].model_paths[level])
		var packed := load(path) as PackedScene
		if packed == null:
			push_error("Missing Encounter Prop export: " + path)
			return null
		var root := packed.instantiate()
		var meshes := root.find_children("*", "MeshInstance3D", true, false)
		if root is MeshInstance3D:
			meshes.push_front(root)
		if meshes.size() != 1:
			push_error("Encounter Props require one merged mesh: " + path)
			root.free()
			return null
		_meshes[key] = meshes[0].mesh
		root.free()
	return _meshes[key] as Mesh

func _ready() -> void:
	build()

func build() -> void:
	if get_child_count() > 0:
		return
	if not records().has(model_id):
		push_error("Unknown Encounter Prop: " + model_id)
		return
	# The compatibility flag is deliberately inert: these assets never own physics.
	if collidable:
		push_warning("Encounter Props are render-only; use the arena's gameplay collision")
	for level in 3:
		var mesh := mesh_for(model_id, level)
		if mesh == null:
			continue
		var visual := MeshInstance3D.new()
		visual.name = "LOD%d" % level
		visual.mesh = mesh
		visual.material_override = ATLAS
		visual.layers = render_layers
		visual.lod_bias = 100.0
		visual.visibility_range_begin = 0.0 if level == 0 else lod_distances[level - 1]
		visual.visibility_range_end = lod_distances[level]
		visual.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(visual)
