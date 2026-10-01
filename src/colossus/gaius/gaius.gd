class_name Gaius
extends HumanoidBoss
## Gaius: the third boss, a stone knight with a sword. Shared boss logic is HumanoidBoss;
## what is Gaius:
##
## - The sword is a bone in the right hand with its own segment (stone blade, flat faces):
##   a weapon that moves with the arm, hits with the blade and can be walked on.
## - SWORD_SLAM: raise the sword over the shoulder (telegraph, the slam point follows the
##   target for the first half), bring it down (blade hit volume, shockwave at the tip),
##   the tip sticks in the ground and the blade stays there as a ramp for ``stuck_time``
##   (Gaius crouches, does nothing else), then pulls it out.
## - Climb route: up the stuck blade -> fist -> forearm fur -> upper arm -> shoulders (rest)
##   -> mane -> back of the head -> onto the helmet.
## - The helmet is an ArmorPlate over the weak point: three charged sword strikes break
##   it; until then the weak point is closed.
## The right arm is placed by two-bone IK from targets in the body frame (idle / raised /
## slam), so the blade always ends where the slam point is.

const SWORD_SLAM := &"sword_slam"
## Sword: grip offset in the hand, blade length along the sword bone's -Y.
const SWORD_GRIP := Vector3(0, -1.2, 0)
const BLADE_LENGTH := 10.4
const BLADE_TIP := Vector3(0, -10.4, 0)

const GAIUS_BONES_EXTRA := [[&"sword", &"hand_r", Vector3(0, -1.2, 0)]]
## Body: the greybox humanoid with a stone breastplate (shoulders = rest surface), a fur
## mane on the back of the neck and the back of the head (way up), a helmet (armour plate)
## over the fur cap, armour on the thighs, and the sword.
const GAIUS_PARTS := [
	[&"hips", Kind.FUR, Vector3(4.4, 1.7, 2.7), Vector3(0, 0.2, 0)],
	[&"spine", Kind.FUR, Vector3(3.6, 2.4, 2.5), Vector3(0, 1.1, 0)],
	[&"chest", Kind.STONE, Vector3(5.4, 2.8, 3.1), Vector3(0, 1.4, 0), &"rest"],
	[&"chest", Kind.FUR, Vector3(4.6, 2.9, 0.5), Vector3(0, 1.2, 1.65)],
	# Fur pauldrons: from the top of an arm onto the shoulders.
	[&"chest", Kind.FUR, Vector3(1.8, 0.55, 2.6), Vector3(2.15, 2.95, 0)],
	[&"chest", Kind.FUR, Vector3(1.8, 0.55, 2.6), Vector3(-2.15, 2.95, 0)],
	[&"neck", Kind.FUR, Vector2(0.85, 2.2), Vector3(0, 0.6, 0.1)],
	[&"neck", Kind.FUR, Vector3(2.0, 2.6, 0.9), Vector3(0, 0.7, 0.95)],
	[&"head", Kind.STONE, Vector3(2.1, 2.2, 2.2), Vector3(0, 1.1, 0)],
	[&"head", Kind.FUR, Vector3(2.1, 0.4, 2.5), Vector3(0, 2.3, 0.15)],
	[&"head", Kind.FUR, Vector3(2.1, 2.3, 0.8), Vector3(0, 1.25, 1.0)],
	[&"head", Kind.ARMOR, Vector3(2.5, 0.55, 2.7), Vector3(0, 2.75, 0.1), &"helmet"],
	[&"upper_arm_l", Kind.FUR, Vector2(0.85, 4.6), Vector3(0, -2.0, 0)],
	[&"forearm_l", Kind.FUR, Vector2(0.75, 4.4), Vector3(0, -2.0, 0)],
	[&"hand_l", Kind.STONE, Vector3(1.3, 1.8, 1.1), Vector3(0, -0.9, 0)],
	[&"thigh_l", Kind.FUR, Vector2(1.0, 4.4), Vector3(0, -1.9, 0)],
	[&"thigh_l", Kind.ARMOR, Vector3(1.5, 2.6, 0.45), Vector3(0, -1.9, -1.05)],
	[&"shin_l", Kind.FUR, Vector2(0.85, 4.0), Vector3(0, -1.7, 0)],
	[&"shin_l", Kind.ARMOR, Vector3(1.3, 2.8, 0.45), Vector3(0, -1.7, -0.85)],
	[&"foot_l", Kind.STONE, Vector3(1.7, 0.7, 3.6), Vector3(0, -0.05, -0.85)],
	[&"sword", Kind.STONE, Vector3(1.9, 10.0, 0.5), Vector3(0, -5.4, 0), &"blade"],
	[&"sword", Kind.STONE, Vector3(2.8, 0.45, 0.55), Vector3(0, -0.2, 0)],
	# The sword hand is wrapped (cloth / fur): from the blade the fist can be grabbed.
	[&"hand_r", Kind.FUR, Vector3(1.45, 1.95, 1.25), Vector3(0, -0.9, 0)],
]
const WEAK_POINT_LOCAL := Vector3(0, 2.52, 0.2)
const REGIONS := {
	&"foot_l": &"foot", &"foot_r": &"foot", &"shin_l": &"calf", &"shin_r": &"calf",
	&"thigh_l": &"thigh", &"thigh_r": &"thigh", &"hips": &"pelvis", &"spine": &"back",
	&"chest": &"back", &"neck": &"neck", &"head": &"head",
	&"upper_arm_l": &"arm", &"forearm_l": &"arm", &"hand_l": &"arm",
	&"upper_arm_r": &"arm", &"forearm_r": &"arm", &"hand_r": &"arm", &"sword": &"sword",
}

