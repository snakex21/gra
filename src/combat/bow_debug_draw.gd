class_name BowDebugDraw
extends MeshInstance3D
## Bow overlay (F3): while drawing, the predicted trajectory for the current draw (white,
## yellow at full draw) from the bow along the aim, the aim point (cyan) and the aim
## vector; for every arrow its flown path (orange) and where it hit (red = target hit,
## grey = surface). World-space lines; costs nothing while hidden.

var player: PlayerCharacter
var _mesh := ImmediateMesh.new()


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = true
	material_override = m
	visible = false


func _process(_delta: float) -> void:
	if not visible or player == null:
		return
	global_transform = Transform3D.IDENTITY
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var bow := player.bow
	if bow.is_aiming():
		var v := bow.aim_dir * bow.speed_for(bow.draw)
		var col := Color.YELLOW if bow.draw >= 1.0 else Color.WHITE
		var prev := bow.launch_point
		for k in range(1, 60):
			var p := ArrowSystem.predict(bow.launch_point, v, k * 0.05)
			_line(prev, p, col)
			prev = p
		_line(bow.launch_point, bow.aim_point, Color(0.3, 0.8, 1.0, 0.6))
		_cross(bow.aim_point, 0.4, Color.CYAN)
	for s in get_tree().get_nodes_in_group(&"arrow_systems"):
		for a in (s as ArrowSystem).arrows:
			var path: PackedVector3Array = a.path
			for i in range(1, path.size()):
				_line(path[i - 1], path[i], Color(1.0, 0.6, 0.2))
		var li: Dictionary = (s as ArrowSystem).last_impact
		if not li.is_empty():
			_cross(li.point, 0.5, Color.RED if li.accepted else Color(0.6, 0.6, 0.6))
	_mesh.surface_end()


func _line(a: Vector3, b: Vector3, c: Color) -> void:
	_mesh.surface_set_color(c)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(c)
	_mesh.surface_add_vertex(b)


func _cross(p: Vector3, r: float, c: Color) -> void:
	_line(p - Vector3.RIGHT * r, p + Vector3.RIGHT * r, c)
	_line(p - Vector3.FORWARD * r, p + Vector3.FORWARD * r, c)
	_line(p - Vector3.UP * r, p + Vector3.UP * r, c)
