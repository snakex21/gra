class_name Hydrus
extends Colossus
## Hydrus: the fifth boss, a sea serpent ~45 m long that lives in a lake. No legs: a head
## and a chain of body segments that follow the head's own path through the water (each
## segment sits on the trail at its distance behind the head), with a slow sideways wave
## along the body.
##
## Loop: it circles the lake past the stone pillars. Wait in the water or on a pillar,
## grab the fur on its side as it passes, climb onto its back (a fur ridge, walkable on
## top) and strike the three glowing spots along the ridge. It fights back by diving: the
## head rears up (the telegraph), then the whole body goes under for a few seconds -
## hold on, under water the grip costs more (holding the breath). A swimmer in its way
## gets rammed (also telegraphed). All three destroyed = defeated (it floats, still).
##
##   intents: CRUISE (circle the lake), APPROACH (slowly, curious), RAM, DIVE, SHAKE_BODY
## Fairness: no dive in the first seconds on its back or right after a weak point hit,
## a long cooldown between dives; no ram at someone on it; shakes under the shared rules.

signal encounter_changed(state: Encounter)

enum Encounter { DORMANT, COMBAT, DEFEATED }
enum Dive { NONE, REAR, DOWN, HOLD, UP }

const CRUISE := &"cruise"
const APPROACH := &"approach"
const RAM := &"ram"
const DIVE := &"dive"
const SHAKE_BODY := &"shake_body"

const SEG_COUNT := 10
const SEG_LEN := 4.4
## Spacing of the head's trail points (m).
const TRAIL_STEP := 0.5
## Body segments carrying a weak point (on the ridge, segment space).
const WEAK_SEGMENTS := [2, 5, 8]
const WEAK_LOCAL := Vector3(0, 1.97, 0)

enum Kind { FUR, STONE }
const COLORS := {Kind.FUR: Color(0.36, 0.3, 0.22), Kind.STONE: Color(0.42, 0.47, 0.46)}

@export_group("Swimming")
## The water's surface (set by the arena); the body swims just under it.
@export var water_level := 0.0
## Centre of the body this far under the surface (the ridge stays out).
@export var swim_depth := 0.9
@export var cruise_speed := 3.4
@export var approach_speed := 2.4
@export var cruise_radius := 40.0
@export var swim_turn_rate := 0.42
@export var wave_amplitude := 0.55
@export_group("Encounter")
@export var notice_radius := 55.0
@export_group("Dive")
@export var dive_rear_time := 1.5
@export var dive_depth := 5.0
@export var dive_hold := 1.5
@export var dive_cooldown := 12.0
## Someone must have been on its back this long before it dives...
@export var dive_after_on_body := 6.0
## ...and have this much stamina left (a dive is a test of grip, not a trap).
@export var dive_min_stamina := 0.6
@export_group("Ram")
@export var ram_telegraph := 1.2
@export var ram_time := 3.5
@export var ram_speed := 7.0
@export var ram_damage := 30.0
@export var ram_cooldown := 8.0
@export var weak_point_health := 90.0

var encounter := Encounter.DORMANT
var weak_points: Array[WeakPoint] = []
var brain_seed := 29
var dive := Dive.NONE
var dive_t := 0.0
## 0..1 how far the head is reared up (dive / ram telegraph).
var rear_w := 0.0
var speed := 0.0
var yaw := 0.0
var stats := {}
var debug_draw: Node3D

var _head := Vector3.ZERO
var _head_y_off := 0.0
var _trail: Array[Vector3] = []
var _bone := {}
var _seg_by_bone := {}
var _dive_cooldown_left := 0.0
var _ram_cooldown_left := 0.0
var _ram_t := -1.0
var _ram_dir := Vector3.FORWARD
var _roll := 0.0
var _flinch_t := 999.0
var _start_xf := Transform3D.IDENTITY
var _ground_probe := {}
var _probe_tick := 0
var _hit_this_ram := {}
## Steering round something in the way (pillars): -1 / 0 / +1 and how long.
var _avoid_side := 0.0
var _avoid_t := 0.0


