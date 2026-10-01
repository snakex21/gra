class_name CombatDebugDraw
extends MeshInstance3D
## Combat overlay (F3): hit volumes (red = active, orange = winding up, grey = idle),
## attack ranges (stomp shockwave ring, sweep arc), the weak point (cyan open / grey
## protected), grip surfaces (brown outlines), rest surfaces (green) and the climb route.
## World-space lines; costs nothing while hidden.

## The intended climb route, as [bone, bone-space point] pairs.
const ROUTE := [
	[&"shin_l", Vector3(0, -2.2, 1.0)], [&"shin_l", Vector3(0, 0.0, 1.0)],
	[&"thigh_l", Vector3(0, -2.0, 1.1)], [&"hips", Vector3(0.6, 0.4, 1.4)],
	[&"spine", Vector3(0, 1.2, 1.3)], [&"chest", Vector3(0, 1.4, 1.95)],
	[&"chest", Vector3(0.9, 2.85, 1.0)], [&"neck", Vector3(0, 0.6, 1.45)],
	[&"head", Vector3(0, 1.4, 1.45)], [&"head", Vector3(0, 2.55, 0.4)],
]

## Any two-legged boss (Valus, Gaius); the climb route line is Valus' own.
var valus: HumanoidBoss
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
	if not visible or valus == null:
		return
	global_transform = Transform3D.IDENTITY
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var a := valus.attack
	var winding := a != null and not a.is_done() and a.phase == ColossusAttack.Phase.TELEGRAPH
	for key in valus.hit_volumes:
		var h: HitVolume = valus.hit_volumes[key]
		var related := a != null and not a.is_done() and ((a.kind == HumanoidBoss.STOMP and String(key).begins_with("foot") and (String(key).ends_with("_l") == (a.limb == 0))) or (a.kind != HumanoidBoss.STOMP and not String(key).begins_with("foot") and (String(key).ends_with("_l") == (a.limb == 0))))
		var col := Color(0.5, 0.5, 0.5, 0.5)
		if h.active:
			col = Color.RED
		elif related and winding:
			col = Color.ORANGE
		_capsule(h.world_a, h.world_b, h.radius, col)
	if a != null and not a.is_done() and a.kind == HumanoidBoss.STOMP and a.phase != ColossusAttack.Phase.PREPARE:
		_circle(valus._slam_point + Vector3.UP * 0.1, valus.shockwave_radius, Color.ORANGE_RED if winding else Color.RED)
	for z in valus.get_danger_zones():
		_circle((z[0] as Vector3) + Vector3.UP * 0.2, z[1], Color(1, 0.6, 0.1))
	var wp := valus.weak_point
	var wc := Color.CYAN if wp.state == WeakPoint.State.OPEN else Color.GRAY
	_cross(wp.world_point(), wp.radius, wc)
	_circle(wp.world_point(), wp.radius, wc)
	# Surfaces: grip (fur) outlines and rest plateaus.
	for seg in valus.segments:
		for c in seg.get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
				var cs := c as CollisionShape3D
				var size: Vector3 = (cs.shape as BoxShape3D).size
				var xf := seg.target_transform * cs.transform
				if cs.has_meta(&"surface") and cs.get_meta(&"surface") == &"rest":
					_box_top(xf, size, Color.GREEN)
				elif cs is ClimbPatch:
					_box_top(xf, size, Color(0.75, 0.5, 0.25, 0.7))
	# Climb route (Valus).
	if not valus is Valus:
		_mesh.surface_end()
		return
	var prev := Vector3.INF
	for r in ROUTE:
		var seg := _seg(r[0])
		if seg == null:
			continue
		var p: Vector3 = seg.target_transform * (r[1] as Vector3)
		if prev != Vector3.INF:
			_line(prev, p, Color.YELLOW)
		_cross(p, 0.25, Color.YELLOW)
		prev = p
	_mesh.surface_end()


func _seg(bone: StringName) -> BodySegment:
	for s in valus.segments:
		if s.bone_name == bone:
			return s
	return null


func _line(a: Vector3, b: Vector3, c: Color) -> void:
	_mesh.surface_set_color(c)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(c)
	_mesh.surface_add_vertex(b)


func _cross(p: Vector3, s: float, c: Color) -> void:
	_line(p - Vector3.RIGHT * s, p + Vector3.RIGHT * s, c)
	_line(p - Vector3.UP * s, p + Vector3.UP * s, c)
	_line(p - Vector3.BACK * s, p + Vector3.BACK * s, c)


func _circle(center: Vector3, r: float, c: Color) -> void:
	var n := 32
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		_line(center + Vector3(cos(a0), 0, sin(a0)) * r, center + Vector3(cos(a1), 0, sin(a1)) * r, c)


func _capsule(a: Vector3, b: Vector3, r: float, c: Color) -> void:
	_line(a, b, c)
	var d := (b - a).normalized() if (b - a).length() > 1e-4 else Vector3.UP
	var u := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := d.cross(u).normalized()
	for k in 4:
		var off := (u if k % 2 == 0 else v) * r * (1.0 if k < 2 else -1.0)
		_line(a + off, b + off, c)


func _box_top(xf: Transform3D, size: Vector3, c: Color) -> void:
	var h := size * 0.5
	var pts := [Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	for i in 4:
		_line(xf * (pts[i] as Vector3), xf * (pts[(i + 1) % 4] as Vector3), c)
