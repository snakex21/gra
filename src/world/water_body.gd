class_name WaterBody
extends Node3D
## A body of still water: a disc of ``radius`` round this node whose surface is at this
## node's height. Wherever the ground inside it is lower than the surface, there is water.
## No collision: the player swims (PlayerCharacter.State.SWIM), Agro treats deep water as
## an edge, a colossus can swim in it. Optional visual: a translucent disc.
##
## Queries go through the group "water" (static helpers below), so any scene can have
## any number of them.

@export var radius := 30.0
@export var show_surface := true
@export var color := Color(0.16, 0.3, 0.34, 0.78)


func _ready() -> void:
	add_to_group(&"water")
	if show_surface:
		var m := CylinderMesh.new()
		m.top_radius = radius
		m.bottom_radius = radius
		m.height = 0.02
		m.radial_segments = 64
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 0.08
		mat.metallic_specular = 0.8
		var mi := MeshInstance3D.new()
		mi.name = "Surface"
		mi.mesh = m
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


func contains_xz(p: Vector3) -> bool:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length() < radius


func surface() -> float:
	return global_position.y


## The water surface above ``p`` (any water body round it), or NAN when there is none.
static func surface_at(tree: SceneTree, p: Vector3) -> float:
	if tree == null:
		return NAN
	for w in tree.get_nodes_in_group(&"water"):
		var wb := w as WaterBody
		if wb and wb.contains_xz(p):
			return wb.surface()
	return NAN


## The water bodies of a tree (cached by callers that query every tick).
static func all(tree: SceneTree) -> Array[WaterBody]:
	var out: Array[WaterBody] = []
	if tree:
		for w in tree.get_nodes_in_group(&"water"):
			if w is WaterBody:
				out.append(w)
	return out
