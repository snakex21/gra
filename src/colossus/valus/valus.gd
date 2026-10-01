class_name Valus
extends HumanoidBoss
## Valus: the first complete boss (vertical slice of the colossus fight). The shared boss
## logic (encounter, stomp, hits, weak point reaction, defeat) is in HumanoidBoss; this is
## what makes Valus Valus:
##
## Climb route: back of a calf (fur) -> back of the thigh -> hips -> back -> mantle onto the
## shoulders (REST surface: stand, no grip, stamina comes back) -> mane on the back of the
## neck -> back of the head -> head top, where the weak point is.
## Attacks: STOMP (lift a foot over the player, slam it down) and ARM SWEEP (low swing of
## the arm on the player's side). PROTECT: a guard over the head, closing the weak point
## for a limited time (FairnessRules budget).

const ARM_SWEEP := &"arm_sweep"
const PROTECT := &"protect_weakpoint"

const VALUS_PARTS := [
	[&"hips", Kind.FUR, Vector3(4.2, 1.6, 2.6), Vector3(0, 0.2, 0)],
	[&"spine", Kind.FUR, Vector3(3.4, 2.4, 2.4), Vector3(0, 1.1, 0)],
	[&"chest", Kind.STONE, Vector3(5.0, 2.8, 3.0), Vector3(0, 1.4, 0), &"rest"],
	[&"chest", Kind.FUR, Vector3(4.4, 2.9, 0.5), Vector3(0, 1.2, 1.6)],
	[&"neck", Kind.FUR, Vector2(0.8, 2.2), Vector3(0, 0.6, 0.1)],
	[&"neck", Kind.FUR, Vector3(2.0, 2.6, 0.9), Vector3(0, 0.7, 0.95)],
	[&"head", Kind.STONE, Vector3(2.0, 2.2, 2.2), Vector3(0, 1.1, 0)],
	[&"head", Kind.FUR, Vector3(2.1, 0.4, 2.5), Vector3(0, 2.3, 0.15)],
	[&"head", Kind.FUR, Vector3(2.1, 2.3, 0.8), Vector3(0, 1.25, 1.0)],
	[&"upper_arm_l", Kind.FUR, Vector2(0.8, 4.6), Vector3(0, -2.0, 0)],
	[&"forearm_l", Kind.FUR, Vector2(0.7, 4.4), Vector3(0, -2.0, 0)],
	[&"forearm_l", Kind.ARMOR, Vector3(0.5, 2.6, 1.3), Vector3(0.75, -2.0, 0)],
	[&"hand_l", Kind.STONE, Vector3(1.3, 1.8, 1.1), Vector3(0, -0.9, 0)],
	[&"thigh_l", Kind.FUR, Vector2(1.0, 4.4), Vector3(0, -1.9, 0)],
	[&"thigh_l", Kind.ARMOR, Vector3(1.5, 2.6, 0.45), Vector3(0, -1.9, -1.05)],
	[&"shin_l", Kind.FUR, Vector2(0.85, 4.0), Vector3(0, -1.7, 0)],
	[&"shin_l", Kind.ARMOR, Vector3(1.3, 2.8, 0.45), Vector3(0, -1.7, -0.85)],
	[&"foot_l", Kind.STONE, Vector3(1.7, 0.7, 3.6), Vector3(0, -0.05, -0.85)],
]
## Weak point on top of the head (head bone space).
const WEAK_POINT_LOCAL := Vector3(0, 2.52, 0.2)
## Body regions by bone (gripping the chest = "back", standing on it = "shoulder").
## The spec's regions are foot / calf / thigh / pelvis / back / shoulder / head; the neck
## (the mane on the way to the head) is reported separately.
const REGIONS := {
	&"foot_l": &"foot", &"foot_r": &"foot", &"shin_l": &"calf", &"shin_r": &"calf",
	&"thigh_l": &"thigh", &"thigh_r": &"thigh", &"hips": &"pelvis", &"spine": &"back",
	&"chest": &"back", &"neck": &"neck", &"head": &"head",
	&"upper_arm_l": &"arm", &"forearm_l": &"arm", &"hand_l": &"arm",
	&"upper_arm_r": &"arm", &"forearm_r": &"arm", &"hand_r": &"arm",
}

@export_group("Valus attacks")
@export var sweep_telegraph := 1.1
@export var sweep_active := 0.6
@export var sweep_recovery := 1.2
@export var sweep_damage := 35.0
## Pelvis drop and forward bow during a sweep (the hand has to come down to the ground).
@export var sweep_crouch := 3.2
@export var sweep_bow := 0.55

