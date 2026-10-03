class_name ReplayViewer
extends Node
## Plays a recorded game back in a GameWorld, with the controls of a viewer:
##
##   K        pause / play          J / L     10 s back / forward
##   [ / ]    slower / faster       F7        free camera (WASD, Q/E, arrows) / back
##   , / .    previous / next marker (a death, a hit, a fall, a defeat, a report...)
##   C        save a clip: the 15 s before here and 5 s after
##
## The timeline shows markers. New clips start from the nearest world checkpoint and
## keep only the required input suffix; legacy recordings can still replay from zero.
##
## Going back restores a checkpoint and runs its remaining input to the target. Running faster (or
## slower) changes how many ticks run per rendered frame, never the tick: the engine's
## time scale and its tick rate change together by a power of two, so each tick's step
## stays exactly 1/60 s and the run is bit for bit the one recorded.

signal reached(tick: int)

## Speed steps (powers of two: the tick stays exact).
const SPEEDS := [0.25, 0.5, 1.0, 2.0, 4.0]
## Fast-forward when seeking.
const SEEK_SPEED := 16.0
const BASE_TICKS := 60
## A jump to a marker lands this long before it (to see what led to it).
const MARKER_LEAD := 3 * 60
const CLIP_BEFORE := 15 * 60
const CLIP_AFTER := 5 * 60
const CLIPS := "res://data/replays/"

var game: GameWorld
var data: Dictionary
var replay: ActionReplay
var paused := false
var speed := 1.0
var free_cam: Camera3D

var _target := -1
var _was_paused := false
var _restore := false
var _label: Label
var _timeline: Control
## The clip's window [from, to] (ticks) when the recording is a clip.
var _clip := []
var _yaw := 0.0
var _pitch := -0.3


func setup(p_game: GameWorld, p_data: Dictionary) -> void:
	game = p_game
	data = p_data


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# After everything else in a tick: it stops a seek exactly at its tick.
	process_physics_priority = 1000
	var layer := CanvasLayer.new()
	layer.layer = 15
	_label = Label.new()
	_label.position = Vector2(16, 12)
	_label.add_theme_font_size_override(&"font_size", 18)
	_label.add_theme_color_override(&"font_shadow_color", Color.BLACK)
	layer.add_child(_label)
	_timeline = Control.new()
	_timeline.set_anchors_preset(Control.PRESET_FULL_RECT)
	_timeline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_timeline.draw.connect(_draw_timeline)
	layer.add_child(_timeline)
	add_child(layer)
	var clip: Variant = data.get("header", {}).get("clip", [])
	if clip is Array and (clip as Array).size() == 2:
		_clip = clip
	restart()
	if not _clip.is_empty():
		paused = false
		seek(int(_clip[0]))


## Rebuild the world from a checkpoint, or the original header for older recordings.
func restart(checkpoint := {}) -> void:
	var h: Dictionary = data.get("header", {})
	game.with_input = false
	game.save_path = ""
	game.seed_offset = int(h.get("seed_offset", 0))
	game.layout_version = int(h.get("world_layout", 1))
	if is_instance_valid(replay):
		replay.free()
	if checkpoint.is_empty() or not WorldSnapshot.restore(game, checkpoint.get("world", {})):
		checkpoint = {}
		game.start_from(h.get("progress", {}))
	replay = ActionReplay.player_for(null, data)
	replay.player_source = game.player
	game.add_child(replay)
	if not checkpoint.is_empty():
		replay.resume_checkpoint(checkpoint)

func checkpoint_before(at: int) -> Dictionary:
	var best := {}
	for c: Dictionary in data.get("checkpoints", []):
		if int(c.tick) <= at and (best.is_empty() or int(c.tick) > int(best.tick)):
			best = c
	return best


func tick() -> int:
	return replay.tick if is_instance_valid(replay) else 0


func length() -> int:
	return int(_clip[1]) if not _clip.is_empty() else int(data.get("ticks", 0))


## [[tick, kind, text], ...] from the recording (inside the clip's window for a clip).
func markers() -> Array:
	var out := []
	for m in data.get("markers", []):
		if _clip.is_empty() or (int(m[0]) >= int(_clip[0]) and int(m[0]) <= int(_clip[1])):
			out.append(m)
	return out


