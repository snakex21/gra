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

@export_group("Stamina")
@export var drain_hang := 3.0       ## per second, just holding on
@export var drain_climb := 5.0      ## extra per second while moving
@export var drain_shake := 24.0     ## extra per second at full shake level
@export var jump_cost := 12.0
@export var regen_rate := 35.0      ## per second standing on solid ground (or a colossus' back)
@export var slip_below := 0.25      ## stamina ratio under which the grip starts sliding
@export var slip_speed_max := 0.45  ## m/s at zero stamina

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


func _ready() -> void:
	add_to_group(&"players")
	collision_layer = Layers.PLAYER
	collision_mask = Layers.SOLID
	floor_max_angle = deg_to_rad(46.0)
	floor_snap_length = 0.3
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
	_regrab_timer -= delta
	if not actions.grab_held:
		_grab_needs_release = false
	if state == State.CLIMB:
		_climb(delta)
	else:
		_locomotion(delta)
	visual.update_visual(self, delta)
	if global_position.y < -60.0:
		respawn()


## Collision object the player is gripping or standing on (null in the air).
func get_support_body() -> Object:
	if state == State.CLIMB and grip:
		return grip.body
	return _support


func is_climbing() -> bool:
	return state == State.CLIMB


func respawn() -> void:
	grip = null
	state = State.AIR
	velocity = Vector3.ZERO
	global_transform = spawn_transform
	stamina.refill()
	reset_physics_interpolation()


# --- ground / air ---------------------------------------------------------------------

func _locomotion(delta: float) -> void:
	var b := actions.view_basis
	var fwd := _flat_dir(-b.z, Vector3.FORWARD)
	var right := _flat_dir(b.x, Vector3.RIGHT)
	var wish := right * actions.move.x + fwd * actions.move.y
	if wish.length() > 1.0:
		wish = wish.normalized()
	var on_floor := is_on_floor()
	var hv := Vector3(velocity.x, 0.0, velocity.z).move_toward(wish * run_speed, (ground_accel if on_floor else air_accel) * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	velocity.y -= gravity * delta
	if actions.consume_jump() and on_floor:
		velocity.y = jump_speed
	move_and_slide()
	if wish.length() > 0.1:
		facing = facing.lerp(wish.normalized(), 1.0 - exp(-12.0 * delta)).normalized()
	_update_support()
	surface_velocity = get_platform_velocity() if is_on_floor() else Vector3.ZERO
	state = State.GROUND if is_on_floor() else State.AIR
	if state == State.GROUND:
		stamina.regen(regen_rate, delta)
	else:
		stamina.tick_idle(delta)
	if actions.grab_held and not _grab_needs_release and _regrab_timer <= 0.0 and stamina.can_grip():
		_try_grab()


func _update_support() -> void:
	_support = null
	if not is_on_floor():
		return
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if c.get_normal().dot(Vector3.UP) > 0.6:
			_support = c.get_collider()
			return


func _try_grab() -> void:
	# Search around the hands (above the head), so catching a surface mid-leap keeps the height.
	var hands := global_position + Vector3.UP * 0.7
	var anchor := ClimbQuery.find_grip(get_world_3d().direct_space_state, hands, grab_radius, facing, _exclude)
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

	var n := grip.world_normal()
	_update_climb_up(n)

	# 2) Leap off / along the surface.
	if actions.consume_jump():
		# With a direction: leap along the surface (caught again by holding grip).
		# Without: push away from the body.
		var move_dir := _climb_direction(actions.move, n)
		var push := n * 0.8 + Vector3.UP * 0.6
		if move_dir != Vector3.ZERO:
			push = move_dir + n * 0.25
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
		return false
	var carried := surface_velocity
	grip = null
	state = State.AIR
	shake_level = 0.0
	global_position = stand
	velocity = carried
	facing = _flat_dir(-n, facing)
	_grab_needs_release = true
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
