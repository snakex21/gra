class_name FlatInputSource
extends Node
## Fills a PlayerActions frame from keyboard / mouse / gamepad.
##
## For now every flat player reads the shared InputMap. Local co-op will give each
## source its own device filter; the gameplay side does not change.

@export var mouse_sensitivity := 0.0025
@export var stick_look_speed := 2.6  ## rad/s at full deflection
@export var invert_y := false

var actions: PlayerActions
## Node whose global basis movement is relative to (the player's camera).
var view: Node3D


func _ready() -> void:
	# Read input before gameplay and camera run.
	process_priority = -100


func _process(delta: float) -> void:
	if actions == null:
		return
	actions.move = Input.get_vector(&"move_left", &"move_right", &"move_back", &"move_forward")
	var stick := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	actions.look_delta += Vector2(stick.x, stick.y * (-1.0 if invert_y else 1.0)) * stick_look_speed * delta
	actions.grab_held = Input.is_action_pressed(&"grab")
	actions.focus_held = Input.is_action_pressed(&"focus")
	actions.attack_held = Input.is_action_pressed(&"attack")
	actions.beam_held = Input.is_action_pressed(&"sword_beam")
	actions.dive_held = Input.is_action_pressed(&"dive")
	if Input.is_action_just_pressed(&"jump"):
		actions.press_jump()
	if Input.is_action_just_pressed(&"interact"):
		actions.press_interact()
	if Input.is_action_just_pressed(&"call_horse"):
		actions.press_call()
	if Input.is_action_just_pressed(&"switch_weapon"):
		actions.press_switch_weapon()
	if view:
		actions.view_basis = view.global_basis
		actions.aim_origin = view.global_position


func _unhandled_input(event: InputEvent) -> void:
	if actions == null:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel: Vector2 = event.screen_relative
		actions.look_delta += Vector2(rel.x, rel.y * (-1.0 if invert_y else 1.0)) * mouse_sensitivity
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
