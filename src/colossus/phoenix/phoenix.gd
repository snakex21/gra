class_name Phoenix
extends WingedGuardian
## New firebird interpretation: lure into falling water, cool the shield, climb
## the dry back during its cooling window and descend before heat rebuilds.
signal phase_changed(phase: Phase)
enum Phase { HOT, COOLING, COOLED, REHEATING }
const STREAMS_LOCAL := [Vector3(-20, 0, -12), Vector3(20, 0, -12)]
var phase := Phase.HOT
var phase_time := 0.0
var heat := 1.0
var cooling_time := 0.0
var fire_time := 0.0
var fire_active := false
var fire_at := Vector3.ZERO
var fire_cooldown := 0.0
var _local_at := Vector3(0, 2.25, 4)
var _ground_yaw := 0.0
var _warning: MeshInstance3D
var _heat_halo: MeshInstance3D
var _cool_material: StandardMaterial3D
var _retreat_to := Vector3.ZERO

func _ready() -> void:
	super()
	_warning = MeshInstance3D.new()
	_warning.name = "LockedFlameWarning"
	_warning.top_level = true
	var disk := CylinderMesh.new()
	disk.top_radius = 3.3
	disk.bottom_radius = 3.3
	disk.height = .04
	_warning.mesh = disk
	_warning.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.albedo_color = Color(.95, .28, .02, .45)
	_warning.material_override = glow
	add_child(_warning)
	_warning.visible = false
	_heat_halo = MeshInstance3D.new()
	_heat_halo.name = "HeatShield"
	var shell := SphereMesh.new()
	shell.radius = 3.0
	shell.height = 5.0
	_heat_halo.mesh = shell
	_heat_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var heat_material := StandardMaterial3D.new()
	heat_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	heat_material.albedo_color = Color(.95, .24, .02, .065)
	heat_material.emission_enabled = true
	heat_material.emission = Color(.8, .12, .01)
	heat_material.emission_energy_multiplier = .35
	_heat_halo.material_override = heat_material
	add_child(_heat_halo)
	_cool_material = StandardMaterial3D.new()
	_cool_material.albedo_color = Color(.34, .50, .55)
	_cool_material.roughness = .89
	_body_material.albedo_color = Color(.58, .32, .09)

func _reset_motion() -> void:
	phase = Phase.HOT
	phase_time = 0
	heat = 1
	cooling_time = 0
	fire_time = 0
	fire_active = false
	fire_cooldown = 1.0
	_local_at = Vector3(0, 2.25, 4)
	_ground_yaw = 0
	_set_ground()
	if is_instance_valid(_warning):
		_warning.visible = false

func _set_ground() -> void:
	global_transform = Transform3D(_spawn_xf.basis * Basis(Vector3.UP, _ground_yaw), _spawn_xf * _local_at)

func _phase(next: Phase) -> void:
	phase = next
	phase_time = 0
	phase_changed.emit(next)

func _nearest_stream() -> Vector3:
	return STREAMS_LOCAL[0] if _flat(_local_at - STREAMS_LOCAL[0]).length() < _flat(_local_at - STREAMS_LOCAL[1]).length() else STREAMS_LOCAL[1]

static func _flat(point: Vector3) -> Vector3:
	return Vector3(point.x, 0, point.z)