func _init() -> void:
	body_height = 4.0
	arena_radius = 50.0
	shake_max_duration = 3.0
	shake_cooldown = 6.0


func _ready() -> void:
	brain = HydrusBrain.new(brain_seed)
	super()
	_start_xf = global_transform
	for i in WEAK_SEGMENTS:
		var wp := WeakPoint.create(_seg_by_bone[_bone_name(i)], WEAK_LOCAL, weak_point_health)
		wp.struck.connect(_on_weak_point_struck.bind(wp))
		wp.destroyed.connect(_on_weak_point_destroyed)
		weak_points.append(wp)
	debug_draw = Node3D.new()
	debug_draw.name = "DebugDraw"
	debug_draw.visible = false
	add_child(debug_draw)
	_reset_stats()


static func _bone_name(i: int) -> StringName:
	return &"head" if i == 0 else StringName("s%d" % i)


# --- body ---------------------------------------------------------------------------

func _build_body() -> void:
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	# Bone poses are world transforms (the body follows its own trail, not this node).
	skeleton.top_level = true
	add_child(skeleton)
	skeleton.global_transform = Transform3D.IDENTITY
	for i in SEG_COUNT:
		var idx := skeleton.add_bone(_bone_name(i))
		_bone[_bone_name(i)] = idx
		skeleton.set_bone_rest(idx, Transform3D.IDENTITY)
	skeleton.reset_bone_poses()
	var mats := {}
	for k in COLORS:
		var m := StandardMaterial3D.new()
		m.albedo_color = COLORS[k]
		m.roughness = 1.0 if k == Kind.FUR else 0.7
		mats[k] = m
	for i in SEG_COUNT:
		var seg := BodySegment.new()
		seg.name = "Seg_" + String(_bone_name(i))
		seg.colossus = self
		seg.bone_name = _bone_name(i)
		seg.bone_idx = _bone[_bone_name(i)]
		add_child(seg)
		segments.append(seg)
		_seg_by_bone[seg.bone_name] = seg
		# Tapering towards the tail.
		var w := 1.0 if i < 3 else lerpf(1.0, 0.55, float(i - 3) / float(SEG_COUNT - 4))
		if i == 0:
			_part(seg, Kind.STONE, Vector3(3.4, 2.6, 4.8), Vector3(0, 0.1, -0.6), mats)
			_part(seg, Kind.FUR, Vector3(2.6, 0.5, 3.0), Vector3(0, 1.55, 0.2), mats)
		else:
			_part(seg, Kind.STONE, Vector3(4.0 * w, 2.8 * w, SEG_LEN + 0.3), Vector3.ZERO, mats)
			# The back: fur over the whole top (walkable).
			_part(seg, Kind.FUR, Vector3(4.0 * w, 0.5, SEG_LEN + 0.2), Vector3(0, 1.4 * w + 0.15, 0), mats)
			# Tufts on the sides of every other segment, from under the water up to the
			# back's fur (one climbable way from the water onto the back).
			if i % 2 == 1:
				var top := 1.4 * w + 0.4
				var bottom := -1.0 * w
				for s: float in [-1.0, 1.0]:
					_part(seg, Kind.FUR, Vector3(0.5, top - bottom, 2.4), Vector3(s * (2.0 * w + 0.25), (top + bottom) * 0.5, 0), mats)
	_reset_trail(global_position, rotation.y)
	_pose_bones(0.0)


func _part(seg: BodySegment, kind: Kind, size: Vector3, center: Vector3, mats: Dictionary) -> void:
	var col: CollisionShape3D = ClimbPatch.new() if kind == Kind.FUR else CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = center
	seg.add_child(col)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.position = center
	mesh.material_override = mats[kind]
	mesh.set_meta(&"kind", 0 if kind == Kind.FUR else 1)
	mesh.set_meta(&"part_size", size)
	seg.add_child(mesh)


## A straight trail behind the head (start, reset).
func _reset_trail(head: Vector3, p_yaw: float) -> void:
	yaw = p_yaw
	_head = Vector3(head.x, water_level - swim_depth, head.z)
	var back := Basis(Vector3.UP, yaw) * Vector3.BACK
	_trail.clear()
	var n := int((SEG_COUNT + 4) * SEG_LEN / TRAIL_STEP)
	for k in range(n, 0, -1):
		_trail.append(_head + back * (k * TRAIL_STEP))