var _sweep_w := 0.0
var _protect_w := 0.0


func _parts() -> Array:
	return VALUS_PARTS


func _make_brain() -> ColossusBrain:
	return ValusBrain.new(brain_seed)


func _weak_point_spec() -> Array:
	return [&"head", WEAK_POINT_LOCAL, 100.0]


func _regions() -> Dictionary:
	return REGIONS


func _attack_kinds() -> Array[StringName]:
	return [STOMP, ARM_SWEEP]


func _make_attack(it: ColossusIntent) -> ColossusAttack:
	if it.kind != ARM_SWEEP:
		return super(it)
	var a := ColossusAttack.make(ARM_SWEEP, sweep_telegraph, sweep_active, sweep_recovery, true)
	a.limb = 0
	if is_instance_valid(it.target_player):
		var local := global_transform.affine_inverse() * it.target_player.global_position
		a.limb = 0 if local.x >= 0.0 else 1
	return a


func _on_attack_phase(a: ColossusAttack) -> void:
	super(a)
	if a.kind == ARM_SWEEP and a.phase == ColossusAttack.Phase.ACTIVE and effects_enabled:
		Sfx.play(self, &"swing", global_position + Vector3.UP * 6.0)


func _attack_volumes(a: ColossusAttack) -> Array[HitVolume]:
	if a.kind != ARM_SWEEP:
		return super(a)
	var out: Array[HitVolume] = []
	if a.phase == ColossusAttack.Phase.ACTIVE:
		var side := "l" if a.limb == 0 else "r"
		out.append(hit_volumes[StringName("forearm_" + side)])
		out.append(hit_volumes[StringName("hand_" + side)])
	return out


func _hit_values(a: ColossusAttack, pl: PlayerCharacter) -> Array:
	if a.kind != ARM_SWEEP:
		return super(a, pl)
	var side := global_basis.x * (1.0 if a.limb == 0 else -1.0)
	return [sweep_damage, -side * 9.0 + Vector3.UP * 4.0, 1.6]


func _attack_danger(a: ColossusAttack) -> Array:
	if a.kind != ARM_SWEEP:
		return super(a)
	if a.phase == ColossusAttack.Phase.TELEGRAPH or a.phase == ColossusAttack.Phase.ACTIVE:
		return [[global_position - global_basis.z * 6.0, 9.0, a.time_left()]]
	return []


func _observe_player(info: ColossusObservation.PlayerInfo, local: Vector3) -> void:
	super(info, local)
	# Sweep: in front, within the arm's arc.
	if local.z < -2.5 and local.z > -7.5 and absf(local.x) < 7.0 and info.player.global_position.y - global_position.y < 3.0:
		info.sweep_side = 1 if local.x >= 0.0 else -1


func _extra_rules(out: Array[StringName]) -> void:
	if rules.protect_expired(_time):
		out.append(PROTECT)
	if weak_point.state != WeakPoint.State.OPEN and intent.kind != PROTECT:
		out.append(PROTECT)


func _update_extra(it: ColossusIntent, _delta: float) -> void:
	var on := it.kind == PROTECT and encounter == Encounter.COMBAT and not rules.protect_expired(_time)
	if on != (weak_point.state == WeakPoint.State.PROTECTED):
		weak_point.set_protected(on)
		rules.on_protect(on, _time)
		if on:
			stats.protects = int(stats.protects) + 1


func _holds_still(it: ColossusIntent) -> bool:
	return it.kind == RECOVER or it.kind == PROTECT


func _extra_drop() -> float:
	return sweep_crouch * _sweep_w


func _reset_extra() -> void:
	_sweep_w = 0.0
	_protect_w = 0.0


func _build_hit_volumes() -> void:
	super()
	for side in ["l", "r"]:
		hit_volumes[StringName("forearm_" + side)] = HitVolume.make(StringName("forearm_" + side), Vector3(0, -0.5, 0), Vector3(0, -4.2, 0), 0.95)
		hit_volumes[StringName("hand_" + side)] = HitVolume.make(StringName("hand_" + side), Vector3(0, 0, 0), Vector3(0, -1.8, 0), 1.0)


# --- poses --------------------------------------------------------------------------

