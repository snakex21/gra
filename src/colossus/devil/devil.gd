class_name Devil
extends WingedGuardian
## New interpretation of the cut guardian: ceiling ambush, sword-light landing,
## short rear climb. This does not claim to reconstruct an unreleased design.
signal phase_changed(phase: Phase)
enum Phase { HANGING, WARNING, DESCENDING, EXPOSED, RECOVERING, RISING }
const CEILING := Vector3(0, 18.0, -4.0)
const LAND := Vector3(0, 2.25, -4.0)
var phase := Phase.HANGING
var phase_time := 0.0
var light_time := 0.0
var exposure_time := 0.0
var _drop_from := CEILING
var _drop_to := LAND
var _lit_drop := false
var _warning: MeshInstance3D
var _hit_once := {}

func _ready() -> void:
	super()
	_warning = MeshInstance3D.new()
	_warning.name = "AmbushWarning"
	_warning.top_level = true
	var disk := CylinderMesh.new()
	disk.top_radius = 3.2
	disk.bottom_radius = 3.2
	disk.height = 0.04
	_warning.mesh = disk
	_warning.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.55, 0.22, 0.04, 0.50)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = Color(0.7, 0.2, 0.04)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_warning.material_override = material
	_warning.layers = 2
	add_child(_warning)
	_warning.visible = false
	_set_layers(self)

static func _set_layers(node: Node) -> void:
	if node is GeometryInstance3D:
		node.layers = 2
	for child in node.get_children():
		_set_layers(child)

func _reset_motion() -> void:
	phase = Phase.HANGING
	phase_time = 0
	light_time = 0
	exposure_time = 0
	_lit_drop = false
	_hit_once.clear()
	_drop_to = LAND
	_wing_angle = 1.15
	_set_motion(CEILING, PI)
	if is_instance_valid(_warning):
		_warning.visible = false

func _phase(next: Phase) -> void:
	phase = next
	phase_time = 0
	_think_left = 0
	phase_changed.emit(next)

func _light_reaches() -> bool:
	for node in get_tree().get_nodes_in_group(&"players"):
		var p := node as PlayerCharacter
		if p == null or p.dead or not p.beam.lantern or p.beam.raise < 1.0:
			continue
		var from := SwordBeam.tip(p)
		var to := get_focus_point() - from
		if to.length() > 40.0 or p.beam.direction.dot(to.normalized()) < cos(deg_to_rad(24)):
			continue
		var ray := PhysicsRayQueryParameters3D.create(from, get_focus_point(), Layers.WORLD)
		if get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			return true
	return false

func _execute_intent(_it: ColossusIntent, delta: float) -> void:
	if debug_override == &"frozen":
		return
	if is_defeated():
		_set_exposed(false)
		_warning.visible = false
		_wing_angle = move_toward(_wing_angle, 0.65, delta * .25)
		return
	if encounter != Encounter.COMBAT:
		return
	phase_time += delta
	light_time = light_time + delta if phase in [Phase.HANGING, Phase.WARNING] and _light_reaches() else 0.0
	if light_time >= .85:
		stats.light_breaks += 1
		_lit_drop = true
		_drop_from = _spawn_xf.affine_inverse() * global_position
		_drop_to = LAND
		_warning.visible = false
		_phase(Phase.DESCENDING)
		light_time = 0
	match phase:
		Phase.HANGING:
			_wing_angle = 1.15 + .06 * sin(_time * 2)
			_set_motion(CEILING, PI)
			if phase_time > 7.0:
				var target := _living_target()
				if target:
					var at := _spawn_xf.affine_inverse() * target.global_position
					_drop_to = Vector3(clampf(at.x, -12, 12), 2.25, clampf(at.z, -19, 18))
					_drop_from = CEILING
					_lit_drop = false
					_hit_once.clear()
					_warning.global_position = _spawn_xf * Vector3(_drop_to.x, .04, _drop_to.z)
					_warning.visible = true
					Sfx.play(self, &"roar", global_position)
					_phase(Phase.WARNING)
		Phase.WARNING:
			_wing_angle = .75
			if phase_time >= 2.2:
				stats.ambushes += 1
				_phase(Phase.DESCENDING)
		Phase.DESCENDING:
			var u := smoothstep(0, 1, phase_time / 2.5)
			_set_motion(_drop_from.lerp(_drop_to, u), lerpf(PI, 0, u))
			_wing_angle = lerpf(.75, .08, u)
			if phase_time >= 2.5:
				stats.landings += 1
				if not _lit_drop:
					_ambush_impact()
				_warning.visible = false
				exposure_time = 0
				_phase(Phase.EXPOSED)
		Phase.EXPOSED:
			_set_motion(_drop_to, .018 * sin(_time * 1.4))
			_wing_angle = .07
			exposure_time += delta
			var limit := 48.0 if _lit_drop else 3.0
			if (exposure_time > limit and not _rider_present()) or exposure_time > 75:
				_phase(Phase.RECOVERING)
		Phase.RECOVERING:
			_wing_angle = .08 + .32 * phase_time / 3
			if phase_time >= 3.0:
				if _rider_present():
					# A protected short landing lets a solo climber descend safely.
					for p in get_tree().get_nodes_in_group(&"players"):
						if owns_body(p.get_support_body()):
							p.apply_hit(8, Vector3.UP * 2 + (_spawn_xf.basis.z * 3), .2, &"devil_takeoff")
				else:
					_drop_from = _spawn_xf.affine_inverse() * global_position
					_phase(Phase.RISING)
		Phase.RISING:
			var u := smoothstep(0, 1, phase_time / 3)
			_set_motion(_drop_from.lerp(CEILING, u), PI * u)
			_wing_angle = .25 + .20 * sin(_time * 7)
			if phase_time > 3:
				_phase(Phase.HANGING)
	_set_exposed(phase == Phase.EXPOSED and _lit_drop)

func _ambush_impact() -> void:
	var impact := _spawn_xf * Vector3(_drop_to.x, .95, _drop_to.z)
	for p in get_tree().get_nodes_in_group(&"players"):
		var id: int = p.get_instance_id()
		if p.dead or _hit_once.has(id) or Vector2(p.global_position.x - impact.x, p.global_position.z - impact.z).length() > 3.2:
			continue
		_hit_once[id] = true
		if p.apply_hit(20.0, (p.global_position - impact).normalized() * 5 + Vector3.UP * 3, .35, &"devil_ambush"):
			stats.hits_on_player += 1

func get_danger_zones() -> Array:
	return [[_spawn_xf * Vector3(_drop_to.x, 0, _drop_to.z), 3.2]] if phase in [Phase.WARNING, Phase.DESCENDING] and not _lit_drop else []

func encounter_hint() -> String:
	match phase:
		Phase.HANGING, Phase.WARNING:
			return "Devil pod sufitem. V — skieruj światło miecza w strażnika; omiń krąg zasadzki."
		Phase.DESCENDING:
			return "Schodzi z sufitu. Podejdź od tyłu dopiero po lądowaniu."
		Phase.EXPOSED:
			return "Światło otworzyło grzbiet. Złap futro od tyłu, wejdź na grzbiet i uderz pieczęć." if _lit_drop else "Pancerz zamknięty. Odsuń się i poczekaj, aż wróci pod sufit."
		_:
			return "Skrzydła się rozkładają — zejdź z grzbietu przed powrotem pod sufit."

func debug_text() -> String:
	return "DEVIL %s %.1f light %.1f\n%s" % [Phase.keys()[phase], phase_time, light_time, super()]
