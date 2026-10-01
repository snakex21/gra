class_name PlayerVisual
extends Node3D
## Greybox player body. Purely cosmetic: orientation + a damped "dangle" offset that
## makes shaking readable (the body swings on its arms) without touching the gameplay anchor.

var _rot := Quaternion.IDENTITY
var _offset := Vector3.ZERO
var _offset_vel := Vector3.ZERO
var _arms: Array[Node3D] = []
var _arm_raise := 0.0
var _lean := Vector3.ZERO
var _down := 0.0


func _ready() -> void:
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.18, 0.28, 0.45)
	var skin_mat := StandardMaterial3D.new()
	skin_mat.albedo_color = Color(0.85, 0.7, 0.55)

	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.35
	body.mesh = capsule
	body.position = Vector3(0, -0.15, 0)
	body.material_override = body_mat
	add_child(body)

	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.17
	sphere.height = 0.34
	head.mesh = sphere
	head.position = Vector3(0, 0.72, 0)
	head.material_override = skin_mat
	add_child(head)

	# Nose so facing is readable.
	var nose := MeshInstance3D.new()
	var nose_mesh := BoxMesh.new()
	nose_mesh.size = Vector3(0.06, 0.06, 0.12)
	nose.mesh = nose_mesh
	nose.position = Vector3(0, 0.72, -0.18)
	nose.material_override = skin_mat
	add_child(nose)

	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(0.3 * side, 0.4, 0)
		add_child(pivot)
		var arm := MeshInstance3D.new()
		var arm_mesh := BoxMesh.new()
		arm_mesh.size = Vector3(0.12, 0.6, 0.12)
		arm.mesh = arm_mesh
		arm.position = Vector3(0, -0.3, 0)
		arm.material_override = skin_mat
		pivot.add_child(arm)
		_arms.append(pivot)


func update_visual(player: PlayerCharacter, delta: float) -> void:
	var target: Basis
	var accel := Vector3.ZERO
	var climbing := player.state == PlayerCharacter.State.CLIMB
	if climbing:
		var n := player.grip.world_normal()
		target = _look_basis(-n, player.climb_up)
		# Gripping fur on a flat top: crouched upright over the hands, not lying flat.
		var w := smoothstep(0.82, 0.95, n.y)
		if w > 0.0:
			var upright := _look_basis(PlayerCharacter._flat_dir(player.climb_up, player.facing), Vector3.UP)
			target = Basis(target.get_rotation_quaternion().slerp(upright.get_rotation_quaternion(), w))
		accel = player.surface_accel
	else:
		target = _look_basis(player.facing, Vector3.UP)
	_rot = _rot.slerp(target.get_rotation_quaternion(), 1.0 - exp(-14.0 * delta))

	# Damped spring: the body lags behind surface accelerations, then swings back.
	var k := 70.0
	var c := 2.0 * sqrt(k) * 0.35
	_offset_vel += (-k * _offset - c * _offset_vel - accel * 0.35) * delta
	_offset += _offset_vel * delta
	if _offset.length() > 0.5:
		_offset = _offset.normalized() * 0.5
	if not climbing:
		_offset = _offset.lerp(Vector3.ZERO, 1.0 - exp(-8.0 * delta))

	# Balance: lean against the surface acceleration when unsteady, lie down when knocked over.
	var standing := player.state == PlayerCharacter.State.GROUND
	var wobble := (1.0 - player.balance.value) if standing else 0.0
	var a_flat := Vector3(player.surface_accel.x, 0.0, player.surface_accel.z)
	var target_lean := (-a_flat.limit_length(20.0) / 20.0) * 0.6 * wobble
	_lean = _lean.lerp(target_lean, 1.0 - exp(-10.0 * delta))
	var fallen := standing and player.balance.state == Balance.State.FALLEN
	_down = lerpf(_down, 1.0 if (fallen or player.dead) else 0.0, 1.0 - exp(-8.0 * delta))

	# Arms up while gripping.
	_arm_raise = lerpf(_arm_raise, 1.0 if climbing else 0.0, 1.0 - exp(-12.0 * delta))
	for arm in _arms:
		arm.rotation.x = PI * 0.95 * _arm_raise

	var b := Basis(_rot)
	if _lean.length() > 0.001:
		# Tilt around the horizontal axis perpendicular to the lean direction.
		var axis := Vector3.UP.cross(_lean.normalized())
		b = Basis(axis, _lean.length()) * b
	var pos := _offset
	if _down > 0.001:
		b = Basis(b.x, -PI * 0.5 * _down) * b
		pos += Vector3.DOWN * 0.6 * _down
	transform = Transform3D(b, pos)


static func _look_basis(forward: Vector3, up: Vector3) -> Basis:
	if forward.length() < 0.001:
		return Basis.IDENTITY
	forward = forward.normalized()
	if absf(forward.dot(up.normalized())) > 0.98:
		up = Vector3.FORWARD if absf(forward.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	return Basis.looking_at(forward, up)
