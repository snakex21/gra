class_name PcVrHands
extends Node3D
## Cosmetic grip-space hands plus an independent loose-sword interaction component.
## WeaponArt/weapons_v4 define a metre-sized sword with Grip=(0,0,0), blade=+Y.

const SwordScript := preload("res://src/vr/pc_vr_sword.gd")
const WRIST_IN_GRIP := Vector3(0.0, -0.050, 0.037)
const FOREARM_LENGTH := 0.27
static var _meshes := {}
static var _materials: Array[StandardMaterial3D] = []

var head: XRCamera3D
var left: XRController3D
var right: XRController3D
var left_hand: Node3D
var right_hand: Node3D
var left_forearm: MeshInstance3D
var right_forearm: MeshInstance3D
var sword: RigidBody3D
var sword_controller: Node3D
var _left_palm: MeshInstance3D
var _right_palm: MeshInstance3D
var _left_gripping := false
var _right_gripping := false


func setup(to_head: XRCamera3D, to_left: XRController3D, to_right: XRController3D) -> void:
	_clear_visuals()
	head = to_head
	left = to_left
	right = to_right
	if not is_instance_valid(left) or not is_instance_valid(right): return
	_ensure_materials()
	left_hand = _hand(left, -1.0, false)
	right_hand = _hand(right, 1.0, false)
	_left_palm = left_hand.get_node("PalmAndFingers") as MeshInstance3D
	_right_palm = right_hand.get_node("PalmAndFingers") as MeshInstance3D
	left_forearm = left_hand.get_node("Forearm") as MeshInstance3D
	right_forearm = right_hand.get_node("Forearm") as MeshInstance3D
	update_hands(false, false)


func setup_sword(body: CharacterBody3D) -> void:
	if is_instance_valid(sword_controller): sword_controller.free()
	sword_controller = SwordScript.new()
	sword_controller.name = "SwordController"
	add_child(sword_controller)
	sword_controller.setup(head, left, right, body)
	sword = sword_controller.sword_body


func step_sword(delta: float, frame: Dictionary, body: CharacterBody3D, ready: bool) -> Dictionary:
	if not is_instance_valid(sword_controller) or sword_controller.player_body != body:
		setup_sword(body)
	return sword_controller.step(delta, frame, ready)


func recall_sword() -> void:
	if is_instance_valid(sword_controller): sword_controller.recall(false)


func sync_sword(delta := 1.0 / 90.0) -> void:
	if is_instance_valid(sword_controller): sword_controller.sync_pose(delta)


func update_hands(left_tracked: bool, right_tracked: bool) -> void:
	if is_instance_valid(left_hand):
		left_hand.visible = left_tracked and is_instance_valid(left) and left.global_transform.is_finite()
		if left_hand.visible: _place_forearm(left, left_forearm, -1.0)
	if is_instance_valid(right_hand):
		right_hand.visible = right_tracked and is_instance_valid(right) and right.global_transform.is_finite()
		if right_hand.visible: _place_forearm(right, right_forearm, 1.0)


## Optional cosmetic pose for a future/active left-hand grip; does not change input.
func set_left_gripping(gripping: bool) -> void:
	if gripping == _left_gripping or not is_instance_valid(_left_palm): return
	_left_gripping = gripping
	_left_palm.mesh = _hand_mesh(-1.0, gripping)


## Blend cosmetic fur grips with the sword's actual ownership; never hide a loose sword.
func set_grips(left_gripping: bool, right_gripping: bool) -> void:
	var held: int = sword_controller.held_hand if is_instance_valid(sword_controller) else -1
	left_gripping = left_gripping or held == 0
	right_gripping = right_gripping or held == 1
	set_left_gripping(left_gripping)
	if right_gripping != _right_gripping and is_instance_valid(_right_palm):
		_right_palm.mesh = _hand_mesh(1.0, right_gripping)
	_right_gripping = right_gripping


