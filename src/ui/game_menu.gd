class_name GameMenu
extends CanvasLayer
## Title, pause and settings menus. Keyboard, mouse and pad (the built-in ui_* actions
## move the focus). Runs while the tree is paused; it never touches gameplay itself: it
## only emits what the player chose and edits a Settings object.
##
##   title    : Continue (when the last slot has a save) / New game / Load / Settings / Quit
##   slots    : the save slots with what is in them (new game: any, load: the used ones)
##   pause    : Resume / Settings / Quit to title
##   settings : mouse sensitivity, volume, invert Y, Agro steering, help, debug text,
##              Controls / Back
##   controls : each rebindable action and its keys; click, then press the new key
##              (Esc cancels); back to the defaults

signal continue_chosen
signal new_game_chosen
signal trial_chosen(kind: StringName)
## A slot picked on the slots screen: a new game in it, or load it.
signal slot_chosen(slot: int, new_game: bool)
signal resume_chosen
signal quit_to_title_chosen
signal quit_chosen
signal settings_changed(settings: Settings)
## The menu opened or closed (the game hides its HUD under it).
signal open_changed(open: bool)

var settings := Settings.new()
var screen := &""

var _root: Control
var _title: VBoxContainer
var _pause: VBoxContainer
var _options: VBoxContainer
var _slots: VBoxContainer
var _controls: VBoxContainer
var _trials: VBoxContainer
var _trial_first: Button
var _continue: Button
var _back_to := &""
var _sens: HSlider
var _volume: HSlider
var _invert: CheckBox
var _ride: CheckBox
var _help: CheckBox
var _debug: CheckBox
var _slot_buttons: Array[Button] = []
var _slots_new := true
var _bind_buttons := {}
## The action waiting for its new key (&"" = none).
var _capturing: StringName = &""


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.06, 0.07, 0.72)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)
	_title = _panel("Cień Kolosa")
	_continue = _button(_title, "Kontynuuj", func() -> void: _close(); continue_chosen.emit())
	_button(_title, "Nowa gra", func() -> void: _open_slots(true))
	_button(_title, "Wczytaj", func() -> void: _open_slots(false))
	_button(_title, "Próby kolosów", func() -> void: _show(&"trials"))
	_button(_title, "Ustawienia", func() -> void: _open_options(&"title"))
	_button(_title, "Wyjście", func() -> void: quit_chosen.emit())
	_slots = _panel("Zapis")
	for i in GameState.SLOTS:
		var slot := i + 1
		_slot_buttons.append(_button(_slots, "", func() -> void: _pick_slot(slot)))
	_button(_slots, "Wróć", func() -> void: _show(&"title"))
	_pause = _panel("Pauza")
	_button(_pause, "Wznów", func() -> void: _close(); resume_chosen.emit())
	_button(_pause, "Ustawienia", func() -> void: _open_options(&"pause"))
	_button(_pause, "Wyjdź do menu", func() -> void: _close(); quit_to_title_chosen.emit())
	_options = _panel("Ustawienia")
	_sens = _slider(_options, "Czułość myszy", 0.0005, 0.01, 0.0001, func(v: float) -> void: settings.mouse_sensitivity = v; _changed())
	_volume = _slider(_options, "Głośność", 0.0, 1.0, 0.05, func(v: float) -> void: settings.volume = v; _changed())
	_invert = _check(_options, "Odwróć oś Y", func(on: bool) -> void: settings.invert_y = on; _changed())
	_ride = _check(_options, "Sterowanie Agro względem konia", func(on: bool) -> void: settings.ride_relative = on; _changed())
	_help = _check(_options, "Podpowiedzi sterowania", func(on: bool) -> void: settings.show_help = on; _changed())
	_debug = _check(_options, "Tekst diagnostyczny", func(on: bool) -> void: settings.show_debug = on; _changed())
	_button(_options, "Sterowanie…", func() -> void: _open_controls())
	_button(_options, "Wróć", func() -> void: _show(_back_to))
	_controls = _panel("Sterowanie", -330.0)
	_controls.add_theme_constant_override(&"separation", 4)
	for pair in InputSetup.REBINDABLE:
		var action: StringName = pair[0]
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = pair[1]
		label.custom_minimum_size = Vector2(190, 0)
		row.add_child(label)
		var b := Button.new()
		b.custom_minimum_size = Vector2(190, 28)
		b.pressed.connect(func() -> void: _start_capture(action))
		row.add_child(b)
		_controls.add_child(row)
		_bind_buttons[action] = b
	_button(_controls, "Przywróć domyślne", func() -> void:
		settings.bindings = {}
		_changed()
		_refresh_bindings())
	_button(_controls, "Wróć", func() -> void: _open_options(_back_to))
	_trials = _panel("Próby kolosów", -330.0)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(400, 500)
	scroll.follow_focus = true
	_trials.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for kind: StringName in BossRoster.ORDER:
		var available := kind in BossRoster.PLAYABLE
		var button := _button(list, BossRoster.label(kind) + ("" if available else " — w przygotowaniu"), func() -> void: _close(); trial_chosen.emit(kind))
		button.disabled = not available
		if available and _trial_first == null:
			_trial_first = button
	_button(list, "Próba jaskini — światło miecza", func() -> void: _close(); trial_chosen.emit(&"cave"))
	_button(_trials, "Wróć", func() -> void: _show(&"title"))
	_close()