## Places the serpent (head at ``pos``, swimming towards ``p_yaw``).
func teleport(pos: Vector3, p_yaw: float) -> void:
	_reset_trail(pos, p_yaw)
	speed = 0.0
	_pose_bones(0.0)
	_sync_segments()
	_sync_segments()
	for s in segments:
		s.reset_physics_interpolation()


## Points on the trail at each distance of ``dists`` (ascending) behind the head, in one
## walk back along it.
func _trail_points(dists: Array[float]) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var k := 0
	var walked := 0.0
	var p := _head
	var i := _trail.size() - 1
	while k < dists.size():
		var q: Vector3 = _trail[i] if i >= 0 else p
		var d := p.distance_to(q)
		while k < dists.size() and (dists[k] <= walked + d or i < 0):
			var f := clampf((dists[k] - walked) / d, 0.0, 1.0) if d > 1e-5 else 0.0
			out.append(p.lerp(q, f))
			k += 1
		walked += d
		p = q
		i -= 1
	return out


func _pose_bones(_delta: float) -> void:
	var dists: Array[float] = []
	for i in SEG_COUNT + 1:
		dists.append(i * SEG_LEN)
	var pts := _trail_points(dists)
	# The swimming wave, growing towards the tail.
	var side := Basis(Vector3.UP, yaw) * Vector3.RIGHT
	for i in range(1, SEG_COUNT + 1):
		pts[i] += side * wave_amplitude * (float(i) / SEG_COUNT) * sin(_time * 1.6 - i * 0.7)
	for i in SEG_COUNT:
		# Segment i spans pts[i] (front) .. pts[i + 1]; its centre in the middle, -Z forward.
		var front: Vector3 = pts[i]
		var rear: Vector3 = pts[i + 1]
		var fwd := (front - rear)
		if fwd.length() < 1e-4:
			fwd = Basis(Vector3.UP, yaw) * Vector3.FORWARD
		var b := Basis.looking_at(fwd.normalized(), Vector3.UP)
		b = b.rotated(fwd.normalized(), _roll * (0.5 + 0.5 * float(i) / SEG_COUNT))
		if i == 0:
			# The head rears up (telegraphs) and its centre is at the front point.
			b = b * Basis(Vector3.RIGHT, rear_w * 0.6)
			skeleton.set_bone_pose(_bone[_bone_name(0)], Transform3D(b, front + Vector3.UP * rear_w * 1.8) )
		else:
			skeleton.set_bone_pose(_bone[_bone_name(i)], Transform3D(b, (front + rear) * 0.5))
	global_position = Vector3(_head.x, water_level, _head.z)


# --- encounter API ------------------------------------------------------------------

func reset_encounter(xf := Transform3D.IDENTITY, use_xf := false) -> void:
	if use_xf:
		_start_xf = xf
	_set_encounter(Encounter.DORMANT)
	for wp in weak_points:
		wp.reset()
	dive = Dive.NONE
	dive_t = 0.0
	rear_w = 0.0
	_head_y_off = 0.0
	_roll = 0.0
	_ram_t = -1.0
	_dive_cooldown_left = 0.0
	_ram_cooldown_left = 0.0
	_flinch_t = 999.0
	_shake_cooldown_left = 0.0
	_time_on_body.clear()
	_off_body_time.clear()
	intent = ColossusIntent.make(ColossusIntent.IDLE)
	teleport(_start_xf.origin, _start_xf.basis.get_euler().y)
	_reset_stats()


func is_defeated() -> bool:
	return encounter == Encounter.DEFEATED


func encounter_name() -> String:
	return Encounter.keys()[encounter]


func beam_weak_point() -> WeakPoint:
	for wp in weak_points:
		if wp.state != WeakPoint.State.DESTROYED:
			return wp
	return null


func weak_points_left() -> int:
	var n := 0
	for wp in weak_points:
		if wp.state != WeakPoint.State.DESTROYED:
			n += 1
	return n


