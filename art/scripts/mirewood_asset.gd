@tool
extends Node3D
## Independent, art-only renderer and opt-in static collision from authored recipes.
## Never modifies gameplay collisions, actors, controllers, or climbing patches.
@export var model_id := "root_island"
@export var collidable := false
@export var lod_distances := Vector3(55.0, 140.0, 520.0)
@export var cast_shadows := true
const ATLAS := preload("res://materials/mirewood/atlas.tres")
static var _records: Dictionary = {}
static var _meshes: Dictionary = {}

static func records() -> Dictionary:
	if _records.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/mirewood_manifest.json"))
		if not data is Dictionary or not data.has("assets"):
			push_error("Invalid Mirewood manifest")
			return {}
		for record in data.assets:
			_records[record.id] = record
	return _records

static func mesh_for(id: String, level: int) -> Mesh:
	var key := "%s:%d" % [id, level]
	if not _meshes.has(key):
		var path := "res://models/mirewood/%s_lod%d.glb" % [id, level]
		var packed := load(path) as PackedScene
		if packed == null:
			push_error("Missing Mirewood export: " + path)
			return null
		var root := packed.instantiate()
		var meshes := root.find_children("*", "MeshInstance3D", true, false)
		if root is MeshInstance3D:
			meshes.push_front(root)
		if meshes.size() != 1:
			push_error("Mirewood exports require one merged mesh: " + path)
			root.free()
			return null
		_meshes[key] = meshes[0].mesh
		root.free()
	return _meshes[key] as Mesh

static func vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

func _ready() -> void:
	build()

func build() -> void:
	if get_child_count() > 0:
		return
	var inventory := records()
	if not inventory.has(model_id):
		push_error("Unknown Mirewood asset: " + model_id)
		return
	for level in 3:
		var visual := MeshInstance3D.new()
		visual.name = "LOD%d" % level
		visual.mesh = mesh_for(model_id, level)
		visual.material_override = ATLAS
		visual.lod_bias = 100.0
		visual.visibility_range_begin = 0.0 if level == 0 else lod_distances[level - 1]
		visual.visibility_range_end = lod_distances[level]
		visual.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(visual)
	if collidable:
		_build_collision(inventory[model_id])

func _build_collision(record: Dictionary) -> void:
	var recipes: Array = record.get("collision_shapes", [])
	if recipes.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = "AuthoredStaticProxy"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	for recipe in recipes:
		var node := CollisionShape3D.new()
		if recipe.type == "box":
			var box := BoxShape3D.new()
			box.size = vector(recipe.size)
			node.shape = box
		elif recipe.type == "convex":
			var hull := ConvexPolygonShape3D.new()
			var points := PackedVector3Array()
			for point in recipe.points:
				points.append(vector(point))
			hull.points = points
			node.shape = hull
		else:
			push_error("Unsupported Mirewood collision recipe: " + str(recipe.type))
			node.free()
			continue
		node.position = vector(recipe.get("position", [0,0,0]))
		node.rotation = vector(recipe.get("rotation", [0,0,0]))
		body.add_child(node)
