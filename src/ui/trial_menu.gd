class_name TrialMenu
extends Node
## Standalone encounter trials return to the campaign selector with Esc / Start.
static var return_to_trials := false
var settings := Settings.new()
static func attach(root: Node) -> void:
	if root.get_node_or_null("TrialMenu"):
		return
	var menu := TrialMenu.new()
	menu.name = "TrialMenu"
	root.add_child(menu)
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.text = "Esc / Start — menu  ·  F5 — ponów walkę"
	label.position = Vector2(24, 64)
	label.add_theme_font_size_override("font_size", 16)
	layer.add_child(label)
	menu.add_child(layer)

func _ready() -> void:
	get_tree().auto_accept_quit = true
	settings.load_from()
	settings.apply_engine()
	_apply_to.call_deferred(get_parent())
	if not OS.has_environment("NO_ART"):
		_dress_trial.call_deferred(get_parent())
	GraphicsQuality.apply.call_deferred(get_parent(), settings.graphics_profile)

func _dress_trial(node: Node) -> void:
	if node is Colossus:
		ArenaArt.dress_colossus_v3(node)
		return # The paired encounter dresses both guardians itself.
	for child in node.get_children():
		_dress_trial(child)

func _apply_to(node: Node) -> void:
	if node is PlayerHud:
		node.show_debug = settings.show_debug
		node.show_help = settings.show_help
	elif node is FlatInputSource:
		node.mouse_sensitivity = settings.mouse_sensitivity
		node.invert_y = settings.invert_y
	elif node is PlayerCharacter:
		node.riding.steer_relative = settings.ride_relative
	for child in node.get_children():
		_apply_to(child)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		get_tree().paused = false
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return_to_trials = true
		get_tree().change_scene_to_file("res://scenes/game.tscn")