func get_focus_point() -> Vector3:
	return segments[3].target_transform.origin + Vector3.UP * 1.5


## A swimming body has no feet: nothing to trample with.
func get_danger_zones() -> Array:
	return []


func head_point() -> Vector3:
	return segments[0].target_transform * Vector3(0, 0.2, -2.6)


func _set_encounter(e: Encounter) -> void:
	if e == encounter:
		return
	encounter = e
	encounter_changed.emit(e)
	if e == Encounter.DEFEATED:
		defeated.emit()


# --- brain, rules ---------------------------------------------------------------------

func observe() -> ColossusObservation:
	var obs := super()
	obs.facts["water_level"] = water_level
	obs.facts["dive_ready"] = _dive_cooldown_left <= 0.0 and dive == Dive.NONE
	obs.facts["encounter"] = encounter
	var swimmers := []
	for info in obs.players:
		var p := info.player as PlayerCharacter
		if p and p.is_swimming():
			swimmers.append(p)
	obs.facts["swimmers"] = swimmers
	return obs


func _choose_intent(obs: ColossusObservation) -> ColossusIntent:
	if encounter == Encounter.DEFEATED:
		return ColossusIntent.make(ColossusIntent.IDLE)
	if encounter == Encounter.DORMANT:
		for info in obs.players:
			if info.distance < notice_radius or info.on_body:
				_set_encounter(Encounter.COMBAT)
		if encounter == Encounter.DORMANT:
			return ColossusIntent.make(CRUISE)
	# A running dive or ram is finished first.
	if dive != Dive.NONE:
		return ColossusIntent.make(DIVE)
	if _ram_t >= 0.0:
		return intent
	return super(obs)


func _shake_kinds() -> Array[StringName]:
	return [SHAKE_BODY]


func _rules_block() -> Array[StringName]:
	var out: Array[StringName] = []
	var on_body := 0.0
	var tired := false
	for p in get_tree().get_nodes_in_group(&"players"):
		var t: float = _time_on_body.get(p.get_instance_id(), 0.0)
		on_body = maxf(on_body, t)
		if t > 0.0 and "stamina" in p and p.stamina.ratio() < dive_min_stamina:
			tired = true
	if on_body < dive_after_on_body or tired or _dive_cooldown_left > 0.0 or _flinch_t < 5.0:
		out.append(DIVE)
	if on_body > 0.0 or _ram_cooldown_left > 0.0:
		out.append(RAM)
	if on_body < 2.0:
		out.append(SHAKE_BODY)
	return out


# --- controller -------------------------------------------------------------------------

func _execute_intent(it: ColossusIntent, delta: float) -> void:
	_dive_cooldown_left = maxf(0.0, _dive_cooldown_left - delta)
	_ram_cooldown_left = maxf(0.0, _ram_cooldown_left - delta)
	_flinch_t += delta
	if encounter == Encounter.DEFEATED:
		speed = move_toward(speed, 0.0, 1.5 * delta)
		_roll = move_toward(_roll, 0.0, delta)
		rear_w = move_toward(rear_w, 0.0, delta)
		_head_y_off = move_toward(_head_y_off, 0.0, delta)
		_advance(delta, global_position + Basis(Vector3.UP, yaw) * Vector3.FORWARD * 10.0)
		return
	var goal := _cruise_goal()
	var want := cruise_speed
	var shake := 0.0
	match it.kind:
		APPROACH:
			goal = _clamp_to_lake(it.target_position)
			want = approach_speed
		RAM:
			_update_ram(it, delta)
			goal = global_position + _ram_dir * 20.0
			want = ram_speed if _ram_t >= ram_telegraph else 0.6
		DIVE:
			_update_dive(delta)
		SHAKE_BODY:
			shake = clampf(it.strength, 0.3, 1.0)
	if it.kind != DIVE and dive == Dive.NONE:
		rear_w = move_toward(rear_w, 1.0 if (it.kind == RAM and _ram_t >= 0.0 and _ram_t < ram_telegraph) else 0.0, delta / 0.5)
	_roll = 0.25 * shake * sin(_time * TAU * 1.1) if shake > 0.0 else move_toward(_roll, 0.0, delta)
	speed = move_toward(speed, want, (6.0 if it.kind == RAM else (2.0 if speed > want else 0.8)) * delta)
	_advance(delta, goal)


