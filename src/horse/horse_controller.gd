class_name HorseController
extends RefCounted
## The horse's "mind and mass": turns a HorseInputIntent (what the rider roughly wants)
## into a body path. It is NOT a car: the rider never sets a velocity.
##
##   intent -> gait level (kick / rein / push)    -> desired speed
##          -> desired direction (camera or rein)  -> local obstacle avoidance -> steer direction
##   desired speed / steer direction -> jerk-limited speed, turn rate limited by the turn
##   radius the current speed allows (wide at a gallop, a slow pivot when standing)
##
## Feet, body sway and IK are done by QuadrupedGait / Horse from this body path.

enum Gait { IDLE, WALK, TROT, GALLOP }
const GAIT_NAMES := ["IDLE", "WALK", "TROT", "GALLOP"]
## Desired speed per gait level (m/s).
const GAIT_SPEED := [0.0, 1.7, 4.2, 9.5]

# --- mass -----------------------------------------------------------------------------
var max_accel := 2.4        ## m/s^2 speeding up
var max_decel := 4.0        ## m/s^2 slowing down
var rein_decel := 5.5       ## m/s^2 when the reins are pulled
var max_jerk := 7.0         ## m/s^3
var max_yaw_accel := 1.8    ## rad/s^2

# --- turning --------------------------------------------------------------------------
## Turn radius R(v) = min_radius + v^2 / lateral_accel: wide at speed, never a turret.
var min_radius := 1.6
var lateral_accel := 4.5
## Turn rate standing still (stepping around on the spot, slowly).
var pivot_turn_rate := 0.6
var steer_gain := 2.2

# --- avoidance ------------------------------------------------------------------------
var probe_mask := Layers.WORLD | Layers.COLOSSUS
var chest_height := 1.1
var low_height := 0.18
## Obstacles up to this height are stepped over, not avoided.
var step_over_height := 0.55
## A drop deeper than this ahead is a cliff.
var cliff_depth := 1.5
## Deceleration the obstacle braking plans with (below max_decel: leaves room for jerk).
var plan_decel := 2.6
## Sphere cast stop distance (centre to obstacle) and centre-to-edge stop distance.
var stop_gap := 1.6
var edge_margin := 1.9
var front_offset := 1.2
var cast_radius := 0.45
## Surfaces with a normal steeper than this are walls, flatter ones are walkable.
var walkable_normal_y := 0.65
const EDGE_SAMPLE := 3.0

# --- state ----------------------------------------------------------------------------
var position := Vector3.ZERO
var yaw := 0.0
var speed := 0.0
var speed_rate := 0.0
var yaw_rate := 0.0
var gait_level := 0
var gait := Gait.IDLE
var time := 0.0

# --- outputs / debug --------------------------------------------------------------------
var desired_speed := 0.0
var desired_dir := Vector3.FORWARD
var steer_dir := Vector3.FORWARD
var avoid_angle := 0.0
var obstacle := "none"          ## none / avoid / step / wall / cliff
var obstacle_distance := INF
var speed_limit := INF
## Distance left before the horse must be standing (wall / edge ahead), INF if none.
var stop_distance := INF
var probe_hits: Array = []       ## [from, to, hit?] for the debug overlay
## Danger zones set by the horse each tick: [[centre, radius, seconds_to_impact], ...]
## (e.g. a colossus foot about to come down).
var danger_zones: Array = []
## Extra distance the horse keeps from a danger zone.
var danger_margin := 2.5
## none / flee (inside a zone: get out) / refuse (the way leads into one: stop short).
var danger_response := "none"
var rays_this_tick := 0

var _avoid_v := 0.0
var _avoid_target := 0.0
var _avoid_side := 0.0
var _held_dir := Vector3.FORWARD
var _last_hit := Vector3.ZERO
var _sphere := SphereShape3D.new()
var _params := PhysicsShapeQueryParameters3D.new()
## Open terrain left out of the body casts (see _cast); set by the horse.
var terrain_rids: Array[RID] = []


func _init() -> void:
	_sphere.radius = cast_radius
	_params.shape = _sphere
	_params.collision_mask = probe_mask


func forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func body_basis() -> Basis:
	return Basis(Vector3.UP, yaw)


## Forget the held heading and avoidance state (after a teleport).
func reset_heading() -> void:
	_held_dir = forward()
	desired_dir = _held_dir
	steer_dir = _held_dir
	avoid_angle = 0.0
	_avoid_v = 0.0
	_avoid_target = 0.0
	_avoid_side = 0.0


## Turn rate the current speed allows (rad/s).
func max_turn_rate(v: float) -> float:
	var moving := v / (min_radius + v * v / lateral_accel)
	return maxf(moving, pivot_turn_rate * clampf(1.0 - v / 1.0, 0.0, 1.0))


## Current turn radius (m); INF when going straight.
func turn_radius() -> float:
	return speed / absf(yaw_rate) if absf(yaw_rate) > 1e-3 and speed > 0.05 else INF


func update(intent: HorseInputIntent, delta: float, space: PhysicsDirectSpaceState3D, exclude: Array[RID]) -> void:
	time += delta
	rays_this_tick = 0
	var fwd := forward()

	# 1) Gait level: kicks speed up, reins slow down; pushing the stick starts a walk.
	var dir := intent.direction
	dir.y = 0.0
	var pushing := intent.drive > 0.3
	var pulling_back := pushing and dir.length() > 0.1 and dir.normalized().dot(fwd) < -0.5 and speed > 1.0
	if pushing and gait_level == 0 and not pulling_back:
		gait_level = 1
	if intent.gait_up:
		gait_level = mini(gait_level + 1, 3)
	if intent.gait_down:
		gait_level = maxi(gait_level - 1, 0)
	var rein := intent.rein or pulling_back
	if rein:
		# Hold the reins to slow down; on release the gait matching the speed is kept.
		gait_level = _gait_for_speed(speed - 0.3)
	desired_speed = GAIT_SPEED[gait_level]
	if intent.hold_speed >= 0.0:
		desired_speed = intent.hold_speed
	if rein:
		desired_speed = 0.0

	# 2) Desired direction: from the rider (camera relative) or horse-relative steering.
	# Without a turn input the horse keeps the heading it was given (it returns to it after
	# going round something), it does not just follow its own nose.
	if dir.length() > 0.1 and not pulling_back:
		desired_dir = dir.normalized()
		_held_dir = desired_dir
	elif absf(intent.turn) > 0.05:
		desired_dir = fwd.rotated(Vector3.UP, -intent.turn * 1.2)
		_held_dir = fwd
	else:
		if speed < 0.1 and intent.drive <= 0.3:
			_held_dir = fwd
		desired_dir = _held_dir

	# 3) Danger first (an animal does not walk under a falling foot), then local avoidance:
	# small corrections and speed limits, never a path search.
	var flee_speed := _danger()
	var tp := Perf.begin()
	if desired_speed <= 0.0 and speed < 0.05 and flee_speed <= 0.0 and absf(yaw_rate) < 0.01:
		# Standing still and wanting nothing: nothing to look out for (saves every query).
		probe_hits.clear()
		speed_limit = INF
		stop_distance = INF
		obstacle = "none"
		obstacle_distance = INF
	else:
		_probe(space, exclude, delta)
	Perf.end(&"horse_probes", tp)
	steer_dir = desired_dir.rotated(Vector3.UP, avoid_angle)
	desired_speed = minf(desired_speed, speed_limit)
	if flee_speed > 0.0:
		desired_speed = maxf(desired_speed, minf(flee_speed, speed_limit + 2.0))

	# 4) Steering within the turn radius the speed allows; sharp requests slow it down.
	var err := fwd.signed_angle_to(steer_dir, Vector3.UP)
	var spooked := danger_response == "flee"
	if absf(err) > 0.6 and speed > GAIT_SPEED[2]:
		desired_speed = minf(desired_speed, GAIT_SPEED[2])
	elif absf(err) > 1.2 and speed > GAIT_SPEED[1] and not spooked:
		desired_speed = minf(desired_speed, GAIT_SPEED[1])
	# Spooked: whirl round on the spot faster than a calm horse would.
	var limit := max_turn_rate(speed) * (2.0 if spooked else 1.0)
	var target_rate := clampf(err * steer_gain, -limit, limit)
	yaw_rate = move_toward(yaw_rate, target_rate, max_yaw_accel * (2.0 if spooked else 1.0) * delta)
	yaw_rate = clampf(yaw_rate, -limit, limit)

	# 5) Speed with limited acceleration and jerk (mass).
	var decel := rein_decel if rein else max_decel
	# Bolting from danger: an animal gets away faster than it sets off for a ride.
	var accel_limit := max_accel * (1.7 if danger_response == "flee" else 1.0)
	var want_accel := clampf((desired_speed - speed) * 2.0, -decel, accel_limit)
	# Something to stop before: brake with the deceleration that stops exactly there (up to
	# the hard limit), instead of lagging behind a speed limit.
	if stop_distance < INF and speed > 0.05:
		var need := speed * speed / (2.0 * maxf(0.05, stop_distance))
		if need > plan_decel * 0.6:
			want_accel = minf(want_accel, -minf(need * 1.15, rein_decel))
	speed_rate = move_toward(speed_rate, want_accel, max_jerk * delta)
	speed = maxf(0.0, speed + speed_rate * delta)
	if speed <= 0.0 and speed_rate < 0.0:
		speed_rate = 0.0
	# The radius limit holds for the new speed too (slowing down never widens the arc).
	limit = max_turn_rate(speed) * (2.0 if spooked else 1.0)
	yaw_rate = clampf(yaw_rate, -limit, limit)

	yaw = wrapf(yaw + yaw_rate * delta, -PI, PI)
	gait = _logical_gait()


