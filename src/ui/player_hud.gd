class_name PlayerHud
extends Control
## Minimal HUD: stamina ring (SotC style) + debug/help text.

var player: PlayerCharacter
var colossus: Colossus
var camera: PlayerCamera
var show_debug := true
var show_help := true

var _label: Label
var _help: Label
var _flash := 0.0
var _perf_timer := 0.0
var _perf_frames := 0
var _perf_text := ""


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
	_perf_timer += delta
	if _perf_timer >= 0.5:
		_sample_perf()
	if show_debug:
		var lines := PackedStringArray()
		lines.append("FPS %d   physics %d Hz   %s" % [Engine.get_frames_per_second(), Engine.physics_ticks_per_second, _perf_text])
		lines.append("P%d %s   stamina %.0f%s   health %.0f" % [player.player_index + 1, player.get_display_state(), player.stamina.value, " EXHAUSTED" if player.stamina.exhausted else "", player.health])
		var bal := player.balance
		lines.append("balance %.2f %s   disturbance %.1f / %.1f m/s2" % [bal.value, Balance.State.keys()[bal.state], bal.disturbance, bal.capacity])
		lines.append("surface |a| %.1f m/s2   |w| %.2f rad/s   |v| %.1f m/s   shake %.2f" % [player.surface_accel.length(), player.surface_angular_velocity.length(), player.surface_velocity.length(), player.shake_level])
		lines.append("fall: vy %.1f m/s   last impact %.1f m/s (%s)" % [player.velocity.y, player.last_impact_speed, FallImpact.Tier.keys()[player.last_impact_tier]])
		var support: Object = player.get_support_body()
		if player.grip:
			lines.append("grip: %s  normal %s" % [_segment_name(player.grip.body), str(player.grip.world_normal().snapped(Vector3.ONE * 0.01))])
		elif support:
			lines.append("standing on: %s" % _segment_name(support))
		if player.last_release_reason != &"":
			lines.append("last release: %s" % player.last_release_reason)
		if camera:
			lines.append("camera: %s  dist %.1f %s" % [camera.debug_state, camera.get_distance(), camera.last_clamp])
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


func _segment_name(o: Object) -> String:
	if o is BodySegment:
		return "%s (bone %s)" % [(o as BodySegment).colossus.name, (o as BodySegment).bone_name]
	return (o as Node).name if o is Node else "?"


## Logic cost per physics tick, averaged over the sampling window.
func _sample_perf() -> void:
	var frames := Engine.get_physics_frames()
	var ticks := maxi(1, frames - _perf_frames)
	_perf_frames = frames
	_perf_timer = 0.0
	var p := Perf.take()
	var us: Dictionary = p.usec
	var q: Dictionary = p.queries
	_perf_text = "logic/tick: colossus %.0f us  player %.0f us  camera %.0f us | queries/tick: climb rays %.1f  grab %.1f  camera %.1f" % [
		us.get(&"colossus", 0) / float(ticks), us.get(&"player", 0) / float(ticks), us.get(&"camera", 0) / float(ticks),
		q.get(&"climb_rays", 0) / float(ticks), q.get(&"grab_queries", 0) / float(ticks), q.get(&"camera_queries", 0) / float(ticks)]