func _hand(controller: XRController3D, side: float, gripping: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "VrHandVisual"
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	root.visible = false
	controller.add_child(root)
	var palm := MeshInstance3D.new()
	palm.name = "PalmAndFingers"
	palm.mesh = _hand_mesh(side, gripping)
	palm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(palm)
	# Same grip frame as WeaponArt._hand_goal: fingers wrap about hand-local -Y.
	palm.transform = Transform3D(Basis(Vector3.FORWARD, PI), WRIST_IN_GRIP)
	var arm := MeshInstance3D.new()
	arm.name = "Forearm"
	arm.mesh = _forearm_mesh()
	arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(arm)
	return root


func _place_forearm(controller: XRController3D, arm: MeshInstance3D, side: float) -> void:
	arm.visible = is_instance_valid(head) and head.global_transform.is_finite()
	if not arm.visible: return
	var wrist := controller.to_global(WRIST_IN_GRIP)
	var rightward := head.global_basis.x
	rightward.y = 0.0
	if rightward.length_squared() < 0.001: rightward = Vector3.RIGHT
	rightward = rightward.normalized()
	var forward := rightward.cross(Vector3.UP)
	var elbow := head.global_position + rightward * (side * 0.25) + Vector3.DOWN * 0.52 + forward * 0.10
	var direction := elbow - wrist
	if direction.length_squared() < 0.0001:
		direction = controller.global_basis.z
	var length := clampf(direction.length(), 0.18, FOREARM_LENGTH)
	var basis := _basis_y(direction.normalized(), controller.global_basis.x)
	basis.y *= length / FOREARM_LENGTH
	arm.global_transform = Transform3D(basis, wrist)


func _clear_visuals() -> void:
	if is_instance_valid(sword_controller): sword_controller.free()
	sword_controller = null
	for node in [left_hand, right_hand]:
		if is_instance_valid(node): node.free()
	left_hand = null
	right_hand = null
	left_forearm = null
	right_forearm = null
	_left_palm = null
	_right_palm = null
	sword = null
	_left_gripping = false
	_right_gripping = false


func _exit_tree() -> void:
	_clear_visuals()


static func _basis_y(axis: Vector3, hint: Vector3) -> Basis:
	var x := hint - axis * hint.dot(axis)
	if x.length_squared() < 0.0001:
		x = axis.cross(Vector3.FORWARD if absf(axis.z) < 0.95 else Vector3.UP)
	x = x.normalized()
	return Basis(x, axis, x.cross(axis).normalized())


static func _ensure_materials() -> void:
	if not _materials.is_empty(): return
	for color in [Color(0.57, 0.42, 0.34), Color(0.20, 0.17, 0.13), Color(0.39, 0.40, 0.32)]:
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.91
		material.vertex_color_use_as_albedo = true
		_materials.append(material)


static func _tools() -> Array[SurfaceTool]:
	var result: Array[SurfaceTool] = []
	for material in _materials:
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tool.set_material(material)
		result.append(tool)
	return result


static func _finish(tools: Array[SurfaceTool]) -> ArrayMesh:
	var result := ArrayMesh.new()
	for tool in tools:
		tool.index()
		tool.commit(result)
	return result


static func _hand_mesh(side: float, gripping: bool) -> ArrayMesh:
	var key := "hand_%s_%s" % [str(side), str(gripping)]
	if _meshes.has(key): return _meshes[key] as ArrayMesh
	var tools := _tools()
	# Metacarpals narrow toward the wrist and little finger, rather than a capsule.
	_loft(tools[0], [[0.004, 0.025, 0.021, 0.0], [-0.018, 0.034, 0.023, -0.002],
		[-0.043, 0.036, 0.022, -0.002], [-0.068, 0.031, 0.019, -0.001],
		[-0.084, 0.017, 0.013, 0.0]], 16)
	for i in 4:
		var y := [-0.027, -0.043, -0.059, -0.073][i] as float
		var radius := [0.0072, 0.0077, 0.0072, 0.0060][i] as float
		var points: Array[Vector3]
		if gripping:
			points = [Vector3(side * 0.025, y, -0.004), Vector3(side * 0.039, y - 0.002, -0.025),
				Vector3(side * 0.026, y - 0.003, -0.060), Vector3(side * 0.001, y - 0.004, -0.064),
				Vector3(-side * 0.017, y - 0.002, -0.044)]
		else:
			# A relaxed climbing hand keeps visible individual fingers and thumb.
			var reach := [0.060, 0.066, 0.060, 0.048][i] as float
			points = [Vector3(side * 0.022, y, -0.010), Vector3(side * 0.031, y - 0.003, -0.038),
				Vector3(side * 0.021, y - 0.005, -0.010 - reach),
				Vector3(side * 0.009, y - 0.006, -0.016 - reach)]
		_tube(tools[0], points, radius, 8, Color(1.06, 1.01, 0.98))
		_ellipsoid(tools[0], Vector3(side * 0.026, y, -0.020), Vector3(0.009, radius * 0.92, 0.010), 8, 4, Color(1.11, 1.04, 1.01))
		var tip := points[-1]
		_ellipsoid(tools[0], tip, Vector3(radius * 0.95, radius * 0.88, radius * 0.95), 8, 4, Color.WHITE)
	# Opposed thumb sits across the index finger/hilt, not alongside four fingers.
	var thumb: Array[Vector3] = [Vector3(side * 0.025, -0.009, -0.006), Vector3(side * 0.038, -0.022, -0.036),
		Vector3(side * (0.019 if gripping else 0.042), -0.031, -0.058),
		Vector3(side * (-0.003 if gripping else 0.027), -0.034, -0.057)]
	_tube(tools[0], thumb, 0.008, 8, Color(1.07, 1.01, 0.98))
	_ellipsoid(tools[0], thumb[-1], Vector3(0.0078, 0.007, 0.008), 8, 4, Color.WHITE)
	# Wrist wrap with three raised linen turns, a seam and a small leather tie.
	_loft(tools[1], [[0.003, 0.026, 0.023, 0.0], [0.015, 0.027, 0.024, 0.0], [0.023, 0.028, 0.025, 0.0]], 12)
	for y in [0.005, 0.012, 0.020]:
		_loft(tools[2], [[y, 0.0275, 0.0245, 0.0], [y + 0.002, 0.0275, 0.0245, 0.0]], 12)
	_tube(tools[1], [Vector3(side * 0.027, 0.006, 0.0), Vector3(side * 0.030, 0.019, 0.008), Vector3(side * 0.027, 0.025, 0.011)], 0.0025, 6)
	var mesh := _finish(tools)
	_meshes[key] = mesh
	return mesh


static func _forearm_mesh() -> ArrayMesh:
	if _meshes.has("forearm"): return _meshes.forearm as ArrayMesh
	var tools := _tools()
	_loft(tools[0], [[0.0, 0.024, 0.021, 0.0], [0.035, 0.027, 0.023, 0.0], [0.065, 0.029, 0.025, 0.0]], 12)
	# Tapered, slightly gathered tunic sleeve. Opaque geometry, no texture/alpha.
	_loft(tools[2], [[0.042, 0.032, 0.028, 0.0], [0.065, 0.034, 0.030, 0.0],
		[0.11, 0.038, 0.033, 0.003], [0.17, 0.040, 0.035, 0.0],
		[0.22, 0.044, 0.037, 0.002], [FOREARM_LENGTH, 0.043, 0.036, 0.0]], 12, 0.05)
	_loft(tools[1], [[0.048, 0.0345, 0.0305, 0.0], [0.060, 0.0355, 0.0315, 0.0]], 12)
	_tube(tools[1], [Vector3(0.0, 0.060, -0.032), Vector3(0.0, 0.12, -0.035),
		Vector3(0.0, 0.19, -0.037), Vector3(0.0, FOREARM_LENGTH, -0.037)], 0.0017, 6)
	var mesh := _finish(tools)
	_meshes.forearm = mesh
	return mesh


static func _triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
	na: Vector3, nb: Vector3, nc: Vector3, color := Color.WHITE) -> void:
	# Godot's front faces use clockwise winding; supplied normals remain outward.
	for pair in [[a, na], [c, nc], [b, nb]]:
		tool.set_normal(pair[1])
		tool.set_color(color)
		tool.add_vertex(pair[0])


