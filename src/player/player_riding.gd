class_name PlayerRiding
extends RefCounted
## Mounting, riding and dismounting for one PlayerCharacter.
##
##   ON_FOOT (near a free horse = "approach") -> MOUNTING -> RIDING -> DISMOUNTING -> ON_FOOT
##
## While riding, the player is anchored to the horse's body bone (the saddle), exactly like
## a climbing grip is anchored to a colossus bone: the position is derived from the bone
## every tick, so there is no drift. Mount and dismount are short arcs computed in the
## horse's frames each tick (they move with the horse: no teleports).
## The rider turns PlayerActions into a device-independent HorseInputIntent.

enum Phase { NONE, MOUNTING, RIDING, DISMOUNTING }

## Shared seated frame correction: render pelvis and physical bow muzzle agree.
const SEATED_VISUAL_OFFSET := -0.28

const MOUNT_RANGE := 2.8
const MOUNT_TIME := 0.6
const DISMOUNT_TIME := 0.65
## Dismount spots in the horse's root frame: left, right, behind, in front.
const DISMOUNT_SPOTS := [Vector3(-1.15, 0, 0), Vector3(1.15, 0, 0), Vector3(0, 0, 2.0), Vector3(0, 0, -2.0)]

var player: PlayerCharacter
var horse: Horse
var phase := Phase.NONE
## Steering relative to the horse instead of the camera (looking away while riding,
## later: aiming the bow). Toggled by the player / settings.
var steer_relative := false
var last_refusal := ""

var _t := 0.0
var _from_local := Vector3.ZERO    # mount start, in the horse body's frame
var _to_local := Vector3.ZERO      # dismount spot, in the horse root frame
var _saved_layer := 0
var _saved_mask := 0


func _init(p_player: PlayerCharacter) -> void:
	player = p_player


## Render-only contact weight. Never changes the collision root or mount arc.
func cosmetic_seat_weight() -> float:
	match phase:
		Phase.RIDING: return 1.0
		Phase.MOUNTING: return smoothstep(0.25, 1.0, _t)
		Phase.DISMOUNTING: return 1.0 - smoothstep(0.0, 0.75, _t)
	return 0.0


func is_active() -> bool:
	return phase != Phase.NONE


## A free horse close enough to mount (null if none).
func horse_in_reach() -> Horse:
	var best: Horse = null
	var best_d := MOUNT_RANGE
	for h in player.get_tree().get_nodes_in_group(&"horses"):
		var horse_node := h as Horse
		if is_instance_valid(horse_node.current_rider):
			continue
		var d := (horse_node.saddle_transform().origin - player.global_position)
		d.y *= 0.5
		if d.length() < best_d:
			best_d = d.length()
			best = horse_node
	return best


func try_mount() -> bool:
	var h := horse_in_reach()
	if h == null:
		return false
	horse = h
	h.set_rider(player)
	phase = Phase.MOUNTING
	_t = 0.0
	_from_local = h.body_transform().affine_inverse() * player.global_position
	_saved_layer = player.collision_layer
	_saved_mask = player.collision_mask
	player.collision_layer = 0
	player.collision_mask = 0
	player.velocity = Vector3.ZERO
	return true


## Already in the saddle of ``h`` (arriving in a new region on horseback): no mount arc.
func mount_now(h: Horse) -> void:
	horse = h
	h.set_rider(player)
	phase = Phase.RIDING
	_t = 1.0
	_saved_layer = player.collision_layer
	_saved_mask = player.collision_mask
	player.collision_layer = 0
	player.collision_mask = 0
	player.state = PlayerCharacter.State.RIDE
	player.global_position = h.saddle_transform().origin
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()


func try_dismount() -> bool:
	if phase != Phase.RIDING:
		return false
	var spot: Variant = _find_dismount_spot()
	if spot == null:
		last_refusal = "no safe place to get off"
		return false
	_to_local = spot
	phase = Phase.DISMOUNTING
	_t = 0.0
	horse.set_rider(null)
	horse.command_stop()
	return true


