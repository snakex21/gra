class_name QuadrupedDebugDraw
extends MeshInstance3D
## World-space debug lines for a GreyboxQuadruped (toggle with F3, like the humanoid's):
##   green  = planted foot (bar height = its share of the weight)   yellow = swinging foot
##   cyan   = planned foot target       orange = weakened leg (support < 1)
##   white  = support polygon           red    = centre of mass and its ground projection
##   magenta = hip height each leg allows (the tilted body plane follows these)
## A subclass adds its own markers (arrow targets, climb route, weak points) by overriding
## _draw_extra(). Costs nothing while hidden.

var colossus: GreyboxQuadruped
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
	global_transform = Transform3D.IDENTITY
	var loco := colossus.loco
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var planted: Array[Vector3] = []
	for i in loco.legs.size():
		var leg := loco.legs[i]
		var weak := leg.support < 0.99
		if leg.is_planted():
			_cross(leg.plant_pos, 0.8, Color.ORANGE if weak else Color.GREEN)
			_line(leg.plant_pos, leg.plant_pos + Vector3.UP * (0.3 + 4.0 * leg.load), Color.GREEN)
			planted.append(leg.plant_pos)
		else:
			_cross(leg.foot_pos, 0.8, Color.YELLOW)
			_cross(leg.target_pos, 0.6, Color.CYAN)
			_line(leg.foot_pos, leg.target_pos, Color.CYAN)
		var hip := Vector3(leg.foot_pos.x, leg.hip_height_allowed, leg.foot_pos.z)
		_cross(hip, 0.4, Color.MAGENTA)
	# Support polygon in gait order around the body (FL, FR, RR, RL).
	var ring: Array[Vector3] = []
	for i in [0, 1, 3, 2]:
		if i < loco.legs.size() and loco.legs[i].is_planted():
			ring.append(loco.legs[i].plant_pos)
	for i in ring.size():
		_line(ring[i] + Vector3.UP * 0.05, ring[(i + 1) % ring.size()] + Vector3.UP * 0.05, Color.WHITE)
	var com_ground := Vector3(loco.com.x, loco.support_center.y, loco.com.z)
	_line(loco.com, com_ground, Color.RED)
	_cross(com_ground, 0.5, Color.RED)
	_cross(loco.support_center, 0.3, Color.WHITE)
	colossus._draw_debug_extra(self)
	_mesh.surface_end()


func line(a: Vector3, b: Vector3, c: Color) -> void:
	_line(a, b, c)


func cross(p: Vector3, r: float, c: Color) -> void:
	_cross(p, r, c)


func circle(center: Vector3, normal: Vector3, r: float, c: Color) -> void:
	var t := normal.cross(Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT).normalized()
	var b := normal.cross(t).normalized()
	for k in 16:
		var a0 := TAU * k / 16.0
		var a1 := TAU * (k + 1) / 16.0
		_line(center + (t * cos(a0) + b * sin(a0)) * r, center + (t * cos(a1) + b * sin(a1)) * r, c)


func _line(a: Vector3, b: Vector3, c: Color) -> void:
	_mesh.surface_set_color(c)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(c)
	_mesh.surface_add_vertex(b)


func _cross(p: Vector3, r: float, c: Color) -> void:
	_line(p - Vector3.RIGHT * r, p + Vector3.RIGHT * r, c)
	_line(p - Vector3.FORWARD * r, p + Vector3.FORWARD * r, c)
	_line(p, p + Vector3.UP * r, c)