func show_title(has_save: bool) -> void:
	_continue.visible = has_save
	_show(&"title")


func show_pause() -> void:
	_show(&"pause")


func is_open() -> bool:
	return screen != &""


## Press of a key while waiting for one (the new binding).
func _input(event: InputEvent) -> void:
	if _capturing == &"" or not event.is_pressed() or event.is_echo():
		return
	if not (event is InputEventKey or event is InputEventMouseButton):
		return
	get_viewport().set_input_as_handled()
	var action := _capturing
	_capturing = &""
	if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		_refresh_bindings()
		return
	bind(action, event)


## Makes ``event`` the keyboard / mouse binding of ``action`` (the pad keeps its own).
func bind(action: StringName, event: InputEvent) -> void:
	var d := InputSetup.event_to(event)
	if d.is_empty():
		return
	settings.bindings[String(action)] = [d]
	_changed()
	_refresh_bindings()


func _start_capture(action: StringName) -> void:
	_capturing = action
	(_bind_buttons[action] as Button).text = "Naciśnij klawisz…"


func _open_controls() -> void:
	_refresh_bindings()
	_show(&"controls")


func _refresh_bindings() -> void:
	for action: StringName in _bind_buttons:
		(_bind_buttons[action] as Button).text = InputSetup.describe(action)


func _open_slots(new_game: bool) -> void:
	_slots_new = new_game
	for i in GameState.SLOTS:
		var d := GameState.describe(GameState.slot_path(i + 1))
		var b := _slot_buttons[i]
		b.text = "Slot %d — %s" % [i + 1, d if d != "" else "pusty"]
		if new_game and d != "":
			b.text += " (nadpisze)"
		b.disabled = not new_game and d == ""
	(_slots.get_child(0) as Label).text = "Nowa gra" if new_game else "Wczytaj"
	_show(&"slots")


func _pick_slot(slot: int) -> void:
	_close()
	slot_chosen.emit(slot, _slots_new)


func _show(s: StringName) -> void:
	if screen == &"":
		open_changed.emit(true)
	screen = s
	_root.visible = true
	var panels := {&"title": _title, &"pause": _pause, &"options": _options, &"slots": _slots, &"controls": _controls, &"trials": _trials}
	for k in panels:
		(panels[k] as Control).visible = k == s
	var panel: VBoxContainer = panels[s]
	if s == &"trials" and _trial_first:
		_trial_first.grab_focus.call_deferred()
		return
	for c in panel.get_children():
		if c is Button and c.visible and not (c as Button).disabled:
			(c as Button).grab_focus.call_deferred()
			break


func _close() -> void:
	if screen != &"":
		open_changed.emit(false)
	screen = &""
	_capturing = &""
	_root.visible = false


func _open_options(back: StringName) -> void:
	_back_to = back
	_sens.set_value_no_signal(settings.mouse_sensitivity)
	_volume.set_value_no_signal(settings.volume)
	_invert.set_pressed_no_signal(settings.invert_y)
	_ride.set_pressed_no_signal(settings.ride_relative)
	_help.set_pressed_no_signal(settings.show_help)
	_debug.set_pressed_no_signal(settings.show_debug)
	_show(&"options")


func _changed() -> void:
	settings_changed.emit(settings)


func _panel(title: String, top := -220.0) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(400, 0)
	box.position = Vector2(-200, top)
	box.add_theme_constant_override(&"separation", 8)
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override(&"font_size", 34)
	box.add_child(t)
	_root.add_child(box)
	return box


func _button(box: VBoxContainer, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 36)
	b.pressed.connect(on_press)
	box.add_child(b)
	return b


func _check(box: VBoxContainer, text: String, on_toggle: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.toggled.connect(on_toggle)
	box.add_child(c)
	return c


func _slider(box: VBoxContainer, text: String, lo: float, hi: float, step: float, on_change: Callable) -> HSlider:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(150, 0)
	row.add_child(label)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(230, 24)
	s.value_changed.connect(on_change)
	row.add_child(s)
	box.add_child(row)
	return s