## Per physics tick while active (the horse has already moved this tick).
func update(delta: float) -> void:
	if not is_instance_valid(horse):
		_finish(Vector3.ZERO)
		return
	var t0 := Perf.begin()
	var saddle := horse.saddle_transform()
	match phase:
		Phase.MOUNTING:
			_t = minf(1.0, _t + delta / MOUNT_TIME)
			var s := _t * _t * (3.0 - 2.0 * _t)
			var body := horse.body_transform()
			var seat_local := body.affine_inverse() * saddle.origin
			var local := _from_local.lerp(seat_local, s) + Vector3.UP * 0.5 * sin(PI * s)
			player.global_position = body * local
			if _t >= 1.0:
				phase = Phase.RIDING
		Phase.RIDING:
			player.global_position = saddle.origin
		Phase.DISMOUNTING:
			_t = minf(1.0, _t + delta / DISMOUNT_TIME)
			var s := _t * _t * (3.0 - 2.0 * _t)
			var target := horse.global_transform * _to_local
			player.global_position = saddle.origin.lerp(target, s) + Vector3.UP * 0.4 * sin(PI * s)
			if _t >= 1.0:
				_finish(horse.controller.forward() * horse.controller.speed * 0.5)
				Perf.end(&"mount", t0)
				return
	player.velocity = horse.controller.forward() * horse.controller.speed
	player.facing = horse.controller.forward()
	player.surface_velocity = player.velocity
	Perf.end(&"mount", t0)


## Device-independent ride intent from this player's actions (called by the horse).
func build_ride_intent(intent: HorseInputIntent) -> void:
	if phase != Phase.RIDING:
		return
	var a := player.actions
	var mv := a.move
	# Aiming the bow: the camera looks wherever the arrow goes, so steering is relative
	# to the horse (the stick turns and drives it); without input it keeps its heading.
	if steer_relative or player.bow.is_aiming():
		intent.turn = mv.x
		intent.drive = maxf(mv.y, 0.0)
		intent.rein = mv.y < -0.6
	elif mv.length() > 0.2:
		# Stick relative to the camera: "roughly that way". Without input the horse keeps
		# its own heading, wherever the camera looks.
		var b := a.view_basis
		var fwd := Vector3(-b.z.x, 0.0, -b.z.z).normalized()
		var right := Vector3(b.x.x, 0.0, b.x.z).normalized()
		intent.direction = (right * mv.x + fwd * mv.y).normalized()
		intent.drive = minf(mv.length(), 1.0)
	intent.gait_up = a.consume_jump()          # kick
	intent.rein = intent.rein or a.grab_held   # pull the reins


func display_state() -> String:
	match phase:
		Phase.MOUNTING:
			return "MOUNT"
		Phase.RIDING:
			return "RIDE"
		Phase.DISMOUNTING:
			return "DISMOUNT"
	return ""


func _finish(inherit_velocity: Vector3) -> void:
	phase = Phase.NONE
	player.collision_layer = _saved_layer if _saved_layer != 0 else Layers.PLAYER
	player.collision_mask = _saved_mask if _saved_mask != 0 else Layers.SOLID
	player.velocity = inherit_velocity
	player.end_riding()
	if is_instance_valid(horse) and horse.current_rider == player:
		horse.set_rider(null)
	horse = null


## A free, walkable spot next to the horse (in its root frame), or null.
func _find_dismount_spot() -> Variant:
	var space := player.get_world_3d().direct_space_state
	var params := PhysicsShapeQueryParameters3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.8
	params.shape = shape
	params.collision_mask = Layers.SOLID
	params.exclude = [player.get_rid(), horse.get_rid()]
	for local in DISMOUNT_SPOTS:
		var w: Vector3 = horse.global_transform * (local as Vector3)
		var hit := ClimbQuery.ray(space, w + Vector3.UP * 2.0, w + Vector3.DOWN * 3.0, [player.get_rid(), horse.get_rid()], Layers.WORLD | Layers.COLOSSUS)
		if hit.is_empty():
			continue
		var ground: Vector3 = hit.position
		if absf(ground.y - horse.global_position.y) > 1.2 or (hit.normal as Vector3).y < 0.7:
			continue
		var center := ground + Vector3.UP * 0.95
		params.transform = Transform3D(Basis.IDENTITY, center)
		if space.intersect_shape(params, 1).is_empty():
			return horse.global_transform.affine_inverse() * center
	return null