@export_group("Sword")
@export var slam_telegraph := 1.5
@export var slam_active := 0.4
## The sword stays in the ground this long (the climb window), then is pulled out...
@export var stuck_time := 8.0
## ...over this long.
@export var pull_time := 1.6
@export var slam_damage := 70.0
@export var slam_shock_radius := 5.0
@export var slam_shock_damage := 26.0
## Slam point distance from Gaius (m), clamped.
@export var slam_min := 13.0
@export var slam_max := 17.5
## Blade elevation when stuck (rad): the ramp's slope.
@export var stuck_angle := 0.42
@export var slam_crouch := 2.6
@export var slam_bow := 0.45
@export var helmet_hits := 3

var helmet: ArmorPlate
## Slam point (ground) of the current / last slam.
var slam_point := Vector3.ZERO

var _slam_w := 0.0
var _impacted := false
var _blade_hold := Vector3.ZERO     # body-frame hand target / blade dir actually used
var _blade_dir := Vector3.FORWARD


func _init() -> void:
	brain_seed = 13
	notice_radius = 46.0


func _bones() -> Array:
	return BONES + GAIUS_BONES_EXTRA


func _parts() -> Array:
	return GAIUS_PARTS


func _make_brain() -> ColossusBrain:
	return GaiusBrain.new(brain_seed)


func _weak_point_spec() -> Array:
	return [&"head", WEAK_POINT_LOCAL, 100.0]


func _regions() -> Dictionary:
	return REGIONS


func _ready() -> void:
	super()
	rules.cooldowns = {STOMP: 6.0, SWORD_SLAM: 9.0}
	# The helmet over the weak point: an armour plate the sword can break.
	var head: BodySegment = _seg_by_bone[&"head"]
	var shape: CollisionShape3D = null
	var meshes: Array[MeshInstance3D] = []
	for c in head.get_children():
		if c is CollisionShape3D and c.has_meta(&"surface") and c.get_meta(&"surface") == &"helmet":
			shape = c
	for c in head.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).position.is_equal_approx(shape.position):
			meshes.append(c)
	helmet = ArmorPlate.create(head, shape, meshes, helmet_hits)
	helmet.broken.connect(_on_helmet_broken)
	helmet.cracked.connect(func(_n: int) -> void:
		stats.helmet_hits = int(stats.helmet_hits) + 1
		_stagger_t = 0.0
		if effects_enabled:
			Sfx.play(self, &"impact", helmet.world_point()))
	weak_point.set_protected(true)


func _reset_extra() -> void:
	_slam_w = 0.0
	_impacted = false
	if helmet:
		helmet.reset()
		weak_point.set_protected(true)