func _pose_overrides(delta: float) -> void:
	var t0 := Perf.begin()
	# Sweep weight: wind-up, swing and return all blend the arm in and out smoothly.
	var sweeping := attack != null and attack.kind == ARM_SWEEP and attack.phase in [ColossusAttack.Phase.TELEGRAPH, ColossusAttack.Phase.ACTIVE, ColossusAttack.Phase.RECOVERY]
	var sweep_target := 0.0
	if sweeping:
		sweep_target = 1.0 if attack.phase != ColossusAttack.Phase.RECOVERY else 1.0 - attack.phase_t()
	_sweep_w = move_toward(_sweep_w, sweep_target, delta / 0.35)
	_protect_w = move_toward(_protect_w, 1.0 if weak_point.state == WeakPoint.State.PROTECTED else 0.0, delta / 0.4)

	var dw := _defeat_weight() if encounter == Encounter.DEFEATED else 0.0
	# Torso: bow while dormant / defeated, rise for the roar, bend into a sweep, flinch.
	var stag := _stagger
	var pitch := -0.25 * _dormant_w + 0.18 * _roar_w - sweep_bow * _sweep_w - defeat_bow * dw + 0.05 * stag * sin(_stagger_phase)
	var twist := 0.0
	var arm_l := Vector3.ZERO
	var arm_r := Vector3.ZERO
	if sweeping or _sweep_w > 0.0:
		var side := 1.0 if (last_attack != null and last_attack.limb == 0) else -1.0
		var r := _sweep_arm(side)
		twist = r[0]
		if side > 0.0:
			arm_l = r[1]
		else:
			arm_r = r[1]
	_add_rot(&"spine", Vector3(pitch * 0.5, twist * 0.5, 0.03 * stag * sin(_stagger_phase * 1.3)))
	_add_rot(&"chest", Vector3(pitch * 0.5, twist * 0.5, 0.0))
	if arm_l != Vector3.ZERO:
		_set_arm(&"upper_arm_l", arm_l, _sweep_w)
	if arm_r != Vector3.ZERO:
		_set_arm(&"upper_arm_r", arm_r, _sweep_w)
	if _protect_w > 0.0:
		# Raise the right arm beside the head (a guard gesture; the head itself closes).
		_set_arm(&"upper_arm_r", Vector3(-0.55, 0.82, 0.15).normalized(), _protect_w)
		_blend_rot(&"forearm_r", Quaternion.from_euler(Vector3(-1.2, 0, 0)), _protect_w)
	if _roar_w > 0.0:
		_set_arm(&"upper_arm_l", Vector3(0.75, -0.65, -0.1).normalized(), _roar_w * 0.7)
		_set_arm(&"upper_arm_r", Vector3(-0.75, -0.65, -0.1).normalized(), _roar_w * 0.7)
	# Head: bowed while dormant / defeated, ducks while protecting, shakes in a flinch.
	var head_pitch := -0.45 * _dormant_w - 0.25 * _protect_w - 0.55 * dw + 0.2 * _roar_w
	_add_rot(&"neck", Vector3(head_pitch * 0.5 + 0.07 * stag * sin(_stagger_phase), 0, 0))
	_add_rot(&"head", Vector3(head_pitch * 0.5, 0.06 * stag * sin(_stagger_phase * 0.7), 0))
	if dw > 0.0:
		for b in [&"upper_arm_l", &"upper_arm_r"]:
			_blend_rot(b, Quaternion.IDENTITY, dw)
	Perf.end(&"boss_pose", t0)


## Arm direction (chest space) and torso twist for the sweep, by phase.
## Returns [twist, arm_dir].
func _sweep_arm(side: float) -> Array:
	var a := last_attack
	var theta := 0.0     # 0 = out to the side, PI/2 = straight ahead
	var elev := 0.1      # angle from hanging straight down
	var twist := 0.0
	match a.phase:
		ColossusAttack.Phase.TELEGRAPH:
			var t := _smooth(a.phase_t())
			theta = lerpf(0.0, -0.6, t)
			elev = lerpf(0.1, 1.35, t)
			twist = 0.45 * side * t
		ColossusAttack.Phase.ACTIVE:
			var t := _smooth(a.phase_t())
			theta = lerpf(-0.6, PI * 0.95, t)
			elev = lerpf(1.35, 0.62, _smooth(minf(1.0, a.phase_t() * 3.0)))
			twist = lerpf(0.45, -0.45, t) * side
		_:
			theta = PI * 0.95
			elev = 0.62
			twist = -0.45 * side
	var out := Vector3(side, 0, 0)
	var h := out * cos(theta) + Vector3.FORWARD * sin(theta)
	var d := (h * sin(elev) + Vector3.DOWN * cos(elev)).normalized()
	return [twist, d]
