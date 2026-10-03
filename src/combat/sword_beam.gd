class_name SwordBeam
extends RefCounted
## The sword raised to the sun: a beam of light that gathers into one bright line when the
## player looks towards the next colossus. The only guide in the world (no map marker).
##
## Hold the beam action with the sword in hand (standing or on Agro). Only the view
## direction matters (``PlayerActions.view_basis``), so a camera, a VR head or a bot
## use it the same way. The beam needs sunlight: one ray towards the sun from the blade,
## re-tested a few times per second; in shadow (under an arch, in a narrow canyon, under
## a colossus) the blade only glints.
##
## ``target`` is set by the region (the valley: the next gate; an arena: the colossus).
## INF means there is nothing to find: the beam scatters and never gathers.

## Seconds to raise the sword (the beam is off until it is up).
var raise_time := 0.35
## Horizontal angle (rad) at which the beam starts to gather, and below which it is one line.
var gather_angle := 0.8
var lock_angle := 0.07
## Sunlight test: ray length and how often it is repeated (in ticks).
var sun_ray_length := 220.0
var sun_test_every := 6
## Direction towards the sun (set by the region from its light).
var sun_direction := Vector3(0.35, 0.85, 0.4).normalized()
## World point the beam leads to (INF: nothing to find).
var target := Vector3.INF
## Underground: a local sword flashlight, independent of sunlight and target guidance.
var lantern := false

var raised := false
## 0 lowered .. 1 sword up.
var raise := 0.0
## 0 scattered .. 1 one bright line towards the target.
var focus := 0.0
## Sunlight on the blade (last test).
var lit := true
## True while the beam is one line towards the target.
var locked := false
## Direction the beam shines (world, unit).
var direction := Vector3.FORWARD
var sun_rays := 0

var _tick := 0


func reset() -> void:
	raised = false
	raise = 0.0
	focus = 0.0
	locked = false
	_tick = 0


static func can_use(p: PlayerCharacter) -> bool:
	if p.dead or p.weapon != PlayerCharacter.Weapon.SWORD or p.sword.is_busy():
		return false
	if p.balance.state == Balance.State.FALLEN:
		return false
	if p.state == PlayerCharacter.State.RIDE:
		return p.riding.phase == PlayerRiding.Phase.RIDING
	return p.state == PlayerCharacter.State.GROUND


## World position of the blade tip while raised.
static func tip(p: PlayerCharacter) -> Vector3:
	return p.global_position + Vector3.UP * 1.55 + PlayerCharacter._flat_dir(p.facing, Vector3.FORWARD) * 0.25


func update(p: PlayerCharacter, delta: float) -> void:
	raised = p.actions.beam_held and can_use(p)
	raise = move_toward(raise, 1.0 if raised else 0.0, delta / raise_time)
	if raise <= 0.0:
		focus = 0.0
		locked = false
		return
	var view := -p.actions.view_basis.z
	direction = view.normalized() if view.length() > 0.01 else Vector3.FORWARD
	_tick += 1
	if lantern:
		lit = true
		focus = 0.0
		locked = false
		return
	if raise >= 1.0 and (_tick % sun_test_every == 1 or sun_test_every <= 1):
		lit = _sunlit(p)
	var want := 0.0
	if raise >= 1.0 and lit and target != Vector3.INF:
		var to := target - p.global_position
		var a := absf(Vector2(direction.x, direction.z).angle_to(Vector2(to.x, to.z)))
		want = 1.0 - smoothstep(lock_angle, gather_angle, a)
		if want > 0.0:
			# The gathered beam bends from the view towards the target.
			var from_blade := target - tip(p)
			direction = direction.slerp(from_blade.normalized(), want * 0.85).normalized()
	focus = move_toward(focus, want, delta * 4.0)
	locked = focus > 0.97


func _sunlit(p: PlayerCharacter) -> bool:
	var space := p.get_world_3d().direct_space_state
	var from := tip(p)
	var q := PhysicsRayQueryParameters3D.create(from, from + sun_direction * sun_ray_length, Layers.WORLD | Layers.COLOSSUS)
	q.exclude = [p.get_rid()]
	sun_rays += 1
	Perf.count(&"beam_rays")
	return space.intersect_ray(q).is_empty()
