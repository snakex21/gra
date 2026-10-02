class_name PhaedraBrain
extends ColossusBrain
## Utility brain for Phaedra: timid and curious. One intent per think tick:
##
##   player hidden in a tunnel : peek (walk to that mouth, lower the head into it)
##   player on foot, close     : stomp (cornered: a front hoof is close), else back away
##   player on foot, mid range : observe (watch), turn towards
##   player on foot, far       : approach slowly (curious), never closer than ~22 m
##   player on body            : shake_body (stronger on the neck), observe
##
## The colossus' rules (FairnessRules, peek cooldown, no peeking with someone on it)
## filter what this proposes. Deterministic for a given seed.

var commitment := 0.1

var _rng := RandomNumberGenerator.new()
var _last_scores := {}


func _init(seed_value := 17) -> void:
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
			_ground_options(obs, focus, options)
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


func _ground_options(obs: ColossusObservation, p: ColossusObservation.PlayerInfo, options: Array[ColossusIntent]) -> void:
	var tunnel := int(obs.facts.get("player_tunnel", -1))
	if tunnel >= 0:
		# Hidden: it cannot see the player, but it knows where they went. Curiosity wins.
		var peek := _make(Phaedra.PEEK, p, 0.8)
		peek.target_position = obs.facts.get("peek_mouth", p.position)
		options.append(peek)
		options.append(_make(Quadratus.OBSERVE, p, 0.3))
		return
	if Quadratus.STOMP in p.opportunities:
		options.append(_make(Quadratus.STOMP, p, 0.85))
	if p.distance < 16.0:
		# Too close in the open: back away from the player, inside the arena.
		var away := obs.self_position - p.position
		away.y = 0.0
		away = away.normalized() if away.length() > 0.1 else -obs.self_forward
		var goal := obs.self_position + away * 14.0
		var from_center := goal - obs.arena_center
		from_center.y = 0.0
		if from_center.length() > obs.arena_radius * 0.75:
			# Cornered against the rim: slip away sideways instead.
			goal = obs.self_position + away.cross(Vector3.UP) * (14.0 if _rng.randf() < 0.5 else -14.0)
		var r := _make(ColossusIntent.REPOSITION, p, 0.6 + 0.2 * clampf((16.0 - p.distance) / 10.0, 0.0, 1.0))
		r.target_position = goal
		options.append(r)
	if absf(p.bearing) > 0.6 and p.distance < 45.0:
		options.append(_make(Quadratus.TURN, p, 0.45))
	if p.distance > 32.0:
		options.append(_make(Quadratus.APPROACH, p, 0.5))
	options.append(_make(Quadratus.OBSERVE, p, 0.35))


func _body_options(p: ColossusObservation.PlayerInfo, options: Array[ColossusIntent]) -> void:
	var t := p.time_on_body
	match p.region:
		# The climber gets a few calm seconds after the head comes up (time to get onto the
		# mane), then a neck toss now and then.
		&"head":
			options.append(_shake(p, 0.5, 0.1 + 0.4 * clampf((t - 6.0) / 6.0, 0.0, 1.0)))
		&"neck":
			options.append(_shake(p, 0.5, 0.15 + 0.45 * clampf((t - 6.0) / 6.0, 0.0, 1.0)))
		&"back":
			options.append(_shake(p, 0.5, 0.15 + 0.45 * clampf((t - 5.0) / 6.0, 0.0, 1.0)))
		_:
			options.append(_shake(p, 0.5, 0.3))
	options.append(_make(Quadratus.OBSERVE, p, 0.2))


func _shake(p: ColossusObservation.PlayerInfo, strength: float, score: float) -> ColossusIntent:
	var s := _make(Quadratus.SHAKE_BODY, p, score)
	s.strength = strength
	return s


func _make(kind: StringName, p: ColossusObservation.PlayerInfo, score: float) -> ColossusIntent:
	var i := ColossusIntent.make(kind)
	if p != null:
		i.target_player = p.player
		i.target_position = p.position
	i.score = score
	return i


func debug_text() -> String:
	var parts := PackedStringArray()
	for k in _last_scores:
		parts.append("%s %.2f" % [k, _last_scores[k]])
	return "brain: " + ", ".join(parts)
