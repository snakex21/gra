class_name HorseDebugDraw
extends MeshInstance3D
## World-space debug lines for Agro (toggle with F3):
##   green / yellow = planted / swinging foot     cyan    = planned landing spot
##   blue (short)   = ground normal               white   = actual heading
##   blue (long)    = desired direction           magenta = steer direction (after avoidance)
##   red / grey     = obstacle probes that hit / missed
## Costs nothing while hidden.

var horse: Horse
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
	if not visible or horse == null:
		return
	global_transform = Transform3D.IDENTITY
	var c := horse.controller
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for leg in horse.gait_planner.legs:
		if leg.is_planted():
			_cross(leg.plant_pos, 0.15, Color.GREEN)
		else:
			_cross(leg.foot_pos, 0.15, Color.YELLOW)
			_cross(leg.target_pos, 0.12, Color.CYAN)
			_line(leg.foot_pos, leg.target_pos, Color.CYAN)
		_line(leg.foot_pos, leg.foot_pos + leg.foot_normal * 0.4, Color(0.3, 0.5, 1.0))
	var o := horse.global_position + Vector3.UP * 2.2
	_line(o, o + c.forward() * 2.0, Color.WHITE)
	_line(o, o + c.desired_dir * 3.0, Color(0.3, 0.5, 1.0))
	_line(o, o + c.steer_dir * 2.5, Color.MAGENTA)
	for h in c.probe_hits:
		_line(h[0], h[1], Color.RED if h[2] else Color(0.6, 0.6, 0.6))
	_mesh.surface_end()


func _line(a: Vector3, b: Vector3, col: Color) -> void:
	_mesh.surface_set_color(col)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(col)
	_mesh.surface_add_vertex(b)


func _cross(p: Vector3, r: float, col: Color) -> void:
	_line(p - Vector3.RIGHT * r, p + Vector3.RIGHT * r, col)
	_line(p - Vector3.FORWARD * r, p + Vector3.FORWARD * r, col)
	_line(p, p + Vector3.UP * r, col)