func _execute_intent(_it: ColossusIntent, delta: float) -> void:
	if debug_override == &"frozen":
		return
	if is_defeated():
		_set_exposed(false)
		_warning.visible = false
		_heat_halo.visible = false
		return
	if encounter != Encounter.COMBAT:
		return
	phase_time += delta
	fire_cooldown = maxf(0, fire_cooldown - delta)
	var wet := _flat(_local_at - _nearest_stream()).length() < 5.7
	match phase:
		Phase.HOT:
			if wet:
				fire_active = false
				_warning.visible = false
				cooling_time = 0
				_phase(Phase.COOLING)
			else:
				var target := _living_target()
				if target:
					var to := _flat(_spawn_xf.affine_inverse() * target.global_position - _local_at)
					if not fire_active and to.length() > 6:
						_local_at += to.normalized() * minf(3.8 * delta, to.length() - 6)
						_local_at.x = clampf(_local_at.x, -65, 65)
						_local_at.z = clampf(_local_at.z, -65, 72)
						_ground_yaw = rotate_toward(_ground_yaw, atan2(-to.x, -to.z), delta * .8)
					if fire_cooldown <= 0 and to.length() < 16 and not _rider_present():
						fire_active = true
						fire_time = 0
						fire_at = target.global_position
						fire_at.y = arena_center.y + .04
						_warning.global_position = fire_at
						_warning.visible = true
						fire_cooldown = 5.5
						Sfx.play(self, &"roar", global_position)
			_wing_angle = .20 + .07 * sin(_time * 2.5)
		Phase.COOLING:
			cooling_time += delta
			heat = maxf(0, 1 - cooling_time / 2)
			_wing_angle = .08
			if cooling_time >= 2:
				stats.coolings += 1
				_phase(Phase.COOLED)
		Phase.COOLED:
			heat = 0
			_wing_angle = .07
			if phase_time >= 17:
				var away := _flat(_local_at - _nearest_stream()).normalized()
				if away.length() < .1:
					away = Vector3(0, 0, 1)
				_retreat_to = _nearest_stream() + away * 11
				_retreat_to.y = 2.25
				_phase(Phase.REHEATING)
		Phase.REHEATING:
			heat = clampf(phase_time / 5, 0, 1)
			_wing_angle = .12 + .15 * sin(_time * 3)
			if phase_time >= 5:
				_set_exposed(false)
				var to := _flat(_retreat_to - _local_at)
				_local_at += to.normalized() * minf(delta * 3, to.length())
				if not wet and phase_time > 7:
					fire_cooldown = 2
					_phase(Phase.HOT)
	if fire_active:
		fire_time += delta
		if fire_time >= 1.75:
			stats["flame_casts"] = int(stats.get("flame_casts", 0)) + 1
			for p in get_tree().get_nodes_in_group(&"players"):
				var inside_water := false
				for stream in STREAMS_LOCAL:
					inside_water = inside_water or _flat(p.global_position - _spawn_xf * stream).length() < 6
				if not p.dead and not inside_water and _flat(p.global_position - fire_at).length() < 3.3:
					if p.apply_hit(16, Vector3.UP * 2 + (p.global_position - fire_at).normalized() * 3, .2, &"phoenix_flame"):
						stats.hits_on_player += 1
			fire_active = false
			_warning.visible = false
	_set_ground()
	_set_exposed(phase == Phase.COOLED or phase == Phase.REHEATING and phase_time < 5)
	_heat_halo.visible = phase in [Phase.HOT, Phase.REHEATING]
	if phase == Phase.REHEATING and phase_time >= 5:
		for p in get_tree().get_nodes_in_group(&"players"):
			if not p.dead and (owns_body(p.get_support_body()) or p.is_climbing() and owns_body(p.grip.body)):
				if p.apply_hit(7, Vector3.UP * 1.5, .1, &"phoenix_heat"):
					stats.hits_on_player += 1
	# Override is per-instance; imported mesh materials remain shared and untouched.
	for segment in segments:
		var art := segment.get_node_or_null("GuardianArt")
		if art:
			for visual in art.get_children():
				visual.material_override = _cool_material if heat < .3 else null

func get_danger_zones() -> Array:
	return [[fire_at, 3.3]] if fire_active else []

func encounter_hint() -> String:
	match phase:
		Phase.HOT:
			return "Tarcza gorąca. Zwab Phoenixa pod strumień wody; omiń pomarańczowy krąg płomienia."
		Phase.COOLING:
			return "Woda studzi pancerz. Poczekaj na otwarcie pieczęci."
		Phase.COOLED:
			return "Grzbiet schłodzony. Wejdź od tyłu i uderz pieczęć mieczem."
		_:
			return "Gorąco wraca — zejdź z grzbietu, zanim tarcza ponownie się zamknie."

func debug_text() -> String:
	return "PHOENIX %s %.1f heat %.2f\n%s" % [Phase.keys()[phase], phase_time, heat, super()]
