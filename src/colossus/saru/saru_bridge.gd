class_name SaruBridge
extends Node3D
## Two suspended counterweights slide separate bridge spans into the chasm.
const STARTS := [Vector3(-20, 5, 15), Vector3(20, 5, -15)]
const BAITS := [Vector3(-27.5, 6.95, 39), Vector3(52, 6.95, 39)]
var opened: Array[bool] = [false, false]
var progress: Array[float] = [0.0, 0.0]
var impacts := 0
var route_open := false
var spans: Array[StaticBody3D] = []
var panels: Array[CollisionShape3D] = []
var panel_meshes: Array[MeshInstance3D] = []
var _mat: StandardMaterial3D

func _ready() -> void:
	process_physics_priority = -15
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.4, 0.42, 0.33)
	for i in 2:
		var span := TerrainKit.box(self, STARTS[i], Vector3(8, 2, 30), _mat)
		span.name = "HangingSpan%d" % i
		span.set_meta(&"saru_counterweight", i)
		spans.append(span)
		var panel := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(8, 20, 3)
		panel.shape = box
		panel.position = Vector3(0, 11, 0)
		span.add_child(panel)
		panels.append(panel)
		var mesh := MeshInstance3D.new()
		var cube := BoxMesh.new()
		cube.size = box.size
		mesh.mesh = cube
		mesh.position = panel.position
		var cloth := StandardMaterial3D.new()
		cloth.albedo_color = Color(0.8, 0.53, 0.13)
		mesh.material_override = cloth
		span.add_child(mesh)
		panel_meshes.append(mesh)
		# The horizontal rails make the shift visible and explain the suspended blocks.
		TerrainKit.box(self, Vector3(0, 28, STARTS[i].z), Vector3(60, 1, 2), _mat)
		for side: float in [-1, 1]:
			TerrainKit.box(self, Vector3(side * 30, 14, STARTS[i].z), Vector3(1.5, 28, 1.5), _mat)

func _physics_process(delta: float) -> void:
	for i in 2:
		if opened[i]:
			progress[i] = minf(1, progress[i] + delta / 3.0)
		var at: Vector3 = STARTS[i]
		at.x = lerpf(at.x, 0.0, smoothstep(0, 1, progress[i]))
		spans[i].position = at
	route_open = progress[0] >= 1 and progress[1] >= 1

func stone_impact(index: int) -> bool:
	if index < 0 or index > 1 or opened[index]:
		return false
	opened[index] = true
	impacts += 1
	panels[index].set_deferred(&"disabled", true)
	panel_meshes[index].visible = false
	return true

func reset() -> void:
	opened = [false, false]
	progress = [0.0, 0.0]
	impacts = 0
	route_open = false
	for i in 2:
		spans[i].position = STARTS[i]
		panels[i].set_deferred(&"disabled", false)
		panel_meshes[i].visible = true