static func _loft(tool: SurfaceTool, rings: Array, segments: int, crease := 0.0) -> void:
	for j in rings.size() - 1:
		var a: Array = rings[j]
		var b: Array = rings[j + 1]
		for i in segments:
			var angle := TAU * float(i) / float(segments)
			var next := TAU * float(i + 1) / float(segments)
			var pa := _ring_point(a, angle, crease)
			var pb := _ring_point(a, next, crease)
			var pc := _ring_point(b, angle, crease)
			var pd := _ring_point(b, next, crease)
			var sign_y := signf(float(b[0]) - float(a[0]))
			# The same normal on a shared ring prevents flat bands across the palm.
			var n0 := _loft_normal(rings, j, angle)
			var n1 := _loft_normal(rings, j, next)
			var n2 := _loft_normal(rings, j + 1, angle)
			var n3 := _loft_normal(rings, j + 1, next)
			if sign_y > 0.0:
				_triangle(tool, pa, pc, pb, n0, n2, n1)
				_triangle(tool, pb, pc, pd, n1, n2, n3)
			else:
				_triangle(tool, pa, pb, pc, n0, n1, n2)
				_triangle(tool, pb, pd, pc, n1, n3, n2)
	for k in [0, rings.size() - 1]:
		var ring: Array = rings[k]
		var normal := Vector3.UP * (-signf(float(rings[1][0]) - float(rings[0][0])) if k == 0 else signf(float(rings[1][0]) - float(rings[0][0])))
		var center := Vector3(0, float(ring[0]), float(ring[3]))
		for i in segments:
			var a := _ring_point(ring, TAU * float(i) / float(segments), crease)
			var b := _ring_point(ring, TAU * float(i + 1) / float(segments), crease)
			if normal.y > 0: _triangle(tool, center, b, a, normal, normal, normal)
			else: _triangle(tool, center, a, b, normal, normal, normal)


