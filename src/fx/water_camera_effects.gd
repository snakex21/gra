class_name WaterCameraEffects
extends Node
## Per-camera environment; a second player's view can be above water at the same time.
var camera: Camera3D
var player: PlayerCharacter
var _source: Environment
var _cave: Environment
var _underwater: Environment
var underwater := false
var _climate_active := false
var _cave_active := true
var _dry_state := {}


## Called by GameWorld at the climate refresh rate. The underwater fog always keeps
## its own density and color; only its ambient illumination follows day and night.
func apply_climate(dry_state: Dictionary) -> void:
	_climate_active = true
	_dry_state = dry_state
	_cave_active = float(dry_state.get("exposure", 1.0)) < 0.05
	if _cave != null and _cave_active:
		for property in ["ambient_light_color", "ambient_light_energy", "fog_enabled", "fog_mode", "fog_density", "fog_height_density", "fog_light_color", "fog_sky_affect", "background_mode", "background_color"]:
			if dry_state.has(property):
				_cave.set(property, dry_state[property])
	if _underwater != null:
		_underwater.ambient_light_energy = maxf(0.16, float(dry_state.get("ambient_light_energy", 0.3)) * 0.65)

func _ready() -> void:
	process_priority = 11


## Shared hysteresis for the camera environment and weather precipitation.
static func is_submerged(at: Vector3, tree: SceneTree, was_underwater := false) -> bool:
	var height := WaterBody.surface_at(tree, at)
	return not is_nan(height) and at.y < height + (0.08 if was_underwater else -0.08)

func _process(_delta: float) -> void:
	if not is_instance_valid(camera) or not is_instance_valid(player):
		return
	if _source == null:
		_source = camera.get_world_3d().environment
		if _source == null:
			_source = Environment.new()
		_cave = _source.duplicate()
		_cave.background_mode = Environment.BG_COLOR
		_cave.background_color = Color(0.012, 0.018, 0.025)
		_cave.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_cave.ambient_light_color = Color(0.35, 0.42, 0.5)
		_cave.ambient_light_energy = 0.3
		_cave.fog_density = 0.012
		_cave.fog_enabled = true
		_cave.fog_light_color = Color(0.09, 0.13, 0.16)
		_underwater = _source.duplicate()
		_underwater.background_mode = Environment.BG_COLOR
		_underwater.background_color = Color(0.035, 0.14, 0.18)
		_underwater.fog_enabled = true
		_underwater.fog_light_color = Color(0.06, 0.23, 0.27)
		_underwater.fog_density = 0.12
		_underwater.fog_height_density = 0.0
		if _climate_active:
			apply_climate(_dry_state)
	# Small hysteresis avoids flicker as a wave passes the near plane.
	underwater = is_submerged(camera.global_position, get_tree(), underwater)
	camera.environment = _underwater if underwater else (_cave if player.beam.lantern and _cave_active else null)
