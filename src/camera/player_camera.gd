class_name PlayerCamera
extends Camera3D
## Third-person orbit camera for one player.
##
## Principles:
##  - The player owns yaw/pitch. Nothing here ever rotates the camera on its own,
##    except while the player HOLDS focus (frame the colossus). Assistance only moves
##    the orbit pivot and the distance.
##  - Distance depends on the situation (ground / near a colossus / standing on it /
##    climbing / focusing) and changes smoothly, so the scale of the colossus reads.
##  - While climbing the pivot leads slightly ahead along the climb direction and out of
##    the surface, so the route above (and the segment you are on) stays in view.
##  - Obstacles:
##      world geometry           -> pull in quickly, ease back out slowly;
##      colossus blocking view   -> after a short grace period, soft pull-in
##                                  (a limb swinging past does not make the camera pump);
##      camera inside a colossus -> hard clamp, immediately. Never inside the body.

@export var distance_ground := 5.0
@export var distance_near_colossus := 6.5
@export var distance_on_colossus := 7.0
@export var distance_climb := 7.0
@export var distance_riding := 5.5
@export var distance_focus_extra := 4.0
## Within this horizontal distance of a colossus the "near colossus" framing is used.
@export var near_colossus_range := 45.0
@export var pivot_height := 0.6
@export var climb_lookahead := 1.2
@export var climb_surface_offset := 0.6
@export var min_pitch := -1.3
@export var max_pitch := 0.95
## Highest boom elevation below the pivot; looking further up only rotates the view.
@export var max_boom_pitch := 0.3
## While focusing, how much the aim is pulled from the colossus towards the player.
@export var focus_player_weight := 0.45
## Probe radius for the pivot and the boom. Must cover the near-plane footprint
## (near 0.08, fov 70, 16:9 -> ~0.115 m). Kept small on purpose: the pivot sits right next
## to the player's body, and Godot's cast_motion ignores overlaps at the start of a cast,
## so the start must be guaranteed free (the pivot is cast out from the body with it).
@export var collision_radius := 0.15
@export var pivot_radius := 0.15
@export var min_distance := 0.4
@export var focus_turn_rate := 4.0
@export_group("Bow")
## Drawing the bow: the camera comes in over the right shoulder and narrows the view.
@export var distance_aim := 3.0
@export var aim_shoulder := 0.75
@export var aim_fov := 52.0
@export var base_fov := 70.0
## Seconds the colossus must keep blocking the view before the camera moves in.
@export var occlusion_grace := 0.35

var player: PlayerCharacter
## Anything with get_focus_point() (a colossus); may be null.
var focus_target: Node

var yaw := 0.0
var pitch := -0.3
## Debug/tests: why the distance is what it is this frame.
var debug_state := ""
var last_clamp := ""

var _pivot := Vector3.ZERO
var _distance := 5.0
var _want_distance := 5.0
var _lookahead := Vector3.ZERO
var _occluded_time := 0.0
var _boom_cap := 0.3
var _initialised := false
var _sphere := SphereShape3D.new()
var _params := PhysicsShapeQueryParameters3D.new()
var _exclude: Array[RID] = []
## 0..1 blend into the over-the-shoulder aiming view.
var aim_weight := 0.0


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	process_priority = 10
	near = 0.08
	far = 4000.0
	fov = 70.0
	_params.shape = _sphere
	var water_view := WaterCameraEffects.new()
	water_view.name = "WaterCameraEffects"
	water_view.camera = self
	water_view.player = player
	add_child(water_view)


func _process(delta: float) -> void:
	if player == null:
		return
	var t0 := Perf.begin()
	_update(delta)
	Perf.end(&"camera", t0)