## Reacts to danger zones. Inside one (plus margin): run out of it, away from its centre
## (returns the speed to flee with). Heading into one: stop short of it (speed limit).
func _danger() -> float:
	danger_response = "none"
	var flee := 0.0
	for z in danger_zones:
		var c: Vector3 = z[0]
		var r: float = float(z[1]) + danger_margin
		var to := Vector3(position.x - c.x, 0.0, position.z - c.z)
		var d := to.length()
		if d < r:
			desired_dir = to / d if d > 0.1 else -forward()
			_held_dir = desired_dir
			flee = maxf(flee, GAIT_SPEED[2] + 1.0)
			danger_response = "flee"
			continue
		if desired_speed <= 0.0 or danger_response == "flee":
			continue
		var along := desired_dir.dot(Vector3(c.x - position.x, 0.0, c.z - position.z))
		if along <= 0.0:
			continue
		var closest := sqrt(maxf(0.0, d * d - along * along))
		if closest >= r:
			continue
		var entry := along - sqrt(r * r - closest * closest)
		if entry < 3.0 + speed * 1.5:
			desired_speed = minf(desired_speed, sqrt(2.0 * plan_decel * maxf(0.0, entry - 0.5)))
			danger_response = "refuse"
	return flee


## Called by the horse after its body moved: a blocked body bleeds speed (no full gallop
## into a wall even if every probe was ignored).
func report_actual_speed(actual_forward_speed: float) -> void:
	if actual_forward_speed < speed - 0.5:
		speed = maxf(0.0, actual_forward_speed)
		speed_rate = minf(speed_rate, 0.0)


func _gait_for_speed(v: float) -> int:
	if v > GAIT_SPEED[2] + 0.5:
		return 3
	if v > GAIT_SPEED[1] + 0.3:
		return 2
	if v > 0.4:
		return 1
	return 0


func _logical_gait() -> Gait:
	match gait:
		Gait.IDLE:
			if speed > 0.25 or absf(yaw_rate) > 0.05:
				return Gait.WALK
		Gait.WALK:
			if speed > 2.8:
				return Gait.TROT
			if speed < 0.1 and absf(yaw_rate) < 0.03:
				return Gait.IDLE
		Gait.TROT:
			if speed > 6.2:
				return Gait.GALLOP
			if speed < 2.4:
				return Gait.WALK
		Gait.GALLOP:
			if speed < 5.6:
				return Gait.TROT
	return gait


