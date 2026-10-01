class_name BodySegment
extends AnimatableBody3D
## Collision body that follows one skeleton bone of a colossus.
##
## Segments are the climbable/collidable representation of the body. They are driven
## from bone transforms (never from the skinned mesh), which keeps collision cheap and
## stable and gives every surface point a well-defined local frame to anchor to.
## Segments are top-level so moving them directly updates physics (sync_to_physics).

var colossus: Colossus
var bone_name: StringName
var bone_idx := -1
## Bone transform written this tick and the one before. Note: with sync_to_physics the
## node's own global_transform only reaches this value after the physics step (Godot
## reverts it until the server syncs back), so the node - and everything rendered or
## anchored to it - is consistently one tick behind the bone. Velocities are computed
## from these targets, which advance every tick.
var target_transform := Transform3D.IDENTITY
var previous_target := Transform3D.IDENTITY
var _initialised := false


func _init() -> void:
	top_level = true
	sync_to_physics = true
	collision_layer = Layers.COLOSSUS
	collision_mask = 0


## Called by the owning colossus once per physics tick, after the bones were posed.
func follow_bone(skeleton: Skeleton3D) -> void:
	var xf := skeleton.global_transform * skeleton.get_bone_global_pose(bone_idx)
	previous_target = target_transform if _initialised else xf
	target_transform = xf
	_initialised = true
	global_transform = xf


## World-space velocity of a point given in this segment's local space.
func local_point_velocity(local_point: Vector3, delta: float) -> Vector3:
	if delta <= 0.0:
		return Vector3.ZERO
	return (target_transform * local_point - previous_target * local_point) / delta


## World-space angular velocity (rad/s) of this segment over the last tick.
## Uses asin of the quaternion's vector part: acos(w) loses small per-tick rotations
## to float32 rounding.
func angular_velocity(delta: float) -> Vector3:
	if delta <= 0.0:
		return Vector3.ZERO
	var q := (target_transform.basis * previous_target.basis.inverse()).get_rotation_quaternion()
	if q.w < 0.0:
		q = -q
	var v := Vector3(q.x, q.y, q.z)
	var s := v.length()
	if s < 1e-9:
		return Vector3.ZERO
	return v / s * (2.0 * asin(minf(s, 1.0))) / delta