func _update(delta: float) -> void:
	var a := player.actions
	yaw -= a.look_delta.x
	pitch -= a.look_delta.y
	a.look_delta = Vector2.ZERO

	# --- pivot: the player, led slightly along the climb route --------------------------
	var climbing := player.is_climbing()
	var body := player.get_global_transform_interpolated().origin
	var target_pivot := body + Vector3.UP * pivot_height
	var lead := Vector3.ZERO
	if climbing and player.grip:
		var moving := a.move.length() > 0.1
		lead = player.climb_up * climb_lookahead * (1.0 if moving else 0.5) + player.grip.world_normal() * climb_surface_offset
	_lookahead = _lookahead.lerp(lead, 1.0 - exp(-3.0 * delta))
	target_pivot += _lookahead
	# Drawing the bow: over the right shoulder (the crosshair stays the view's centre).
	aim_weight = move_toward(aim_weight, 1.0 if player.bow.is_aiming() else 0.0, delta / 0.25)
	if aim_weight > 0.0:
		var right := Basis.from_euler(Vector3(0.0, yaw, 0.0)).x
		target_pivot += (right * aim_shoulder + Vector3.UP * 0.15) * _smooth_w(aim_weight)
	# The pivot itself must stay in free space (look-ahead can point under an overhang).
	var space := get_world_3d().direct_space_state
	# The horse being ridden is part of "us" for the camera; other horses are obstacles.
	var ridden := player.riding.horse if player.is_riding() and is_instance_valid(player.riding.horse) else null
	if _exclude.is_empty() or (ridden != null) != (_exclude.size() > 1):
		_exclude = [player.get_rid()]
		if ridden:
			_exclude.append(ridden.get_rid())
	var origin := _free_origin(space, body)
	var to_pivot := target_pivot - origin
	if to_pivot.length() > 0.01:
		target_pivot = origin + to_pivot * (_cast(space, origin, to_pivot.normalized(), to_pivot.length(), Layers.SOLID, pivot_radius) / to_pivot.length())
	else:
		target_pivot = origin
	if not _initialised:
		_pivot = target_pivot
		_distance = distance_ground
		_want_distance = distance_ground
		_initialised = true
	# Softer follow while the body under the player shakes: the view stays calm.
	var stiffness := lerpf(20.0, 7.0, player.shake_level) if climbing else lerpf(25.0, 10.0, 1.0 - player.balance.value)
	_pivot = _pivot.lerp(target_pivot, 1.0 - exp(-stiffness * delta))
	# Smoothing can drag the pivot through a moving limb: never let it rest inside one.
	if _inside(space, _pivot, Layers.COLOSSUS, pivot_radius):
		_pivot = target_pivot

	# --- situational distance -------------------------------------------------------------
	var want := distance_ground
	debug_state = "ground"
	if player.is_riding():
		var v: float = player.riding.horse.get_speed() if is_instance_valid(player.riding.horse) else 0.0
		want = distance_riding + v * 0.15
		debug_state = "riding"
	elif climbing:
		want = distance_climb
		debug_state = "climb"
	elif player.is_on_colossus():
		want = distance_on_colossus
		debug_state = "on colossus"
	elif _near_colossus():
		want = distance_near_colossus
		debug_state = "near colossus"
	if a.focus_held and is_instance_valid(focus_target):
		want += distance_focus_extra
		debug_state += " + focus"
		var focus_point: Vector3 = focus_target.get_focus_point()
		var dir := focus_point - _pivot
		if dir.length() > 0.5:
			var t := 1.0 - exp(-focus_turn_rate * delta)
			yaw = lerp_angle(yaw, atan2(-dir.x, -dir.z), t)
			# Aim between the player and the colossus so both stay in frame.
			var aim := focus_point.lerp(_pivot, focus_player_weight) - global_position
			pitch = lerpf(pitch, atan2(aim.y, Vector2(aim.x, aim.z).length()), t)
	if aim_weight > 0.0:
		want = lerpf(want, distance_aim, _smooth_w(aim_weight))
		debug_state += " + aim"
	fov = lerpf(base_fov, aim_fov, _smooth_w(aim_weight))
	pitch = clampf(pitch, min_pitch, max_pitch)
	_want_distance = lerpf(_want_distance, want, 1.0 - exp(-(1.5 + 6.0 * aim_weight) * delta))

	# --- obstacles ------------------------------------------------------------------------
	# Looking up (at a colossus above) tilts the camera but does not swing the boom
	# under the player into the ground: the boom pitch is capped, the view is not.
	var b := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	_boom_cap = lerpf(_boom_cap, 0.0 if a.focus_held else max_boom_pitch, 1.0 - exp(-3.0 * delta))
	var back := Basis.from_euler(Vector3(minf(pitch, _boom_cap), yaw, 0.0)).z
	last_clamp = ""
	var allowed := _cast(space, _pivot, back, _want_distance, Layers.WORLD)
	if allowed < _want_distance - 0.01:
		last_clamp = "world"
	var colossus_free := _cast(space, _pivot, back, allowed, Layers.COLOSSUS)
	if colossus_free < allowed - 0.01:
		_occluded_time += delta
		if _occluded_time > occlusion_grace:
			allowed = colossus_free
			last_clamp = "colossus (occluded)"
	else:
		_occluded_time = 0.0

	if allowed < _distance:
		_distance = lerpf(_distance, allowed, 1.0 - exp(-12.0 * delta))
	else:
		_distance = lerpf(_distance, allowed, 1.0 - exp(-2.0 * delta))

	# Hard guarantees, after smoothing: never inside world geometry or a colossus.
	var hard_world := _cast(space, _pivot, back, _distance, Layers.WORLD)
	if hard_world < _distance:
		_distance = hard_world
	if _inside(space, _pivot + back * _distance, Layers.COLOSSUS):
		_distance = _cast(space, _pivot, back, _distance, Layers.COLOSSUS)
		last_clamp = "colossus (inside)"
	# Prefer a minimum boom length, but only where it is actually free; otherwise sit on
	# the pivot (which is guaranteed free) rather than inside the body.
	if _distance < min_distance:
		_distance = min_distance if not _inside(space, _pivot + back * min_distance, Layers.SOLID) else _distance
	global_transform = Transform3D(b, _pivot + back * _distance)


