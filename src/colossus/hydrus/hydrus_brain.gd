class_name HydrusBrain
extends ColossusBrain
## Utility brain for Hydrus. One intent per think tick:
##
##   someone on its back   : dive (after a while), else shake now and then, else cruise on
##   a swimmer close by     : ram (telegraphed), else approach slowly (curious)
##   otherwise              : cruise round the lake
##
## The colossus' rules (dive / ram cooldowns, no dive right after climbing on or after a
## hit, no ram at someone on it, shake limits) filter what this proposes. Deterministic
## for a given seed.

var _rng := RandomNumberGenerator.new()
var _last := {}


func _init(seed_value := 29) -> void:
	_rng.seed = seed_value


func decide(obs: ColossusObservation) -> ColossusIntent:
	var options: Array[ColossusIntent] = []
	var cruise := ColossusIntent.make(Hydrus.CRUISE)
	cruise.score = 0.2
	options.append(cruise)
	var on_body: ColossusObservation.PlayerInfo = null
	var swimmer: ColossusObservation.PlayerInfo = null
	for info in obs.players:
		if info.on_body:
			on_body = info
		elif (obs.facts.get("swimmers", []) as Array).has(info.player) and (swimmer == null or info.distance < swimmer.distance):
			swimmer = info
	if on_body:
		var d := ColossusIntent.make(Hydrus.DIVE)
		d.target_player = on_body.player
		d.score = 0.5 + 0.4 * clampf(on_body.time_on_body / 15.0, 0.0, 1.0)
		options.append(d)
		var s := ColossusIntent.make(Hydrus.SHAKE_BODY, 0.6 + 0.4 * _rng.randf())
		s.target_player = on_body.player
		s.score = 0.3 + 0.2 * _rng.randf()
		options.append(s)
	elif swimmer:
		if swimmer.distance < 26.0:
			var r := ColossusIntent.make(Hydrus.RAM)
			r.target_player = swimmer.player
			r.target_position = swimmer.position
			r.score = 0.45 + 0.1 * _rng.randf()
			options.append(r)
		var a := ColossusIntent.make(Hydrus.APPROACH)
		a.target_player = swimmer.player
		a.target_position = swimmer.position
		a.score = 0.35
		options.append(a)
	var best: ColossusIntent = null
	for o in options:
		if o.kind in obs.blocked_intents:
			continue
		if o.kind == obs.current_intent:
			o.score += 0.08
		if best == null or o.score > best.score:
			best = o
	_last.clear()
	for o in options:
		_last[String(o.kind)] = o.score
	return best


func debug_text() -> String:
	var parts := []
	for k in _last:
		parts.append("%s %.2f" % [k, _last[k]])
	return "brain: " + "  ".join(parts)
