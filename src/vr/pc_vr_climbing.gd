class_name PcVrClimbing
extends RefCounted
## Two tracked hands constrain the origin to material points on real ClimbPatch
## colliders. Only actual capsule displacement moves the camera/origin.
const PRESS := 0.65
const RELEASE := 0.35
const REACH := 0.18
const MAX_ERROR := 0.6
const MAX_SPEED := 2.5

var origin: XROrigin3D
var body: CharacterBody3D
var controllers: Array[XRController3D] = []
var anchors: Array[SurfaceAnchor] = [null, null]
var stamina := 100.0
var displacement := Vector3.ZERO
var _armed := [false, false]
var _contact_local := [Vector3.ZERO, Vector3.ZERO]


func setup(p_origin: XROrigin3D, p_body: CharacterBody3D, left: XRController3D, right: XRController3D) -> void:
	origin = p_origin
	body = p_body
	controllers = [left, right]


func is_climbing() -> bool:
	return anchors[0] != null or anchors[1] != null


func release_all() -> void:
	anchors = [null, null]
	_armed = [false, false]
	displacement = Vector3.ZERO


func step(delta: float, frame: Dictionary, head: XRCamera3D) -> bool:
	displacement = Vector3.ZERO
	var active := 0
	var correction := Vector3.ZERO
	for i in 2:
		var tracked: bool = frame.left_tracked if i == 0 else frame.right_tracked
		var strength: float = frame.left_grip if i == 0 else frame.right_grip
		var hand := controllers[i]
		if not tracked or not hand.global_transform.is_finite() or hand.global_position.distance_to(head.global_position) > 1.5:
			anchors[i] = null
			_armed[i] = false
			continue
		if strength <= RELEASE:
			anchors[i] = null
			_armed[i] = true
		if anchors[i] != null and not anchors[i].is_valid():
			anchors[i] = null
			_armed[i] = false
		if anchors[i] == null and strength >= PRESS and _armed[i]:
			_armed[i] = false
			if stamina > 1.0:
				var exclude: Array[RID] = [body.get_rid()]
				var anchor := ClimbQuery.find_grip(body.get_world_3d().direct_space_state, hand.global_position, REACH, -hand.global_basis.z, exclude)
				if anchor != null and anchor.world_point().distance_to(hand.global_position) <= REACH + .001:
					# Do not grab through another solid object between palm and fur.
					var ray := PhysicsRayQueryParameters3D.create(hand.global_position, anchor.query_point() - anchor.query_normal() * .04, Layers.SOLID)
					ray.exclude = exclude
					ray.hit_from_inside = true
					var hit := body.get_world_3d().direct_space_state.intersect_ray(ray)
					if not hit.is_empty() and hit.collider == anchor.body and ClimbQuery.patch_from_hit(hit) == anchor.shape:
						anchors[i] = anchor
						# Preserve the visual skin/collider gap; acquisition never jerks
						# the head to make a palm coincide with the collision surface.
						_contact_local[i] = anchor.body.global_transform.affine_inverse() * hand.global_position
		if anchors[i] != null:
			var error: Vector3 = anchors[i].body.global_transform * _contact_local[i] - hand.global_position
			if not error.is_finite() or error.length() > MAX_ERROR:
				# A jumped pose or teleported support never drags the camera with it.
				release_all()
				body.velocity = Vector3.ZERO
				return false
			correction += error
			active += 1
	if active == 0:
		if body.is_on_floor():
			stamina = minf(100.0, stamina + delta * 20.0)
		return false
	correction = (correction / active).limit_length(MAX_SPEED * delta)
	var before := body.global_position
	if correction.length_squared() > 0.0000001:
		body.move_and_collide(correction)
		displacement = body.global_position - before
		origin.global_position += displacement
	body.velocity = Vector3.ZERO
	stamina = maxf(0.0, stamina - delta * 3.0 - displacement.length() * 4.0)
	if stamina <= 0.0:
		release_all()
		return false
	return true
