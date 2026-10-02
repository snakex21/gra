class_name PlayerHud
extends Control
## Minimal HUD: stamina ring (SotC style) + debug/help text.

var player: PlayerCharacter
var colossus: Colossus
var camera: PlayerCamera
var horse: Horse
## Boss encounter (banner, state); may be null.
var encounter: BossEncounter
## Banner when there is no encounter banner (the valley: hints, the end of the game).
var message := ""
var show_debug := true
var show_help := true

var _label: Label
var _help: Label
var _banner: Label
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
		"HOLD RMB / Shift / R1: grip  (release to let go)   HOLD LMB / F / X: charge sword / draw bow, release: strike / shoot   Tab / R / D-pad right: sword <-> bow",
		"Space / A: jump (while gripping: leap off / along surface)",
		"Q / MMB / L1: frame the colossus   HOLD V / L2: raise the sword to the sun (the beam leads to the next colossus)",
		"E / Y: mount / dismount Agro   C: call Agro   riding: stick = direction, Space/A = kick, RMB/R1 = reins",
		"F5: reset encounter   F6: ride steering camera/horse-relative   Backspace: respawn   F2: colossus mode   F3: debug + overlays   F4: locomotion A/B   F1: help",
		"Click to capture the mouse, Esc to release it (in the game: Esc / P / Start = pause menu)",
	])
	add_child(_help)
	_banner = Label.new()
	_banner.add_theme_color_override(&"font_shadow_color", Color.BLACK)
	_banner.add_theme_font_size_override(&"font_size", 44)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_banner)


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
	# The help never covers the debug text: it only shows below it.
	_help.visible = show_help and (not show_debug or _label.position.y + _label.size.y < size.y - _help.size.y - 16.0)
	_banner.text = encounter.banner if encounter and encounter.banner != "" else message
	_banner.size = Vector2(size.x, 60)
	_banner.position = Vector2(0, size.y * 0.3)
	_help.position = Vector2(16, size.y - _help.size.y - 16)
	_label.visible = show_debug
	_perf_timer += delta
	if _perf_timer >= 0.5:
		_sample_perf()
	if show_debug:
		var lines := PackedStringArray()
		lines.append("FPS %d   physics %d Hz   %s" % [Engine.get_frames_per_second(), Engine.physics_ticks_per_second, _perf_text])
		var weapon_text := "sword %s %.0f%%" % [player.sword.state_name(), player.sword.charge * 100.0]
		if player.weapon == PlayerCharacter.Weapon.BOW:
			var bw := player.bow
			weapon_text = "bow %s draw %.0f%% (%.0f m/s)  shots %d" % [bw.state_name(), bw.draw * 100.0, bw.speed_for(bw.draw), bw.shots]
			if not bw.last_shot.is_empty():
				var a: Dictionary = bw.last_shot.arrow
				weapon_text += "  last arrow %s" % a.state
		lines.append("P%d %s   HP %.0f   stamina %.0f%s   %s" % [player.player_index + 1, player.get_display_state(), player.health, player.stamina.value, " EXHAUSTED" if player.stamina.exhausted else "", weapon_text])
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
		if horse:
			lines.append(horse.debug_text())
		if encounter:
			lines.append("ENCOUNTER %s  resets %d  t %.1fs" % [encounter.state_name(), encounter.resets, encounter.time])
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
	# Breath (inside the ring, only when some is used).
	var air := clampf(player.breath / player.breath_max, 0.0, 1.0)
	if air < 0.999:
		var ac := Color(0.45, 0.75, 1.0) if air > 0.25 else Color(0.45, 0.75, 1.0, 0.4 + 0.6 * absf(sin(_flash * 8.0)))
		draw_arc(center, r - 14.0, -PI / 2.0, -PI / 2.0 + TAU * air, 48, ac, 5.0, true)
	# Health (bottom left of the ring) and sword charge.
	var hp := clampf(player.health / player.fall.max_health, 0.0, 1.0)
	var bar := Rect2(size.x - 260.0, size.y - 30.0, 140.0, 8.0)
	draw_rect(bar, Color(0, 0, 0, 0.45))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * hp, bar.size.y)), Color(0.85, 0.3, 0.25))
	if player.sword.state == PlayerSword.State.CHARGE:
		draw_arc(center, r + 14.0, -PI / 2.0, -PI / 2.0 + TAU * player.sword.charge, 48, Color(0.7, 0.9, 1.0), 4.0, true)
	# Bow: crosshair in the middle of the view and the draw around it.
	if player.weapon == PlayerCharacter.Weapon.BOW:
		var c := size * 0.5
		var aiming := player.bow.is_aiming()
		var cc := Color(1, 1, 1, 0.9 if aiming else 0.35)
		draw_line(c + Vector2(-10, 0), c + Vector2(-3, 0), cc, 2.0)
		draw_line(c + Vector2(3, 0), c + Vector2(10, 0), cc, 2.0)
		draw_line(c + Vector2(0, -10), c + Vector2(0, -3), cc, 2.0)
		draw_line(c + Vector2(0, 3), c + Vector2(0, 10), cc, 2.0)
		if aiming:
			draw_arc(c, 18.0, -PI / 2.0, -PI / 2.0 + TAU * player.bow.draw, 48, Color(1.0, 0.85, 0.4) if player.bow.draw >= 1.0 else Color(0.9, 0.9, 0.9), 3.0, true)
	# Boss weak points (one bar each).
	var wps: Array = []
	if colossus is HumanoidBoss:
		wps = [(colossus as HumanoidBoss).weak_point]
	elif colossus is Quadratus:
		wps = (colossus as Quadratus).weak_points
	# Gaius: the helmet's cracks as a grey bar under the weak point.
	if colossus is Gaius:
		var h := (colossus as Gaius).helmet
		var hb := Rect2(size.x * 0.5 - 150.0, 30.0, 300.0, 5.0)
		draw_rect(hb, Color(0, 0, 0, 0.45))
		draw_rect(Rect2(hb.position, Vector2(hb.size.x * (1.0 - h.progress()), hb.size.y)), Color(0.7, 0.7, 0.68))
	for i in wps.size():
		var wp: WeakPoint = wps[i]
		var w := 300.0 / wps.size() - 6.0
		var wb := Rect2(size.x * 0.5 - 150.0 + i * (w + 12.0), 18.0, w, 8.0)
		draw_rect(wb, Color(0, 0, 0, 0.45))
		draw_rect(Rect2(wb.position, Vector2(wb.size.x * (1.0 - wp.progress()), wb.size.y)), Color(0.5, 0.85, 1.0))


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
	var p := Perf.take(&"hud")
	var us: Dictionary = p.usec
	var q: Dictionary = p.queries
	var n := float(ticks)
	_perf_text = "logic/tick: colossus %.0f us (brain %.0f, combat %.0f, hits %.0f, locomotion %.0f, IK %.0f)  arrows %.0f us (%.1f rays)  vfx %.0f  Agro %.0f us (controller %.0f incl. probes %.0f, steps %.0f, IK+body %.0f)  player %.0f us (mount %.0f)  camera %.0f us | rays/tick: climb %.1f  horse %.1f  grab %.1f  camera %.1f" % [
		us.get(&"colossus", 0) / n, us.get(&"brain", 0) / n, us.get(&"boss_combat", 0) / n, us.get(&"boss_hits", 0) / n, us.get(&"locomotion", 0) / n, us.get(&"ik", 0) / n, us.get(&"arrows", 0) / n, q.get(&"arrow_rays", 0) / n, us.get(&"vfx", 0) / n,
		us.get(&"horse", 0) / n, us.get(&"horse_controller", 0) / n, us.get(&"horse_probes", 0) / n, us.get(&"horse_steps", 0) / n, us.get(&"horse_ik", 0) / n,
		us.get(&"player", 0) / n, us.get(&"mount", 0) / n, us.get(&"camera", 0) / n,
		q.get(&"climb_rays", 0) / n, q.get(&"horse_rays", 0) / n, q.get(&"grab_queries", 0) / n, q.get(&"camera_queries", 0) / n]
