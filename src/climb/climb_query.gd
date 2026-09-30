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


static func ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID], mask := Layers.SOLID) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
	q.hit_back_faces = false
	return space.intersect_ray(q)


## Anchor from a ray hit, or null when the hit surface cannot be gripped.
static func anchor_from_hit(hit: Dictionary) -> SurfaceAnchor:
	if hit.is_empty():
		return null
	var patch := patch_from_hit(hit)
	if patch == null:
		return null
	return SurfaceAnchor.from_hit(_hit_body(hit), patch, hit.position, hit.normal)


## Looks for a grippable surface within ``radius`` of ``center``.
## ``preferred_dir`` biases the search (e.g. the direction the player faces).
static func find_grip(space: PhysicsDirectSpaceState3D, center: Vector3, radius: float, preferred_dir: Vector3, exclude: Array[RID]) -> SurfaceAnchor:
	# 1) Closest contact of a sphere: handles surfaces in any direction (above while falling, etc.).
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	params.transform = Transform3D(Basis.IDENTITY, center)
	params.collision_mask = Layers.COLOSSUS | Layers.WORLD
	params.exclude = exclude
	var rest := space.get_rest_info(params)
	if not rest.is_empty():
		# Refine with a ray to get an exact point/normal on the surface.
		var to_surface: Vector3 = rest.point - center
		if to_surface.length() > 0.001:
			var dir := to_surface.normalized()
			var anchor := anchor_from_hit(ray(space, center, center + dir * (radius + 0.3), exclude))
			if anchor:
				return anchor
	# 2) Fan of rays around the preferred direction (the sphere may have found a
	#    non-climbable shape first, e.g. armour next to fur).
	var fwd := preferred_dir
	fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	var dirs := [fwd, (fwd + Vector3.UP * 0.6).normalized(), (fwd - Vector3.UP * 0.6).normalized(),
		(fwd + right * 0.7).normalized(), (fwd - right * 0.7).normalized(), Vector3.UP, Vector3.DOWN]
	for d in dirs:
		var anchor := anchor_from_hit(ray(space, center, center + d * (radius + 0.3), exclude))
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
