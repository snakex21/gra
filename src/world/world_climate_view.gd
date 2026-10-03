class_name WorldClimateView
extends Node3D
## Cosmetic weather only. Keep this node outside GameWorld.region/checkpoints.
## refresh() never writes camera.environment, actor state, collision or global shader TIME.

const SKY_SHADER := preload("res://src/fx/weather_sky.gdshader")
const PROFILES := {
	"low": {"rain": 96, "radius": 6.0, "detail": 0.0},
	"balanced": {"rain": 176, "radius": 8.0, "detail": 1.0},
	"high": {"rain": 256, "radius": 10.0, "detail": 2.0}
}
static var _rain_mesh: CylinderMesh
static var _rain_material: StandardMaterial3D

var sun: DirectionalLight3D
var environment: Environment
var sky_material: ShaderMaterial
var rain: CPUParticles3D
var last_sample := {}
var _profile := ""
var _dry_state := {}
var _configured := false

func setup(world: Node3D, explicit_sun: DirectionalLight3D = null, explicit_environment: WorldEnvironment = null) -> void:
	if _configured:
		return
	sun = explicit_sun
	var world_environment := explicit_environment
	for child in world.get_children():
		if sun == null and child is DirectionalLight3D:
			sun = child
		if world_environment == null and child is WorldEnvironment:
			world_environment = child
	if not is_instance_valid(sun) or not is_instance_valid(world_environment):
		push_error("WorldClimateView.setup needs the world's existing Sun and WorldEnvironment")
		return
	if world_environment.environment == null:
		world_environment.environment = Environment.new()
	environment = world_environment.environment
	sky_material = ShaderMaterial.new()
	sky_material.shader = SKY_SHADER
	# Reuse the authored Sky. Replacing a newly dirtied Sky before its first render
	# leaves native radiance allocations behind in Godot 4.6 Compatibility.
	if environment.sky == null:
		environment.sky = Sky.new()
	environment.sky.radiance_size = Sky.RADIANCE_SIZE_32
	environment.sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	environment.sky.sky_material = sky_material
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_sky_contribution = 0.0
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.volumetric_fog_enabled = false
	environment.ssao_enabled = false
	environment.ssil_enabled = false
	environment.ssr_enabled = false
	environment.sdfgi_enabled = false
	_build_rain()
	_configured = true

