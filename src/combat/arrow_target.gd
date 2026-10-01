class_name ArrowTarget
extends Node3D
## A spot an arrow can hit for a gameplay effect (Quadratus' hoof soles, later other
## colossi's marks). Lives on a BodySegment (moves with its bone) or any Node3D.
##
## Hit test: the arrow's path this tick against a sphere (``radius``) around the spot,
## in the spot's own moving frame (swept: a fast foot cannot tunnel through an arrow).
## A hit only counts when the arrow comes in against the face (``normal_local``, within
## ``max_incidence_deg``) and while the owner keeps ``enabled`` true; otherwise the
## arrow just strikes the surface there (reason says why: disabled / wrong_side).

signal hit(info: Dictionary)

var segment: BodySegment
var local_point := Vector3.ZERO
## Face direction in the parent's space; an arrow must travel against it.
var normal_local := Vector3.UP
var radius := 0.7
var max_incidence_deg := 80.0
## Set by the owner every tick (e.g. only while the hoof is lifted).
var enabled := true
## Free tag for the owner (leg index...).
var tag: Variant = null
var hits_accepted := 0
var hits_rejected := 0
var last_reason: StringName = &""


static func create(parent: Node3D, p_local: Vector3, p_normal: Vector3, p_radius: float, p_tag: Variant = null) -> ArrowTarget:
	var t := ArrowTarget.new()
	t.segment = parent as BodySegment
	t.local_point = p_local
	t.normal_local = p_normal.normalized()
	t.radius = p_radius
	t.tag = p_tag
	t.position = p_local
	t.name = "ArrowTarget"
	parent.add_child(t)
	return t


func _ready() -> void:
	add_to_group(&"arrow_targets")


## Frame of the parent this tick (segments: the bone target, i.e. current tick).
func frame() -> Transform3D:
	return segment.target_transform if segment else get_parent().global_transform


func previous_frame() -> Transform3D:
	return segment.previous_target if segment else get_parent().global_transform


func world_point() -> Vector3:
	return frame() * local_point


func world_normal() -> Vector3:
	return (frame().basis * normal_local).normalized()


## Swept test of an arrow moving p0 -> p1 this tick. Returns the fraction (0..1) of the
## path where it enters the sphere, or -1.
func sweep(p0: Vector3, p1: Vector3) -> float:
	var a := p0 - previous_frame() * local_point
	var b := p1 - world_point()
	var d := b - a
	var aa := d.dot(d)
	var bb := 2.0 * a.dot(d)
	var cc := a.dot(a) - radius * radius
	if cc <= 0.0:
		return 0.0
	if aa < 1e-10:
		return -1.0
	var disc := bb * bb - 4.0 * aa * cc
	if disc < 0.0:
		return -1.0
	var t := (-bb - sqrt(disc)) / (2.0 * aa)
	return t if t >= 0.0 and t <= 1.0 else -1.0


## Decides whether an arrow flying along ``dir`` counts. Emits ``hit`` when it does.
func evaluate(dir: Vector3, at: Vector3, arrow: Dictionary) -> Dictionary:
	var reason: StringName = &"hit"
	if not enabled:
		reason = &"disabled"
	elif dir.normalized().dot(-world_normal()) < cos(deg_to_rad(max_incidence_deg)):
		reason = &"wrong_side"
	last_reason = reason
	var info := {"accepted": reason == &"hit", "reason": reason, "target": self, "point": at, "arrow": arrow, "tag": tag}
	if reason == &"hit":
		hits_accepted += 1
		hit.emit(info)
	else:
		hits_rejected += 1
	return info
