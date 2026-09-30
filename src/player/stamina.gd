class_name Stamina
extends RefCounted
## Grip stamina. Pure data + rules, no nodes, so it is trivial to test and to replicate.

signal exhausted_changed(is_exhausted: bool)

var max_value := 100.0
var value := 100.0
## Once exhausted, the climber cannot grip again until stamina recovers to this value.
var recover_threshold := 30.0
var exhausted := false
## Seconds before regeneration starts after the last drain.
var regen_delay := 0.35

var _since_drain := 999.0


func ratio() -> float:
	return value / max_value


func can_grip() -> bool:
	return not exhausted and value > 0.0


func drain(amount: float) -> void:
	if amount <= 0.0:
		return
	_since_drain = 0.0
	value = maxf(0.0, value - amount)
	if value <= 0.0 and not exhausted:
		exhausted = true
		exhausted_changed.emit(true)


func regen(rate: float, delta: float) -> void:
	_since_drain += delta
	if _since_drain < regen_delay:
		return
	value = minf(max_value, value + rate * delta)
	if exhausted and value >= recover_threshold:
		exhausted = false
		exhausted_changed.emit(false)


func tick_idle(delta: float) -> void:
	_since_drain += delta


func refill() -> void:
	value = max_value
	_since_drain = 999.0
	if exhausted:
		exhausted = false
		exhausted_changed.emit(false)
