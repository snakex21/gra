class_name PlayerBow
extends RefCounted
## The bow: IDLE -> DRAW -> AIM -> RELEASE -> RECOVERY.
##
## Hold the attack action to draw (``draw`` 0..1 over ``draw_time``; full draw = AIM, held
## as long as the button is), release to shoot. The arrow's speed grows with the draw;
## an arrow released under ``min_draw`` is not shot (the string is let down). The arrow is
## a real projectile simulated by the world's ArrowSystem.
##
## Aim: the view direction from PlayerActions (camera for flat play, a controller for VR).
## The arrow leaves the bow towards the point the view ray hits (or a far point), so what
## is under the crosshair is what the arrow flies at; gravity is the player's problem.
## Usable on foot and on horseback (the horse keeps its own heading while aiming).

signal shot(arrow: Dictionary)

enum State { IDLE, DRAW, AIM, RELEASE, RECOVERY }

var draw_time := 0.9
var release_time := 0.1
var recovery_time := 0.45
var min_draw := 0.2
var min_speed := 22.0
var max_speed := 58.0
## Longest aim ray (also the aim point when the ray hits nothing).
var aim_range := 250.0

var state := State.IDLE
var draw := 0.0
var state_time := 0.0
var shots := 0
var last_shot := {}
## Debug: current launch point, direction and speed while drawing.
var launch_point := Vector3.ZERO
var aim_dir := Vector3.FORWARD
var aim_point := Vector3.ZERO


func reset() -> void:
	state = State.IDLE
	draw = 0.0
	state_time = 0.0


func is_aiming() -> bool:
	return state == State.DRAW or state == State.AIM


func is_busy() -> bool:
	return state != State.IDLE


func speed_for(d: float) -> float:
	return lerpf(min_speed, max_speed, clampf(d, 0.0, 1.0))


static func can_use(p: PlayerCharacter) -> bool:
	if p.dead or p.balance.state == Balance.State.FALLEN:
		return false
	if p.state == PlayerCharacter.State.RIDE:
		return p.riding.phase == PlayerRiding.Phase.RIDING
	return p.state == PlayerCharacter.State.GROUND


func update(p: PlayerCharacter, delta: float) -> void:
	state_time += delta
	var usable := can_use(p)
	if is_aiming():
		_update_aim(p)
	match state:
		State.IDLE:
			if usable and p.actions.attack_held:
				_enter(State.DRAW)
				draw = 0.0
		State.DRAW, State.AIM:
			if not usable:
				_enter(State.IDLE)
				draw = 0.0
			elif p.actions.attack_held:
				draw = minf(1.0, draw + delta / draw_time)
				if draw >= 1.0 and state == State.DRAW:
					_enter(State.AIM)
			elif draw < min_draw:
				_enter(State.IDLE)
				draw = 0.0
			else:
				_enter(State.RELEASE)
				_shoot(p)
		State.RELEASE:
			if state_time >= release_time:
				_enter(State.RECOVERY)
		State.RECOVERY:
			if state_time >= recovery_time:
				_enter(State.IDLE)
				draw = 0.0


## Right-cheek draw anchor shared by nock, aiming and the real projectile.
## The head and shoulder girdle face the same aim frame cosmetically. This
## socket reads deterministic gameplay input, never the smoothed render rig.
func draw_frame(p: PlayerCharacter) -> Basis:
	var up := Vector3.UP
	if p.riding and p.riding.is_active() and is_instance_valid(p.riding.horse):
		var weight := p.riding.cosmetic_seat_weight()
		up = up.lerp(p.riding.horse.body_transform().basis.y.normalized(), weight).normalized()
	var forward := -p.actions.view_basis.z.normalized()
	if absf(forward.dot(up)) > .999:
		up = p.actions.view_basis.y.normalized()
	return Basis.looking_at(forward, up)

func bow_point(p: PlayerCharacter) -> Vector3:
	var seated_offset := Vector3.ZERO
	if p.riding and p.riding.is_active() and is_instance_valid(p.riding.horse):
		seated_offset = p.riding.horse.body_transform().basis.y * (PlayerRiding.SEATED_VISUAL_OFFSET * p.riding.cosmetic_seat_weight())
	return p.global_position + seated_offset + draw_frame(p) * Vector3(.17, .55, .05)


func _update_aim(p: PlayerCharacter) -> void:
	launch_point = bow_point(p)
	var b := p.actions.view_basis
	var view_dir := -b.z.normalized()
	var origin := p.actions.aim_origin if p.actions.aim_origin != Vector3.INF else p.global_position + Vector3.UP * 0.7
	aim_point = origin + view_dir * aim_range
	var space := p.get_world_3d().direct_space_state
	var exclude: Array[RID] = [p.get_rid()]
	if p.is_riding() and is_instance_valid(p.riding.horse):
		exclude.append(p.riding.horse.get_rid())
	var hit := ClimbQuery.ray(space, origin, aim_point, exclude, Layers.WORLD | Layers.COLOSSUS, &"bow_aim_rays")
	if not hit.is_empty():
		aim_point = hit.position
	aim_dir = (aim_point - launch_point).normalized()
	# Turn the archer towards the aim (on foot).
	if not p.is_riding():
		var flat := Vector3(aim_dir.x, 0.0, aim_dir.z)
		if flat.length() > 0.1:
			p.facing = flat.normalized()


func _shoot(p: PlayerCharacter) -> void:
	_update_aim(p)
	var speed := speed_for(draw)
	var vel := aim_dir * speed
	# Moving archers (horseback) give the arrow their own velocity.
	if p.is_riding():
		vel += p.velocity
	var sys := ArrowSystem.of(p)
	var a := sys.spawn(launch_point, vel, p)
	shots += 1
	last_shot = {"draw": draw, "speed": speed, "dir": aim_dir, "point": launch_point, "aim_point": aim_point, "arrow": a}
	Perf.count(&"bow_shots")
	shot.emit(a)


## Launch direction (low arc) that carries an arrow of ``speed`` from ``from`` to ``to``
## under gravity ``g``; Vector3.ZERO when out of range. Used by bots / AI companions.
static func launch_direction(from: Vector3, to: Vector3, speed: float, g := 9.8) -> Vector3:
	var d := to - from
	var flat := Vector3(d.x, 0.0, d.z)
	var x := flat.length()
	if x < 1e-3:
		return Vector3.UP if d.y > 0.0 else Vector3.DOWN
	var y := d.y
	var v2 := speed * speed
	var disc := v2 * v2 - g * (g * x * x + 2.0 * y * v2)
	if disc < 0.0:
		return Vector3.ZERO
	var angle := atan((v2 - sqrt(disc)) / (g * x))
	return (flat / x * cos(angle) + Vector3.UP * sin(angle)).normalized()


func _enter(s: State) -> void:
	state = s
	state_time = 0.0


func state_name() -> String:
	return State.keys()[state]
