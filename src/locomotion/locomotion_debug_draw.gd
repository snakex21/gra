class_name LocomotionDebugDraw
extends MeshInstance3D
## World-space debug lines for a GreyboxHumanoid's locomotion (toggle with F3):
##   green  = planted (stance) foot      yellow = swinging foot
##   cyan   = planned foot target         blue   = ground normal at the foot
##   white  = support line/area           red    = centre of mass and its ground projection
## Costs nothing while hidden.

var colossus: GreyboxHumanoid
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
	if not visible or colossus == null:
		return
	var loco := colossus.loco
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var planted: Array[Vector3] = []
	for leg in loco.legs:
		if leg.is_planted():
			_cross(leg.plant_pos, 0.8, Color.GREEN)
			planted.append(leg.plant_pos)
		else:
			_cross(leg.foot_pos, 0.8, Color.YELLOW)
			_cross(leg.target_pos, 0.6, Color.CYAN)
			_line(leg.foot_pos, leg.target_pos, Color.CYAN)
		_line(leg.foot_pos, leg.foot_pos + leg.foot_normal * 1.5, Color(0.3, 0.5, 1.0))
	for i in planted.size():
		_line(planted[i] + Vector3.UP * 0.05, planted[(i + 1) % planted.size()] + Vector3.UP * 0.05, Color.WHITE)
	var com_ground := Vector3(loco.com.x, loco.support_center.y, loco.com.z)
	_line(loco.com, com_ground, Color.RED)
	_cross(com_ground, 0.5, Color.RED)
	_cross(loco.support_center, 0.3, Color.WHITE)
	_mesh.surface_end()


func _line(a: Vector3, b: Vector3, c: Color) -> void:
	_mesh.surface_set_color(c)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(c)
	_mesh.surface_add_vertex(b)


func _cross(p: Vector3, r: float, c: Color) -> void:
	_line(p - Vector3.RIGHT * r, p + Vector3.RIGHT * r, c)
	_line(p - Vector3.FORWARD * r, p + Vector3.FORWARD * r, c)
	_line(p, p + Vector3.UP * r, c)
