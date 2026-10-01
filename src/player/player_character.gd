class_name PlayerCharacter
extends CharacterBody3D
## Player character: ground locomotion + climbing on static or moving bodies.
##
## Gameplay reads only ``actions`` (PlayerActions). There is no singleton player: every
## instance joins the "players" group and colossi/cameras/HUDs are given a reference.
##
## Climbing model: while gripping, the only state is a SurfaceAnchor (body + local
## point + local normal). The body position is derived from it every tick, so the
## climber is carried by the colossus exactly. Moving = crawling the anchor across
## collision shapes with short raycasts (see ClimbQuery.crawl).

signal grabbed(anchor: SurfaceAnchor)
signal grip_released(reason: StringName)
signal mantled
## Emitted on every landing; ``tier`` is FallImpact.Tier.
signal landed(impact_speed: float, tier: int, damage: float)
signal died

enum State { GROUND, AIR, CLIMB }

@export_group("Locomotion")
@export var run_speed := 5.5
@export var ground_accel := 40.0
@export var air_accel := 6.0
@export var gravity := 22.0
@export var jump_speed := 7.0

@export_group("Climbing")
@export var climb_speed := 1.6
## Body centre distance from the surface while gripping.
@export var hang_distance := 0.45
## Hands are this far above the body centre along the climb "up" direction.
@export var hand_reach := 0.9
@export var grab_radius := 0.8
@export var regrab_delay := 0.3
@export var climb_jump_speed := 6.5
## In the air, the wider "rescue" grab search only runs while falling faster than this.
@export var rescue_fall_speed := 3.0

@export_group("Stamina")
@export var drain_hang := 3.0       ## per second, just holding on
@export var drain_climb := 5.0      ## extra per second while moving
@export var drain_shake := 24.0     ## extra per second at full shake level
@export var jump_cost := 12.0
@export var regen_rate := 35.0      ## per second standing on solid ground (or a colossus' back)
@export var slip_below := 0.25      ## stamina ratio under which the grip starts sliding
@export var slip_speed_max := 0.45  ## m/s at zero stamina

@export_group("Standing on moving surfaces")
@export var slide_max_speed := 9.0

@export_group("Health")
@export var health_regen := 4.0          ## per second
@export var health_regen_delay := 4.0    ## seconds after damage
@export var respawn_delay := 3.0

@export_group("Shake response")
## Surface acceleration (m/s^2) where the climber starts to feel the shake...
@export var shake_accel_min := 3.0
## ...and where it counts as full violence.
@export var shake_accel_max := 30.0

var player_index := 0
var actions := PlayerActions.new()
var stamina := Stamina.new()
var state := State.AIR
var grip: SurfaceAnchor
## Tangent direction that counts as "up" while climbing (parallel transported).
var climb_up := Vector3.UP
## World velocity of the gripped material point.
var surface_velocity := Vector3.ZERO
## Low-pass filtered acceleration of the gripped point.
var surface_accel := Vector3.ZERO
## 0..1 how violently the gripped surface is moving.
var shake_level := 0.0
## Horizontal facing on the ground.
var facing := Vector3.FORWARD
var spawn_transform := Transform3D.IDENTITY
var balance := Balance.new()
var fall := FallImpact.new()
var health := 100.0
## World angular velocity of the supporting / gripped segment (rad/s).
var surface_angular_velocity := Vector3.ZERO
## Impact speed and tier of the last landing (debug/tests).
var last_impact_speed := 0.0
var last_impact_tier := FallImpact.Tier.NONE
## Body is out of play (health 0) and waiting to respawn.
var dead := false
var visual: PlayerVisual
## Stats for debugging / tests.
var last_release_reason: StringName = &""

var _support: Object
var _regrab_timer := 0.0
var _grab_needs_release := false
var _prev_surface_velocity := Vector3.ZERO
var _grip_ticks := 0
var _last_normal := Vector3.UP
var _moving := false
var _exclude: Array[RID] = []
var _shape: CapsuleShape3D
var _support_local := Vector3.ZERO
var _support_normal := Vector3.UP
var _support_ticks := 0
var _slide_velocity := Vector3.ZERO
var _carry_body: BodySegment
var _carry_local := Vector3.ZERO
var _carry_basis := Basis.IDENTITY
var _climb_slipping := false
var _since_damage := 999.0
var _dead_time := 0.0


