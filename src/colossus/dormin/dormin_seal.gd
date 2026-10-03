class_name DorminSeal
extends Node3D
## Three original finale locks: sustained light; light + heavy blade; frozen
## moving shadow + quick blade. The player's ordinary sword discovers these via
## the existing armour-target protocol.
signal dispelled
enum Kind { DAWN, ANCHOR, SHADOW }
var kind := Kind.DAWN
var broken := false
var light_time := 0.0
var exposed_left := 0.0
var clock := 0.0
var radius := 1.15
var _home := Vector3.ZERO
var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _hit_cooldown := 0.0

func _ready() -> void:
	process_physics_priority = -8
	_home = position
	if kind != Kind.DAWN:
		add_to_group(&"armor_plates")
	_mesh = MeshInstance3D.new()
	var crystal := SphereMesh.new()
	crystal.radius = .72
	crystal.height = 1.3
	crystal.radial_segments = 12
	crystal.rings = 5
	_mesh.mesh = crystal
	_material = StandardMaterial3D.new()
	_material.albedo_color = [Color(.67, .83, .66), Color(.58, .39, .19), Color(.10, .09, .14)][kind]
	_material.emission_enabled = true
	_material.emission = [Color(.43, .7, .4), Color(.8, .35, .05), Color(.25, .10, .43)][kind]
	_material.emission_energy_multiplier = .35
	_mesh.material_override = _material
	add_child(_mesh)
	var base := MeshInstance3D.new()
	var pedestal := CylinderMesh.new()
	pedestal.top_radius = 1.0
	pedestal.bottom_radius = 1.1
	pedestal.height = .3
	pedestal.radial_segments = 8
	base.mesh = pedestal
	base.position.y = -.65
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(.32, .35, .32)
	base.material_override = stone
	add_child(base)

func world_point() -> Vector3:
	return global_position

func reset() -> void:
	broken = false
	light_time = 0
	exposed_left = 0
	clock = 0
	_hit_cooldown = 0
	position = _home
	if _mesh:
		_mesh.visible = true

func _physics_process(delta: float) -> void:
	if broken:
		return
	clock += delta
	exposed_left = maxf(0, exposed_left - delta)
	_hit_cooldown = maxf(0, _hit_cooldown - delta)
	if kind == Kind.SHADOW and exposed_left <= 0:
		position = _home + Vector3(sin(clock * .75) * 2.8, 0, cos(clock * .75) * 1.2)
	var lit := false
	for node in get_tree().get_nodes_in_group(&"players"):
		var p := node as PlayerCharacter
		if p == null or p.dead or p.beam.raise < 1 or not p.beam.lit:
			continue
		var from := SwordBeam.tip(p)
		var to := global_position - from
		if to.length() > 32 or p.beam.direction.dot(to.normalized()) < cos(deg_to_rad(18)):
			continue
		var ray := PhysicsRayQueryParameters3D.create(from, global_position, Layers.WORLD)
		if get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			lit = true
	light_time = light_time + delta if lit else 0
	_material.emission_energy_multiplier = .35 + light_time * 1.5 + (1.6 if exposed_left > 0 else 0)
	if kind == Kind.DAWN and light_time >= 1.25:
		_break()
	elif kind != Kind.DAWN and light_time >= .7:
		exposed_left = 7.0 if kind == Kind.ANCHOR else 3.6
	if kind == Kind.SHADOW and exposed_left <= 0:
		for p in get_tree().get_nodes_in_group(&"players"):
			if not p.dead and p.global_position.distance_to(global_position) < 1.7 and _hit_cooldown <= 0:
				p.apply_hit(8, (p.global_position - global_position).normalized() * 2, .1, &"dormin_shadow")
				_hit_cooldown = 2.5

func try_hit(at: Vector3, power: float, source: StringName) -> Dictionary:
	var reason: StringName = &""
	if source != &"sword":
		reason = &"not_a_sword"
	elif broken:
		reason = &"destroyed"
	elif kind == Kind.DAWN or exposed_left <= 0:
		reason = &"protected"
	elif at.distance_to(global_position) > radius:
		reason = &"out_of_range"
	elif kind == Kind.ANCHOR and power < .75:
		reason = &"too_weak"
	elif kind == Kind.SHADOW and power > .45:
		reason = &"too_slow"
	if reason != &"":
		return {"accepted": false, "reason": reason, "damage": 0.0}
	_break()
	return {"accepted": true, "reason": &"hit", "damage": 1.0}

func _break() -> void:
	if broken:
		return
	broken = true
	_mesh.visible = false
	dispelled.emit()
