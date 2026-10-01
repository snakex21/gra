class_name Colossus
extends Node3D
## Base class for every colossus.
##
## Pipeline, once per physics tick:
##   observe world -> (at think rate) brain.decide() -> encounter rules filter the intent
##   -> _execute_intent() continuous controller -> _pose_bones() -> segments follow bones
##
## A concrete colossus provides the rig (_build_body), the controller (_execute_intent,
## _pose_bones) and its encounter rules (_rules_block). The brain is swappable.

signal intent_changed(intent: ColossusIntent)

## Seconds between brain decisions.
@export var think_interval := 0.25
## Approximate standing height, used to normalise player height on the body.
@export var body_height := 17.0
@export var arena_radius := 60.0
## Fairness rule: a shake never lasts longer than this...
@export var shake_max_duration := 3.0
## ...and is followed by at least this long without shaking.
@export var shake_cooldown := 5.0
## A player who loses contact for less than this still counts as being on the body.
@export var on_body_grace := 0.5

var skeleton: Skeleton3D
var segments: Array[BodySegment] = []
var brain: ColossusBrain
var intent: ColossusIntent = ColossusIntent.make(ColossusIntent.IDLE)
var arena_center := Vector3.ZERO
## Debug override of the brain: &"" (brain), &"frozen", &"walk", &"turn", &"shake", &"manual".
var debug_override: StringName = &""
## Shake strength used by the &"shake" debug override (0..1).
var debug_shake_strength := 1.0

var _time := 0.0
var _think_left := 0.0
var _intent_time := 0.0
var _shake_cooldown_left := 0.0
var _time_on_body := {}  # player instance id -> seconds
var _off_body_time := {}  # player instance id -> seconds since last contact
var _last_observation: ColossusObservation


func _ready() -> void:
	add_to_group(&"colossi")
	# Colossi must be posed before players read their anchors in the same tick.
	process_physics_priority = -10
	arena_center = global_position
	_build_body()
	if brain == null:
		brain = UtilityBrain.new()
	_sync_segments()
	# Second sync so previous_transform == current (zero initial velocity).
	_sync_segments()


func _physics_process(delta: float) -> void:
	var t0 := Perf.begin()
	_time += delta
	_intent_time += delta
	_shake_cooldown_left = maxf(0.0, _shake_cooldown_left - delta)
	_update_time_on_body(delta)

	# Hard encounter rules can end an intent immediately, independent of the brain.
	if intent.kind == ColossusIntent.SHAKE_PLAYER and _intent_time >= shake_max_duration and debug_override != &"shake":
		_shake_cooldown_left = shake_cooldown
		_think_left = 0.0

	_think_left -= delta
	if _think_left <= 0.0:
		_think_left = think_interval
		_last_observation = observe()
		_set_intent(_choose_intent(_last_observation))

	_execute_intent(intent, delta)
	_pose_bones(delta)
	_sync_segments()
	_post_sync(delta)
	Perf.end(&"colossus", t0)


func observe() -> ColossusObservation:
	var obs := ColossusObservation.new()
	obs.time = _time
	obs.self_position = global_position
	obs.self_forward = -global_basis.z
	obs.arena_center = arena_center
	obs.arena_radius = arena_radius
	obs.current_intent = intent.kind
	obs.blocked_intents = _blocked_intents()
	for p in get_tree().get_nodes_in_group(&"players"):
		var player := p as Node3D
		var info := ColossusObservation.PlayerInfo.new()
		info.player = player
		info.position = player.global_position
		info.distance = player.global_position.distance_to(global_position)
		var support: Object = player.get_support_body() if player.has_method(&"get_support_body") else null
		info.on_body = owns_body(support) or _time_on_body.has(player.get_instance_id())
		if owns_body(support):
			info.segment = (support as BodySegment).bone_name
		info.time_on_body = _time_on_body.get(player.get_instance_id(), 0.0)
		info.height_ratio = clampf((player.global_position.y - global_position.y) / body_height, 0.0, 1.0)
		if "stamina" in player:
			info.stamina_ratio = player.stamina.ratio()
		obs.players.append(info)
	return obs


