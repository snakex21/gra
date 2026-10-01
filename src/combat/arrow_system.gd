class_name ArrowSystem
extends Node3D
## Every arrow in flight in one world, simulated in fixed physics ticks only (the same
## trajectory at any render rate; visuals are interpolated by the engine).
##
## Per arrow and tick: ballistic step (gravity, no drag), then
##   1) analytic swept test against every enabled ArrowTarget (no physics query),
##   2) one ray along the step against the world and the colossi.
## The first hit along the path wins. An arrow that strikes a colossus sticks to that
## segment (bone-local, it moves with it); in the ground it stays; after ``stuck_life``
## seconds it disappears. Owners hear about target hits through ArrowTarget.hit and
## everyone through ``impact``.

signal impact(info: Dictionary)

@export var gravity := 9.8
@export var max_flight_time := 8.0
@export var stuck_life := 12.0
@export var max_arrows := 48

## Each arrow: {"id", "pos", "vel", "state" (&"flying"/&"stuck"), "age", "owner",
## "segment" (BodySegment or null), "local" (Transform3D in the segment), "node"}.
var arrows: Array[Dictionary] = []
var shots := 0
var last_impact := {}

var _next_id := 1
var _mesh: BoxMesh
var _mat: StandardMaterial3D


## The arrow system of ``node``'s world (created next to it on first use).
static func of(node: Node) -> ArrowSystem:
	for n in node.get_tree().get_nodes_in_group(&"arrow_systems"):
		if (n as Node).is_inside_tree() and n.get_world_3d() == (node as Node3D).get_world_3d():
			return n
	var s := ArrowSystem.new()
	s.name = "Arrows"
	var parent := node.get_parent() if node.get_parent() else node
	parent.add_child(s)
	return s


func _ready() -> void:
	add_to_group(&"arrow_systems")
	# After colossi (-10), horses and players (0): targets are posed for this tick.
	process_physics_priority = 20
	_mesh = BoxMesh.new()
	_mesh.size = Vector3(0.05, 0.05, 1.0)
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.85, 0.8, 0.65)


func spawn(pos: Vector3, vel: Vector3, owner: Node = null) -> Dictionary:
	while arrows.size() >= max_arrows:
		_remove(0)
	var a := {"id": _next_id, "pos": pos, "vel": vel, "state": &"flying", "age": 0.0, "owner": owner, "segment": null, "local": Transform3D.IDENTITY, "node": null, "start": pos, "path": PackedVector3Array([pos])}
	_next_id += 1
	shots += 1
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.material_override = _mat
	mi.top_level = true
	add_child(mi)
	mi.global_transform = _arrow_xf(pos, vel)
	mi.reset_physics_interpolation()
	a.node = mi
	arrows.append(a)
	return a


func flying_count() -> int:
	var n := 0
	for a in arrows:
		if a.state == &"flying":
			n += 1
	return n


func clear() -> void:
	while not arrows.is_empty():
		_remove(arrows.size() - 1)


## Position after ``t`` seconds of free flight (the same integration as the simulation,
## which is exact for constant gravity).
static func predict(pos: Vector3, vel: Vector3, t: float, g := 9.8) -> Vector3:
	return pos + vel * t + Vector3.DOWN * 0.5 * g * t * t


func _physics_process(delta: float) -> void:
	var t0 := Perf.begin()
	var space := get_world_3d().direct_space_state
	var targets := get_tree().get_nodes_in_group(&"arrow_targets")
	var i := 0
	while i < arrows.size():
		var a: Dictionary = arrows[i]
		a.age += delta
		if a.state == &"flying":
			_fly(a, delta, space, targets)
		else:
			if a.segment != null and is_instance_valid(a.segment):
				var xf: Transform3D = (a.segment as BodySegment).target_transform * a.local
				a.pos = xf.origin
				(a.node as Node3D).global_transform = xf
		if (a.state == &"flying" and a.age > max_flight_time) or (a.state == &"stuck" and a.age > stuck_life):
			_remove(i)
			continue
		i += 1
	Perf.end(&"arrows", t0)


func _fly(a: Dictionary, delta: float, space: PhysicsDirectSpaceState3D, targets: Array) -> void:
	var p0: Vector3 = a.pos
	var v0: Vector3 = a.vel
	var p1 := p0 + v0 * delta + Vector3.DOWN * 0.5 * gravity * delta * delta
	var v1 := v0 + Vector3.DOWN * gravity * delta
	var best_t := 2.0
	var best_target: ArrowTarget = null
	for n in targets:
		var tgt := n as ArrowTarget
		Perf.count(&"arrow_target_tests")
		var t := tgt.sweep(p0, p1)
		if t >= 0.0 and t < best_t:
			best_t = t
			best_target = tgt
	var exclude: Array[RID] = []
	if a.owner is CollisionObject3D:
		exclude.append((a.owner as CollisionObject3D).get_rid())
	var hit := ClimbQuery.ray(space, p0, p1, exclude, Layers.WORLD | Layers.COLOSSUS, &"arrow_rays")
	var ray_t := 2.0
	if not hit.is_empty():
		ray_t = (hit.position as Vector3).distance_to(p0) / maxf(p0.distance_to(p1), 1e-6)
	(a.path as PackedVector3Array).append(p1)
	if best_target != null and best_t <= ray_t:
		# Where it lands on the mark: the point of the path closest to the mark's centre
		# (still inside the sphere), not the sphere's rim.
		var c := best_target.world_point()
		var seg := p1 - p0
		var u := clampf((c - p0).dot(seg) / maxf(seg.length_squared(), 1e-9), best_t, minf(1.0, ray_t))
		var at := p0 + seg * u
		var info := best_target.evaluate(v0, at, a)
		_stick(a, at, v0, best_target.segment, best_target.get_parent() as Node3D)
		_report(a, at, best_target.segment, info)
		return
	if not hit.is_empty():
		var seg := hit.collider as BodySegment
		_stick(a, hit.position, v0, seg, hit.collider as Node3D)
		_report(a, hit.position, seg, {"accepted": false, "reason": &"surface", "target": null, "point": hit.position, "arrow": a, "tag": null})
		return
	a.pos = p1
	a.vel = v1
	(a.node as Node3D).global_transform = _arrow_xf(p1, v1)


func _stick(a: Dictionary, at: Vector3, vel: Vector3, seg: BodySegment, _body: Node3D) -> void:
	a.state = &"stuck"
	a.flight = a.age
	a.age = 0.0
	# Half the shaft in the surface.
	var xf := _arrow_xf(at - vel.normalized() * 0.3, vel)
	a.pos = at
	if seg:
		a.segment = seg
		a.local = seg.target_transform.affine_inverse() * xf
	(a.node as Node3D).global_transform = xf


func _report(a: Dictionary, at: Vector3, seg: BodySegment, info: Dictionary) -> void:
	info.segment = seg
	info.colossus = seg.colossus if seg else null
	info.flight_time = a.get("flight", a.age)
	info.id = a.id
	info.point = at
	last_impact = info
	impact.emit(info)


func _remove(i: int) -> void:
	var a: Dictionary = arrows[i]
	if is_instance_valid(a.node):
		(a.node as Node).queue_free()
	arrows.remove_at(i)


static func _arrow_xf(p: Vector3, v: Vector3) -> Transform3D:
	if v.length_squared() < 1e-6:
		return Transform3D(Basis.IDENTITY, p)
	var up := Vector3.UP if absf(v.normalized().y) < 0.99 else Vector3.RIGHT
	return Transform3D(Basis.looking_at(v, up), p)
