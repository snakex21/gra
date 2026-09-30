class_name PlayerHud
extends Control
## Minimal HUD: stamina ring (SotC style) + debug/help text.

var player: PlayerCharacter
var colossus: Colossus
var show_debug := true
var show_help := true

var _label: Label
var _help: Label
var _flash := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.position = Vector2(16, 12)
	_label.add_theme_color_override(&"font_shadow_color", Color.BLACK)
	_label.add_theme_font_size_override(&"font_size", 15)
	add_child(_label)
	_help = Label.new()
	_help.add_theme_color_override(&"font_shadow_color", Color.BLACK)
	_help.add_theme_font_size_override(&"font_size", 15)
	_help.text = "\n".join([
		"WASD / left stick: move      mouse / right stick: camera",
		"HOLD RMB / Shift / R1: grip  (release to let go)",
		"Space / A: jump (while gripping: leap off / along surface)",
		"Q / MMB / L1: frame the colossus",
		"Backspace: respawn   F2: colossus mode   F3: debug   F1: help",
		"Click to capture the mouse, Esc to release",
	])
	add_child(_help)


func _process(delta: float) -> void:
	if player == null:
		return
	# Parent is a CanvasLayer (not a Control), so anchors do not resize us.
	size = get_viewport_rect().size
	_flash += delta
	if Input.is_action_just_pressed(&"debug_draw"):
		show_debug = not show_debug
	if Input.is_action_just_pressed(&"toggle_help"):
		show_help = not show_help
	_help.visible = show_help
	_help.position = Vector2(16, size.y - _help.size.y - 16)
	_label.visible = show_debug
	if show_debug:
		var st: String = PlayerCharacter.State.keys()[player.state]
		var lines := PackedStringArray()
		lines.append("FPS %d   physics %d Hz" % [Engine.get_frames_per_second(), Engine.physics_ticks_per_second])
		lines.append("P%d %s  stamina %.0f%s  shake %.2f  |v_surface| %.1f m/s" % [player.player_index + 1, st, player.stamina.value, " EXHAUSTED" if player.stamina.exhausted else "", player.shake_level, player.surface_velocity.length()])
		if player.grip:
			var seg := player.grip.body.name
			lines.append("grip: %s  normal %s" % [seg, str(player.grip.world_normal().snapped(Vector3.ONE * 0.01))])
		if player.last_release_reason != &"":
			lines.append("last release: %s" % player.last_release_reason)
		if colossus:
			lines.append(colossus.debug_text())
		_label.text = "\n".join(lines)
	queue_redraw()


func _draw() -> void:
	if player == null:
		return
	var center := Vector2(size.x - 90.0, size.y - 90.0)
	var r := 42.0
	var ratio := player.stamina.ratio()
	draw_arc(center, r, 0.0, TAU, 64, Color(0, 0, 0, 0.45), 12.0, true)
	var col := Color(0.95, 0.85, 0.35).lerp(Color(0.95, 0.25, 0.2), 1.0 - smoothstep(0.1, 0.45, ratio))
	if player.stamina.exhausted:
		col.a = 0.4 + 0.6 * absf(sin(_flash * 8.0))
	if ratio > 0.0:
		draw_arc(center, r, -PI / 2.0, -PI / 2.0 + TAU * ratio, 64, col, 10.0, true)
	if player.is_climbing():
		draw_circle(center, 6.0 + 6.0 * player.shake_level, Color(1, 1, 1, 0.8))
