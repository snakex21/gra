class_name PlayerCamera
extends Camera3D
## Third-person orbit camera for one player.
##
## Rules: the player always owns yaw/pitch (no automatic re-centering fighting the stick);
## assistance is opt-in (hold focus to frame the colossus). Obstacles:
##  - world geometry pulls the camera in (fast in, slow out);
##  - colossus limbs only pull it in when the camera would end up *inside* them, so a
##    swinging arm crossing the line of sight does not make the camera pump in and out.
## While climbing on a shaking body the pivot is softened so the view does not jitter.

@export var distance_ground := 5.0
@export var distance_climb := 6.5
@export var distance_focus_extra := 3.0
@export var pivot_height := 0.6
@export var min_pitch := -1.3
@export var max_pitch := 0.95
@export var collision_radius := 0.3
@export var focus_turn_rate := 4.0

var player: PlayerCharacter
## Anything with get_focus_point() (a colossus); may be null.
var focus_target: Node

var yaw := 0.0
var pitch := -0.3
var _pivot := Vector3.ZERO
var _distance := 5.0
var _initialised := false


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	process_priority = 10
	near = 0.1
	far = 4000.0
	fov = 70.0


func _process(delta: float) -> void:
	if player == null:
		return
	var a := player.actions
	yaw -= a.look_delta.x
	pitch -= a.look_delta.y
	a.look_delta = Vector2.ZERO

	var climbing := player.is_climbing()
	var target_pivot := player.get_global_transform_interpolated().origin + Vector3.UP * pivot_height
	if not _initialised:
		_pivot = target_pivot
		_initialised = true
	var stiffness := lerpf(20.0, 7.0, player.shake_level) if climbing else 25.0
	_pivot = _pivot.lerp(target_pivot, 1.0 - exp(-stiffness * delta))

	var want := distance_climb if climbing else distance_ground
	if a.focus_held and is_instance_valid(focus_target):
		want += distance_focus_extra
		var dir: Vector3 = focus_target.get_focus_point() - _pivot
		if dir.length() > 0.5:
			var t := 1.0 - exp(-focus_turn_rate * delta)
			yaw = lerp_angle(yaw, atan2(-dir.x, -dir.z), t)
			pitch = lerpf(pitch, atan2(dir.y, Vector2(dir.x, dir.z).length()), t)
	pitch = clampf(pitch, min_pitch, max_pitch)

	var b := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var back := b.z
	var allowed := _resolve_obstacles(_pivot, back, want)
	if allowed < _distance:
		_distance = lerpf(_distance, allowed, 1.0 - exp(-30.0 * delta))
	else:
		_distance = lerpf(_distance, allowed, 1.0 - exp(-2.5 * delta))
	global_transform = Transform3D(b, _pivot + back * _distance)


func snap_behind_player() -> void:
	if player:
		var f := player.facing
		yaw = atan2(-f.x, -f.z)
	_initialised = false


func _resolve_obstacles(pivot: Vector3, back: Vector3, want: float) -> float:
	var space := get_world_3d().direct_space_state
	var d := _cast(space, pivot, back, want, Layers.WORLD)
	if _inside(space, pivot + back * d, Layers.COLOSSUS):
		d = _cast(space, pivot, back, want, Layers.SOLID)
	return maxf(d, 0.4)


func _cast(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, length: float, mask: int) -> float:
	var sphere := SphereShape3D.new()
	sphere.radius = collision_radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	params.transform = Transform3D(Basis.IDENTITY, from)
	params.motion = dir * length
	params.collision_mask = mask
	params.exclude = [player.get_rid()]
	var r := space.cast_motion(params)
	return r[0] * length


func _inside(space: PhysicsDirectSpaceState3D, p: Vector3, mask: int) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = collision_radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	params.transform = Transform3D(Basis.IDENTITY, p)
	params.collision_mask = mask
	return not space.intersect_shape(params, 1).is_empty()
