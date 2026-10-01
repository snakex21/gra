class_name Fx
## Light visual effects (no heavy particle systems): dust under heavy feet, a bigger cloud
## for a stomp, a small flash when a weak point is hit. A handful of CPU particles each,
## unshaded, no shadows, freed when done. ``Fx.enabled = false`` turns them off for
## benchmarks; ``Fx.spawned`` counts effects (perf report).

static var enabled := true
static var spawned := 0
static var _dust_mat: StandardMaterial3D
static var _burst_mat: StandardMaterial3D


static func dust(parent: Node, at: Vector3, size: float) -> void:
	if not enabled or parent == null or not parent.is_inside_tree():
		return
	var t0 := Perf.begin()
	if _dust_mat == null:
		_dust_mat = StandardMaterial3D.new()
		_dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_dust_mat.vertex_color_use_as_albedo = true
		_dust_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 10 if size < 1.5 else 18
	p.lifetime = 1.4 if size < 1.5 else 2.2
	p.explosiveness = 0.9
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 1.2 * size
	p.emission_ring_inner_radius = 0.3 * size
	p.emission_ring_height = 0.1
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.0 * size
	p.initial_velocity_max = 2.5 * size
	p.gravity = Vector3(0, -0.6, 0)
	p.damping_min = 1.5
	p.damping_max = 2.5
	p.scale_amount_min = 0.8 * size
	p.scale_amount_max = 1.6 * size
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.55, 0.5, 0.42, 0.55))
	ramp.set_color(1, Color(0.55, 0.5, 0.42, 0.0))
	p.color_ramp = ramp
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.material = _dust_mat
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spawn(parent, p, at)
	Perf.end(&"vfx", t0)


static func burst(parent: Node, at: Vector3) -> void:
	if not enabled or parent == null or not parent.is_inside_tree():
		return
	var t0 := Perf.begin()
	if _burst_mat == null:
		_burst_mat = StandardMaterial3D.new()
		_burst_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_burst_mat.albedo_color = Color(0.8, 0.95, 1.0)
		_burst_mat.emission_enabled = true
		_burst_mat.emission = Color(0.6, 0.9, 1.0)
		_burst_mat.emission_energy_multiplier = 4.0
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 14
	p.lifetime = 0.6
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 6.0
	p.gravity = Vector3(0, -8.0, 0)
	p.scale_amount_min = 0.12
	p.scale_amount_max = 0.22
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 6
	m.rings = 3
	m.material = _burst_mat
	p.mesh = m
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spawn(parent, p, at)
	Perf.end(&"vfx", t0)


static func _spawn(parent: Node, p: CPUParticles3D, at: Vector3) -> void:
	spawned += 1
	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)