## Local avoidance, a few queries per tick (no path search):
##  - seven body-wide sphere casts fanned around the desired direction: steer towards the
##    free one closest to what the rider wants (with a little hysteresis);
##  - one sphere cast along the actual heading, as long as the braking distance: slow down
##    so the horse stops before anything it is really heading into;
##  - one low ray: obstacles small enough to step over do not count as walls;
##  - ground samples along the heading: a drop deeper than cliff_depth is an edge, found
##    precisely by bisection, and the horse stops before it.
## Walkable slopes (ramps) are never obstacles.
func _probe(space: PhysicsDirectSpaceState3D, exclude: Array[RID], delta: float) -> void:
	probe_hits.clear()
	speed_limit = INF
	stop_distance = INF
	obstacle = "none"
	obstacle_distance = INF
	var centre := position + Vector3.UP * chest_height
	var fwd := forward()
	# 1) Steering: the free direction closest to the request.
	var length := maxf(4.0, 2.5 + speed * 1.0)
	# The request itself first; if it is blocked, go round on the side away from what is in
	# the way, and stay on that side until the way is clear (no dithering). The first free
	# candidate wins, so open ground costs a single cast.
	var best := INF
	var right := desired_dir.cross(Vector3.UP).normalized()
	for a: float in _avoid_order():
		var d: Vector3 = desired_dir.rotated(Vector3.UP, a)
		var clear := _cast(space, centre, d, length, exclude)
		probe_hits.append([centre, centre + d * clear, clear < length])
		if clear >= length - 0.01:
			best = a
			if a == 0.0:
				_avoid_side = 0.0
			break
		if a == 0.0 and _avoid_side == 0.0:
			_avoid_side = 1.0 if (_last_hit - centre).dot(right) > 0.0 else -1.0
	if best == INF:
		# Nothing free (a wall wider than the fan): keep the current correction and stop in
		# front of it. Choosing a whole new way round is the rider's call, not the horse's.
		best = _avoid_target
		obstacle = "wall"
	elif best != 0.0:
		obstacle = "avoid"
	_avoid_target = best
	# 2) Braking: along the way the horse is actually steering, as far as it needs to stop,
	# plus a short bumper straight ahead of the body for anything it cannot turn away from.
	var brake_len := maxf(3.0, 2.0 + speed * 0.5 + speed * speed / (2.0 * plan_decel))
	var way := desired_dir.rotated(Vector3.UP, avoid_angle)
	var ahead := _cast(space, centre, way, brake_len, exclude)
	probe_hits.append([centre, centre + way * ahead, ahead < brake_len])
	var bumper_len := stop_gap + 0.6 + speed * 0.3
	var bumper := _cast(space, centre, fwd, bumper_len, exclude)
	if bumper < bumper_len:
		probe_hits.append([centre, centre + fwd * bumper, true])
		ahead = minf(ahead, bumper)
	# Low feeler: a log or a bump is stepped over (at most at a trot), a higher block is not.
	var low_from := position + fwd * front_offset + Vector3.UP * low_height
	var low := _ray(space, low_from, low_from + fwd * minf(brake_len, 6.0), exclude)
	if not low.is_empty() and (low.normal as Vector3).y < walkable_normal_y:
		var at: Vector3 = low.position
		var top := _ray(space, at + fwd * 0.25 + Vector3.UP * (chest_height + 0.5), at + fwd * 0.25 + Vector3.DOWN * 0.5, exclude)
		var height := ((top.position as Vector3).y - position.y) if not top.is_empty() else chest_height
		var d_low := low_from.distance_to(at) + front_offset - 0.45
		probe_hits.append([low_from, at, true])
		if height <= step_over_height:
			if obstacle == "none":
				obstacle = "step"
				obstacle_distance = d_low
			speed_limit = minf(speed_limit, GAIT_SPEED[2] + 0.5)
		else:
			ahead = minf(ahead, d_low)
	if ahead < brake_len:
		obstacle_distance = minf(obstacle_distance, ahead)
		if obstacle == "none":
			obstacle = "avoid"
		speed_limit = minf(speed_limit, _stop_speed(ahead - stop_gap))
		stop_distance = minf(stop_distance, ahead - stop_gap)
	# 3) Edges: ground samples along the heading, refined by bisection when one drops away.
	var edge := _find_edge(space, fwd, brake_len, exclude)
	if edge < INF:
		obstacle = "cliff"
		obstacle_distance = edge
		speed_limit = minf(speed_limit, _stop_speed(edge - edge_margin))
		stop_distance = minf(stop_distance, edge - edge_margin)
	# Smooth the correction (continuous heading changes).
	var k := 6.0
	_avoid_v += ((_avoid_target - avoid_angle) * k * k - _avoid_v * 2.0 * k) * delta
	avoid_angle += _avoid_v * delta


