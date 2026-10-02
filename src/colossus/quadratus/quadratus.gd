class_name Quadratus
extends QuadrupedBoss
## Quadratus: the second boss, a huge four-legged colossus. Not "Valus on four legs":
## its body is out of reach while it stands, so the fight is about bringing it down.
##
##   observe -> QuadratusBrain.decide -> FairnessRules filter -> intent
##   -> attacks / reactions + movement -> four-leg locomotion (gait, tilt, support) / IK
##
## Loop: keep moving between and around its legs, wait until a hind hoof lifts (its
## glowing sole tips backwards in every step), shoot it from behind. The hit leg loses
## its support (LegState.support -> 0): the step planner stops using it, the other three
## carry the weight, the body pitches and rolls down onto that corner and the thigh fur
## comes within reach. Climb the thigh, the flank, onto the back: weak point on the rump,
## then along the back and the neck to the crown. Both destroyed = defeated.
##
## The fight itself (encounter, attacks, shakes, buckling legs, fairness) is the shared
## QuadrupedBoss; Quadratus brings its anatomy, its brain and its weak points.

## Bones (rest offsets, unrotated). Forward -Z, left -X. The body bone sits above the hip
## centre; the legs hang from the body, so a tilted body tilts every hip with it.
const BONES := [
	[&"body", &"", Vector3(0, 8.6, 0)],
	[&"neck", &"body", Vector3(0, 0.6, -6.2)],
	[&"head", &"neck", Vector3(0, 0.8, -3.0)],
	[&"fl_up", &"body", Vector3(-2.7, -1.4, -5.0)],
	[&"fl_low", &"fl_up", Vector3(0, -4.0, 0)],
	[&"fl_foot", &"fl_low", Vector3(0, -3.6, 0)],
	[&"fr_up", &"body", Vector3(2.7, -1.4, -5.0)],
	[&"fr_low", &"fr_up", Vector3(0, -4.0, 0)],
	[&"fr_foot", &"fr_low", Vector3(0, -3.6, 0)],
	[&"rl_up", &"body", Vector3(-2.7, -1.4, 5.0)],
	[&"rl_low", &"rl_up", Vector3(0, -4.0, 0)],
	[&"rl_foot", &"rl_low", Vector3(0, -3.6, 0)],
	[&"rr_up", &"body", Vector3(2.7, -1.4, 5.0)],
	[&"rr_low", &"rr_up", Vector3(0, -4.0, 0)],
	[&"rr_foot", &"rr_low", Vector3(0, -3.6, 0)],
]
const LEGS := [[&"fl_up", &"fl_low", &"fl_foot"], [&"fr_up", &"fr_low", &"fr_foot"], [&"rl_up", &"rl_low", &"rl_foot"], [&"rr_up", &"rr_low", &"rr_foot"]]