static func _smooth_w(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


## A point next to the player that is guaranteed to be in free space, used as the start
## of the pivot cast. While climbing, the player's body is not collided against other
## segments (only the hands are anchored), so the hands pushed out along the surface
## normal are tried first; then the body; then pushing out along the normal.
func _free_origin(space: PhysicsDirectSpaceState3D, body: Vector3) -> Vector3:
	var candidates: Array[Vector3] = []
	var out := Vector3.UP
	if player.is_climbing() and player.grip:
		out = player.grip.world_normal()
		candidates.append(player.grip.world_point() + out * (pivot_radius + 0.3))
	candidates.append(body)
	for c in candidates:
		if not _inside(space, c, Layers.SOLID, pivot_radius):
			return c
	for i in range(1, 8):
		var c := candidates[0] + out * 0.25 * i
		if not _inside(space, c, Layers.SOLID, pivot_radius):
			return c
	return candidates[0]


func snap_behind_player() -> void:
	if player:
		var f := player.facing
		yaw = atan2(-f.x, -f.z)
	_initialised = false


func get_distance() -> float:
	return _distance


func _near_colossus() -> bool:
	if not is_instance_valid(focus_target):
		return false
	var d: Vector3 = (focus_target as Node3D).global_position - player.global_position
	d.y = 0.0
	return d.length() < near_colossus_range


func _cast(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, length: float, mask: int, radius := -1.0) -> float:
	if length <= 0.0:
		return 0.0
	_sphere.radius = collision_radius if radius < 0.0 else radius
	_params.transform = Transform3D(Basis.IDENTITY, from)
	_params.motion = dir * length
	_params.collision_mask = mask
	_params.exclude = _exclude
	Perf.count(&"camera_queries")
	var r := space.cast_motion(_params)
	return r[0] * length


func _inside(space: PhysicsDirectSpaceState3D, p: Vector3, mask: int, radius := -1.0) -> bool:
	_sphere.radius = collision_radius if radius < 0.0 else radius
	_params.transform = Transform3D(Basis.IDENTITY, p)
	_params.motion = Vector3.ZERO
	_params.collision_mask = mask
	_params.exclude = _exclude
	Perf.count(&"camera_queries")
	return not space.intersect_shape(_params, 1).is_empty()