func _ready() -> void:
	add_to_group(&"players")
	collision_layer = Layers.PLAYER
	collision_mask = Layers.SOLID
	floor_max_angle = deg_to_rad(46.0)
	floor_snap_length = 0.3
	# Standing on colossi is handled by our own segment-local carry (_apply_carry).
	platform_floor_layers = 0
	platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_DO_NOTHING
	_shape = CapsuleShape3D.new()
	_shape.radius = 0.35
	_shape.height = 1.8
	var col := CollisionShape3D.new()
	col.shape = _shape
	add_child(col)
	visual = PlayerVisual.new()
	visual.name = "Visual"
	add_child(visual)
	_exclude = [get_rid()]
	spawn_transform = global_transform


func _physics_process(delta: float) -> void:
	var t0 := Perf.begin()
	_regrab_timer -= delta
	if not actions.grab_held:
		_grab_needs_release = false
	_update_health(delta)
	if state == State.CLIMB:
		_climb(delta)
	else:
		_locomotion(delta)
	visual.update_visual(self, delta)
	if global_position.y < -60.0:
		respawn()
	Perf.end(&"player", t0)


## Collision object the player is gripping or standing on (null in the air).
func get_support_body() -> Object:
	if state == State.CLIMB and grip:
		return grip.body
	return _support


func is_climbing() -> bool:
	return state == State.CLIMB


## Player-facing state name: GROUND / STAND / AIR / GRIP / CLIMB / SLIP / FALLEN / DEAD,
## plus "(unstable)" while balance is shaky.
func get_display_state() -> String:
	if dead:
		return "DEAD"
	match state:
		State.CLIMB:
			if _climb_slipping:
				return "SLIP"
			return "CLIMB" if _moving else "GRIP"
		State.AIR:
			return "AIR"
	match balance.state:
		Balance.State.FALLEN:
			return "FALLEN"
		Balance.State.STUMBLE:
			return "SLIP"
	var s := "STAND" if is_on_colossus() else "GROUND"
	if balance.state == Balance.State.UNSTABLE:
		s += " (unstable)"
	return s


func is_on_colossus() -> bool:
	return get_support_body() is BodySegment


func respawn() -> void:
	grip = null
	state = State.AIR
	dead = false
	velocity = Vector3.ZERO
	_slide_velocity = Vector3.ZERO
	_carry_body = null
	global_transform = spawn_transform
	stamina.refill()
	balance.reset()
	health = fall.max_health
	reset_physics_interpolation()


# --- ground / air ---------------------------------------------------------------------