## Head forward along its heading, turning towards ``goal`` (limited rate); the trail
## grows behind it.
func _advance(delta: float, goal: Vector3) -> void:
	var to := goal - _head
	to.y = 0.0
	_avoid(delta)
	if _avoid_t > 0.0:
		to = Basis(Vector3.UP, yaw + _avoid_side * 0.9) * Vector3.FORWARD * 10.0
	if to.length() > 0.5:
		var want_yaw := atan2(-to.x, -to.z)
		var rate := swim_turn_rate * (1.4 if speed < 2.0 else 1.0)
		yaw += clampf(angle_difference(yaw, want_yaw), -rate * delta, rate * delta)
	var fwd := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	var y := water_level - swim_depth + _head_y_off
	# Never into the lake bed (a ray down every few ticks).
	_probe_tick += 1
	if _probe_tick % 6 == 0 or _ground_probe.is_empty():
		var q := PhysicsRayQueryParameters3D.create(_head + Vector3.UP * 20.0, _head + Vector3.DOWN * 40.0, Layers.WORLD)
		_ground_probe = get_world_3d().direct_space_state.intersect_ray(q)
	# The lake bed only (whatever stands out of the water is avoided, not climbed).
	if not _ground_probe.is_empty() and (_ground_probe.position as Vector3).y < water_level - 2.0:
		y = maxf(y, (_ground_probe.position as Vector3).y + 1.8)
	var next := _head + fwd * speed * delta
	next.y = move_toward(_head.y, y, 2.5 * delta)
	_head = next
	# The trail: a point every TRAIL_STEP metres (the body is laid along it).
	if _trail.is_empty() or _head.distance_to(_trail[_trail.size() - 1]) >= TRAIL_STEP:
		_trail.append(_head)
		var keep := int(((SEG_COUNT + 3) * SEG_LEN) / TRAIL_STEP) + 8
		if _trail.size() > keep * 2:
			_trail = _trail.slice(_trail.size() - keep)


## Something ahead at swimming depth (a pillar): turn away from it for a while, to the
## side that is free.
func _avoid(delta: float) -> void:
	_avoid_t = maxf(0.0, _avoid_t - delta)
	if _probe_tick % 6 != 3 or speed < 0.3:
		return
	var space := get_world_3d().direct_space_state
	var from := Vector3(_head.x, water_level - 0.4, _head.z)
	var fwd := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	# Three feelers across the body's width (the body behind sweeps the inside of a turn).
	var side := fwd.cross(Vector3.UP).normalized()
	var ahead := {}
	for o: float in [0.0, -3.0, 3.0]:
		var f := from + side * o
		ahead = space.intersect_ray(PhysicsRayQueryParameters3D.create(f, f + fwd * (12.0 + speed * 2.5), Layers.WORLD))
		if not ahead.is_empty() and (ahead.normal as Vector3).y <= 0.7:
			break
	if ahead.is_empty() or (ahead.normal as Vector3).y > 0.7:
		return
	if _avoid_t <= 0.0:
		var right := Basis(Vector3.UP, yaw - 0.7) * Vector3.FORWARD
		var left := Basis(Vector3.UP, yaw + 0.7) * Vector3.FORWARD
		var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + right * 14.0, Layers.WORLD))
		var l := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + left * 14.0, Layers.WORLD))
		_avoid_side = 1.0 if r.is_empty() == l.is_empty() and ahead.collider.get_instance_id() % 2 == 0 or (not l.is_empty() and r.is_empty()) else -1.0
		_avoid_side = -1.0 if (not l.is_empty() and r.is_empty()) else (1.0 if (l.is_empty() and not r.is_empty()) else _avoid_side)
	_avoid_t = 1.5


