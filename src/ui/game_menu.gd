class_name GameMenu
extends CanvasLayer
## Title, pause and settings menus. Keyboard, mouse and pad (the built-in ui_* actions
## move the focus). Runs while the tree is paused; it never touches gameplay itself: it
## only emits what the player chose and edits a Settings object.
##
##   title    : Continue (when there is a save) / New game / Settings / Quit
##   pause    : Resume / Settings / Quit to title
##   settings : mouse sensitivity, invert Y, Agro steering, help, debug text / Back

signal continue_chosen
signal new_game_chosen
signal resume_chosen
signal quit_to_title_chosen
signal quit_chosen
signal settings_changed(settings: Settings)

var settings := Settings.new()
var screen := &""

var _root: Control
var _title: VBoxContainer
var _pause: VBoxContainer
var _options: VBoxContainer
var _continue: Button
var _back_to := &""
var _sens: HSlider
var _invert: CheckBox
var _ride: CheckBox
var _help: CheckBox
var _debug: CheckBox


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
	_button(_title, "Nowa gra", func() -> void: _close(); new_game_chosen.emit())
	_button(_title, "Ustawienia", func() -> void: _open_options(&"title"))
	_button(_title, "Wyjście", func() -> void: quit_chosen.emit())
	_pause = _panel("Pauza")
	_button(_pause, "Wznów", func() -> void: _close(); resume_chosen.emit())
	_button(_pause, "Ustawienia", func() -> void: _open_options(&"pause"))
	_button(_pause, "Wyjdź do menu", func() -> void: _close(); quit_to_title_chosen.emit())
	_options = _panel("Ustawienia")
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Czułość myszy"
	row.add_child(label)
	_sens = HSlider.new()
	_sens.min_value = 0.0005
	_sens.max_value = 0.01
	_sens.step = 0.0001
	_sens.custom_minimum_size = Vector2(240, 24)
	_sens.value_changed.connect(func(v: float) -> void: settings.mouse_sensitivity = v; _changed())
	row.add_child(_sens)
	_options.add_child(row)
	_invert = _check(_options, "Odwróć oś Y", func(on: bool) -> void: settings.invert_y = on; _changed())
	_ride = _check(_options, "Sterowanie Agro względem konia", func(on: bool) -> void: settings.ride_relative = on; _changed())
	_help = _check(_options, "Podpowiedzi sterowania", func(on: bool) -> void: settings.show_help = on; _changed())
	_debug = _check(_options, "Tekst diagnostyczny", func(on: bool) -> void: settings.show_debug = on; _changed())
	_button(_options, "Wróć", func() -> void: _show(_back_to))
	_close()


func show_title(has_save: bool) -> void:
	_continue.visible = has_save
	_show(&"title")


func show_pause() -> void:
	_show(&"pause")


func is_open() -> bool:
	return screen != &""


func _show(s: StringName) -> void:
	screen = s
	_root.visible = true
	_title.visible = s == &"title"
	_pause.visible = s == &"pause"
	_options.visible = s == &"options"
	var panel: VBoxContainer = {&"title": _title, &"pause": _pause, &"options": _options}[s]
	for c in panel.get_children():
		if c is Button and c.visible:
			(c as Button).grab_focus.call_deferred()
			break


func _close() -> void:
	screen = &""
	_root.visible = false


func _open_options(back: StringName) -> void:
	_back_to = back
	_sens.set_value_no_signal(settings.mouse_sensitivity)
	_invert.set_pressed_no_signal(settings.invert_y)
	_ride.set_pressed_no_signal(settings.ride_relative)
	_help.set_pressed_no_signal(settings.show_help)
	_debug.set_pressed_no_signal(settings.show_debug)
	_show(&"options")


func _changed() -> void:
	settings_changed.emit(settings)


func _panel(title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(380, 0)
	box.position = Vector2(-190, -150)
	box.add_theme_constant_override(&"separation", 10)
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
	b.custom_minimum_size = Vector2(0, 38)
	b.pressed.connect(on_press)
	box.add_child(b)
	return b


func _check(box: VBoxContainer, text: String, on_toggle: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.toggled.connect(on_toggle)
	box.add_child(c)
	return c
