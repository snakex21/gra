class_name ColossusIntent
extends RefCounted
## WHAT the colossus wants to do. Produced by a ColossusBrain, executed by the colossus'
## continuous motion controller (HOW). Intents are small plain data so they can be logged,
## replayed, compared in A/B tests and sent over the network.
##
## ``kind`` is a StringName instead of an enum so new colossi can add their own intents
## without touching shared code. Common kinds:
##   idle, reposition, focus_player, shake_player, attack, protect_weakpoint, charge,
##   retreat, expose_side, environmental_attack

const IDLE := &"idle"
const REPOSITION := &"reposition"
const FOCUS_PLAYER := &"focus_player"
const SHAKE_PLAYER := &"shake_player"

var kind: StringName = IDLE
## Player this intent is about (may be null).
var target_player: Node3D
## World position this intent is about (reposition goal, attack point...).
var target_position := Vector3.ZERO
## 0..1 urgency / intensity hint for the controller.
var strength := 1.0
## Utility score that selected it (debug / A/B logging only).
var score := 0.0


static func make(p_kind: StringName, p_strength := 1.0) -> ColossusIntent:
	var i := ColossusIntent.new()
	i.kind = p_kind
	i.strength = p_strength
	return i


func describe() -> String:
	var s := String(kind)
	if target_player:
		s += " -> %s" % target_player.name
	return "%s (%.2f)" % [s, score]
