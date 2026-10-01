class_name QuadratusBrain
extends ColossusBrain
## Utility brain for Quadratus. One intent per think tick:
##
##   foot hit       : react_to_foot_hit (just hit), lower_body (resting on three legs),
##                    recover (pushing itself up)
##   player on foot : stomp (by a front hoof), head_attack (in front, along the head's
##                    swing), turn (beside / behind it: a slow walking turn, which lifts
##                    the hind hooves), approach (far), reposition (now and then), observe
##   player on body : shake_body (stronger and sooner on the neck / head), observe
##
## Cooldowns, telegraphs and anti-spam are not here: FairnessRules and the colossus'
## own rules filter whatever this proposes. Deterministic for a given seed.

var commitment := 0.1

var _rng := RandomNumberGenerator.new()
var _last_scores := {}


func _init(seed_value := 11) -> void:
	_rng.seed = seed_value


func decide(obs: ColossusObservation) -> ColossusIntent:
	var options: Array[ColossusIntent] = []
	var idle := ColossusIntent.make(ColossusIntent.IDLE)
	idle.score = 0.05
	options.append(idle)
	var buckle: StringName = obs.facts.get("buckle", &"NONE")
	var focus: ColossusObservation.PlayerInfo = null
	for info in obs.players:
		if focus == null or (info.on_body and not focus.on_body) or (info.on_body == focus.on_body and info.distance < focus.distance):
			focus = info
	match buckle:
		&"REACT":
			options.append(_make(Quadratus.REACT_FOOT, focus, 1.0))
		&"KNEEL":
			options.append(_make(Quadratus.LOWER_BODY, focus, 0.9))
		&"RISE":
			options.append(_make(Quadratus.RECOVER, focus, 0.9))
		_:
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
	if Quadratus.STOMP in p.opportunities:
		options.append(_make(Quadratus.STOMP, p, 0.85))
	if Quadratus.HEAD_ATTACK in p.opportunities:
		options.append(_make(Quadratus.HEAD_ATTACK, p, 0.8))
	if absf(p.bearing) > 0.7 and p.distance < 40.0:
		# Someone beside or behind: turn towards them (slowly, stepping).
		options.append(_make(Quadratus.TURN, p, 0.5 + 0.2 * clampf((absf(p.bearing) - 0.7) / 1.5, 0.0, 1.0)))
	if p.distance > 18.0:
		options.append(_make(Quadratus.APPROACH, p, 0.55 + 0.1 * clampf((p.distance - 18.0) / 30.0, 0.0, 1.0)))
	if _rng.randf() < 0.08:
		var r := _make(ColossusIntent.REPOSITION, p, 0.45)
		var side := Vector3(cos(obs.time * 0.37), 0.0, sin(obs.time * 0.37))
		r.target_position = obs.self_position + side * 14.0
		options.append(r)
	options.append(_make(Quadratus.OBSERVE, p, 0.35))


func _body_options(p: ColossusObservation.PlayerInfo, options: Array[ColossusIntent]) -> void:
	var t := p.time_on_body
	match p.region:
		&"thigh", &"shin", &"hoof":
			options.append(_shake(p, 0.5, 0.15 + 0.4 * clampf((t - 2.0) / 5.0, 0.0, 1.0)))
		&"rump", &"back":
			options.append(_shake(p, 0.55, 0.15 + 0.5 * clampf((t - 2.5) / 6.0, 0.0, 1.0)))
		&"neck", &"head":
			options.append(_shake(p, 0.65, 0.45 + 0.35 * clampf(t / 6.0, 0.0, 1.0)))
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
