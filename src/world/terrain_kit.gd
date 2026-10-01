class_name TerrainKit
## Simple static test terrain (greybox): slopes, bumps and steps on the WORLD layer.
## Used by the sandbox and the locomotion tests; not final level geometry.


## A test course running along -Z from ``origin`` (all heights relative to origin.y):
##   0..-12   flat
##  -12..-32  10 deg ramp up (+3.5 m)
##  -32..-46  plateau with low bumps (0.25-0.5 m)
##  -46       0.8 m step down, then flat to -60
## Returns the root node.
static func build_course(parent: Node, origin: Vector3, width := 22.0) -> Node3D:
	var root := Node3D.new()
	root.name = "TerrainCourse"
	root.position = origin
	parent.add_child(root)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.46, 0.36)
	var rise := 20.0 * tan(deg_to_rad(10.0))
	ramp(root, Vector3(0, 0, -12), 20.0, 10.0, width, mat)
	box(root, Vector3(0, rise - 1.0, -39.0), Vector3(width, 2.0, 14.0), mat)
	var bumps := [Vector3(-5, 0, -35), Vector3(4, 0, -37), Vector3(-1, 0, -40.5), Vector3(6, 0, -43), Vector3(-6, 0, -44)]
	var heights := [0.35, 0.5, 0.25, 0.4, 0.3]
	for i in bumps.size():
		var h: float = heights[i]
		box(root, bumps[i] + Vector3(0, rise + h * 0.5 - 0.2, 0), Vector3(3.5, h + 0.4, 3.0), mat, Basis(Vector3.UP, 0.4 * i))
	box(root, Vector3(0, rise - 0.8 - 1.0, -53.0), Vector3(width, 2.0, 14.0), mat)
	return root


## Ramp rising along -Z from ``start`` (top surface starts at start.y).
static func ramp(parent: Node3D, start: Vector3, length: float, angle_deg: float, width: float, mat: Material) -> StaticBody3D:
	var a := deg_to_rad(angle_deg)
	var thickness := 2.0
	var basis := Basis(Vector3.RIGHT, a)
	var top_mid := start + Vector3(0, length * 0.5 * tan(a), -length * 0.5)
	var center := top_mid - basis.y * (thickness * 0.5)
	var body := box(parent, center, Vector3(width, thickness, length / cos(a) + 0.6), mat, basis)
	return body


static func box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, rot := Basis.IDENTITY) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.basis = rot
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = mat
	body.add_child(mesh)
	# Transform before entering the tree: physics queries in the same frame must see it there.
	body.position = pos
	parent.add_child(body)
	return body
