class_name InputSetup
## Registers the default flat input actions at runtime if the project does not define them.
## Keeping the bindings in code keeps project.godot small and readable; any action
## defined in Project Settings takes precedence.


## Actions a player can rebind (keyboard / mouse; the pad keeps its defaults), with the
## names shown in the menu.
const REBINDABLE := [
	[&"move_forward", "Naprzód"], [&"move_back", "Do tyłu"], [&"move_left", "W lewo"], [&"move_right", "W prawo"],
	[&"jump", "Skok"], [&"grab", "Chwyt"], [&"attack", "Cios / strzał"], [&"focus", "Patrz na kolosa"],
	[&"interact", "Wsiądź / zsiądź"], [&"call_horse", "Zawołaj Agro"], [&"switch_weapon", "Zmień broń"],
	[&"sword_beam", "Miecz do słońca"],
]


static func defaults() -> Dictionary:
	return {
		&"move_forward": [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)],
		&"move_back": [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)],
		&"move_left": [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)],
		&"move_right": [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)],
		&"look_left": [_axis(JOY_AXIS_RIGHT_X, -1.0)],
		&"look_right": [_axis(JOY_AXIS_RIGHT_X, 1.0)],
		&"look_up": [_axis(JOY_AXIS_RIGHT_Y, -1.0)],
		&"look_down": [_axis(JOY_AXIS_RIGHT_Y, 1.0)],
		&"jump": [_key(KEY_SPACE), _button(JOY_BUTTON_A)],
		&"grab": [_mouse(MOUSE_BUTTON_RIGHT), _key(KEY_SHIFT), _button(JOY_BUTTON_RIGHT_SHOULDER), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)],
		&"focus": [_key(KEY_Q), _mouse(MOUSE_BUTTON_MIDDLE), _button(JOY_BUTTON_LEFT_SHOULDER)],
		&"interact": [_key(KEY_E), _button(JOY_BUTTON_Y)],
		&"attack": [_mouse(MOUSE_BUTTON_LEFT), _key(KEY_F), _button(JOY_BUTTON_X)],
		&"sword_beam": [_key(KEY_V), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)],
		&"switch_weapon": [_key(KEY_TAB), _key(KEY_R), _button(JOY_BUTTON_DPAD_RIGHT)],
		&"encounter_reset": [_key(KEY_F5)],
		&"call_horse": [_key(KEY_C), _button(JOY_BUTTON_DPAD_DOWN)],
		&"ride_steer_mode": [_key(KEY_F6), _button(JOY_BUTTON_DPAD_UP)],
		&"respawn": [_key(KEY_BACKSPACE), _button(JOY_BUTTON_BACK)],
		&"debug_colossus_mode": [_key(KEY_F2)],
		&"debug_draw": [_key(KEY_F3)],
		&"debug_locomotion_mode": [_key(KEY_F4)],
		&"toggle_help": [_key(KEY_F1)],
		&"pause": [_key(KEY_ESCAPE), _key(KEY_P), _button(JOY_BUTTON_START)],
		&"bug_report": [_key(KEY_F9)],
	}


static func ensure_defaults() -> void:
	var d := defaults()
	for name: StringName in d:
		_action(name, d[name])


## The player's own keys (Settings.bindings: action -> [{"key": code} | {"mouse": button}])
## replace the keyboard and mouse events of those actions; pad events stay.
static func apply_bindings(bindings: Dictionary) -> void:
	ensure_defaults()
	for pair in REBINDABLE:
		var name: StringName = pair[0]
		_restore(name)
		if not bindings.has(String(name)):
			continue
		for e in InputMap.action_get_events(name):
			if e is InputEventKey or e is InputEventMouseButton:
				InputMap.action_erase_event(name, e)
		for item in bindings[String(name)]:
			var ev := event_from(item)
			if ev:
				InputMap.action_add_event(name, ev)


## Back to the default events of one action.
static func _restore(name: StringName) -> void:
	var d := defaults()
	if not d.has(name):
		return
	InputMap.action_erase_events(name)
	for e in d[name]:
		InputMap.action_add_event(name, e)


static func event_to(e: InputEvent) -> Dictionary:
	if e is InputEventKey:
		return {"key": int((e as InputEventKey).physical_keycode)}
	if e is InputEventMouseButton:
		return {"mouse": int((e as InputEventMouseButton).button_index)}
	return {}


static func event_from(d: Variant) -> InputEvent:
	if not (d is Dictionary):
		return null
	if (d as Dictionary).has("key"):
		return _key(int(d.key) as Key)
	if (d as Dictionary).has("mouse"):
		return _mouse(int(d.mouse) as MouseButton)
	return null


## What an action is bound to on the keyboard / mouse, for the menu ("W, Up").
static func describe(name: StringName) -> String:
	var parts := PackedStringArray()
	for e in InputMap.action_get_events(name):
		if e is InputEventKey:
			parts.append(OS.get_keycode_string((e as InputEventKey).physical_keycode))
		elif e is InputEventMouseButton:
			parts.append(["", "LPM", "PPM", "ŚPM"][clampi((e as InputEventMouseButton).button_index, 0, 3)] if (e as InputEventMouseButton).button_index <= 3 else "Mysz %d" % (e as InputEventMouseButton).button_index)
	return ", ".join(parts)


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