static func _ring_point(ring: Array, angle: float, crease: float) -> Vector3:
	var fold := 1.0 + sin(angle * 6.0 + float(ring[0]) * 41.0) * crease
	return Vector3(cos(angle) * float(ring[1]) * fold, float(ring[0]), float(ring[3]) + sin(angle) * float(ring[2]) * fold)


static func _loft_normal(rings: Array, index: int, angle: float) -> Vector3:
	var ring: Array = rings[index]
	var before: Array = rings[maxi(index - 1, 0)]
	var after: Array = rings[mini(index + 1, rings.size() - 1)]
	var span := float(after[0]) - float(before[0])
	var dx := (float(after[1]) - float(before[1])) / span
	var dz := (float(after[2]) - float(before[2])) / span
	var center := (float(after[3]) - float(before[3])) / span
	var c := cos(angle)
	var s := sin(angle)
	return Vector3(c / float(ring[1]), -c * c * dx / float(ring[1]) - s * s * dz / float(ring[2]) - s * center / float(ring[2]), s / float(ring[2])).normalized()


static func _tube(tool: SurfaceTool, points: Array[Vector3], radius: float, segments: int, color := Color.WHITE) -> void:
	var ring_points: Array[PackedVector3Array] = []
	var ring_normals: Array[PackedVector3Array] = []
	for j in points.size():
		var direction := points[mini(j + 1, points.size() - 1)] - points[maxi(j - 1, 0)]
		var basis := _basis_y(direction.normalized(), Vector3.UP)
		var verts := PackedVector3Array()
		var normals := PackedVector3Array()
		for i in segments:
			var angle := TAU * float(i) / float(segments)
			var normal := basis.x * cos(angle) + basis.z * sin(angle)
			verts.append(points[j] + normal * radius * (0.87 if j == points.size() - 1 else 1.0))
			normals.append(normal)
		ring_points.append(verts)
		ring_normals.append(normals)
	for j in points.size() - 1:
		for i in segments:
			var n := (i + 1) % segments
			_triangle(tool, ring_points[j][i], ring_points[j + 1][i], ring_points[j][n], ring_normals[j][i], ring_normals[j + 1][i], ring_normals[j][n], color)
			_triangle(tool, ring_points[j][n], ring_points[j + 1][i], ring_points[j + 1][n], ring_normals[j][n], ring_normals[j + 1][i], ring_normals[j + 1][n], color)
	for j in [0, points.size() - 1]:
		var normal := (points[0] - points[1]).normalized() if j == 0 else (points[-1] - points[-2]).normalized()
		for i in segments:
			var n := (i + 1) % segments
			if j == 0: _triangle(tool, points[j], ring_points[j][i], ring_points[j][n], normal, normal, normal, color)
			else: _triangle(tool, points[j], ring_points[j][n], ring_points[j][i], normal, normal, normal, color)


static func _ellipsoid(tool: SurfaceTool, center: Vector3, radius: Vector3, segments: int, rings: int, color := Color.WHITE) -> void:
	for j in rings:
		for i in segments:
			var vertices: Array[Vector3] = []
			var normals: Array[Vector3] = []
			for pair in [[j, i], [j + 1, i], [j, i + 1], [j + 1, i + 1]]:
				var p := PI * float(pair[0]) / float(rings)
				var a := TAU * float(pair[1]) / float(segments)
				var unit := Vector3(sin(p) * cos(a), cos(p), sin(p) * sin(a))
				vertices.append(center + unit * radius)
				normals.append((unit / radius).normalized())
			_triangle(tool, vertices[0], vertices[2], vertices[1], normals[0], normals[2], normals[1], color)
			_triangle(tool, vertices[2], vertices[3], vertices[1], normals[2], normals[3], normals[1], color)
