class_name AvionBrain
extends ColossusBrain
## Utility brain for Avion. One intent per think tick:
##
##   someone on its back : carry them round over the water, roll now and then
##   someone in reach     : swoop at them (the nearest)
##   otherwise            : circle high over the lake
##
## The colossus' rules (swoop cooldown, no swoop with someone on it, rolls only over the
## water and under the shake limits, none right after a hit) filter what this proposes.

var _rng := RandomNumberGenerator.new()
var _last := {}


func _init(seed_value := 41) -> void:
	_rng.seed = seed_value


func decide(obs: ColossusObservation) -> ColossusIntent:
	var options: Array[ColossusIntent] = []
	var circle := ColossusIntent.make(Avion.CIRCLE)
	circle.score = 0.2
	options.append(circle)
	var rider: ColossusObservation.PlayerInfo = null
	var nearest: ColossusObservation.PlayerInfo = null
	for info in obs.players:
		if info.on_body:
			rider = info
		elif nearest == null or info.distance < nearest.distance:
			nearest = info
	if rider:
		var c := ColossusIntent.make(Avion.CARRY)
		c.target_player = rider.player
		c.score = 0.4
		options.append(c)
		var s := ColossusIntent.make(Avion.SHAKE_BODY, 0.6 + 0.4 * _rng.randf())
		s.target_player = rider.player
		s.score = 0.3 + 0.25 * _rng.randf() + 0.1 * clampf(rider.time_on_body / 20.0, 0.0, 1.0)
		options.append(s)
	elif nearest and not (nearest.player as PlayerCharacter).is_swimming():
		var w := ColossusIntent.make(Avion.SWOOP)
		w.target_player = nearest.player
		w.score = 0.6
		options.append(w)
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
