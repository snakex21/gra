class_name GaiusBrain
extends ColossusBrain
## Utility brain for Gaius. One intent per think tick:
##
##   player on the ground : sword_slam (in front, in the slam band), stomp (by a foot),
##                          search_player (behind), approach (far), observe_player
##   player on the body   : shake_player (stronger and sooner higher up), observe
## Cooldowns, telegraphs and anti-spam are not here: FairnessRules filter it.
## Deterministic for a given seed.

var commitment := 0.1

var _rng := RandomNumberGenerator.new()
var _last_scores := {}


func _init(seed_value := 13) -> void:
	_rng.seed = seed_value


func decide(obs: ColossusObservation) -> ColossusIntent:
	var options: Array[ColossusIntent] = []
	var idle := ColossusIntent.make(ColossusIntent.IDLE)
	idle.score = 0.05
	options.append(idle)
	var focus: ColossusObservation.PlayerInfo = null
	for info in obs.players:
		if focus == null or (info.on_body and not focus.on_body) or (info.on_body == focus.on_body and info.distance < focus.distance):
			focus = info
	if focus != null:
		if focus.on_body:
			_body_options(focus, options)
		else:
			_ground_options(focus, options)
	var best: ColossusIntent = null
	_last_scores.clear()
	for o in options:
		if o.kind in obs.blocked_intents:
			continue
		if o.kind == obs.current_intent:
			o.score += commitment
		o.score += _rng.randf() * 0.02
		_last_scores[o.kind] = maxf(_last_scores.get(o.kind, 0.0), o.score)
		if best == null or o.score > best.score:
			best = o
	return best


func _ground_options(p: ColossusObservation.PlayerInfo, options: Array[ColossusIntent]) -> void:
	if Gaius.SWORD_SLAM in p.opportunities:
		options.append(_make(Gaius.SWORD_SLAM, p, 0.85))
	if Gaius.STOMP in p.opportunities:
		options.append(_make(Gaius.STOMP, p, 0.8))
	if absf(p.bearing) > 1.8 and p.distance < 30.0:
		options.append(_make(Gaius.SEARCH, p, 0.55))
	if p.distance > 20.0:
		options.append(_make(Gaius.APPROACH, p, 0.5 + 0.1 * clampf((p.distance - 20.0) / 30.0, 0.0, 1.0)))
	options.append(_make(Gaius.OBSERVE, p, 0.35))


func _body_options(p: ColossusObservation.PlayerInfo, options: Array[ColossusIntent]) -> void:
	var t := p.time_on_body
	match p.region:
		&"sword", &"arm":
			# On the blade or the arm: it waits for the sword to come out of the ground.
			options.append(_shake(p, 0.5, 0.1 + 0.4 * clampf((t - 7.0) / 6.0, 0.0, 1.0)))
		&"foot", &"calf", &"thigh", &"pelvis", &"back":
			options.append(_shake(p, 0.5, 0.1 + 0.55 * clampf((t - 2.5) / 6.0, 0.0, 1.0)))
		&"shoulder":
			options.append(_shake(p, 0.45, 0.2 + 0.4 * clampf(t / 8.0, 0.0, 1.0)))
		&"neck", &"head":
			options.append(_shake(p, 0.6, 0.5 + 0.3 * clampf(t / 6.0, 0.0, 1.0)))
		_:
			options.append(_shake(p, 0.6, 0.3))
	options.append(_make(Gaius.OBSERVE, p, 0.2))


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