func _reset_stats() -> void:
	super()
	stats.helmet_hits = 0
	stats.slam_impacts = 0
	stats.helmet_broken_at = -1.0


func _on_helmet_broken() -> void:
	stats.helmet_broken_at = _time
	weak_point.set_protected(false)
	_stagger_t = 0.0
	if effects_enabled:
		Fx.burst(get_parent(), helmet.world_point())
		Sfx.play(self, &"weak_hit", helmet.world_point())
	if encounter == Encounter.COMBAT:
		_set_intent(ColossusIntent.make(RECOVER))


## Is the sword stuck in the ground right now (the blade is a ramp)?
func sword_stuck() -> bool:
	return attack != null and not attack.is_done() and attack.kind == SWORD_SLAM and attack.phase == ColossusAttack.Phase.RECOVERY and attack.phase_time < stuck_time


## Blade tip in world space this tick.
func blade_tip() -> Vector3:
	return (_seg_by_bone[&"sword"] as BodySegment).target_transform * BLADE_TIP


# --- attacks ------------------------------------------------------------------------

func _attack_kinds() -> Array[StringName]:
	return [STOMP, SWORD_SLAM]


func _make_attack(it: ColossusIntent) -> ColossusAttack:
	if it.kind != SWORD_SLAM:
		return super(it)
	var a := ColossusAttack.make(SWORD_SLAM, slam_telegraph, slam_active, stuck_time + pull_time, true)
	a.limb = 1
	return a


func _on_attack_phase(a: ColossusAttack) -> void:
	super(a)
	if a.kind != SWORD_SLAM:
		return
	match a.phase:
		ColossusAttack.Phase.TELEGRAPH:
			_impacted = false
			slam_point = _slam_goal(a.target_point)
		ColossusAttack.Phase.ACTIVE:
			if effects_enabled:
				Sfx.play(self, &"swing", get_focus_point())


func _attack_tick(a: ColossusAttack, delta: float) -> void:
	super(a, delta)
	if a.kind != SWORD_SLAM:
		return
	# The first half of the wind-up follows the target (2.5 m/s at most), then it is locked.
	if a.phase == ColossusAttack.Phase.TELEGRAPH and a.phase_t() < 0.5 and is_instance_valid(a.target_player):
		var want := _slam_goal(a.target_player.global_position)
		var step := _flat(want - slam_point)
		if step.length() > 2.5 * delta:
			step = step.normalized() * 2.5 * delta
		slam_point = _ground_under(slam_point + step)
	if a.phase == ColossusAttack.Phase.ACTIVE and not _impacted and a.phase_t() >= 0.999:
		_impacted = true


## Ground point in front of Gaius, on the sword side, at slam distance.
func _slam_goal(p: Vector3) -> Vector3:
	var local := global_transform.affine_inverse() * p
	var flat := Vector2(local.x, local.z)
	var d := clampf(-local.z, slam_min, slam_max)
	var x := clampf(local.x, -5.0, 1.5)
	if flat.length() < 0.01:
		x = -2.0
	return _ground_under(global_transform * Vector3(x, 0, -d))


func _attack_volumes(a: ColossusAttack) -> Array[HitVolume]:
	if a.kind != SWORD_SLAM:
		return super(a)
	var out: Array[HitVolume] = []
	if a.phase == ColossusAttack.Phase.ACTIVE and a.phase_t() > 0.35:
		out.append(hit_volumes[&"sword"])
	return out


func _attack_shock(a: ColossusAttack) -> Array:
	if a.kind != SWORD_SLAM:
		return super(a)
	if a.phase == ColossusAttack.Phase.RECOVERY and a.phase_time < 0.12:
		return [slam_point, slam_shock_radius, slam_shock_damage]
	return []


func _hit_values(a: ColossusAttack, pl: PlayerCharacter) -> Array:
	if a.kind != SWORD_SLAM:
		return super(a, pl)
	return [slam_damage, _flat(pl.global_position - slam_point).normalized() * 6.0 + Vector3.UP * 2.5, 2.2]