## Seeks to the next (``dir`` 1) or previous (-1) marker, MARKER_LEAD before it; returns
## the marker ([] when there is none that way).
func jump_marker(dir: int) -> Array:
	var now := tick()
	var best := []
	for m in markers():
		var at := int(m[0])
		if dir > 0 and at - MARKER_LEAD > now and (best.is_empty() or at < int(best[0])):
			best = m
		elif dir < 0 and at - MARKER_LEAD < now - 30 and (best.is_empty() or at > int(best[0])):
			best = m
	if not best.is_empty():
		seek(maxi(int(best[0]) - MARKER_LEAD, 0 if _clip.is_empty() else int(_clip[0])))
	return best


## Saves a checkpoint and trimmed input around ``at`` (default: here). Returns
## its path ("" when it could not be written).
func save_clip(at := -1, path := "") -> String:
	if at < 0:
		at = tick()
	var from := maxi(0, at - CLIP_BEFORE)
	var to := mini(int(data.get("ticks", 0)), at + CLIP_AFTER)
	var clip := data.duplicate(true)
	var checkpoint := checkpoint_before(from)
	if not checkpoint.is_empty():
		var cursor := int(checkpoint.cursor)
		var kept := []
		for i in range(cursor, clip.frames.size()):
			var f: Array = clip.frames[i]
			if f.size() < 4 or int(f[3]) <= to:
				kept.append(f)
		clip.frames = kept
		clip.checkpoints = []
		for c: Dictionary in data.get("checkpoints", []):
			if int(c.tick) >= int(checkpoint.tick) and int(c.tick) <= to:
				var adjusted := c.duplicate(true)
				adjusted.cursor = int(c.cursor) - cursor
				clip.checkpoints.append(adjusted)
		clip.markers = (data.get("markers", []) as Array).filter(func(m: Array) -> bool: return int(m[0]) >= from and int(m[0]) <= to)
	var h: Dictionary = clip.get("header", {})
	h["clip"] = [from, to]
	clip["header"] = h
	clip.ticks = to
	if path == "":
		path = CLIPS + "clip_%s.replay" % Time.get_datetime_string_from_system().replace(":", "-")
	path = PortablePaths.prepare(path)
	if path == "":
		return ""
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return ""
	f.store_var(clip)
	f.close()
	return path


## Runs (or rewinds and runs) to ``t`` and stops there, paused or playing as before.
func seek(t: int) -> void:
	t = clampi(t, 0, maxi(length(), 0))
	_was_paused = paused
	var checkpoint := checkpoint_before(t)
	if t < tick() or (not checkpoint.is_empty() and int(checkpoint.tick) > tick()):
		restart(checkpoint)
	if t == tick():
		reached.emit(t)
		return
	_target = t
	_set_rate(SEEK_SPEED)
	get_tree().paused = false


func set_paused(on: bool) -> void:
	paused = on
	if _target < 0:
		get_tree().paused = on


func faster(step: int) -> void:
	var i := clampi(SPEEDS.find(speed) + step, 0, SPEEDS.size() - 1)
	speed = SPEEDS[i]
	if _target < 0:
		_set_rate(speed)


func _physics_process(_delta: float) -> void:
	if _target < 0 and not _clip.is_empty() and tick() >= int(_clip[1]) and not paused:
		# The end of the clip: it stops there.
		set_paused(true)
		reached.emit(tick())
		return
	if _target >= 0 and tick() >= _target:
		# Exactly here: stop the tree before the next tick of this frame.
		_target = -1
		get_tree().paused = true
		_restore = true
		reached.emit(tick())


