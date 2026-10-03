class_name WebAnchor
extends Node3D
## A physical web knot can be severed by either sword or a real arrow.
signal severed(anchor: WebAnchor)
var radius := 1.3
var is_cut := false
var arrow_target: ArrowTarget
var _mesh: MeshInstance3D
var _mat: StandardMaterial3D

func _ready() -> void:
	add_to_group(&"armor_plates")
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	add_child(body)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.4
	shape.shape = sphere
	body.add_child(shape)
	_mesh = MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.4
	ball.height = 0.8
	_mesh.mesh = ball
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(1, 0.75, 0.15)
	_mat.emission_enabled = true
	_mat.emission = _mat.albedo_color
	_mesh.material_override = _mat
	add_child(_mesh)
	arrow_target = ArrowTarget.create(self, Vector3.ZERO, Vector3.UP, 0.85)
	arrow_target.max_incidence_deg = 180.0
	arrow_target.hit.connect(func(info: Dictionary) -> void:
		if info.accepted:
			_cut())

func world_point() -> Vector3:
	return global_position

func try_hit(at: Vector3, power: float, source: StringName) -> Dictionary:
	var reason: StringName = &"web_cut"
	if is_cut:
		reason = &"already_cut"
	elif source != &"sword":
		reason = &"not_a_sword"
	elif at.distance_to(world_point()) > radius:
		reason = &"out_of_range"
	elif power < 0.2:
		reason = &"too_weak"
	if reason != &"web_cut":
		return {"accepted": false, "reason": reason, "damage": 0.0}
	_cut()
	return {"accepted": true, "reason": reason, "damage": 0.0}

func _cut() -> void:
	if is_cut:
		return
	is_cut = true
	arrow_target.enabled = false
	_mat.albedo_color = Color(0.15, 0.14, 0.12)
	_mat.emission_energy_multiplier = 0.0
	severed.emit(self)

func reset() -> void:
	is_cut = false
	arrow_target.enabled = true
	arrow_target.hits_accepted = 0
	arrow_target.hits_rejected = 0
	_mat.albedo_color = Color(1, 0.75, 0.15)
	_mat.emission_energy_multiplier = 1.0
