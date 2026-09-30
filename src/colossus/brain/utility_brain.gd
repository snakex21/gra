class_name UtilityBrain
extends ColossusBrain
## First ColossusBrain implementation: simple utility scoring with commitment.
## Deterministic for a given seed, so tests and A/B comparisons are reproducible.

## Bonus added to the currently running intent to avoid dithering between options.
var commitment := 0.12
## Stop approaching a player on the ground at this distance.
var approach_stop_distance := 14.0

var _rng := RandomNumberGenerator.new()
var _wander_goal := Vector3.ZERO
var _has_goal := false
var _last_scores := {}


func _init(seed_value := 1234) -> void:
	_rng.seed = seed_value


func decide(obs: ColossusObservation) -> ColossusIntent:
	var options: Array[ColossusIntent] = []

	var idle := ColossusIntent.make(ColossusIntent.IDLE)
	idle.score = 0.15
	options.append(idle)

	# Wander around the arena.
	if not _has_goal or obs.self_position.distance_to(_wander_goal) < 6.0:
		_pick_wander_goal(obs)
	var wander := ColossusIntent.make(ColossusIntent.REPOSITION)
	wander.target_position = _wander_goal
	wander.score = 0.35
	options.append(wander)

	# Walk towards / face the nearest player on the ground.
	var nearest := obs.nearest_player()
	if nearest and not nearest.on_body and nearest.distance < obs.arena_radius * 1.2:
		var focus := ColossusIntent.make(ColossusIntent.FOCUS_PLAYER)
		focus.target_player = nearest.player
		focus.target_position = nearest.position
		focus.score = 0.3 + 0.3 * clampf(1.0 - nearest.distance / 60.0, 0.0, 1.0)
		options.append(focus)

	# Try to throw off whoever has been on the body the longest / highest.
	for info in obs.players_on_body():
		var shake := ColossusIntent.make(ColossusIntent.SHAKE_PLAYER)
		shake.target_player = info.player
		shake.strength = clampf(0.6 + 0.4 * info.height_ratio, 0.0, 1.0)
		# Grows with time on the body: the climber always gets a few calm seconds first.
		shake.score = 0.1 + 0.5 * clampf(info.time_on_body / 6.0, 0.0, 1.0) + 0.2 * info.height_ratio
		options.append(shake)

	var best: ColossusIntent = null
	_last_scores.clear()
	for o in options:
		if o.kind in obs.blocked_intents:
			continue
		if o.kind == obs.current_intent:
			o.score += commitment
		_last_scores[o.kind] = maxf(_last_scores.get(o.kind, 0.0), o.score)
		if best == null or o.score > best.score:
			best = o
	return best


func debug_text() -> String:
	var parts := PackedStringArray()
	for k in _last_scores:
		parts.append("%s %.2f" % [k, _last_scores[k]])
	return "utility: " + ", ".join(parts)


func _pick_wander_goal(obs: ColossusObservation) -> void:
	var a := _rng.randf() * TAU
	var r := obs.arena_radius * _rng.randf_range(0.25, 0.7)
	_wander_goal = obs.arena_center + Vector3(cos(a) * r, 0.0, sin(a) * r)
	_has_goal = true