func refresh(sample: Dictionary, observer: Vector3, region_kind: String, graphics_profile: String = "balanced", force: bool = false) -> void:
	if not _configured:
		return
	var profile := graphics_profile if PROFILES.has(graphics_profile) else "balanced"
	var config: Dictionary = PROFILES[profile]
	if profile != _profile:
		_profile = profile
		rain.amount = config.rain
		rain.emission_box_extents = Vector3(config.radius, 0.35, config.radius)
		rain.visibility_aabb = AABB(Vector3(-config.radius - 3.0, -8.0, -config.radius - 3.0), Vector3(config.radius * 2.0 + 6.0, 9.0, config.radius * 2.0 + 6.0))
		sky_material.set_shader_parameter("cloud_detail", config.detail)
	last_sample = sample.duplicate()
	var hour := fposmod(float(sample.get("hour", 12.0)), 24.0)
	var daylight := clampf(float(sample.get("daylight", 1.0)), 0.0, 1.0)
	var cloud := clampf(float(sample.get("cloud", 0.2)), 0.0, 1.0)
	var precipitation := clampf(float(sample.get("rain", 0.0)), 0.0, 1.0)
	var mist := clampf(float(sample.get("fog", 0.0)), 0.0, 1.0)
	var haze := clampf(float(sample.get("haze", 0.0)), 0.0, 1.0)
	var anomaly := clampf(float(sample.get("anomaly", 0.0)), 0.0, 1.0)
	var exposure := clampf(float(sample.get("exposure", 1.0)), 0.0, 1.0)
	var sheltered := bool(sample.get("sheltered", false))
	var wind_strength := clampf(float(sample.get("wind_strength", 0.2)), 0.0, 1.0)
	var wind: Vector3 = sample.get("wind_direction", Vector3.RIGHT)
	wind.y = 0.0
	wind = wind.normalized() if wind.length_squared() > 0.0001 else Vector3.RIGHT
	var angle := (hour - 6.0) / 24.0 * TAU
	var sun_toward := Vector3(-cos(angle) * 0.95, sin(angle), 0.26).normalized()
	var moon_toward := -sun_toward
	var twilight := (1.0 - smoothstep(0.0, 0.45, absf(sun_toward.y))) * (1.0 - cloud * 0.7)
	var day_top := Color(0.28, 0.46, 0.55).lerp(Color(0.42, 0.47, 0.49), cloud * 0.82)
	var day_horizon := Color(0.77, 0.79, 0.69).lerp(Color(0.61, 0.66, 0.65), cloud * 0.9)
	var sky_top := Color(0.035, 0.060, 0.095).lerp(day_top, daylight)
	var horizon := Color(0.13, 0.18, 0.23).lerp(day_horizon, daylight)
	horizon = horizon.lerp(Color(0.70, 0.39, 0.24), twilight * 0.48)
	if haze > 0.0:
		horizon = horizon.lerp(Color(0.65, 0.57, 0.42), haze * daylight * 0.44)
	var cloud_color := Color(0.075, 0.095, 0.13).lerp(Color(0.84, 0.83, 0.73), daylight)
	cloud_color = cloud_color.lerp(Color(0.39, 0.43, 0.44), precipitation * daylight * 0.55)
	var day_index := float(sample.get("day_index", 0))
	# Clock-derived advection: stable after seek/load, no render-clock-dependent TIME.
	var wind_phase := fposmod((day_index * 24.0 + hour) * (0.045 + wind_strength * 0.12), 100.0)
	sky_material.set_shader_parameter("sky_top", sky_top)
	sky_material.set_shader_parameter("sky_horizon", horizon)
	sky_material.set_shader_parameter("ground_color", horizon.darkened(0.22))
	sky_material.set_shader_parameter("cloud_color", cloud_color)
	sky_material.set_shader_parameter("cloud_coverage", cloud)
	sky_material.set_shader_parameter("cloud_shift", Vector2(wind.x, wind.z) * wind_phase)
	sky_material.set_shader_parameter("daylight", daylight)
	sky_material.set_shader_parameter("sun_direction", sun_toward)
	sky_material.set_shader_parameter("moon_direction", moon_toward)
	sky_material.set_shader_parameter("sun_color", Color(1.0, 0.88, 0.64).lerp(Color(1.0, 0.46, 0.20), twilight * 0.65))
	sky_material.set_shader_parameter("anomaly", anomaly)
	# The same directional light handles moonlight; never a second shadow atlas.
	var light_toward := sun_toward if sun_toward.y >= -0.035 else moon_toward
	var up := Vector3.FORWARD if absf(light_toward.dot(Vector3.UP)) > 0.98 else Vector3.UP
	sun.global_basis = Basis.looking_at(-light_toward, up)
	sun.light_color = Color(0.57, 0.68, 0.86).lerp(Color(1.0, 0.94, 0.78).lerp(Color(1.0, 0.63, 0.37), twilight * 0.55), daylight)
	sun.light_energy = lerpf(0.17, 1.15, daylight) * (1.0 - cloud * 0.54) * lerpf(0.0, 1.0, exposure)
	var ambient_color := Color(0.46, 0.57, 0.72).lerp(Color(0.61, 0.70, 0.77), daylight)
	ambient_color = ambient_color.lerp(Color(0.51, 0.47, 0.64), anomaly * 0.07)
	var ambient_energy := lerpf(0.30, 0.62, daylight) * lerpf(0.48, 1.0, exposure)
	var fog_color := horizon.lerp(Color(0.17, 0.18, 0.24), anomaly * 0.10)
	var fog_density := 0.00062 + mist * 0.0036 + precipitation * 0.001 + haze * 0.0021
	var inside := exposure < 0.05
	if inside:
		fog_color = Color(0.09, 0.13, 0.16)
		fog_density = 0.004 + mist * 0.003
		ambient_color = Color(0.35, 0.42, 0.50)
		ambient_energy = 0.20
	environment.background_mode = Environment.BG_COLOR if inside else Environment.BG_SKY
	environment.background_color = Color(0.012, 0.018, 0.025) if inside else horizon
	environment.ambient_light_color = ambient_color
	environment.ambient_light_energy = ambient_energy
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_density = fog_density
	environment.fog_height_density = 0.0
	environment.fog_light_color = fog_color
	environment.fog_light_energy = 1.0
	environment.fog_sky_affect = 0.14
	_dry_state = {
		"ambient_light_color": ambient_color, "ambient_light_energy": ambient_energy,
		"fog_enabled": true, "fog_mode": Environment.FOG_MODE_EXPONENTIAL,
		"fog_density": fog_density, "fog_height_density": 0.0,
		"fog_light_color": fog_color, "fog_sky_affect": 0.14,
		"background_mode": environment.background_mode, "background_color": environment.background_color,
		"sky": environment.sky, "region_kind": region_kind, "exposure": exposure
	}
	rain.global_position = observer + Vector3(0, 5.5, 0)
	rain.direction = (Vector3.DOWN + wind * wind_strength * 0.36).normalized()
	rain.color = Color(0.67, 0.76, 0.82, (0.06 + precipitation * 0.16) * lerpf(0.65, 1.0, daylight))
	var show_rain := precipitation > 0.04 and exposure >= 0.5 and not sheltered
	var was_visible := rain.visible
	rain.visible = show_rain
	rain.emitting = show_rain
	if show_rain and (force or not was_visible):
		rain.restart(true)

func dry_environment_state() -> Dictionary:
	return _dry_state.duplicate()

func clear() -> void:
	if is_instance_valid(rain):
		rain.visible = false
		rain.emitting = false
	last_sample = {}

func _build_rain() -> void:
	if _rain_mesh == null:
		_rain_material = StandardMaterial3D.new()
		_rain_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_rain_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_rain_material.vertex_color_use_as_albedo = true
		_rain_material.albedo_color = Color.WHITE
		_rain_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_rain_material.disable_fog = true
		_rain_mesh = CylinderMesh.new()
		_rain_mesh.top_radius = 0.010
		_rain_mesh.bottom_radius = 0.010
		_rain_mesh.height = 0.38
		_rain_mesh.radial_segments = 4
		_rain_mesh.rings = 1
		_rain_mesh.cap_top = false
		_rain_mesh.cap_bottom = false
		_rain_mesh.material = _rain_material
	rain = CPUParticles3D.new()
	rain.name = "NearCameraRain"
	rain.mesh = _rain_mesh
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.direction = Vector3.DOWN
	rain.spread = 2.0
	rain.initial_velocity_min = 11.0
	rain.initial_velocity_max = 13.0
	rain.gravity = Vector3(0, -1.5, 0)
	rain.lifetime = 0.56
	rain.lifetime_randomness = 0.1
	rain.local_coords = false
	rain.fixed_fps = 30
	rain.fract_delta = true
	rain.use_fixed_seed = true
	rain.seed = 47821
	rain.set_particle_flag(CPUParticles3D.PARTICLE_FLAG_ALIGN_Y_TO_VELOCITY, true)
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rain.visible = false
	rain.emitting = false
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.10, 0.78, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	rain.color_ramp = ramp
	add_child(rain)
