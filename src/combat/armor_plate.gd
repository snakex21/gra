class_name ArmorPlate
extends Node3D
## A breakable armour plate on a colossus (Gaius' helmet): one collision part (and its
## mesh) on a BodySegment. Charged sword strikes crack it; after ``hits_to_break`` it
## breaks off: the shape stops colliding, the mesh disappears, ``broken`` fires (the
## colossus opens what was under it). Weak strikes and arrows bounce off.
##
## Same strike API as WeakPoint (world_point / radius / try_hit), so the sword treats
## both alike.

signal cracked(hits: int)
signal broken
signal rejected(reason: StringName)

var segment: BodySegment
var local_point := Vector3.ZERO
var radius := 1.6
var hits_to_break := 3
## Strikes weaker than this (charge 0..1) bounce off.
var min_power := 0.55
var hits := 0
var is_broken := false
var last_reason: StringName = &""
var shape: CollisionShape3D
var meshes: Array[MeshInstance3D] = []

var _crack_mat: StandardMaterial3D


## Wraps an existing part (``shape`` and its meshes) of ``segment``.
static func create(p_segment: BodySegment, p_shape: CollisionShape3D, p_meshes: Array[MeshInstance3D], p_hits := 3) -> ArmorPlate:
	var a := ArmorPlate.new()
	a.segment = p_segment
	a.shape = p_shape
	a.meshes = p_meshes
	a.local_point = p_shape.position
	a.hits_to_break = p_hits
	a.position = a.local_point
	a.name = "ArmorPlate"
	p_segment.add_child(a)
	return a


func _ready() -> void:
	add_to_group(&"armor_plates")


func world_point() -> Vector3:
	return segment.target_transform * local_point


## ``source`` must be &"sword", ``power`` the strike charge (0..1).
func try_hit(at: Vector3, power: float, source: StringName) -> Dictionary:
	var reason: StringName = &""
	if is_broken:
		reason = &"broken"
	elif source != &"sword":
		reason = &"not_a_sword"
	elif at.distance_to(world_point()) > radius:
		reason = &"out_of_range"
	elif power < min_power:
		reason = &"too_weak"
	if reason != &"":
		last_reason = reason
		rejected.emit(reason)
		return {"accepted": false, "reason": reason, "damage": 0.0}
	hits += 1
	last_reason = &"crack"
	cracked.emit(hits)
	_show_cracks()
	if hits >= hits_to_break:
		_break()
		return {"accepted": true, "reason": &"armor_broken", "damage": 0.0}
	return {"accepted": true, "reason": &"armor_cracked", "damage": 0.0}


func reset() -> void:
	hits = 0
	is_broken = false
	last_reason = &""
	shape.set_deferred(&"disabled", false)
	for m in meshes:
		m.visible = true
		if _crack_mat:
			m.material_overlay = null


func progress() -> float:
	return float(hits) / hits_to_break


func _break() -> void:
	is_broken = true
	shape.set_deferred(&"disabled", true)
	for m in meshes:
		m.visible = false
	broken.emit()


func _show_cracks() -> void:
	if _crack_mat == null:
		_crack_mat = StandardMaterial3D.new()
		_crack_mat.albedo_color = Color(0.1, 0.08, 0.06, 0.0)
		_crack_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_crack_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_crack_mat.albedo_color.a = 0.25 * hits
	for m in meshes:
		m.material_overlay = _crack_mat
