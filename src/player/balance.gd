class_name Balance
extends RefCounted
## Balance of a player standing (not gripping) on a possibly moving surface.
##
## Deliberately not a ragdoll: one scalar ``value`` (1 = steady, 0 = knocked down) driven
## continuously by a "disturbance" in m/s^2 computed from what the feet feel:
##   - tangential acceleration of the surface point (shake, start/stop, direction change),
##   - acceleration along the surface normal (heave), weighted lower,
##   - rotation of the segment (spinning under your feet is disorienting),
##   - slope steeper than comfortable,
## multiplied up when the player is moving fast relative to the surface.
## Disturbance above ``capacity`` drains balance; below it balance recovers.
##
##   STABLE -> UNSTABLE -> STUMBLE -> FALLEN
##   full     reduced     little      none     control
##   1.6      1.0         0.55        0.35     friction coefficient (resistance to sliding)

enum State { STABLE, UNSTABLE, STUMBLE, FALLEN }

signal state_changed(old_state: State, new_state: State)

## Disturbance (m/s^2) absorbed without losing any balance.
var capacity := 6.0
## Excess disturbance (m/s^2) that removes the whole balance in one second.
var loss_scale := 30.0
## Balance regained per second while undisturbed.
var recover_rate := 0.7
var rotation_weight := 3.0      ## m/s^2 per rad/s of surface rotation
var normal_weight := 0.4        ## heave counts less than sideways jerks
var comfortable_slope := deg_to_rad(15.0)
var run_penalty := 0.6          ## +60% disturbance at full running speed
## Minimum time on the ground after being knocked down.
var fallen_min_time := 1.2
var get_up_value := 0.45

var value := 1.0
var state := State.STABLE
## Last computed disturbance (m/s^2), for debugging/tuning.
var disturbance := 0.0
var _fallen_time := 0.0


## Advances the balance model. ``normal`` is the support normal, ``speed_ratio`` the
## player's speed relative to the surface divided by run speed.
func update(accel: Vector3, angular_velocity: Vector3, normal: Vector3, gravity: float, speed_ratio: float, delta: float) -> void:
	disturbance = measure(accel, angular_velocity, normal, gravity, speed_ratio)
	var excess := disturbance - capacity
	if excess > 0.0:
		value = maxf(0.0, value - excess / loss_scale * delta)
	else:
		value = minf(1.0, value + recover_rate * delta)
	if state == State.FALLEN:
		_fallen_time += delta
		if _fallen_time >= fallen_min_time and value >= get_up_value:
			_set_state(State.STUMBLE)
		return
	if value <= 0.0:
		knock_down()
		return
	_classify()


## Recover while not standing on anything (in the air you are not being shaken).
func recover(delta: float) -> void:
	disturbance = 0.0
	value = minf(1.0, value + recover_rate * delta)
	if state == State.FALLEN:
		_fallen_time += delta
		if _fallen_time < fallen_min_time or value < get_up_value:
			return
	_classify()


func measure(accel: Vector3, angular_velocity: Vector3, normal: Vector3, gravity: float, speed_ratio: float) -> float:
	var a_n := accel.dot(normal)
	var a_t := accel - normal * a_n
	var slope := acos(clampf(normal.dot(Vector3.UP), -1.0, 1.0))
	var slope_term := gravity * maxf(0.0, sin(slope) - sin(comfortable_slope))
	var d := a_t.length() + normal_weight * absf(a_n) + rotation_weight * angular_velocity.length() + slope_term
	return d * (1.0 + run_penalty * clampf(speed_ratio, 0.0, 1.5))


## Instant loss, e.g. from a hard landing.
func hit(amount: float) -> void:
	value = maxf(0.0, value - amount)
	if value <= 0.0:
		knock_down()
	elif state != State.FALLEN:
		_classify()


func knock_down(duration := -1.0) -> void:
	value = 0.0
	_fallen_time = 0.0 if duration < 0.0 else fallen_min_time - duration
	_set_state(State.FALLEN)


func reset() -> void:
	value = 1.0
	disturbance = 0.0
	_fallen_time = 0.0
	_set_state(State.STABLE)


## How much of the player's own movement input is applied (0..1).
func control() -> float:
	match state:
		State.STABLE:
			return 1.0
		State.UNSTABLE:
			return lerpf(0.55, 1.0, inverse_lerp(0.35, 0.7, value))
		State.STUMBLE:
			return 0.2
	return 0.0


## Coulomb friction coefficient of the feet (or body, when knocked down) against the
## surface. Planted feet hold firmly; a fallen body slides on slopes and under shaking.
func friction() -> float:
	match state:
		State.STABLE:
			return 1.6
		State.UNSTABLE:
			return 1.0
		State.STUMBLE:
			return 0.55
	return 0.35


func _classify() -> void:
	var next := state
	match state:
		State.STABLE:
			if value < 0.7:
				next = State.UNSTABLE
		State.UNSTABLE:
			if value >= 0.75:
				next = State.STABLE
			elif value < 0.35:
				next = State.STUMBLE
		State.STUMBLE, State.FALLEN:
			if value >= 0.75:
				next = State.STABLE
			elif value >= 0.4:
				next = State.UNSTABLE
	_set_state(next)


func _set_state(s: State) -> void:
	if s == state:
		return
	var old := state
	state = s
	state_changed.emit(old, s)
