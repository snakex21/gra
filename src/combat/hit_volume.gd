class_name HitVolume
extends RefCounted
## A capsule attached to a bone (from ``a`` to ``b`` in bone space, ``radius``): the part of
## a limb that actually deals damage. Tested analytically against the player's capsule
## (no physics queries), and drawn by the debug overlay while active.

var bone: StringName
var a := Vector3.ZERO
var b := Vector3.ZERO
var radius := 1.0
## World-space end points, refreshed by update() each tick.
var world_a := Vector3.ZERO
var world_b := Vector3.ZERO
var active := false


static func make(p_bone: StringName, p_a: Vector3, p_b: Vector3, p_radius: float) -> HitVolume:
	var h := HitVolume.new()
	h.bone = p_bone
	h.a = p_a
	h.b = p_b
	h.radius = p_radius
	return h


func update(bone_xf: Transform3D) -> void:
	world_a = bone_xf * a
	world_b = bone_xf * b


## Does this capsule touch a vertical capsule (player) centred at ``center``?
func touches(center: Vector3, half_height: float, other_radius: float) -> bool:
	return distance_to_capsule(center, half_height) <= radius + other_radius


## Distance between the two capsule axes.
func distance_to_capsule(center: Vector3, half_height: float) -> float:
	var p0 := center + Vector3.DOWN * half_height
	var p1 := center + Vector3.UP * half_height
	return segment_distance(world_a, world_b, p0, p1)


## Closest distance between segments p1-q1 and p2-q2.
static func segment_distance(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-8 and e <= 1e-8:
		return r.length()
	if a <= 1e-8:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1e-8:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var bb := d1.dot(d2)
			var denom := a * e - bb * bb
			s = clampf((bb * f - c * e) / denom, 0.0, 1.0) if denom > 1e-8 else 0.0
			t = (bb * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((bb - c) / a, 0.0, 1.0)
	return ((p1 + d1 * s) - (p2 + d2 * t)).length()