func _attack_danger(a: ColossusAttack) -> Array:
	if a.kind != SWORD_SLAM:
		return super(a)
	match a.phase:
		ColossusAttack.Phase.PREPARE:
			return [[_slam_goal(a.target_point), slam_shock_radius + 1.0, a.telegraph_time + a.active_time]]
		ColossusAttack.Phase.TELEGRAPH, ColossusAttack.Phase.ACTIVE:
			# The whole blade path: a strip from the feet to the slam point.
			var mid := global_position.lerp(slam_point, 0.6)
			return [[slam_point, slam_shock_radius + 1.0, a.time_left()], [mid, 4.0, a.time_left()]]
	return []


func _on_phase(a: ColossusAttack) -> void:
	super(a)
	if a.kind == SWORD_SLAM and a.phase == ColossusAttack.Phase.RECOVERY:
		stats.slam_impacts = int(stats.slam_impacts) + 1
		if effects_enabled:
			Fx.dust(get_parent(), slam_point, 2.6)
			Sfx.play(self, &"stomp", slam_point)


func _observe_player(info: ColossusObservation.PlayerInfo, local: Vector3) -> void:
	super(info, local)
	if info.stomp_foot >= 0:
		info.opportunities.append(STOMP)
	# Sword: in front, in the slam band, on the ground.
	if -local.z > slam_min - 4.0 and -local.z < slam_max + 3.0 and local.x > -8.0 and local.x < 4.0 and info.player.global_position.y - global_position.y < 3.0:
		info.opportunities.append(SWORD_SLAM)


func _holds_still(it: ColossusIntent) -> bool:
	return it.kind == RECOVER


func _extra_drop() -> float:
	return slam_crouch * _slam_w


func _extra_rules(out: Array[StringName]) -> void:
	# Nothing else while the sword is stuck in the ground (the climb window).
	if sword_stuck():
		out.append(ColossusIntent.SHAKE_PLAYER)


func _build_hit_volumes() -> void:
	super()
	hit_volumes[&"sword"] = HitVolume.make(&"sword", Vector3(0, -1.0, 0), BLADE_TIP, 1.1)


# --- poses --------------------------------------------------------------------------

func _pose_overrides(delta: float) -> void:
	var t0 := Perf.begin()
	var a := last_attack
	var slamming := a != null and not a.is_done() and a.kind == SWORD_SLAM and a.phase != ColossusAttack.Phase.PREPARE
	# Crouch and bow while the blade is down (so the arm reaches), out again on the pull.
	var crouch := 0.0
	if slamming:
		match a.phase:
			ColossusAttack.Phase.TELEGRAPH:
				crouch = 0.0
			ColossusAttack.Phase.ACTIVE:
				crouch = _smooth(a.phase_t())
			ColossusAttack.Phase.RECOVERY:
				crouch = 1.0 if a.phase_time < stuck_time else 1.0 - _smooth((a.phase_time - stuck_time) / pull_time)
	_slam_w = move_toward(_slam_w, crouch, delta / 0.25) if crouch < _slam_w else crouch
	var dw := _defeat_weight() if encounter == Encounter.DEFEATED else 0.0
	var stag := _stagger
	var pitch := -0.25 * _dormant_w + 0.18 * _roar_w - slam_bow * _slam_w - defeat_bow * dw + 0.05 * stag * sin(_stagger_phase)
	var twist := 0.0
	if slamming and a.phase == ColossusAttack.Phase.TELEGRAPH:
		twist = -0.3 * _smooth(a.phase_t())
	elif slamming and a.phase == ColossusAttack.Phase.ACTIVE:
		twist = lerpf(-0.3, 0.1, _smooth(a.phase_t()))
	_add_rot(&"spine", Vector3(pitch * 0.5, twist * 0.5, 0.03 * stag * sin(_stagger_phase * 1.3)))
	_add_rot(&"chest", Vector3(pitch * 0.5, twist * 0.5, 0.0))
	if _roar_w > 0.0:
		_set_arm(&"upper_arm_l", Vector3(0.75, -0.65, -0.1).normalized(), _roar_w * 0.7)
	var head_pitch := -0.45 * _dormant_w - 0.55 * dw + 0.2 * _roar_w
	_add_rot(&"neck", Vector3(head_pitch * 0.5 + 0.07 * stag * sin(_stagger_phase), 0, 0))
	_add_rot(&"head", Vector3(head_pitch * 0.5, 0.06 * stag * sin(_stagger_phase * 0.7), 0))
	if dw > 0.0:
		_blend_rot(&"upper_arm_l", Quaternion.IDENTITY, dw)
	_pose_sword_arm(delta)
	Perf.end(&"boss_pose", t0)


