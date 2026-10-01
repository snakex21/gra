class_name TwoBoneIK
## Analytic two-bone IK (hip-knee-ankle, shoulder-elbow-wrist).
##
## Returns world-space (or any common space) bases for both bones using this rig
## convention: a bone's child lies along its local -Y, and its local +X is the hinge axis
## (positive rotation about +X swings the limb forward). The knee bends towards ``pole``.
## The target distance is clamped short of full extension, so the knee never snaps
## through the straight-leg singularity.

const EXTENSION_LIMIT := 0.995


## Returns {"upper": Basis, "lower": Basis, "mid": Vector3, "end": Vector3, "error": float}.
static func solve(root: Vector3, target: Vector3, upper_len: float, lower_len: float, pole: Vector3) -> Dictionary:
	var d := target - root
	var dist := d.length()
	var dn := d / dist if dist > 1e-5 else Vector3.DOWN
	var reach := clampf(dist, absf(upper_len - lower_len) + 0.01, (upper_len + lower_len) * EXTENSION_LIMIT)
	var n := dn.cross(pole)
	if n.length() < 1e-4:
		n = dn.cross(Vector3.FORWARD if absf(dn.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT)
	n = n.normalized()
	var cos_a := (upper_len * upper_len + reach * reach - lower_len * lower_len) / (2.0 * upper_len * reach)
	var a := acos(clampf(cos_a, -1.0, 1.0))
	var t := dn * cos(a) + n.cross(dn) * sin(a)
	var mid := root + t * upper_len
	var end := root + dn * reach
	var s := (end - mid).normalized()
	var upper := Basis(n, -t, n.cross(-t))
	var lower := Basis(n, -s, n.cross(-s))
	return {"upper": upper, "lower": lower, "mid": mid, "end": end, "error": end.distance_to(target)}
