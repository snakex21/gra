class_name ClimbQuery
## Physics queries used by climbing: finding a grip and crawling along surfaces.
##
## Surfaces are ordinary collision shapes (preferably boxes/capsules attached to bones),
## never the rendered skinned mesh. Crawling works on any convex or concave arrangement
## of shapes, which is how the climber moves between bone segments.

## Distance in front of the surface from which crawl rays are cast.
const PROBE := 0.4
## Offset of the close-range "wall ahead" ray.
const NEAR_PROBE := 0.08


## Returns the ClimbPatch hit by a query result, or null if the surface is not climbable.
static func patch_from_hit(hit: Dictionary) -> ClimbPatch:
	var body := _hit_body(hit)
	if body == null:
		return null
	var owner_id := body.shape_find_owner(hit.shape)
	var shape_owner := body.shape_owner_get_owner(owner_id)
	return shape_owner as ClimbPatch


static var _ray_params: PhysicsRayQueryParameters3D
static var _sphere_params: PhysicsShapeQueryParameters3D
static var _sphere: SphereShape3D


## Single raycast. Reuses one parameters object, so no per-call allocation.
static func ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID], mask := Layers.SOLID) -> Dictionary:
	if _ray_params == null:
		_ray_params = PhysicsRayQueryParameters3D.new()
		_ray_params.hit_back_faces = false
	_ray_params.from = from
	_ray_params.to = to
	_ray_params.collision_mask = mask
	_ray_params.exclude = exclude
	Perf.count(&"climb_rays")
	return space.intersect_ray(_ray_params)


## Anchor from a ray hit, or null when the hit surface cannot be gripped.
static func anchor_from_hit(hit: Dictionary) -> SurfaceAnchor:
	if hit.is_empty():
		return null
	var patch := patch_from_hit(hit)
	if patch == null:
		return null
	return SurfaceAnchor.from_hit(_hit_body(hit), patch, hit.position, hit.normal)


## Finds the nearest grippable surface point within ``radius`` of ``center``, in any
## direction. Candidates come from one sphere overlap query; the closest point on each
## ClimbPatch is computed analytically, then verified with one short ray (so armour lying
## over fur, or another body in the way, correctly prevents the grab).
## ``preferred_dir`` slightly favours surfaces the player is facing.
static func find_grip(space: PhysicsDirectSpaceState3D, center: Vector3, radius: float, preferred_dir: Vector3, exclude: Array[RID]) -> SurfaceAnchor:
	if _sphere_params == null:
		_sphere = SphereShape3D.new()
		_sphere_params = PhysicsShapeQueryParameters3D.new()
		_sphere_params.shape = _sphere
	_sphere.radius = radius
	_sphere_params.transform = Transform3D(Basis.IDENTITY, center)
	_sphere_params.collision_mask = Layers.COLOSSUS | Layers.WORLD
	_sphere_params.exclude = exclude
	Perf.count(&"grab_queries")
	var results := space.intersect_shape(_sphere_params, 12)
	var candidates := []
	for r in results:
		var body := r.collider as CollisionObject3D
		if body == null:
			continue
		var patch := body.shape_owner_get_owner(body.shape_find_owner(r.shape)) as ClimbPatch
		if patch == null:
			continue
		# Shape frame as the physics server sees it (see SurfaceAnchor.from_hit).
		var rel := body.global_transform.affine_inverse() * patch.global_transform
		var xf := SurfaceAnchor.body_query_transform(body) * rel
		var cl := patch.closest_local(xf.affine_inverse() * center)
		if cl.is_empty():
			continue
		var wp: Vector3 = xf * (cl[0] as Vector3)
		var wn: Vector3 = (xf.basis * (cl[1] as Vector3)).normalized()
		var to_point := wp - center
		var score := to_point.length()
		if preferred_dir != Vector3.ZERO and score > 0.001:
			score -= 0.15 * preferred_dir.normalized().dot(to_point / score)
		candidates.append([score, wp, wn])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in mini(candidates.size(), 3):
		var wp: Vector3 = candidates[i][1]
		var wn: Vector3 = candidates[i][2]
		var anchor := anchor_from_hit(ray(space, wp + wn * 0.35, wp - wn * 0.3, exclude))
		if anchor:
			return anchor
	return null


## Moves an anchor ``distance`` metres along the surface in world direction ``dir``
## (dir should be tangent to the surface). Handles concave corners (wall ahead),
## flat/curved continuation and convex edges (wrapping around a box or limb),
## including transfers between different bodies/segments.
## Returns null when the move is blocked (no grippable surface there).
static func crawl(space: PhysicsDirectSpaceState3D, anchor: SurfaceAnchor, dir: Vector3, distance: float, exclude: Array[RID]) -> SurfaceAnchor:
	var p := anchor.query_point()
	var n := anchor.query_normal()
	# 1) Concave: something in the way ahead of the hands. Checked close to the surface
	#    (small steps, e.g. a hip box above a thigh) and further out (big overhangs).
	for lift in [NEAR_PROBE, PROBE]:
		var from: Vector3 = p + n * lift
		var ahead := ray(space, from, from + dir * (distance + 0.15), exclude)
		if ahead.is_empty():
			continue
		var a := anchor_from_hit(ahead)
		# Only transfer onto surfaces that face back towards us (not grazing).
		if a and (ahead.normal as Vector3).dot(-dir) > 0.2:
			return a
		return null
	# 2) Continuation of the current surface (flat or curved).
	var target := p + dir * distance
	var down := ray(space, target + n * PROBE, target - n * (PROBE + 0.35), exclude)
	if not down.is_empty():
		return anchor_from_hit(down)
	# 3) Convex edge: wrap around it by looking back from below the old surface level.
	var under := target - n * 0.25
	var back := ray(space, under, under - dir * (distance + 0.35), exclude)
	if not back.is_empty():
		return anchor_from_hit(back)
	return null


static func _hit_body(hit: Dictionary) -> CollisionObject3D:
	return hit.get("collider") as CollisionObject3D
