class_name WeakPoint
extends Node3D
## A weak point on a colossus: a spot on one segment (moves with its bone), with its own
## health. Only a sword strike that lands on it while it is open counts; the colossus is
## beaten through its weak points, not through a generic health bar.
##
## Lives as a child of the BodySegment it belongs to. For gameplay the position is taken
## from the segment's target transform of the *current* tick (the node itself is drawn one
## tick behind, like every segment visual).

signal struck(damage: float, health_left: float)
signal rejected(reason: StringName)
signal destroyed

enum State { OPEN, PROTECTED, DESTROYED }

@export var max_health := 100.0
## Hits further than this from the centre miss.
@export var radius := 1.1
## Damage of an uncharged / fully charged sword strike.
@export var damage_min := 12.0
@export var damage_max := 40.0
## Strikes weaker than this (charge 0..1) bounce off.
@export var min_power := 0.0

var segment: BodySegment
var local_point := Vector3.ZERO
var health := 100.0
var state := State.OPEN
## Seconds since the last accepted hit (feedback, colossus reaction).
var since_hit := 999.0
## 0..1: the sword's beam rests on it (it glows brighter; decays by itself).
var revealed := 0.0
var last_reason: StringName = &""
var hits_accepted := 0
var hits_rejected := 0

var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _lid: MeshInstance3D


static func create(p_segment: BodySegment, p_local: Vector3, p_health := 100.0) -> WeakPoint:
	var w := WeakPoint.new()
	w.segment = p_segment
	w.local_point = p_local
	w.max_health = p_health
	w.health = p_health
	w.position = p_local
	w.name = "WeakPoint"
	p_segment.add_child(w)
	return w


func _ready() -> void:
	add_to_group(&"weak_points")
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.55, 0.85, 1.0)
	_mat.emission_enabled = true
	_mat.emission = Color(0.4, 0.8, 1.0)
	_mat.emission_energy_multiplier = 2.0
	_mesh = MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = 0.75
	m.bottom_radius = 0.75
	m.height = 0.08
	m.radial_segments = 20
	_mesh.mesh = m
	_mesh.material_override = _mat
	_mesh.position = Vector3(0, 0.02, 0)
	add_child(_mesh)
	# Stone lid shown while protected.
	_lid = MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 0.85
	lm.bottom_radius = 0.9
	lm.height = 0.18
	lm.radial_segments = 12
	_lid.mesh = lm
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(0.45, 0.45, 0.42)
	_lid.material_override = lmat
	_lid.position = Vector3(0, 0.1, 0)
	_lid.visible = false
	add_child(_lid)


func _physics_process(delta: float) -> void:
	since_hit += delta
	revealed = maxf(0.0, revealed - delta * 1.5)
	_update_visual()


## Weak point centre in world space for this tick.
func world_point() -> Vector3:
	return segment.target_transform * local_point


## Tries a hit. ``source`` must be &"sword". ``power`` is the strike charge (0..1).
## Returns {"accepted": bool, "reason": StringName, "damage": float}.
func try_hit(at: Vector3, power: float, source: StringName) -> Dictionary:
	var reason: StringName = &""
	if source != &"sword":
		reason = &"not_a_sword"
	elif state == State.DESTROYED:
		reason = &"destroyed"
	elif state == State.PROTECTED:
		reason = &"protected"
	elif at.distance_to(world_point()) > radius:
		reason = &"out_of_range"
	elif power < min_power:
		reason = &"too_weak"
	if reason != &"":
		last_reason = reason
		hits_rejected += 1
		rejected.emit(reason)
		return {"accepted": false, "reason": reason, "damage": 0.0}
	var dmg := lerpf(damage_min, damage_max, clampf(power, 0.0, 1.0))
	health = maxf(0.0, health - dmg)
	since_hit = 0.0
	hits_accepted += 1
	last_reason = &"hit"
	struck.emit(dmg, health)
	if health <= 0.0:
		state = State.DESTROYED
		destroyed.emit()
	return {"accepted": true, "reason": &"hit", "damage": dmg}


func set_protected(on: bool) -> void:
	if state == State.DESTROYED:
		return
	state = State.PROTECTED if on else State.OPEN


func reset() -> void:
	health = max_health
	state = State.OPEN
	since_hit = 999.0
	hits_accepted = 0
	hits_rejected = 0
	last_reason = &""


func progress() -> float:
	return 1.0 - health / max_health


func state_name() -> String:
	return State.keys()[state]


func _update_visual() -> void:
	if _mat == null:
		return
	var flash := clampf(1.0 - since_hit / 0.35, 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.004)
	match state:
		State.OPEN:
			_mat.emission = Color(0.4, 0.8, 1.0).lerp(Color(1.0, 0.95, 0.8), flash)
			_mat.emission_energy_multiplier = 1.5 + 1.0 * pulse + 6.0 * flash + 5.0 * revealed
		State.PROTECTED:
			_mat.emission_energy_multiplier = 0.2 + 2.0 * revealed
		State.DESTROYED:
			_mat.emission = Color(0.2, 0.2, 0.25)
			_mat.emission_energy_multiplier = 0.1
	_lid.visible = state == State.PROTECTED
