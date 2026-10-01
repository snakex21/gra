class_name ClimbPatch
extends CollisionShape3D
## A collision shape the player can grip (fur, ledges, cracked stone...).
##
## Climbability is a property of the individual shape, not of the whole body, so a
## single colossus segment can mix fur (ClimbPatch) with smooth stone or armour
## (plain CollisionShape3D). Rays that hit a plain shape are treated as a wall
## the climber cannot hold on to.

## Multiplier for stamina drain while holding this patch (1 = normal, >1 = harder).
@export var grip_cost := 1.0
## Constant downward slide speed (m/s) even with full stamina. 0 = firm grip.
@export var slip_speed := 0.0


## Closest point on this shape's surface to ``p`` and the outward normal there, both in
## the shape's local space: [point, normal]. Box, capsule (Y axis) and sphere are handled
## analytically (no physics queries); other shapes return [] and are ignored by grab search.
func closest_local(p: Vector3) -> Array:
	if shape is BoxShape3D:
		var half: Vector3 = (shape as BoxShape3D).size * 0.5
		var q := p.clamp(-half, half)
		if not q.is_equal_approx(p):
			return [q, (p - q).normalized()]
		# Inside: push out through the nearest face.
		var dist := half - p.abs()
		var axis := 0 if dist.x < dist.y and dist.x < dist.z else (1 if dist.y < dist.z else 2)
		var n := Vector3.ZERO
		n[axis] = signf(p[axis]) if p[axis] != 0.0 else 1.0
		q[axis] = half[axis] * n[axis]
		return [q, n]
	if shape is CapsuleShape3D:
		var cap := shape as CapsuleShape3D
		var hs := maxf(0.0, cap.height * 0.5 - cap.radius)
		var c := Vector3(0.0, clampf(p.y, -hs, hs), 0.0)
		var d := p - c
		var n := d.normalized() if d.length() > 1e-4 else Vector3.RIGHT
		return [c + n * cap.radius, n]
	if shape is SphereShape3D:
		var n := p.normalized() if p.length() > 1e-4 else Vector3.UP
		return [n * (shape as SphereShape3D).radius, n]
	return []