## Body: one long fur torso (walkable top), a stone saddle on the back (rest), armour
## over the shoulders' flanks, fur only on the upper part of the thighs (out of reach
## while the legs stand), stone shins and hooves, a fur neck and a fur cap on the head.
const PARTS := [
	[&"body", Kind.FUR, Vector3(6.4, 4.4, 7.0), Vector3(0, 0, -3.0)],
	[&"body", Kind.FUR, Vector3(6.0, 4.3, 6.4), Vector3(0, 0.05, 3.4)],
	[&"body", Kind.STONE, Vector3(3.6, 0.4, 3.4), Vector3(0, 2.05, -1.0), &"rest"],
	# Haunches: fur flush with the outside of the thighs, from the hip up to the back (the
	# way from a lowered thigh onto the rump, no overhang under the belly).
	[&"body", Kind.FUR, Vector3(0.9, 4.3, 3.4), Vector3(-3.4, 0.05, 4.8)],
	[&"body", Kind.FUR, Vector3(0.9, 4.3, 3.4), Vector3(3.4, 0.05, 4.8)],
	[&"body", Kind.ARMOR, Vector3(0.5, 3.4, 4.8), Vector3(-3.42, -0.2, -3.8)],
	[&"body", Kind.ARMOR, Vector3(0.5, 3.4, 4.8), Vector3(3.42, -0.2, -3.8)],
	[&"neck", Kind.FUR, Vector3(2.6, 2.6, 3.6), Vector3(0, 0.3, -1.2)],
	[&"head", Kind.STONE, Vector3(2.6, 2.2, 3.0), Vector3(0, 0.2, -0.9)],
	[&"head", Kind.FUR, Vector3(2.7, 0.5, 2.6), Vector3(0, 1.5, -0.6)],
	# Fur on the back of the head: from the neck up onto the crown.
	[&"head", Kind.FUR, Vector3(2.7, 2.4, 0.6), Vector3(0, 0.55, 0.6)],
	[&"fl_up", Kind.FUR, Vector2(1.05, 3.0), Vector3(0, -1.1, 0)],
	[&"fr_up", Kind.FUR, Vector2(1.05, 3.0), Vector3(0, -1.1, 0)],
	[&"rl_up", Kind.FUR, Vector2(1.15, 3.2), Vector3(0, -1.2, 0)],
	[&"rr_up", Kind.FUR, Vector2(1.15, 3.2), Vector3(0, -1.2, 0)],
	# Knees: stone below the thigh fur (keeps the fur out of reach while it stands).
	[&"fl_up", Kind.STONE, Vector2(0.85, 2.4), Vector3(0, -3.0, 0)],
	[&"fr_up", Kind.STONE, Vector2(0.85, 2.4), Vector3(0, -3.0, 0)],
	[&"rl_up", Kind.STONE, Vector2(0.9, 2.4), Vector3(0, -3.0, 0)],
	[&"rr_up", Kind.STONE, Vector2(0.9, 2.4), Vector3(0, -3.0, 0)],
	[&"fl_low", Kind.STONE, Vector2(0.75, 3.8), Vector3(0, -1.8, 0)],
	[&"fr_low", Kind.STONE, Vector2(0.75, 3.8), Vector3(0, -1.8, 0)],
	[&"rl_low", Kind.STONE, Vector2(0.75, 3.8), Vector3(0, -1.8, 0)],
	[&"rr_low", Kind.STONE, Vector2(0.75, 3.8), Vector3(0, -1.8, 0)],
	[&"fl_foot", Kind.STONE, Vector3(1.9, 0.6, 2.2), Vector3(0, -0.3, -0.2)],
	[&"fr_foot", Kind.STONE, Vector3(1.9, 0.6, 2.2), Vector3(0, -0.3, -0.2)],
	[&"rl_foot", Kind.STONE, Vector3(1.9, 0.6, 2.2), Vector3(0, -0.3, -0.2)],
	[&"rr_foot", Kind.STONE, Vector3(1.9, 0.6, 2.2), Vector3(0, -0.3, -0.2)],
]
## Weak points: on the rump (body bone space) and the crown (head bone space).
const RUMP_LOCAL := Vector3(0, 2.22, 5.0)
const CROWN_LOCAL := Vector3(0, 1.77, -0.5)
## Legs whose soles are arrow targets.
const TARGET_LEGS := [2, 3]
## The intended climb route (debug overlay): [bone, bone-space point].
const ROUTE := [
	[&"rl_up", Vector3(-1.15, -2.4, 0)], [&"rl_up", Vector3(-1.15, -0.6, 0)],
	[&"body", Vector3(-3.85, -1.0, 4.8)], [&"body", Vector3(-3.85, 1.9, 4.8)],
	[&"body", Vector3(-2.6, 2.2, 4.8)], [&"body", Vector3(0, 2.22, 5.0)],
	[&"body", Vector3(0, 2.7, -1.0)], [&"body", Vector3(0, 2.2, -5.8)],
	[&"neck", Vector3(0, 1.6, -1.2)], [&"head", Vector3(0, 1.75, -0.5)],
]


func _rig() -> Dictionary:
	return {"bones": BONES, "legs": LEGS, "upper": 4.0, "lower": 3.6, "ankle": 0.6, "body_above_hips": 1.4, "hip_height": 7.2}


func _parts() -> Array:
	return PARTS


func _make_brain() -> ColossusBrain:
	return QuadratusBrain.new(brain_seed)


func _weak_point_specs() -> Array:
	return [[&"body", RUMP_LOCAL, weak_point_health, false], [&"head", CROWN_LOCAL, weak_point_health, true]]


func _target_legs() -> Array:
	return TARGET_LEGS


func _boss_label() -> String:
	return "QUADRATUS"


func _route() -> Array:
	return ROUTE
