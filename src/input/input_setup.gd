class_name InputSetup
## Registers the default flat input actions at runtime if the project does not define them.
## Keeping the bindings in code keeps project.godot small and readable; any action
## defined in Project Settings takes precedence.


static func ensure_defaults() -> void:
	_action(&"move_forward", [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)])
	_action(&"move_back", [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)])
	_action(&"move_left", [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)])
	_action(&"move_right", [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)])
	_action(&"look_left", [_axis(JOY_AXIS_RIGHT_X, -1.0)])
	_action(&"look_right", [_axis(JOY_AXIS_RIGHT_X, 1.0)])
	_action(&"look_up", [_axis(JOY_AXIS_RIGHT_Y, -1.0)])
	_action(&"look_down", [_axis(JOY_AXIS_RIGHT_Y, 1.0)])
	_action(&"jump", [_key(KEY_SPACE), _button(JOY_BUTTON_A)])
	_action(&"grab", [_mouse(MOUSE_BUTTON_RIGHT), _key(KEY_SHIFT), _button(JOY_BUTTON_RIGHT_SHOULDER), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)])
	_action(&"focus", [_key(KEY_Q), _mouse(MOUSE_BUTTON_MIDDLE), _button(JOY_BUTTON_LEFT_SHOULDER)])
	_action(&"interact", [_key(KEY_E), _button(JOY_BUTTON_Y)])
	_action(&"call_horse", [_key(KEY_C), _button(JOY_BUTTON_DPAD_DOWN)])
	_action(&"ride_steer_mode", [_key(KEY_F6), _button(JOY_BUTTON_DPAD_UP)])
	_action(&"respawn", [_key(KEY_BACKSPACE), _button(JOY_BUTTON_BACK)])
	_action(&"debug_colossus_mode", [_key(KEY_F2)])
	_action(&"debug_draw", [_key(KEY_F3)])
	_action(&"debug_locomotion_mode", [_key(KEY_F4)])
	_action(&"toggle_help", [_key(KEY_F1)])


static func _action(name: StringName, events: Array) -> void:
	if InputMap.has_action(name):
		return
	InputMap.add_action(name, 0.25)
	for e in events:
		InputMap.action_add_event(name, e)


static func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


static func _mouse(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	return e


static func _button(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.device = -1
	return e


static func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	e.device = -1
	return e