func _locomotion(delta: float) -> void:
	var b := actions.view_basis
	var fwd := _flat_dir(-b.z, Vector3.FORWARD)
	var right := _flat_dir(b.x, Vector3.RIGHT)
	var wish := right * actions.move.x + fwd * actions.move.y
	if wish.length() > 1.0:
		wish = wish.normalized()
	if dead:
		wish = Vector3.ZERO
	var on_floor := is_on_floor()
	# Ride the body exactly (same idea as the grip anchor), before anything else moves us.
	_apply_carry(on_floor)

	# Feel the support: acceleration / rotation of the surface under the feet -> balance.
	if on_floor:
		_sense_support(delta)
		var rel_speed := (Vector3(velocity.x, 0.0, velocity.z) - _slide_velocity).length()
		balance.update(surface_accel, surface_angular_velocity, _support_normal, gravity, rel_speed / run_speed, delta)
	else:
		_support_ticks = 0
		surface_angular_velocity = Vector3.ZERO
		balance.recover(delta)

	# Own movement (scaled by balance) and involuntary sliding are tracked separately:
	# ``velocity`` (relative to the platform while on the floor) = own + slide.
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	if on_floor:
		var own := (hv - _slide_velocity).move_toward(wish * run_speed * balance.control(), ground_accel * delta)
		_update_slide(delta)
		hv = own + _slide_velocity
	else:
		_slide_velocity = Vector3.ZERO
		# Air control only steers; without input the momentum (e.g. inherited from the
		# colossus) is kept.
		if wish.length() > 0.1:
			hv = hv.move_toward(wish * run_speed, air_accel * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	velocity.y -= gravity * delta
	if actions.consume_jump() and on_floor and balance.control() > 0.5:
		velocity.y = jump_speed

	var was_airborne := not on_floor
	var pre_velocity := velocity
	var carried_velocity := _prev_surface_velocity if on_floor and _support is BodySegment else Vector3.ZERO
	move_and_slide()
	if wish.length() > 0.1 and balance.control() > 0.0:
		facing = facing.lerp(wish.normalized(), 1.0 - exp(-12.0 * delta)).normalized()
	_update_support()
	_record_carry()
	surface_velocity = _support_point_velocity(delta) if is_on_floor() else Vector3.ZERO
	state = State.GROUND if is_on_floor() else State.AIR
	if not was_airborne and state == State.AIR:
		# Leaving the body (walked/slid off, jumped, thrown): keep its velocity.
		velocity += carried_velocity
	if was_airborne and state == State.GROUND:
		var impact := -(pre_velocity - surface_velocity).dot(get_floor_normal())
		_on_landed(impact)
	if state == State.GROUND:
		stamina.regen(regen_rate, delta)
	else:
		stamina.tick_idle(delta)

	# Grab: normal grab, or a rescue grab while losing balance / falling (even if the
	# button has been held since a mantle).
	var falling := state == State.AIR and velocity.y < -rescue_fall_speed
	var rescue := falling or balance.state >= Balance.State.STUMBLE
	if actions.grab_held and (not _grab_needs_release or rescue) and _regrab_timer <= 0.0 and stamina.can_grip() and not dead:
		_try_grab(rescue)


## Moves the player with the supporting segment using a local anchor, so standing on a
## moving / rotating colossus has no drift. Godot's own platform carry is disabled
## (see _ready) because it is inexact for rotating kinematic bodies.
func _apply_carry(on_floor: bool) -> void:
	if not on_floor or not is_instance_valid(_carry_body):
		_carry_body = null
		return
	var xf := _carry_body.global_transform
	global_position = xf * _carry_local
	var rot := xf.basis * _carry_basis.inverse()
	facing = _flat_dir(rot * facing, facing)


func _record_carry() -> void:
	if _support is BodySegment:
		_carry_body = _support
		_carry_local = _carry_body.global_transform.affine_inverse() * global_position
		_carry_basis = _carry_body.global_basis
	else:
		_carry_body = null


func _support_point_velocity(delta: float) -> Vector3:
	if _support is BodySegment:
		return (_support as BodySegment).local_point_velocity(_support_local, delta)
	return Vector3.ZERO


## Measures the material point under the feet (velocity, filtered acceleration, rotation).
func _sense_support(delta: float) -> void:
	var seg := _support as BodySegment
	if seg == null:
		surface_accel = surface_accel.lerp(Vector3.ZERO, 1.0 - exp(-20.0 * delta))
		surface_angular_velocity = Vector3.ZERO
		_support_ticks = 0
		return
	var v := seg.local_point_velocity(_support_local, delta)
	if _support_ticks > 0:
		var a := (v - _prev_surface_velocity) / delta
		surface_accel = surface_accel.lerp(a, 1.0 - exp(-20.0 * delta))
	else:
		surface_accel = Vector3.ZERO
	_prev_surface_velocity = v
	surface_angular_velocity = seg.angular_velocity(delta)
	_support_ticks += 1


## Inertia relative to the surface, with Coulomb friction: the body only slides when
## (downhill gravity - surface acceleration) exceeds friction * normal load. A surface
## accelerating downwards unloads the feet; shaking on a slope therefore "walks" the
## body downhill, deterministically. Friction depends on the balance state.
func _update_slide(delta: float) -> void:
	var n := _support_normal
	var g := Vector3.DOWN * gravity
	var a_n := surface_accel.dot(n)
	var force := (g - n * g.dot(n)) - (surface_accel - n * a_n)
	force.y = 0.0
	var limit := balance.friction() * maxf(0.0, gravity * n.y + a_n)
	var speed := _slide_velocity.length()
	if speed < 0.05:
		if force.length() <= limit:
			_slide_velocity = Vector3.ZERO
			return
		_slide_velocity += force.normalized() * (force.length() - limit) * delta
	else:
		var dir := _slide_velocity / speed
		var next := _slide_velocity + (force - dir * limit) * delta
		# Kinetic friction stops the slide, it never reverses it.
		if next.dot(dir) < 0.0 and force.length() <= limit:
			next = Vector3.ZERO
		_slide_velocity = next
	_slide_velocity = _slide_velocity.limit_length(slide_max_speed)


func _on_landed(impact_speed: float) -> void:
	last_impact_speed = maxf(impact_speed, 0.0)
	last_impact_tier = fall.tier(last_impact_speed)
	var dmg := fall.damage(last_impact_speed)
	match last_impact_tier:
		FallImpact.Tier.HARD:
			balance.hit(0.6)
		FallImpact.Tier.SEVERE:
			balance.knock_down(1.6)
	if dmg > 0.0:
		_take_damage(dmg)
	landed.emit(last_impact_speed, last_impact_tier, dmg)


func _take_damage(amount: float) -> void:
	health = maxf(0.0, health - amount)
	_since_damage = 0.0
	if health <= 0.0 and not dead:
		dead = true
		_dead_time = 0.0
		balance.knock_down(respawn_delay)
		died.emit()


func _update_health(delta: float) -> void:
	_since_damage += delta
	if dead:
		_dead_time += delta
		if _dead_time >= respawn_delay:
			respawn()
		return
	if _since_damage > health_regen_delay:
		health = minf(fall.max_health, health + health_regen * delta)


func _update_support() -> void:
	var previous := _support
	_support = null
	if not is_on_floor():
		return
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if c.get_normal().dot(Vector3.UP) > 0.6:
			_set_support(c.get_collider(), c.get_normal(), c.get_position(), previous)
			return
	# Floor snapping can keep us on the floor without reporting a collision: confirm the
	# support with one short ray instead of losing it for a tick.
	var feet := global_position + Vector3.DOWN * (_shape.height * 0.5 - 0.1)
	var hit := ClimbQuery.ray(get_world_3d().direct_space_state, feet, feet + Vector3.DOWN * (floor_snap_length + 0.2), _exclude)
	if not hit.is_empty() and (hit.normal as Vector3).dot(Vector3.UP) > 0.6:
		_set_support(hit.collider, hit.normal, hit.position, previous)


func _set_support(collider: Object, nrm: Vector3, point: Vector3, previous: Object) -> void:
	_support = collider
	_support_normal = nrm
	if _support is BodySegment:
		_support_local = (_support as Node3D).global_transform.affine_inverse() * point
	if _support != previous:
		_support_ticks = 0


func _try_grab(rescue := false) -> void:
	var space := get_world_3d().direct_space_state
	# Search around the hands (above the head), so catching a surface mid-leap keeps the height.
	# Same height as where the hands end up when hanging, so a caught leap keeps its height.
	var anchor := ClimbQuery.find_grip(space, global_position + Vector3.UP * hand_reach, grab_radius, facing, _exclude)
	# Fur in front of the chest (e.g. a leg that slants away above the head). While
	# rescuing, the wider body search below already covers this region.
	if anchor == null and not rescue:
		anchor = ClimbQuery.find_grip(space, global_position + Vector3.UP * 0.3, grab_radius, facing, _exclude)
	# Rescue: anything within reach of the whole body (edge under the feet, limb passing by).
	if anchor == null and rescue:
		anchor = ClimbQuery.find_grip(space, global_position + Vector3.DOWN * 0.3, grab_radius + 0.35, facing, _exclude)
	if anchor:
		_attach(anchor)


func _attach(anchor: SurfaceAnchor) -> void:
	grip = anchor
	state = State.CLIMB
	_grip_ticks = 0
	var n := anchor.world_normal()
	_last_normal = n
	climb_up = Vector3.UP - n * n.y
	if climb_up.length() < 0.3:
		climb_up = facing - n * facing.dot(n)
	climb_up = _safe_normalized(climb_up, _any_perpendicular(n))
	surface_velocity = anchor.point_velocity(get_physics_process_delta_time())
	_prev_surface_velocity = surface_velocity
	surface_accel = Vector3.ZERO
	shake_level = 0.0
	velocity = Vector3.ZERO
	_slide_velocity = Vector3.ZERO
	# Holding on steadies you: balance is restored while gripping.
	balance.reset()
	_place_on_grip()
	reset_physics_interpolation()
	grabbed.emit(anchor)


# --- climbing -------------------------------------------------------------------------

func _climb(delta: float) -> void:
	if grip == null or not grip.is_valid():
		_release(&"invalid")
		return
	if not actions.grab_held:
		_release(&"let_go")
		return

	# 1) Motion of the gripped material point -> shake level.
	var v := grip.point_velocity(delta)
	if _grip_ticks > 0:
		var a := (v - _prev_surface_velocity) / delta
		surface_accel = surface_accel.lerp(a, 1.0 - exp(-20.0 * delta))
	_prev_surface_velocity = v
	surface_velocity = v
	_grip_ticks += 1
	shake_level = smoothstep(shake_accel_min, shake_accel_max, surface_accel.length())
	surface_angular_velocity = (grip.body as BodySegment).angular_velocity(delta) if grip.body is BodySegment else Vector3.ZERO

	var n := grip.world_normal()
	_update_climb_up(n)

	# 2) Leap off / along the surface.
	if actions.consume_jump():
		# With a direction: leap along the surface (caught again by holding grip).
		# Without: push away from the body.
		var move_dir := _climb_direction(actions.move, n)
		var push := n * 0.8 + Vector3.UP * 0.6
		if move_dir != Vector3.ZERO:
			push = move_dir + n * 0.1
		stamina.drain(jump_cost)
		_release(&"jump", push.normalized() * climb_jump_speed)
		return

	# 3) Crawl.
	_moving = actions.move.length() > 0.1
	if _moving:
		var dir := _climb_direction(actions.move, n)
		var speed := climb_speed * (1.0 - 0.75 * shake_level)
		if dir != Vector3.ZERO and not _crawl(dir, speed * delta):
			if dir.dot(Vector3.UP) > 0.5 and _try_mantle():
				return

	# 4) Slip when tired or on slippery patches.
	var slip := grip.slip_speed() + slip_speed_max * clampf(1.0 - stamina.ratio() / slip_below, 0.0, 1.0)
	_climb_slipping = slip > 0.0
	if slip > 0.0:
		n = grip.world_normal()
		var down := Vector3.DOWN - n * n.dot(Vector3.DOWN)
		if down.length() > 0.2:
			_crawl(down.normalized(), slip * delta)

	# 5) Stamina.
	var drain := drain_hang + (drain_climb if _moving else 0.0) + drain_shake * shake_level
	stamina.drain(drain * grip.grip_cost() * delta)
	if not stamina.can_grip():
		_release(&"exhausted")
		return

	_place_on_grip()


func _crawl(dir: Vector3, distance: float) -> bool:
	var next := ClimbQuery.crawl(get_world_3d().direct_space_state, grip, dir, distance, _exclude)
	if next == null:
		return false
	# Never teleport through thin gaps.
	if next.world_point().distance_to(grip.world_point()) > distance * 3.0 + 0.6:
		return false
	grip = next
	_update_climb_up(next.world_normal())
	return true


## Keeps "up" continuous while the surface normal changes (moving body, crawling around
## limbs, onto undersides) and snaps it towards world up on wall-like surfaces.
func _update_climb_up(n: Vector3) -> void:
	if not _last_normal.is_equal_approx(n) and _last_normal.dot(n) > -0.999:
		climb_up = Quaternion(_last_normal, n) * climb_up
	_last_normal = n
	climb_up -= n * climb_up.dot(n)
	var wall_up := Vector3.UP - n * n.y
	var wall_weight := clampf((wall_up.length() - 0.3) / 0.4, 0.0, 1.0)
	climb_up = _safe_normalized(climb_up, _any_perpendicular(n))
	if wall_weight > 0.0:
		climb_up = climb_up.lerp(wall_up.normalized(), wall_weight).normalized()


## Move input -> world tangent direction. On walls "forward" means up; on top
## surfaces input is camera relative.
func _climb_direction(move: Vector2, n: Vector3) -> Vector3:
	if move.length() < 0.1:
		return Vector3.ZERO
	var right := climb_up.cross(n)
	var wall_dir := right * move.x + climb_up * move.y
	var cb := actions.view_basis
	var cam_dir := cb.x * move.x - cb.z * move.y
	cam_dir -= n * cam_dir.dot(n)
	# Camera-relative only on top surfaces; on walls and undersides the transported
	# climb frame keeps "forward" meaning "keep going the way you were climbing".
	var w := smoothstep(0.55, 0.85, n.y)
	var d := wall_dir.lerp(_safe_normalized(cam_dir, wall_dir) * wall_dir.length(), w)
	d -= n * d.dot(n)
	return _safe_normalized(d, Vector3.ZERO)


## Pull up onto a walkable surface above the hands (top of a shoulder, a ledge).
func _try_mantle() -> bool:
	var space := get_world_3d().direct_space_state
	var p := grip.query_point()
	var n := grip.query_normal()
	var over := p - n * 0.8
	var hit := ClimbQuery.ray(space, over + Vector3.UP * 2.2, over - Vector3.UP * 0.2, _exclude)
	if hit.is_empty() or hit.normal.dot(Vector3.UP) < 0.7:
		return false
	var stand := (hit.position as Vector3) + Vector3.UP * (_shape.height * 0.5 + 0.05)
	if _overlaps(stand):
		# Something stands right there (a neck, a head): look for room along the edge.
		var along := n.cross(Vector3.UP)
		along.y = 0.0
		along = along.normalized() if along.length() > 0.01 else Vector3.RIGHT
		var found := false
		for off in [0.4, -0.4, 0.8, -0.8]:
			var c: Vector3 = stand + along * off
			var h2 := ClimbQuery.ray(space, Vector3(c.x, stand.y + 1.5, c.z), Vector3(c.x, stand.y - 1.5, c.z), _exclude)
			if h2.is_empty() or h2.normal.dot(Vector3.UP) < 0.7:
				continue
			c = (h2.position as Vector3) + Vector3.UP * (_shape.height * 0.5 + 0.05)
			if not _overlaps(c):
				stand = c
				found = true
				break
		if not found:
			return false
	var carried := surface_velocity
	grip = null
	_climb_slipping = false
	state = State.AIR
	shake_level = 0.0
	global_position = stand
	velocity = carried
	facing = _flat_dir(-n, facing)
	_grab_needs_release = true
	_regrab_timer = regrab_delay
	stamina.tick_idle(0.0)
	reset_physics_interpolation()
	mantled.emit()
	return true


func _place_on_grip() -> void:
	var n := grip.world_normal()
	global_position = grip.world_point() + n * hang_distance - climb_up * hand_reach
	velocity = surface_velocity


func _release(reason: StringName, impulse := Vector3.ZERO) -> void:
	var n := Vector3.ZERO
	if grip and grip.is_valid():
		n = grip.world_normal()
	grip = null
	_climb_slipping = false
	state = State.AIR
	shake_level = 0.0
	velocity = surface_velocity + impulse
	_regrab_timer = regrab_delay
	last_release_reason = reason
	if n != Vector3.ZERO:
		facing = _flat_dir(-n, facing)
		_move_clear_of_surface(n)
	grip_released.emit(reason)


## After letting go the upright capsule may intersect the body (e.g. hanging under an arm).
func _move_clear_of_surface(n: Vector3) -> void:
	var candidates := [Vector3.ZERO, n * 0.3, n * 0.6 + Vector3.DOWN * 0.5, Vector3.DOWN * 1.0 + n * 0.3, n * 1.0]
	for offset in candidates:
		if not _overlaps(global_position + offset):
			global_position += offset
			return


func _overlaps(center: Vector3) -> bool:
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _shape
	params.transform = Transform3D(Basis.IDENTITY, center)
	params.collision_mask = Layers.SOLID
	params.exclude = _exclude
	return not get_world_3d().direct_space_state.intersect_shape(params, 1).is_empty()


static func _flat_dir(v: Vector3, fallback: Vector3) -> Vector3:
	v.y = 0.0
	return v.normalized() if v.length() > 0.001 else fallback


static func _safe_normalized(v: Vector3, fallback: Vector3) -> Vector3:
	return v.normalized() if v.length() > 0.001 else fallback


static func _any_perpendicular(n: Vector3) -> Vector3:
	var ref := Vector3.FORWARD if absf(n.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	return (ref - n * ref.dot(n)).normalized()
