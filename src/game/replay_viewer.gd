class_name ReplayViewer
extends Node
## Plays a recorded game back in a GameWorld, with the controls of a viewer:
##
##   K        pause / play          J / L     10 s back / forward
##   [ / ]    slower / faster       F7        free camera (WASD, Q/E, arrows) / back
##
## The recording is deterministic, so going back means starting the world again from
## the recording's start and running forward to that tick, fast. Running faster (or
## slower) changes how many ticks run per rendered frame, never the tick: the engine's
## time scale and its tick rate change together by a power of two, so each tick's step
## stays exactly 1/60 s and the run is bit for bit the one recorded.

signal reached(tick: int)

## Speed steps (powers of two: the tick stays exact).
const SPEEDS := [0.25, 0.5, 1.0, 2.0, 4.0]
## Fast-forward when seeking.
const SEEK_SPEED := 16.0
const BASE_TICKS := 60

var game: GameWorld
var data: Dictionary
var replay: ActionReplay
var paused := false
var speed := 1.0
var free_cam: Camera3D

var _target := -1
var _was_paused := false
var _restore := false
var _label: Label
var _yaw := 0.0
var _pitch := -0.3


func setup(p_game: GameWorld, p_data: Dictionary) -> void:
	game = p_game
	data = p_data


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# After everything else in a tick: it stops a seek exactly at its tick.
	process_physics_priority = 1000
	var layer := CanvasLayer.new()
	layer.layer = 15
	_label = Label.new()
	_label.position = Vector2(16, 12)
	_label.add_theme_font_size_override(&"font_size", 18)
	_label.add_theme_color_override(&"font_shadow_color", Color.BLACK)
	layer.add_child(_label)
	add_child(layer)
	restart()


## The world again from the recording's start, with a fresh playback.
func restart() -> void:
	var h: Dictionary = data.get("header", {})
	game.with_input = false
	game.save_path = ""
	game.seed_offset = int(h.get("seed_offset", 0))
	if is_instance_valid(replay):
		replay.free()
	game.start_from(h.get("progress", {}))
	replay = ActionReplay.player_for(null, data)
	replay.player_source = game.player
	game.add_child(replay)


func tick() -> int:
	return replay.tick if is_instance_valid(replay) else 0


func length() -> int:
	return int(data.get("ticks", 0))


## Runs (or rewinds and runs) to ``t`` and stops there, paused or playing as before.
func seek(t: int) -> void:
	t = clampi(t, 0, maxi(length(), 0))
	_was_paused = paused
	if t < tick():
		restart()
	if t == tick():
		reached.emit(t)
		return
	_target = t
	_set_rate(SEEK_SPEED)
	get_tree().paused = false


func set_paused(on: bool) -> void:
	paused = on
	if _target < 0:
		get_tree().paused = on


func faster(step: int) -> void:
	var i := clampi(SPEEDS.find(speed) + step, 0, SPEEDS.size() - 1)
	speed = SPEEDS[i]
	if _target < 0:
		_set_rate(speed)


func _physics_process(_delta: float) -> void:
	if _target >= 0 and tick() >= _target:
		# Exactly here: stop the tree before the next tick of this frame.
		_target = -1
		get_tree().paused = true
		_restore = true
		reached.emit(tick())


func _process(delta: float) -> void:
	if _restore:
		_restore = false
		_set_rate(speed)
		paused = _was_paused
		get_tree().paused = paused
	if free_cam and free_cam.current:
		_fly(delta)
	if _label:
		var t := tick() / float(BASE_TICKS)
		_label.text = "POWTÓRKA  %.1f / %.1f s  x%s%s   K pauza  J/L ±10 s  [ ] prędkość  F7 kamera" % [t, length() / float(BASE_TICKS), str(speed), "  (pauza)" if paused else ""]


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).physical_keycode:
		KEY_K:
			set_paused(not paused)
		KEY_J:
			seek(tick() - 10 * BASE_TICKS)
		KEY_L:
			seek(tick() + 10 * BASE_TICKS)
		KEY_BRACKETLEFT:
			faster(-1)
		KEY_BRACKETRIGHT:
			faster(1)
		KEY_F7:
			_toggle_free_camera()
		_:
			return
	get_viewport().set_input_as_handled()


## Tick rate and time scale together (powers of two): the step stays 1/60 s.
static func _set_rate(k: float) -> void:
	Engine.physics_ticks_per_second = int(round(BASE_TICKS * k))
	Engine.time_scale = k
	Engine.max_physics_steps_per_frame = maxi(8, int(8 * k))


func _exit_tree() -> void:
	_set_rate(1.0)


func _toggle_free_camera() -> void:
	if free_cam == null:
		free_cam = Camera3D.new()
		free_cam.name = "FreeCamera"
		free_cam.far = 4000.0
		add_child(free_cam)
	if free_cam.current:
		var cam: Variant = game.refs.get("camera")
		if cam is Camera3D:
			(cam as Camera3D).current = true
		return
	var from: Camera3D = get_viewport().get_camera_3d()
	if from:
		free_cam.global_transform = from.global_transform
		var e := from.global_basis.get_euler()
		_yaw = e.y
		_pitch = e.x
	free_cam.current = true


func _fly(delta: float) -> void:
	var turn := Vector2(float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_UP)) - float(Input.is_physical_key_pressed(KEY_DOWN)))
	_yaw -= turn.x * 1.6 * delta
	_pitch = clampf(_pitch + turn.y * 1.2 * delta, -1.4, 1.4)
	free_cam.basis = Basis.from_euler(Vector3(_pitch, _yaw, 0))
	var move := Vector3(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	var fast := 4.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
	free_cam.position += free_cam.basis * move * 14.0 * fast * delta