## Speed from which the horse can still stop within ``distance`` (planned deceleration).
## Candidate angles in order of preference (0 first, then the committed side).
func _avoid_order() -> Array:
	var side := _avoid_side if _avoid_side != 0.0 else 1.0
	return [0.0, 0.25 * side, 0.5 * side, -0.25 * side, 0.85 * side, -0.5 * side, -0.85 * side]


func _stop_speed(distance: float) -> float:
	return sqrt(2.0 * plan_decel * maxf(0.0, distance))


## Distance along ``dir`` to the first drop deeper than cliff_depth (INF if none).
func _find_edge(space: PhysicsDirectSpaceState3D, dir: Vector3, length: float, exclude: Array[RID]) -> float:
	var n := clampi(ceili(length / EDGE_SAMPLE), 2, 6)
	var prev_y := position.y
	var prev_d := 0.0
	for i in range(1, n + 1):
		var d := length * float(i) / n
		var y := _ground_y(space, dir, d, prev_y, exclude)
		if prev_y - y > cliff_depth:
			# Bisection between the last good sample and this one.
			var lo := prev_d
			var hi := d
			for k in 3:
				var mid := (lo + hi) * 0.5
				if prev_y - _ground_y(space, dir, mid, prev_y, exclude) > cliff_depth * 0.5:
					hi = mid
				else:
					lo = mid
			return lo
		prev_y = y
		prev_d = d
	return INF


func _ground_y(space: PhysicsDirectSpaceState3D, dir: Vector3, d: float, ref_y: float, exclude: Array[RID]) -> float:
	var at := Vector3(position.x, ref_y, position.z) + dir * d
	var hit := _ray(space, at + Vector3.UP * 2.0, at + Vector3.DOWN * (cliff_depth + 1.0), exclude)
	var y: float = (hit.position as Vector3).y if not hit.is_empty() else -INF
	probe_hits.append([at + Vector3.UP * 0.3, Vector3(at.x, maxf(y, at.y - cliff_depth - 1.0), at.z), hit.is_empty()])
	return y


## Free distance for a body-wide sphere; walkable slopes do not block. Open terrain
## (bodies in the "walkable_terrain" group: the valley's height field) is left out of
## this cast: it is never an obstacle there, and testing a slope ahead costs two queries
## per direction. The ground probes (edges, steps) still see it.
func _cast(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, length: float, exclude: Array[RID]) -> float:
	rays_this_tick += 1
	Perf.count(&"horse_rays")
	_params.transform = Transform3D(Basis.IDENTITY, from)
	_params.motion = dir * length
	_params.exclude = exclude + terrain_rids if not terrain_rids.is_empty() else exclude
	var r := space.cast_motion(_params)
	if r.is_empty() or r[1] >= 1.0:
		return length
	# What did it touch? A ramp or the ground is not an obstacle.
	rays_this_tick += 1
	Perf.count(&"horse_rays")
	_params.transform = Transform3D(Basis.IDENTITY, from + dir * length * r[1])
	_params.motion = Vector3.ZERO
	var info := space.get_rest_info(_params)
	if not info.is_empty() and (info.normal as Vector3).y >= walkable_normal_y:
		return length
	_last_hit = info.point if not info.is_empty() else from + dir * length * r[1]
	return length * r[0]


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID]) -> Dictionary:
	rays_this_tick += 1
	return ClimbQuery.ray(space, from, to, exclude, probe_mask, &"horse_rays")
