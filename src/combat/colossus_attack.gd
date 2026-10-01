class_name ColossusAttack
extends RefCounted
## One colossus attack in progress: TELEGRAPH -> ACTIVE -> RECOVERY.
##
## Pure timing + data. The colossus poses its limbs from ``phase`` / ``phase_t`` and tests
## its hit volumes only while ACTIVE. Damage can never happen in the same tick the attack
## was chosen: the fairness rules clamp every telegraph to a minimum before it starts.
## Everything advances in physics ticks only (independent of the render rate).

enum Phase { NONE, PREPARE, TELEGRAPH, ACTIVE, RECOVERY, DONE }

var kind: StringName
## Seconds per phase (after the fairness clamp).
var telegraph_time := 0.8
var active_time := 0.3
var recovery_time := 1.0
## Heavy attacks get a longer minimum recovery from the rules.
var heavy := false

var phase := Phase.NONE
## Seconds spent in the current phase.
var phase_time := 0.0
## Attack target (world point), target player, limb / side index (-1 none).
var target_point := Vector3.ZERO
var target_player: Node3D
var limb := -1
## Players already hit by this attack (instance ids): one hit per attack and player.
var hit_ids := {}
## Total seconds since start (debug).
var age := 0.0


static func make(p_kind: StringName, telegraph: float, active: float, recovery: float, p_heavy := false) -> ColossusAttack:
	var a := ColossusAttack.new()
	a.kind = p_kind
	a.telegraph_time = telegraph
	a.active_time = active
	a.recovery_time = recovery
	a.heavy = p_heavy
	a.phase = Phase.PREPARE
	return a


## Starts the telegraph (the colossus calls this once it is ready, e.g. both feet planted).
func begin_telegraph() -> void:
	_enter(Phase.TELEGRAPH)


## Advances the timers; returns true when the phase changed this tick.
func tick(delta: float) -> bool:
	age += delta
	if phase == Phase.PREPARE or phase == Phase.DONE or phase == Phase.NONE:
		phase_time += delta
		return false
	phase_time += delta
	var length := duration_of(phase)
	if phase_time + 1e-6 >= length:
		match phase:
			Phase.TELEGRAPH:
				_enter(Phase.ACTIVE)
			Phase.ACTIVE:
				_enter(Phase.RECOVERY)
			Phase.RECOVERY:
				_enter(Phase.DONE)
		return true
	return false


func duration_of(p: Phase) -> float:
	match p:
		Phase.TELEGRAPH:
			return telegraph_time
		Phase.ACTIVE:
			return active_time
		Phase.RECOVERY:
			return recovery_time
	return 0.0


## 0..1 progress through the current phase.
func phase_t() -> float:
	var d := duration_of(phase)
	return clampf(phase_time / d, 0.0, 1.0) if d > 0.0 else 1.0


func is_active() -> bool:
	return phase == Phase.ACTIVE


func is_done() -> bool:
	return phase == Phase.DONE


## Seconds left in the current phase.
func time_left() -> float:
	return maxf(0.0, duration_of(phase) - phase_time)


func phase_name() -> String:
	return Phase.keys()[phase]


func describe() -> String:
	if phase == Phase.NONE:
		return "-"
	return "%s %s %.2f/%.2f s" % [kind, phase_name(), phase_time, duration_of(phase)]


func _enter(p: Phase) -> void:
	phase = p
	phase_time = 0.0
