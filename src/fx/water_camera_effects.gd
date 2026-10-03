class_name WaterCameraEffects
extends Node
## Per-camera environment; a second player's view can be above water at the same time.
var camera: Camera3D
var player: PlayerCharacter
var _source: Environment
var _cave: Environment
var _underwater: Environment
var underwater := false

func _ready() -> void:
	process_priority = 11

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
	var y := WaterBody.surface_at(get_tree(), camera.global_position)
	# Small hysteresis avoids flicker as a wave passes the near plane.
	if is_nan(y):
		underwater = false
	else:
		underwater = camera.global_position.y < y + (0.08 if underwater else -0.08)
	camera.environment = _underwater if underwater else (_cave if player.beam.lantern else null)