func _cruise_goal() -> Vector3:
	# The point a bit ahead on a circle round the lake's centre.
	var off := _head - arena_center
	var a := atan2(off.z, off.x) + 0.55
	return arena_center + Vector3(cos(a), 0, sin(a)) * cruise_radius


func _clamp_to_lake(p: Vector3) -> Vector3:
	var off := p - arena_center
	off.y = 0.0
	return arena_center + off.limit_length(arena_radius)


func _update_dive(delta: float) -> void:
	if dive == Dive.NONE:
		dive = Dive.REAR
		dive_t = 0.0
		stats.dives = int(stats.dives) + 1
		Sfx.play(self, &"roar", head_point())
	dive_t += delta
	match dive:
		Dive.REAR:
			rear_w = move_toward(rear_w, 1.0, delta / 0.6)
			if dive_t >= dive_rear_time:
				dive = Dive.DOWN
				dive_t = 0.0
		Dive.DOWN:
			rear_w = move_toward(rear_w, 0.0, delta / 0.4)
			_head_y_off = move_toward(_head_y_off, -dive_depth, 3.5 * delta)
			if _head_y_off <= -dive_depth + 0.05:
				dive = Dive.HOLD
				dive_t = 0.0
		Dive.HOLD:
			if dive_t >= dive_hold:
				dive = Dive.UP
				dive_t = 0.0
		Dive.UP:
			_head_y_off = move_toward(_head_y_off, 0.0, 3.0 * delta)
			# Over only when the whole body is up again (the dip runs back along it).
			var all_up := true
			for sg in segments:
				if sg.target_transform.origin.y < water_level - swim_depth - 0.3:
					all_up = false
					break
			if _head_y_off >= 0.0 and all_up and dive_t > 0.5:
				dive = Dive.NONE
				_dive_cooldown_left = dive_cooldown
				_think_left = 0.0


func _update_ram(it: ColossusIntent, delta: float) -> void:
	if _ram_t < 0.0:
		_ram_t = 0.0
		_hit_this_ram.clear()
		stats.rams = int(stats.rams) + 1
	_ram_t += delta
	if _ram_t < ram_telegraph:
		var to := it.target_position - _head
		to.y = 0.0
		if to.length() > 0.5:
			_ram_dir = to.normalized()
	elif _ram_t >= ram_telegraph + ram_time:
		_ram_t = -1.0
		_ram_cooldown_left = ram_cooldown
		_think_left = 0.0


func _post_sync(_delta: float) -> void:
	# The ram hits whoever is in front of the head while it charges.
	if _ram_t < ram_telegraph or encounter != Encounter.COMBAT:
		return
	var h := head_point()
	for p in get_tree().get_nodes_in_group(&"players"):
		var pl := p as PlayerCharacter
		if pl == null or pl.dead or owns_body(pl.get_support_body()) or _hit_this_ram.has(pl.get_instance_id()):
			continue
		if pl.global_position.distance_to(h) < 3.2:
			_hit_this_ram[pl.get_instance_id()] = true
			var away := (pl.global_position - _head)
			away.y = 0.0
			if pl.apply_hit(ram_damage, away.normalized() * 8.0 + Vector3.UP * 3.0, 1.0, &"ram"):
				stats.player_hits = int(stats.player_hits) + 1


func _on_weak_point_struck(_damage: float, _left: float, _wp: WeakPoint) -> void:
	stats.weak_point_hits = int(stats.weak_point_hits) + 1
	if encounter == Encounter.DORMANT:
		_set_encounter(Encounter.COMBAT)
	_flinch_t = 0.0
	_flinched(1.2)


func _on_weak_point_destroyed() -> void:
	if weak_points_left() == 0:
		_set_encounter(Encounter.DEFEATED)


func _reset_stats() -> void:
	stats = {"dives": 0, "rams": 0, "player_hits": 0, "weak_point_hits": 0}


func debug_text() -> String:
	var wps := []
	for wp in weak_points:
		wps.append("%.0f" % wp.health)
	return "HYDRUS %s  intent %s  speed %.1f  dive %s  weak points %s\n%s" % [encounter_name(), intent.kind, speed, Dive.keys()[dive], ", ".join(wps), super()]
