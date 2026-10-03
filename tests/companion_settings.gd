extends Node
## Optional mode remains portable/backwards compatible and applies directly in UI.
var failures := 0
var deadline := Time.get_ticks_msec() + 30000
const TEST_PATH := "res://tests/output/companion_menu_settings.json"

func _process(_delta: float) -> void:
	if Time.get_ticks_msec() > deadline:
		push_error("Companion settings test timed out or stopped after a runtime error")
		get_tree().quit(1)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _ready() -> void:
	InputSetup.ensure_defaults()
	var original_exists := FileAccess.file_exists(Settings.DEFAULT_PATH)
	var original_content := FileAccess.get_file_as_string(Settings.DEFAULT_PATH) if original_exists else ""
	var settings := Settings.new()
	check(settings.companion_mode == &"off" and Settings.VERSION == 1, "Companion changed default solitary mode/settings version")
	settings.mouse_sensitivity = .0041
	settings.invert_y = true
	settings.ride_relative = true
	settings.show_help = false
	settings.show_debug = true
	settings.graphics_profile = "low"
	settings.volume = .35
	settings.slot = 2
	settings.bindings = {"jump": [{"key": KEY_K}]}
	var legacy := settings.to_dict()
	legacy.erase("companion_mode")
	settings.companion_mode = &"programmed"
	settings.from_dict(legacy)
	check(settings.companion_mode == &"off", "Old settings retained an enabled companion")
	var expected := settings.to_dict()
	for mode: StringName in Settings.COMPANION_MODES:
		settings.companion_mode = mode
		check(settings.save(TEST_PATH), "Companion settings could not be written to project-local path")
		var loaded := Settings.new()
		check(loaded.load_from(TEST_PATH) and loaded.to_dict() == settings.to_dict(), "Companion mode/settings JSON roundtrip failed: " + String(mode))
		var dictionary := loaded.to_dict()
		dictionary.erase("companion_mode")
		var comparison := expected.duplicate(true)
		comparison.erase("companion_mode")
		check(dictionary == comparison, "Companion mode disturbed volume/graphics/bindings/slot/other settings")
	for malformed: Variant in [null, 0, 1, true, [], {}, "coop", "LOCAL_MODEL", " programmed "]:
		var loaded := Settings.new()
		loaded.companion_mode = &"local_model"
		loaded.from_dict({"version": 1, "companion_mode": malformed})
		check(loaded.companion_mode == &"off", "Malformed companion mode was accepted: " + str(malformed))
	settings.companion_mode = &"bad"
	check(settings.to_dict().companion_mode == "off", "Serializer emitted a mode outside the whitelist")
	settings.companion_mode = &"off"
	var menu := GameMenu.new()
	menu.settings = settings
	add_child(menu)
	var changes := []
	menu.settings_changed.connect(func(value: Settings) -> void:
		changes.append(value.companion_mode)
		check(value == settings, "Menu emitted a different settings object"))
	menu.show_pause()
	menu._open_options(&"pause")
	await frames(3)
	check(menu._companion.get_item_count() == 3, "Menu did not contain exactly three companion choices")
	check(menu._companion.get_item_text(0) == "Samotna podróż" and menu._companion.get_item_text(1) == "Kompan AI" and menu._companion.get_item_text(2) == "Kompan AI z lokalnym modelem", "Menu companion labels do not match plain Polish choices")
	check(get_viewport().gui_get_focus_owner() == menu._companion, "Keyboard/pad focus did not start on the optional companion")
	# The native dropdown routes its PopupMenu selection into OptionButton, then
	# the same settings_changed used by the actual game; no extra Apply button.
	for index in [1, 2, 0]:
		menu._companion.get_popup().index_pressed.emit(index)
		check(settings.companion_mode == Settings.COMPANION_MODES[index], "Menu did not immediately apply companion choice")
		check(menu._companion.selected == index, "Native dropdown did not reflect applied choice")
		if index == 2:
			check(menu._companion_hint.text.contains("niedostępny") and menu._companion_hint.text.contains("zwykły kompan AI"), "Local model option lacked a plain fallback explanation")
	check(changes == [&"programmed", &"local_model", &"off"], "Menu did not emit one immediate change per selection/revert")
	menu._options.get_child(menu._options.get_child_count()-1).pressed.emit()
	check(menu.screen == &"pause", "Settings Back did not return to pause")
	check(settings.companion_mode == &"off", "Leaving settings resurrected companion after selecting solitary travel")
	settings.companion_mode = &"local_model"
	menu._open_options(&"title")
	await frames(2)
	check(menu._companion.selected == 2 and changes.size() == 3, "Reopening settings lost selection or emitted an unwanted change")
	for dimensions: Vector2i in [Vector2i(1280,720), Vector2i(1600,900)]:
		get_window().size = dimensions
		await frames(3)
		var panel := menu._options.get_global_rect()
		check(get_viewport().get_visible_rect().encloses(panel), "Companion options panel overflowed viewport: " + str(dimensions))
		check(menu._companion.size.x >= menu._companion.get_minimum_size().x, "Companion option text was clipped")
	# Native UI navigation retains ordinary joypad/keyboard actions.
	var next := menu._companion.find_next_valid_focus()
	check(next == menu._graphics, "Tab/pad traversal skipped the graphics selector after companion")
	var event := InputEventAction.new()
	event.action = &"ui_down"
	event.pressed = true
	get_viewport().push_input(event)
	await frames(1)
	check(get_viewport().gui_get_focus_owner() == menu._graphics, "Native down navigation did not move from companion to graphics")
	check(InputMap.has_action(&"ui_accept") and InputMap.has_action(&"ui_cancel"), "Menu lost standard keyboard/pad accept/cancel actions")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tests/output/companion_menu.png")) == OK, "Companion menu capture failed")
	menu._close()
	check(not menu.is_open(), "Menu could not close after companion settings")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	check(FileAccess.file_exists(Settings.DEFAULT_PATH) == original_exists and (not original_exists or FileAccess.get_file_as_string(Settings.DEFAULT_PATH) == original_content), "Companion UI test overwrote player settings")
	print("COMPANION_SETTINGS: %d failure(s); version 1, 3 modes, legacy/invalid off, portable roundtrip, existing fields, immediate menu change/revert, keyboard/pad focus, 720p/900p fit" % failures)
	get_tree().quit(1 if failures else 0)

func frames(count: int) -> void:
	for i in count: await get_tree().process_frame
