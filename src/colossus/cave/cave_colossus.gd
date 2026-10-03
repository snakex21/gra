class_name CaveColossus
extends Valus
## Bonus cave encounter: the existing climbing rig, a retreat to a dark fissure,
## and a long exposure window when the player lures it out with the sword light.
enum Shelter { EXPOSED, RETREATING, HIDDEN }
const RETREAT := &"cave_retreat"
const HIDE := &"cave_hide"

@export var exposure_time := 22.0
@export var hide_limit := 8.0
@export var lure_time := 1.0
var shelter := Shelter.EXPOSED
var shelter_t := 0.0
var light_t := 0.0
var fissure_side := 1.0

func _init() -> void:
	arena_radius = 17.0
	notice_radius = 30.0
	brain_seed = 53

func _extra_rules(out: Array[StringName]) -> void:
	# Its cover is the fissure; never additionally shield the crown with a hand.
	out.append(PROTECT)

func _choose_intent(obs: ColossusObservation) -> ColossusIntent:
	if debug_override != &"" or encounter != Encounter.COMBAT:
		return super(obs)
	var ridden := obs.players.any(func(p: ColossusObservation.PlayerInfo) -> bool: return p.on_body)
	if ridden:
		shelter = Shelter.EXPOSED
		shelter_t = 0.0
		return super(obs)
	if attack != null and not attack.is_done():
		return super(obs)
	if shelter == Shelter.EXPOSED and shelter_t >= exposure_time:
		shelter = Shelter.RETREATING
		shelter_t = 0.0
		fissure_side = -fissure_side
	if shelter == Shelter.RETREATING:
		var retreat := ColossusIntent.make(ColossusIntent.REPOSITION)
		retreat.target_position = arena_center + Vector3(fissure_side * 13.0, 0, -10.0)
		if global_position.distance_to(retreat.target_position) < 2.5 or shelter_t >= 10.0:
			shelter = Shelter.HIDDEN
			shelter_t = 0.0
		return retreat
	if shelter == Shelter.HIDDEN:
		return ColossusIntent.make(HIDE)
	return super(obs)

func _update_extra(_it: ColossusIntent, delta: float) -> void:
	shelter_t += delta
	if is_defeated():
		return
	var illuminated := false
	if shelter == Shelter.HIDDEN:
		for n in get_tree().get_nodes_in_group(&"players"):
			var p := n as PlayerCharacter
			if p == null or p.dead or not p.beam.lantern or p.beam.raise < 1.0:
				continue
			var to := get_focus_point() - SwordBeam.tip(p)
			if to.length() > 40.0 or p.beam.direction.dot(to.normalized()) < cos(deg_to_rad(24.0)):
				continue
			var q := PhysicsRayQueryParameters3D.create(SwordBeam.tip(p), get_focus_point(), Layers.WORLD)
			if get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				illuminated = true
	light_t = light_t + delta if illuminated else 0.0
	if shelter == Shelter.HIDDEN and (light_t >= lure_time or shelter_t >= hide_limit):
		shelter = Shelter.EXPOSED
		shelter_t = 0.0
		light_t = 0.0
		_think_left = 0.0
	weak_point.set_protected(shelter == Shelter.HIDDEN)

func _holds_still(it: ColossusIntent) -> bool:
	return it.kind == HIDE or super(it)

func _reset_extra() -> void:
	super()
	shelter = Shelter.EXPOSED
	shelter_t = 0.0
	light_t = 0.0
	fissure_side = 1.0

func _debug_extra() -> String:
	return "cave %s %.1f s, light %.1f s" % [Shelter.keys()[shelter], shelter_t, light_t]