func owns_body(obj: Object) -> bool:
	return obj is BodySegment and (obj as BodySegment).colossus == self


## Point the camera frames when the player asks to focus on the colossus.
func get_focus_point() -> Vector3:
	return global_position + Vector3.UP * body_height * 0.6


func debug_text() -> String:
	var mode := "brain" if debug_override == &"" else String(debug_override)
	var s := "%s [%s] intent: %s" % [name, mode, intent.describe()]
	if _shake_cooldown_left > 0.0:
		s += "  shake cooldown %.1fs" % _shake_cooldown_left
	if brain:
		s += "\n" + brain.debug_text()
	return s


func cycle_debug_override() -> void:
	var modes: Array[StringName] = [&"", &"frozen", &"walk", &"turn", &"shake"]
	debug_override = modes[(modes.find(debug_override) + 1) % modes.size()]
	_think_left = 0.0


# --- to implement in concrete colossi -------------------------------------------------

## Create skeleton, segments (BodySegment + shapes + visuals).
func _build_body() -> void:
	pass


## Continuous controller: turn the current intent into smooth motion targets.
func _execute_intent(_intent: ColossusIntent, _delta: float) -> void:
	pass


## Write bone poses for this tick.
func _pose_bones(_delta: float) -> void:
	pass


## Called after the segments followed the bones (measurements, debug).
func _post_sync(_delta: float) -> void:
	pass


## Extra encounter-specific rules. Return intents that must not be chosen right now.
func _rules_block() -> Array[StringName]:
	return []


# --- internals ------------------------------------------------------------------------

func _choose_intent(obs: ColossusObservation) -> ColossusIntent:
	match debug_override:
		&"frozen", &"manual":
			# "manual": movement comes from debug values set by tests/tools, never the brain.
			return ColossusIntent.make(ColossusIntent.IDLE)
		&"walk":
			var w := ColossusIntent.make(ColossusIntent.REPOSITION)
			w.target_position = arena_center + (global_position - arena_center).rotated(Vector3.UP, 0.6).normalized() * arena_radius * 0.5
			return w
		&"turn":
			# Turn on the spot: goal behind the colossus, never reached.
			var t := ColossusIntent.make(ColossusIntent.REPOSITION)
			t.target_position = global_position + global_basis.z * 20.0 + global_basis.x * 2.0
			return t
		&"shake":
			return ColossusIntent.make(ColossusIntent.SHAKE_PLAYER, debug_shake_strength)
	var chosen := brain.decide(obs)
	if chosen == null or chosen.kind in obs.blocked_intents:
		return ColossusIntent.make(ColossusIntent.IDLE)
	return chosen


func _blocked_intents() -> Array[StringName]:
	var blocked := _rules_block()
	if _shake_cooldown_left > 0.0:
		blocked.append(ColossusIntent.SHAKE_PLAYER)
	return blocked


func _set_intent(next: ColossusIntent) -> void:
	if next.kind != intent.kind:
		if intent.kind == ColossusIntent.SHAKE_PLAYER and _shake_cooldown_left <= 0.0:
			# Any shake that ends (for whatever reason) starts the cooldown.
			_shake_cooldown_left = shake_cooldown * clampf(_intent_time / shake_max_duration, 0.3, 1.0)
		_intent_time = 0.0
		intent = next
		intent_changed.emit(intent)
	else:
		# Same kind: keep the running timer but refresh targets.
		intent = next


func _update_time_on_body(delta: float) -> void:
	for p in get_tree().get_nodes_in_group(&"players"):
		var id: int = p.get_instance_id()
		var support: Object = p.get_support_body() if p.has_method(&"get_support_body") else null
		if owns_body(support):
			_time_on_body[id] = _time_on_body.get(id, 0.0) + delta
			_off_body_time[id] = 0.0
		elif _time_on_body.has(id):
			# Brief contact loss (a hop, a slide, a missed floor tick) does not reset it.
			_off_body_time[id] = _off_body_time.get(id, 0.0) + delta
			if _off_body_time[id] > on_body_grace:
				_time_on_body.erase(id)
				_off_body_time.erase(id)


func _sync_segments() -> void:
	for s in segments:
		s.follow_bone(skeleton)