## Right arm by IK so the hand (and the sword in it) follow targets in the body frame.
func _pose_sword_arm(delta: float) -> void:
	var a := last_attack
	var chest_xf := skeleton.get_bone_global_pose(_bone[&"chest"])
	var shoulder := chest_xf * (_rest[&"upper_arm_r"] as Vector3)
	# Idle: sword in front, tip down but off the ground.
	var hand := shoulder + Vector3(0.4, -6.2, -2.6)
	var dir := Vector3(0.1, -0.42, -1.0).normalized()
	var inv := global_transform.affine_inverse()
	if a != null and not a.is_done() and a.kind == SWORD_SLAM and a.phase != ColossusAttack.Phase.PREPARE:
		var raised_hand := shoulder + Vector3(0.6, 2.6, 1.4)
		var raised_dir := Vector3(0.05, 0.6, 0.8).normalized()
		var slam_local := inv * slam_point
		var toward := Vector3(-slam_local.x, 0, -slam_local.z).normalized()
		var stuck_dir := (-toward * cos(stuck_angle) + Vector3.DOWN * sin(stuck_angle)).normalized()
		var stuck_hand := slam_local - stuck_dir * BLADE_LENGTH - stuck_dir * 1.2
		match a.phase:
			ColossusAttack.Phase.TELEGRAPH:
				var t := _smooth(a.phase_t() / 0.7)
				hand = hand.lerp(raised_hand, t)
				dir = dir.slerp(raised_dir, t)
			ColossusAttack.Phase.ACTIVE:
				var t := a.phase_t()
				t = t * t
				hand = raised_hand.lerp(stuck_hand, t)
				dir = raised_dir.slerp(stuck_dir, t)
			ColossusAttack.Phase.RECOVERY:
				if a.phase_time < stuck_time:
					hand = stuck_hand
					dir = stuck_dir
				else:
					var t := _smooth((a.phase_time - stuck_time) / pull_time)
					hand = stuck_hand.lerp(hand, t)
					dir = stuck_dir.slerp(dir, t)
	if delta > 0.0 and not (a != null and not a.is_done() and a.kind == SWORD_SLAM):
		# Outside the slam the arm settles softly (no snaps when the torso moves).
		hand = _blade_hold.lerp(hand, 1.0 - exp(-6.0 * delta)) if _blade_hold != Vector3.ZERO else hand
		dir = _blade_dir.slerp(dir, 1.0 - exp(-6.0 * delta)).normalized()
	_blade_hold = hand
	_blade_dir = dir.normalized()
	var r := TwoBoneIK.solve(shoulder, hand, 4.2, 4.2, Vector3(-1.0, -0.4, 0.4).normalized())
	var upper: Basis = r.upper
	var lower: Basis = r.lower
	skeleton.set_bone_pose_rotation(_bone[&"upper_arm_r"], (chest_xf.basis.orthonormalized().inverse() * upper).get_rotation_quaternion())
	skeleton.set_bone_pose_rotation(_bone[&"forearm_r"], (upper.inverse() * lower).get_rotation_quaternion())
	# Hand: the sword bone's -Y along the blade, its flat face (+Z) as close to up as it gets.
	var y := -_blade_dir
	var z := (Vector3.UP - y * Vector3.UP.dot(y))
	z = z.normalized() if z.length() > 0.05 else Vector3.BACK
	var hand_basis := Basis(y.cross(z), y, z)
	skeleton.set_bone_pose_rotation(_bone[&"hand_r"], (lower.inverse() * hand_basis).get_rotation_quaternion())


func _debug_extra() -> String:
	return "helmet %s %d/%d  sword %s  slam point %s" % ["BROKEN" if helmet.is_broken else "intact", helmet.hits, helmet.hits_to_break, "STUCK" if sword_stuck() else "held", str(slam_point.snapped(Vector3.ONE * 0.1))]
