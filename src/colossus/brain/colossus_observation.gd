class_name ColossusObservation
extends RefCounted
## Everything a ColossusBrain is allowed to know, gathered by the colossus each think tick.
## Brains must not reach into the scene tree themselves: this keeps them swappable
## (utility AI, small learned model, scripted) and testable in isolation.

class PlayerInfo:
	var player: Node3D
	var position := Vector3.ZERO
	var distance := 0.0
	## Player is gripping or standing on one of our segments.
	var on_body := false
	## Continuous seconds spent on the body.
	var time_on_body := 0.0
	## Height of the player above the colossus root, normalised by colossus height (0 feet .. 1 head).
	var height_ratio := 0.0
	var segment: StringName = &""
	var stamina_ratio := 1.0

var time := 0.0
var self_position := Vector3.ZERO
var self_forward := Vector3.FORWARD
var players: Array[PlayerInfo] = []
## Intents the encounter rules currently forbid (e.g. shake on cooldown). Brains may use
## this to avoid wasting a decision, but the rules are enforced regardless.
var blocked_intents: Array[StringName] = []
var current_intent: StringName = ColossusIntent.IDLE
var arena_center := Vector3.ZERO
var arena_radius := 60.0


func players_on_body() -> Array[PlayerInfo]:
	var out: Array[PlayerInfo] = []
	for p in players:
		if p.on_body:
			out.append(p)
	return out


func nearest_player() -> PlayerInfo:
	var best: PlayerInfo = null
	for p in players:
		if best == null or p.distance < best.distance:
			best = p
	return best
