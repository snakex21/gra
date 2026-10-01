@tool
extends Node3D
## Render-only GLB LODs and deliberately separate low-detail static collision.
## Does not depend on any player, colossus, camera, or climbing class.

@export var model_id := "rock_01"
@export var collidable := false
@export var lod_distances := Vector3(35.0, 90.0, 260.0)
@export var collision_kind := "hull"

const ATLAS := preload("res://materials/ancient_valley/atlas.tres")
const FOLIAGE := preload("res://materials/ancient_valley/wind.tres")
static var _mesh_cache: Dictionary = {}


static func mesh_for(id: String, level: int, category := "ancient_valley") -> Mesh:
	var path := "res://models/%s/%s_lod%d.glb" % [category, id, level]
	if not _mesh_cache.has(path):
		var packed := load(path) as PackedScene
		if packed == null:
			push_error("Missing art export: " + path)
			return null
		var scene := packed.instantiate()
		var meshes := scene.find_children("*", "MeshInstance3D", true, false)
		if scene is MeshInstance3D:
			meshes.push_front(scene)
		assert(meshes.size() == 1, "Each art GLB must contain one merged mesh")
		_mesh_cache[path] = meshes[0].mesh
		scene.free()
	return _mesh_cache[path] as Mesh


func _ready() -> void:
	build()


func build() -> void:
	if get_child_count() > 0:
		return
	var is_plant := model_id in ["grass_dry_v2", "fern", "reed", "moss_patch", "shrub_heather", "shrub_thorn", "tree_cypress", "tree_oak", "tree_willow"]
	for level in 3:
		var visual := MeshInstance3D.new()
		visual.name = "LOD%d" % level
		visual.mesh = mesh_for(model_id, level)
		visual.lod_bias = 100.0 # Explicit artist LODs, not a second aggressive automatic reduction.
		visual.material_override = FOLIAGE if is_plant else ATLAS
		visual.visibility_range_begin = 0.0 if level == 0 else lod_distances[level - 1]
		visual.visibility_range_end = lod_distances[level]
		visual.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if is_plant else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(visual)
	if collidable:
		_build_collision()


func _box(body: StaticBody3D, pos: Vector3, size: Vector3, angle := 0.0) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = pos
	col.rotation.z = angle
	body.add_child(col)


func _build_collision() -> void:
	if collision_kind in ["none", "existing_segment"]:
		return
	var body := StaticBody3D.new()
	body.name = "LowPolyCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	match collision_kind:
		"opening_boxes":
			var r := 2.0 if model_id == "arch" else 1.2
			for side in [-1,1]:
				_box(body,Vector3(side*(r+.4),1.5,0),Vector3(.8,3,1))
			for j in 11:
				var a := (j+.5)*PI/11.0
				_box(body,Vector3(cos(a)*(r+.4),3+sin(a)*(r+.4),0),Vector3(.8,.7,1),a)
		"rock_arch_boxes":
			for side in [-1,1]:
				_box(body,Vector3(side*5,5.5,0),Vector3(4,11,5))
			_box(body,Vector3(0,10.5,0),Vector3(12,3,5))
		"channel_boxes":
			_box(body,Vector3(0,.12,0),Vector3(4,.24,1.2))
			for side in [-1,1]:
				_box(body,Vector3(0,.35,side*.65),Vector3(4,.7,.22))
		"stair_ramp_v2":
			var shape := ConvexPolygonShape3D.new()
			shape.points = PackedVector3Array([Vector3(-2,0,2),Vector3(2,0,2),Vector3(-2,.3,2),Vector3(2,.3,2),Vector3(-2,0,-2),Vector3(2,0,-2),Vector3(-2,2.4,-2),Vector3(2,2.4,-2)])
			var col := CollisionShape3D.new()
			col.shape=shape
			body.add_child(col)
		"arch_boxes":
			_box(body, Vector3(-3.75, 2.2, 0), Vector3(1.5, 4.4, 1.75))
			_box(body, Vector3(3.75, 2.2, 0), Vector3(1.5, 4.4, 1.75))
			for j in 13:
				var angle := (j + 0.5) * PI / 13.0
				_box(body, Vector3(cos(angle) * 3.75, 4.4 + sin(angle) * 3.75, 0), Vector3(1.5, 0.84, 1.7), angle)
		"stair_ramp":
			var shape := ConvexPolygonShape3D.new()
			shape.points = PackedVector3Array([Vector3(-2,0,.27), Vector3(2,0,.27), Vector3(-2,.34,.27), Vector3(2,.34,.27), Vector3(-2,0,-3.77), Vector3(2,0,-3.77), Vector3(-2,2.72,-3.77), Vector3(2,2.72,-3.77)])
			var col := CollisionShape3D.new()
			col.shape = shape
			body.add_child(col)
		"trunk":
			var shape := CylinderShape3D.new()
			shape.radius = 0.48
			shape.height = 3.0
			var col := CollisionShape3D.new()
			col.shape = shape
			col.position.y = 1.5
			body.add_child(col)
		_:
			var source := load("res://models/ancient_valley/%s_collision.glb" % model_id) as PackedScene
			if source == null:
				push_error("Missing separate collision source for " + model_id)
				return
			var scene := source.instantiate()
			var mesh := scene.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
			var shape := ConvexPolygonShape3D.new()
			shape.points = mesh.mesh.get_faces()
			var col := CollisionShape3D.new()
			col.shape = shape
			body.add_child(col)
			scene.free()
