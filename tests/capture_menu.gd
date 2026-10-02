extends Node
## Visual smoke test for the menus: the title, the pause menu and the settings over the
## temple in the valley. Saves tests/output/menu_*.png. Run with
## tools/capture_screenshots.sh menu.

var game: GameWorld
var menu: GameMenu
var tick := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	InputSetup.ensure_defaults()
	game = GameWorld.new()
	game.with_input = false
	game.with_art = not OS.has_environment("NO_ART")
	game.save_path = ""
	add_child(game)
	game.start(true)
	menu = GameMenu.new()
	menu.open_changed.connect(func(open: bool) -> void: (game.refs.hud as CanvasItem).visible = not open)
	add_child(menu)


func _physics_process(_delta: float) -> void:
	tick += 1
	match tick:
		60:
			menu.show_title(true)
		64:
			await _shot("menu_01_title")
			menu.show_pause()
		68:
			await _shot("menu_02_pause")
			menu._open_options(&"pause")
		72:
			await _shot("menu_03_settings")
			get_tree().quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tests/output/%s.png" % name))
	print("shot ", name)
