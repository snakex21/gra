class_name SentinelBrain
extends ColossusBrain
## Utility brain for the Sentinel. Proposes one intent per think tick:
##
##   player on the ground : stomp (close to a foot), arm_sweep (in front), approach (far),
##                          search_player (behind), observe_player (otherwise)
##   player on the body   : reposition (on a foot / calf: move the leg), shake_player
##                          (thigh..back, stronger and sooner the higher he is),
##                          protect_weakpoint (on the head, close to the weak point)
##
## Every option has a plain meaning. Cooldowns, telegraphs and anti-spam are NOT here:
## the FairnessRules filter whatever this proposes (blocked intents are skipped).
## Deterministic for a given seed.

var commitment := 0.1

var _rng := RandomNumberGenerator.new()
var _last_scores := {}
var _shuffle_dir := 1.0


func _init(seed_value := 7) -> void:
	_rng.seed = seed_value


func decide(obs: ColossusObservation) -> ColossusIntent:
	var options: Array[ColossusIntent] = []
	var idle := ColossusIntent.make(ColossusIntent.IDLE)
	idle.score = 0.05
	options.append(idle)
	var focus: ColossusObservation.PlayerInfo = null
	for info in obs.players:
		if info.on_body:
			_body_options(obs, info, options)
			if focus == null or not focus.on_body:
				focus = info
		elif focus == null or (not focus.on_body and info.distance < focus.distance):
			focus = info
	if focus != null and not focus.on_body:
		_ground_options(obs, focus, options)
	var best: ColossusIntent = null
	_last_scores.clear()
	for o in options:
		if o.kind in obs.blocked_intents:
			continue
		if o.kind == obs.current_intent:
			o.score += commitment
		# Tiny deterministic jitter breaks exact ties without changing the meaning.
		o.score += _rng.randf() * 0.02
		_last_scores[o.kind] = maxf(_last_scores.get(o.kind, 0.0), o.score)
		if best == null or o.score > best.score:
			best = o
	return best


func _ground_options(obs: ColossusObservation, p: ColossusObservation.PlayerInfo, options: Array[ColossusIntent]) -> void:
	if p.stomp_foot >= 0:
		options.append(_make(Sentinel.STOMP, p, 0.85))
	if p.sweep_side != 0:
		options.append(_make(Sentinel.ARM_SWEEP, p, 0.8 if p.stomp_foot < 0 else 0.7))
	if absf(p.bearing) > 2.0 and p.distance < 30.0:
		options.append(_make(Sentinel.SEARCH, p, 0.55))
	if p.distance > 16.0:
		options.append(_make(Sentinel.APPROACH, p, 0.5 + 0.1 * clampf((p.distance - 16.0) / 30.0, 0.0, 1.0)))
	options.append(_make(Sentinel.OBSERVE, p, 0.35))


func _body_options(obs: ColossusObservation, p: ColossusObservation.PlayerInfo, options: Array[ColossusIntent]) -> void:
	var t := p.time_on_body
	match p.region:
		&"foot", &"calf":
			# Move the leg the player clings to (steps), instead of a full shake.
			var r := _make(ColossusIntent.REPOSITION, p, 0.4 + 0.3 * clampf(t / 4.0, 0.0, 1.0))
			_shuffle_dir = -_shuffle_dir if _rng.randf() < 0.3 else _shuffle_dir
			var side := Vector3(cos(obs.time * 0.1), 0.0, sin(obs.time * 0.1))
			r.target_position = obs.self_position + side * 8.0 * _shuffle_dir
			options.append(r)
			options.append(_shake(p, 0.6, 0.15 + 0.3 * clampf(t / 6.0, 0.0, 1.0)))
		&"thigh", &"pelvis", &"back", &"arm":
			# The climber gets a few calm seconds, then a moderate shake.
			options.append(_shake(p, 0.5, 0.1 + 0.55 * clampf((t - 2.5) / 6.0, 0.0, 1.0)))
		&"shoulder":
			# Standing on the shoulders (the rest plateau): annoyed, but in no hurry.
			options.append(_shake(p, 0.45, 0.2 + 0.4 * clampf(t / 8.0, 0.0, 1.0)))
		&"neck":
			options.append(_shake(p, 0.5, 0.45 + 0.3 * clampf(t / 6.0, 0.0, 1.0)))
		&"head":
			# The strongest attempt to throw the player off, and closing the weak point.
			options.append(_shake(p, 0.6, 0.55 + 0.3 * clampf(t / 6.0, 0.0, 1.0)))
			if p.near_weakpoint and obs.weak_point_open:
				options.append(_make(Sentinel.PROTECT, p, 0.8))
		_:
			options.append(_shake(p, 0.7, 0.3))
	var observe := _make(Sentinel.OBSERVE, p, 0.2)
	options.append(observe)


func _shake(p: ColossusObservation.PlayerInfo, strength: float, score: float) -> ColossusIntent:
	var s := _make(ColossusIntent.SHAKE_PLAYER, p, score)
	s.strength = strength
	return s


func _make(kind: StringName, p: ColossusObservation.PlayerInfo, score: float) -> ColossusIntent:
	var i := ColossusIntent.make(kind)
	i.target_player = p.player
	i.target_position = p.position
	i.score = score
	return i


func debug_text() -> String:
	var parts := PackedStringArray()
	for k in _last_scores:
		parts.append("%s %.2f" % [k, _last_scores[k]])
	return "brain: " + ", ".join(parts)
