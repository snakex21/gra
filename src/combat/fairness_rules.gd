class_name FairnessRules
extends RefCounted
## Hand-designed encounter rules, separate from (and stronger than) any colossus brain.
## The brain only proposes; these rules decide what is allowed right now and clamp the
## timing of every attack. No brain can bypass them:
##
##   - every attack has at least ``min_telegraph`` of warning before it can hurt,
##   - a heavy attack is followed by at least ``heavy_recovery_min`` of recovery,
##   - each attack kind has its own cooldown, and there is a gap between any two attacks,
##   - the same attack never runs more than ``max_repeat`` times in a row,
##   - shake: limited duration and a minimum cooldown (the base Colossus enforces these too),
##     and never right after a heavy attack,
##   - weak point protection: limited duration, a cooldown, and a budget per time window,
##     so the weak point is open most of the time,
##   - repositioning cannot go on forever (the way onto the body is never cut off for long).
##
## Time is the colossus' simulation time (physics ticks), never the render clock.

var min_telegraph := 0.6
var heavy_recovery_min := 1.2
var attack_gap := 1.5
var max_repeat := 2
## Only attacks within this many seconds count as "in a row".
var repeat_window := 20.0
var cooldowns := {&"stomp": 6.0, &"arm_sweep": 6.0}
var shake_after_attack := 1.5
var protect_max := 2.5
var protect_cooldown := 6.0
## At most this many seconds of protection within any ``protect_window`` seconds.
var protect_budget := 5.0
var protect_window := 20.0
var reposition_max := 8.0
var reposition_cooldown := 4.0
## No attack starts against a player who is knocked down, nor this long after he got up.
var downed_grace := 1.2

var _last_end := {}           # kind -> time the last one ended
var _last_attack_end := -999.0
var _last_heavy_end := -999.0
var _history: Array = []      # [kind, start time]
var _protect_log: Array = []  # [start, end]
var _protect_start := -1.0
var _reposition_start := -1.0
var _last_reposition_end := -999.0
var _last_down := -999.0
## Count of rule interventions (debug / tests).
var interventions := 0


func reset() -> void:
	_last_end.clear()
	_last_attack_end = -999.0
	_last_heavy_end = -999.0
	_history.clear()
	_protect_log.clear()
	_protect_start = -1.0
	_reposition_start = -1.0
	_last_reposition_end = -999.0
	_last_down = -999.0
	interventions = 0


## Clamps an attack's timing before it starts.
func clamp_attack(a: ColossusAttack) -> void:
	if a.telegraph_time < min_telegraph:
		a.telegraph_time = min_telegraph
		interventions += 1
	if a.heavy and a.recovery_time < heavy_recovery_min:
		a.recovery_time = heavy_recovery_min
		interventions += 1


func on_attack_start(kind: StringName, now: float) -> void:
	_history.append([kind, now])
	if _history.size() > 8:
		_history.pop_front()


func on_attack_end(a: ColossusAttack, now: float) -> void:
	_last_end[a.kind] = now
	_last_attack_end = now
	if a.heavy:
		_last_heavy_end = now


func on_protect(on: bool, now: float) -> void:
	if on and _protect_start < 0.0:
		_protect_start = now
	elif not on and _protect_start >= 0.0:
		_protect_log.append([_protect_start, now])
		_last_end[&"protect_weakpoint"] = now
		_protect_start = -1.0


func on_reposition(on: bool, now: float) -> void:
	if on and _reposition_start < 0.0:
		_reposition_start = now
	elif not on and _reposition_start >= 0.0:
		_last_reposition_end = now
		_reposition_start = -1.0


## Called every tick while the target player is knocked down.
func on_player_down(now: float) -> void:
	_last_down = now


## Must a running protection end now?
func protect_expired(now: float) -> bool:
	return _protect_start >= 0.0 and now - _protect_start >= protect_max


func reposition_expired(now: float) -> bool:
	return _reposition_start >= 0.0 and now - _reposition_start >= reposition_max


## Seconds of protection within the last window (including a running one).
func protect_used(now: float) -> float:
	var used := 0.0
	for e in _protect_log:
		var s: float = maxf(e[0], now - protect_window)
		used += maxf(0.0, float(e[1]) - s)
	if _protect_start >= 0.0:
		used += now - maxf(_protect_start, now - protect_window)
	return used


## Intents that are not allowed right now.
func blocked(now: float) -> Array[StringName]:
	var out: Array[StringName] = []
	for kind in cooldowns:
		if now - _last_down < downed_grace:
			out.append(kind)
		elif now - float(_last_end.get(kind, -999.0)) < float(cooldowns[kind]):
			out.append(kind)
		elif now - _last_attack_end < attack_gap:
			out.append(kind)
		elif _repeats(kind, now) >= max_repeat:
			out.append(kind)
	if now - _last_heavy_end < shake_after_attack:
		out.append(ColossusIntent.SHAKE_PLAYER)
	if now - float(_last_end.get(&"protect_weakpoint", -999.0)) < protect_cooldown or protect_used(now) >= protect_budget:
		out.append(&"protect_weakpoint")
	if _reposition_start < 0.0 and now - _last_reposition_end < reposition_cooldown:
		out.append(&"reposition")
	return out


func _repeats(kind: StringName, now: float) -> int:
	var n := 0
	for i in range(_history.size() - 1, -1, -1):
		if _history[i][0] != kind or now - float(_history[i][1]) > repeat_window:
			break
		n += 1
	return n
