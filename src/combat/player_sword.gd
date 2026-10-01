class_name PlayerSword
extends RefCounted
## Minimal sword for colossus fights: READY -> CHARGE -> STRIKE -> RECOVERY.
##
## Hold the attack action to charge (the longer, the stronger, up to ``charge_time``),
## release to strike. The strike tests once, on its first tick, against every weak point
## in range; there is no generic melee against other enemies yet.
## Usable standing or while gripping (the classic stab while holding on). Driven only by
## PlayerActions, so a human, an AI companion or a test bot use it the same way.

signal struck(result: Dictionary)

enum State { READY, CHARGE, STRIKE, RECOVERY }

var charge_time := 1.2
var strike_time := 0.2
var recovery_time := 0.45
## Strikes released before this much charge are quick jabs (charge counted as 0).
var min_charge := 0.12

var state := State.READY
var charge := 0.0
var state_time := 0.0
## Result of the last strike ({} until the first one).
var last_result := {}
var strikes := 0

var _struck_this_strike := false
var _power := 0.0


func reset() -> void:
	state = State.READY
	charge = 0.0
	state_time = 0.0
	_struck_this_strike = false


## True while the player should not crawl / should move slowly.
func is_busy() -> bool:
	return state == State.CHARGE or state == State.STRIKE


func update(p: PlayerCharacter, delta: float) -> void:
	state_time += delta
	var can_use := not p.dead and (p.state == PlayerCharacter.State.GROUND or p.state == PlayerCharacter.State.CLIMB) and p.balance.state != Balance.State.FALLEN
	match state:
		State.READY:
			if can_use and p.actions.attack_held:
				_enter(State.CHARGE)
				charge = 0.0
		State.CHARGE:
			if not can_use:
				_enter(State.READY)
				charge = 0.0
			elif p.actions.attack_held:
				charge = minf(1.0, charge + delta / charge_time)
			else:
				_power = 0.0 if charge < min_charge else charge
				_enter(State.STRIKE)
				_struck_this_strike = false
		State.STRIKE:
			if not _struck_this_strike:
				_struck_this_strike = true
				_strike(p)
			if state_time >= strike_time:
				_enter(State.RECOVERY)
		State.RECOVERY:
			if state_time >= recovery_time:
				_enter(State.READY)
				charge = 0.0


## Where the blade can land this tick: at the hands while gripping, in front of / below
## the feet while standing.
func strike_points(p: PlayerCharacter) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	if p.is_climbing() and p.grip:
		var hand := p.grip.world_point()
		var n := p.grip.world_normal()
		pts.append(hand - n * 0.1)
		pts.append(hand + p.climb_up * 0.4 - n * 0.1)
	else:
		var f := p.facing
		pts.append(p.global_position + f * 0.7 + Vector3.DOWN * 0.85)
		pts.append(p.global_position + f * 1.1 + Vector3.DOWN * 0.3)
	return pts


func _strike(p: PlayerCharacter) -> void:
	strikes += 1
	var best := {"accepted": false, "reason": &"nothing_in_reach", "damage": 0.0, "power": _power}
	var best_d := INF
	var pts := strike_points(p)
	for node in p.get_tree().get_nodes_in_group(&"weak_points"):
		var wp := node as WeakPoint
		var d := INF
		var at := pts[0]
		for q in pts:
			var dq := q.distance_to(wp.world_point())
			if dq < d:
				d = dq
				at = q
		if d > wp.radius * 2.5 or d >= best_d:
			continue
		best_d = d
		var r := wp.try_hit(at, _power, &"sword")
		r.power = _power
		r.weak_point = wp
		best = r
		if r.accepted:
			break
	last_result = best
	Perf.count(&"sword_checks")
	struck.emit(best)


func _enter(s: State) -> void:
	state = s
	state_time = 0.0


func state_name() -> String:
	return State.keys()[state]