func _process(delta: float) -> void:
	if _restore:
		_restore = false
		_set_rate(speed)
		paused = _was_paused
		get_tree().paused = paused
	_flash_t = maxf(0.0, _flash_t - delta)
	if free_cam and free_cam.current:
		_fly(delta)
	if _label:
		var t := tick() / float(BASE_TICKS)
		var next := ""
		for m in markers():
			if int(m[0]) > tick():
				next = "   następny: %s %s za %.0f s" % [_marker_name(m[1]), m[2], (int(m[0]) - tick()) / float(BASE_TICKS)]
				break
		_label.text = "%s  %.1f / %.1f s  x%s%s   K pauza  J/L ±10 s  [ ] prędkość  ,/. znaczniki  C wycinek  F7 kamera%s" % ["WYCINEK" if not _clip.is_empty() else "POWTÓRKA", t, length() / float(BASE_TICKS), str(speed), "  (pauza)" if paused else "", next]
		_timeline.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).physical_keycode:
		KEY_K:
			set_paused(not paused)
		KEY_J:
			seek(tick() - 10 * BASE_TICKS)
		KEY_L:
			seek(tick() + 10 * BASE_TICKS)
		KEY_BRACKETLEFT:
			faster(-1)
		KEY_BRACKETRIGHT:
			faster(1)
		KEY_F7:
			_toggle_free_camera()
		KEY_COMMA:
			jump_marker(-1)
		KEY_PERIOD:
			jump_marker(1)
		KEY_C:
			var path := save_clip()
			if path != "":
				print("Clip saved: ", ProjectSettings.globalize_path(path))
				_flash_text = "Zapisano wycinek " + path.get_file()
				_flash_t = 3.0
		_:
			return
	get_viewport().set_input_as_handled()


## Tick rate and time scale together (powers of two): the step stays 1/60 s.
static func _set_rate(k: float) -> void:
	Engine.physics_ticks_per_second = int(round(BASE_TICKS * k))
	Engine.time_scale = k
	Engine.max_physics_steps_per_frame = maxi(8, int(8 * k))


const MARKER_COLORS := {"death": Color(0.9, 0.2, 0.2), "hit": Color(1.0, 0.6, 0.2), "fall": Color(0.95, 0.85, 0.3),
	"region": Color(0.6, 0.8, 1.0), "defeat": Color(0.5, 1.0, 0.5), "report": Color(1, 1, 1)}
const MARKER_NAMES := {"death": "śmierć", "hit": "trafienie", "fall": "upadek", "region": "obszar", "defeat": "pokonany", "report": "zgłoszenie"}
var _flash_text := ""
var _flash_t := 0.0


static func _marker_name(kind: String) -> String:
	return MARKER_NAMES.get(kind, kind)


## The timeline: the whole recording (or the clip's window), where we are, the markers.
func _draw_timeline() -> void:
	var size := _timeline.size
	var bar := Rect2(24.0, size.y - 34.0, size.x - 48.0, 6.0)
	_timeline.draw_rect(bar, Color(0, 0, 0, 0.5))
	var lo := 0 if _clip.is_empty() else int(_clip[0])
	var hi := maxi(length(), lo + 1)
	var x_of := func(t: int) -> float: return bar.position.x + bar.size.x * clampf(float(t - lo) / float(hi - lo), 0.0, 1.0)
	_timeline.draw_rect(Rect2(bar.position, Vector2(float(x_of.call(tick())) - bar.position.x, bar.size.y)), Color(0.85, 0.85, 0.85, 0.8))
	for m in markers():
		var x: float = x_of.call(int(m[0]))
		_timeline.draw_rect(Rect2(x - 2.0, bar.position.y - 7.0, 4.0, bar.size.y + 14.0), MARKER_COLORS.get(m[1], Color.WHITE))
	if _flash_t > 0.0:
		_timeline.draw_string(ThemeDB.fallback_font, Vector2(24.0, size.y - 46.0), _flash_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)


func _exit_tree() -> void:
	_set_rate(1.0)


func _toggle_free_camera() -> void:
	if free_cam == null:
		free_cam = Camera3D.new()
		free_cam.name = "FreeCamera"
		free_cam.far = 4000.0
		add_child(free_cam)
	if free_cam.current:
		var cam: Variant = game.refs.get("camera")
		if cam is Camera3D:
			(cam as Camera3D).current = true
		return
	var from: Camera3D = get_viewport().get_camera_3d()
	if from:
		free_cam.global_transform = from.global_transform
		var e := from.global_basis.get_euler()
		_yaw = e.y
		_pitch = e.x
	free_cam.current = true


func _fly(delta: float) -> void:
	var turn := Vector2(float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_UP)) - float(Input.is_physical_key_pressed(KEY_DOWN)))
	_yaw -= turn.x * 1.6 * delta
	_pitch = clampf(_pitch + turn.y * 1.2 * delta, -1.4, 1.4)
	free_cam.basis = Basis.from_euler(Vector3(_pitch, _yaw, 0))
	var move := Vector3(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	var fast := 4.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
	free_cam.position += free_cam.basis * move * 14.0 * fast * delta
