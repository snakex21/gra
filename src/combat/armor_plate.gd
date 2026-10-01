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
## Crack patterns, one more set of lines per strike (generated once, no texture files).
static var _crack_textures: Array[ImageTexture] = []


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
	var fx_parent: Node = segment.colossus.get_parent() if segment.colossus else segment
	Sfx.play(segment, &"crack", at)
	Fx.dust(fx_parent, at, 0.8 if hits < hits_to_break else 2.2)
	if hits >= hits_to_break:
		Sfx.play(segment, &"impact", at)
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
		_crack_mat.albedo_color = Color(0.08, 0.06, 0.05, 1.0)
		_crack_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_crack_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		# Object space: the cracks stay on the plate while the head moves.
		_crack_mat.uv1_triplanar = true
		_crack_mat.uv1_world_triplanar = false
		_crack_mat.uv1_scale = Vector3.ONE * 0.45
	_crack_mat.albedo_texture = crack_texture(clampi(hits, 1, 3))
	for m in meshes:
		m.material_overlay = _crack_mat


## Dark jagged crack lines on transparent ground; ``level`` 1..3 adds more of them.
static func crack_texture(level: int) -> ImageTexture:
	if _crack_textures.is_empty():
		var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var rng := RandomNumberGenerator.new()
		rng.seed = 7071
		for l in 3:
			for c in 3 + l * 3:
				var p := Vector2(128, 128) + Vector2(rng.randf_range(-40, 40), rng.randf_range(-40, 40))
				var dir := Vector2.from_angle(rng.randf() * TAU)
				for s in 18 + l * 6:
					dir = dir.rotated(rng.randf_range(-0.6, 0.6))
					var q := p + dir * rng.randf_range(4.0, 9.0)
					for k in 8:
						var x := p.lerp(q, k / 8.0)
						for o in [Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN]:
							var px := Vector2i(posmod(int(x.x + o.x), 256), posmod(int(x.y + o.y), 256))
							img.set_pixelv(px, Color(1, 1, 1, 0.95))
					p = q
			_crack_textures.append(ImageTexture.create_from_image(img.duplicate()))
	return _crack_textures[clampi(level, 1, 3) - 1]
