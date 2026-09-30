class_name SurfaceAnchor
extends RefCounted
## A point + normal on a (possibly moving) collider, stored in the collider's local space.
##
## This is the core of climbing on colossi: the climber never stores a world position
## while gripping. Every physics tick the world position is recomputed from the body's
## current transform, so the player moves with the body exactly, with no drift or lag,
## regardless of how the body is animated.
##
## For networking this is also the state to replicate: (segment id, local point, local normal).

var body: CollisionObject3D
var shape: CollisionShape3D
var local_point: Vector3
var local_normal: Vector3


## Builds an anchor from a physics query result (ray / rest info).
## The hit is converted to local space with the transform the *physics server* used for
## the query. For kinematic bodies that can lag the node transform by one tick; using the
## server transform keeps the local point exactly on the surface that was actually hit.
static func from_hit(p_body: CollisionObject3D, p_shape: CollisionShape3D, world_point: Vector3, world_normal: Vector3) -> SurfaceAnchor:
	var a := SurfaceAnchor.new()
	a.body = p_body
	a.shape = p_shape
	var xf := body_query_transform(p_body)
	var inv := xf.affine_inverse()
	a.local_point = inv * world_point
	a.local_normal = (inv.basis * world_normal).normalized()
	return a


static func body_query_transform(p_body: CollisionObject3D) -> Transform3D:
	if p_body is PhysicsBody3D:
		return PhysicsServer3D.body_get_state(p_body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	return p_body.global_transform


func is_valid() -> bool:
	return is_instance_valid(body) and is_instance_valid(shape) and not shape.disabled


func world_point() -> Vector3:
	return body.global_transform * local_point


func world_normal() -> Vector3:
	return (body.global_basis * local_normal).normalized()


## Point/normal where the physics server currently has the shape. Use these as the
## origin of physics queries so rays and shapes are always in the same frame.
func query_point() -> Vector3:
	return body_query_transform(body) * local_point


func query_normal() -> Vector3:
	return (body_query_transform(body).basis * local_normal).normalized()


## World velocity of the anchored material point (not of the climber's own motion along it).
func point_velocity(delta: float) -> Vector3:
	if body is BodySegment:
		return (body as BodySegment).local_point_velocity(local_point, delta)
	return Vector3.ZERO


func grip_cost() -> float:
	return (shape as ClimbPatch).grip_cost if shape is ClimbPatch else 1.0


func slip_speed() -> float:
	return (shape as ClimbPatch).slip_speed if shape is ClimbPatch else 0.0
