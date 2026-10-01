class_name QuadratusBot
extends Node
## Scripted test driver for the Quadratus fight. It KNOWS the loop and plays it through
## PlayerActions only (like a human or a future AI companion):
##
##   enter (on foot, or on Agro) -> get behind it (dodging telegraphed attacks)
##   -> bow: draw, wait until a hind hoof lifts, lead the moving sole, shoot
##   -> it kneels: (dismount,) sword, run to the lowered thigh, jump and grab the fur
##   -> climb the thigh and the flank onto the back -> crouch on the rump weak point,
##   grip the fur, charge, strike (hold on through shakes) -> along the back and the neck
##   -> onto the head -> crown weak point -> COLOSSUS DEFEATED.
## Thrown off / the knee came up again -> back to the bow. Dead -> wait for the reset.
## Every phase has a timeout, recorded as a stall (never hidden).

signal finished(result: Dictionary)

enum Phase { ENTER, MOUNT, RIDE, POSITION, SHOOT, DISMOUNT, TO_LEG, GRAB_LEG, CLIMB, ON_BACK, CLIMB_HEAD, STRIKE, DESCEND, FALLEN, DEAD, DONE }

const TIMEOUTS := {
	Phase.ENTER: 40.0, Phase.MOUNT: 10.0, Phase.RIDE: 60.0, Phase.POSITION: 40.0, Phase.SHOOT: 40.0,
	Phase.DISMOUNT: 6.0, Phase.TO_LEG: 20.0, Phase.GRAB_LEG: 6.0, Phase.CLIMB: 30.0,
	Phase.ON_BACK: 40.0, Phase.CLIMB_HEAD: 25.0, Phase.STRIKE: 40.0, Phase.DESCEND: 30.0, Phase.FALLEN: 20.0, Phase.DEAD: 30.0,
}

var player: PlayerCharacter
var quadratus: Quadratus
var encounter: BossEncounter
var horse: Horse
## Variant: fight from Agro (ride behind it, shoot from the saddle, dismount to climb).
var use_horse := false
## Distance behind the hind legs to shoot from (m); varied per run by the soak.
var shoot_distance := 13.0
var phase := Phase.ENTER
var phase_time := 0.0
var time := 0.0
var stats := {"falls": 0, "grabs": 0, "strikes": 0, "weak_hits": 0, "rejected": 0, "evades": 0, "stalls": [], "deaths": 0, "death_causes": [], "detours": 0, "max_height": 0.0,
	"shots": 0, "arrow_hits": 0, "arrow_wrong_side": 0, "arrow_disabled": 0, "arrow_surface": 0, "arrow_lost": 0, "buckles_used": 0, "buckles_missed": 0, "shots_from_horse": 0, "mounts": 0, "dismounts": 0}
var events := PackedStringArray()
var verbose := false
var result := {}

var _evading := false
var _blocked := 0.0
var _detour := 0.0
var _detour_side := 1.0
var _last_damage := "none"
var _side := 1.0
var _grab_release := 0
var _jumped := false
var _used_this_buckle := false
var _shot_pending := false


func _ready() -> void:
	# After the colossus (-10) and the horse (-9), before the player (0).
	process_physics_priority = -5


func setup(p_player: PlayerCharacter, p_q: Quadratus, p_encounter: BossEncounter, p_horse: Horse = null) -> void:
	player = p_player
	quadratus = p_q
	encounter = p_encounter
	horse = p_horse
	player.sword.struck.connect(_on_struck)
	player.bow.shot.connect(func(_a: Dictionary) -> void:
		stats.shots += 1
		if player.is_riding():
			stats.shots_from_horse += 1)
	player.hit_taken.connect(func(dmg: float, source: StringName) -> void: _last_damage = "%s %.0f" % [source, dmg])
	player.landed.connect(func(speed: float, _tier: int, dmg: float) -> void:
		if dmg > 0.0:
			_last_damage = "fall %.1f m/s (%.0f, %s)" % [speed, dmg, Phase.keys()[phase]])
	player.died.connect(func() -> void: (func() -> void: stats.death_causes.append(_last_damage)).call_deferred())
	encounter.encounter_reset.connect(func(_n: int) -> void: _enter(Phase.ENTER))
	ArrowSystem.of(player).impact.connect(_on_arrow_impact)
	quadratus.buckle_changed.connect(func(b: Quadratus.Buckle) -> void:
		if b == Quadratus.Buckle.REACT:
			_used_this_buckle = false
		elif b == Quadratus.Buckle.NONE and not _used_this_buckle:
			stats.buckles_missed += 1)


func _physics_process(delta: float) -> void:
	if player == null or phase == Phase.DONE:
		return
	time += delta
	phase_time += delta
	var a := player.actions
	a.move = Vector2.ZERO
	stats.max_height = maxf(stats.max_height, player.global_position.y)
	if quadratus.is_defeated():
		_finish(true, "defeated")
		return
	if player.dead and phase != Phase.DEAD:
		stats.deaths += 1
		_enter(Phase.DEAD)
	if phase_time > float(TIMEOUTS.get(phase, 999.0)):
		_stall()
		return
	var on_body := quadratus.owns_body(player.get_support_body())
	if phase in [Phase.CLIMB, Phase.ON_BACK, Phase.CLIMB_HEAD, Phase.STRIKE, Phase.DESCEND] and not on_body and not player.is_climbing() and player.state == PlayerCharacter.State.GROUND:
		stats.falls += 1
		_log("fell off (%s)" % player.last_release_reason)
		_enter(Phase.FALLEN)
	match phase:
		Phase.ENTER:
			a.grab_held = false
			a.attack_held = false
			if use_horse and is_instance_valid(horse) and not player.is_riding():
				_enter(Phase.MOUNT)
			elif player.is_riding():
				_enter(Phase.RIDE)
			else:
				_enter(Phase.POSITION)
		Phase.MOUNT:
			_mount()
		Phase.RIDE:
			_ride()
		Phase.POSITION:
			_position()
		Phase.SHOOT:
			_shoot()
		Phase.DISMOUNT:
			_dismount()
		Phase.TO_LEG:
			_to_leg()
		Phase.GRAB_LEG:
			_grab_leg()
		Phase.CLIMB:
			_climb()
		Phase.ON_BACK:
			_on_back()
		Phase.CLIMB_HEAD:
			_climb_head()
		Phase.STRIKE:
			_strike()
		Phase.DESCEND:
			_descend()
		Phase.FALLEN:
			a.grab_held = false
			a.attack_held = false
			if player.is_climbing() or on_body and player.state == PlayerCharacter.State.GROUND:
				_reroute()
			elif player.state == PlayerCharacter.State.GROUND and player.balance.state != Balance.State.FALLEN and phase_time > 0.5:
				_after_ground()
		Phase.DEAD:
			a.grab_held = false
			a.attack_held = false


# --- bow -------------------------------------------------------------------------------

## Where to stand: behind the hind legs, a bit to the side of the one to shoot.
func _shoot_spot() -> Vector3:
	var local := Vector3(_side * 3.2, 0, 5.0 + shoot_distance)
	var p := quadratus.global_transform * local
	p.y = player.global_position.y
	return p


func _position() -> void:
	_want_weapon(PlayerCharacter.Weapon.BOW)
	# Keep a drawn bow drawn while moving (letting go would shoot).
	player.actions.attack_held = player.bow.is_aiming()
	player.actions.grab_held = false
	if _kneeling():
		_enter(Phase.TO_LEG)
		return
	if _evade():
		return
	var spot := _shoot_spot()
	var d := _flat(spot - player.global_position).length()
	if d < 2.5:
		_enter(Phase.SHOOT)
		return
	_run_around_to(spot)


func _shoot() -> void:
	var a := player.actions
	a.grab_held = false
	_want_weapon(PlayerCharacter.Weapon.BOW)
	if _kneeling():
		a.attack_held = false
		_enter(Phase.TO_LEG)
		return
	if _evade():
		a.attack_held = false
		return
	# Keep behind it while it turns (it walks round towards us: its hind hooves lift).
	var spot := _shoot_spot()
	var drift := _flat(spot - player.global_position)
	if drift.length() > 5.0:
		a.attack_held = false
		_enter(Phase.POSITION)
		return
	if drift.length() > 1.5 and not player.bow.is_aiming():
		_run_to(spot, 0.6)
	_aim_and_release()


## Draws to full and lets go when a hind sole is (and will stay) exposed. Returns true
## while aiming at something.
func _aim_and_release() -> bool:
	var a := player.actions
	var bow := player.bow
	var shot := _best_shot()
	if shot.is_empty():
		# Nothing to shoot yet: aim roughly at the hind legs, keep the bow drawn.
		var rear := quadratus.global_transform * Vector3(0, 1.5, 5.0)
		_aim_dir((rear - bow.bow_point(player)).normalized())
		a.attack_held = bow.state != PlayerBow.State.RECOVERY and bow.state != PlayerBow.State.RELEASE
		return false
	_aim_dir(shot.dir)
	if bow.state == PlayerBow.State.AIM and shot.ready:
		a.attack_held = false
		_log("shoot %s (lead %.2f s, %.1f m)" % [Quadratus.LEG_NAMES[shot.leg], shot.t, shot.dist])
		return true
	a.attack_held = bow.state != PlayerBow.State.RECOVERY and bow.state != PlayerBow.State.RELEASE
	return true


## The best exposed sole: {leg, dir, t, dist, ready} or {}.
func _best_shot() -> Dictionary:
	var bow := player.bow
	var from := bow.bow_point(player)
	var speed := bow.speed_for(1.0)
	var best := {}
	var dt := get_physics_process_delta_time()
	for t in quadratus.arrow_targets:
		var i := int(t.tag)
		var leg := quadratus.loco.legs[i]
		if leg.phase != LegState.Phase.SWING or leg.scripted or not t.enabled and leg.swing_t > 0.35:
			continue
		var p := t.world_point()
		var v := (p - t.previous_frame() * t.local_point) / dt
		# Lead the moving sole: iterate the flight time.
		var flight := from.distance_to(p) / speed
		var aim := p
		for k in 3:
			aim = p + v * flight
			flight = from.distance_to(aim) / (speed * 0.98)
		var dir := PlayerBow.launch_direction(from, aim, speed)
		if dir == Vector3.ZERO:
			continue
		# Comes in against the sole and nothing solid in between?
		var facing := dir.dot(-t.world_normal())
		var ready := t.enabled and leg.swing_t < 0.62 and facing > 0.3 and _clear_line(from, aim)
		var score := facing - flight
		if best.is_empty() or score > best.score:
			best = {"leg": i, "dir": dir, "t": flight, "dist": from.distance_to(aim), "ready": ready, "score": score}
	return best


func _clear_line(from: Vector3, to: Vector3) -> bool:
	var space := player.get_world_3d().direct_space_state
	var exclude: Array[RID] = [player.get_rid()]
	if player.is_riding():
		exclude.append(player.riding.horse.get_rid())
	var hit := ClimbQuery.ray(space, from, to.lerp(from, 0.06), exclude, Layers.WORLD | Layers.COLOSSUS, &"bot_rays")
	return hit.is_empty()


func _aim_dir(dir: Vector3) -> void:
	var a := player.actions
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.FORWARD
	a.view_basis = Basis.looking_at(dir, up)
	# Aim ray from the bow itself: what the bot computes is exactly what is shot.
	a.aim_origin = player.bow.bow_point(player)


func _on_arrow_impact(info: Dictionary) -> void:
	var arrow: Dictionary = info.arrow
	if arrow.owner != player:
		return
	match info.reason:
		&"hit":
			stats.arrow_hits += 1
			_log("ARROW HIT %s" % Quadratus.LEG_NAMES[int(info.tag)])
		&"wrong_side":
			stats.arrow_wrong_side += 1
		&"disabled":
			stats.arrow_disabled += 1
		_:
			stats.arrow_surface += 1


# --- horse -----------------------------------------------------------------------------

func _mount() -> void:
	var a := player.actions
	if player.is_riding():
		if player.riding.phase == PlayerRiding.Phase.RIDING:
			stats.mounts += 1
			_enter(Phase.RIDE)
		return
	var seat := horse.saddle_transform().origin
	if _flat(seat - player.global_position).length() < 2.2:
		a.press_interact()
	else:
		_run_to(seat)


func _ride() -> void:
	var a := player.actions
	if not player.is_riding():
		_enter(Phase.POSITION)
		return
	_want_weapon(PlayerCharacter.Weapon.BOW)
	if _kneeling():
		a.attack_held = false
		_enter(Phase.DISMOUNT)
		return
	# Ride a wide circle behind it; shoot from the saddle when a sole shows.
	var behind := quadratus.global_transform * Vector3(_side * 6.0, 0, 5.0 + shoot_distance + 6.0)
	var to := _flat(behind - player.global_position)
	# Draw only once in bow range (a drawn bow slows the ride: the stick steers the horse).
	var aiming := false
	if _flat(quadratus.global_position - player.global_position).length() < 40.0:
		aiming = _aim_and_release() or player.bow.is_aiming()
	else:
		a.attack_held = false
	var c := horse.controller
	if aiming:
		# Horse-relative steering while aiming: keep the heading, a gentle turn back
		# towards the spot behind it if we drift off.
		var ang := c.forward().signed_angle_to(to.normalized(), Vector3.UP) if to.length() > 1.0 else 0.0
		a.move = Vector2(clampf(-ang, -0.6, 0.6), 0.0)
		if to.length() < 6.0:
			a.grab_held = true   # reins: slow down near the spot
		else:
			a.grab_held = false
		return
	a.grab_held = to.length() < 4.0
	if to.length() > 2.0:
		_look(to)
		a.move = Vector2(0, 1)
		if c.speed < 3.0 and int(phase_time * 60.0) % 40 == 0:
			a.press_jump()   # kick up to a trot


func _dismount() -> void:
	var a := player.actions
	a.attack_held = false
	if not player.is_riding():
		stats.dismounts += 1
		_enter(Phase.TO_LEG)
		return
	if not _kneeling():
		_enter(Phase.RIDE)
		return
	var leg_spot := _thigh_entry()
	var to := _flat(leg_spot - player.global_position)
	if to.length() > 30.0:
		# Far: ride closer at a trot or faster (on foot is 5.5 m/s).
		_look(to)
		a.move = Vector2(0, 1)
		a.grab_held = false
		if horse.controller.speed < 4.0 and int(phase_time * 60.0) % 30 == 0:
			a.press_jump()
	else:
		a.grab_held = true
		if horse.controller.speed < 1.5 and int(phase_time * 60.0) % 20 == 0:
			a.press_interact()


# --- climbing ---------------------------------------------------------------------------

func _kneeling() -> bool:
	return quadratus.buckle == Quadratus.Buckle.KNEEL or (quadratus.buckle == Quadratus.Buckle.REACT and quadratus.buckle_t > 0.6)


## Ground point beside the lowered thigh (outside of the leg).
func _thigh_entry() -> Vector3:
	var i := maxi(quadratus.buckle_leg, 2)
	var seg: BodySegment = quadratus._seg_by_bone[quadratus.leg_bones[i][0]]
	var side := -1.0 if i == 2 else 1.0
	var p := seg.target_transform * Vector3(0, -2.4, 0) + quadratus.global_basis.x * side * 1.6 + quadratus.global_basis.z * 0.8
	p.y = quadratus.loco.legs[i].plant_pos.y + 0.95
	return p


func _to_leg() -> void:
	var a := player.actions
	a.attack_held = false
	a.grab_held = false
	if player.is_riding():
		_enter(Phase.DISMOUNT)
		return
	_want_weapon(PlayerCharacter.Weapon.SWORD)
	if not _kneeling():
		_enter(Phase.POSITION)
		return
	var entry := _thigh_entry()
	if _flat(entry - player.global_position).length() < 1.0:
		_enter(Phase.GRAB_LEG)
		return
	_run_around_to(entry)


func _grab_leg() -> void:
	var a := player.actions
	if not _kneeling() and not player.is_climbing():
		_enter(Phase.POSITION)
		return
	var i := maxi(quadratus.buckle_leg, 2)
	var seg: BodySegment = quadratus._seg_by_bone[quadratus.leg_bones[i][0]]
	var center := seg.target_transform * Vector3(0, -1.6, 0)
	_look(center - player.global_position)
	a.move = Vector2(0, 0.5)
	a.grab_held = phase_time > 0.05
	if not _jumped and phase_time > 0.15 and player.state == PlayerCharacter.State.GROUND:
		a.press_jump()
		_jumped = true
	if player.is_climbing():
		stats.grabs += 1
		_used_this_buckle = true
		stats.buckles_used += 1
		_log("grabbed %s" % _grip_bone())
		_enter(Phase.CLIMB)
	elif phase_time > 1.6:
		_enter(Phase.TO_LEG)


func _climb() -> void:
	var a := player.actions
	a.grab_held = true
	_look(quadratus.get_focus_point() - player.global_position)
	if not player.is_climbing():
		if player.state != PlayerCharacter.State.AIR and quadratus.region_of(player) != &"":
			_reroute()
		return
	var bone := _grip_bone()
	if bone in [&"neck", &"head"]:
		_enter(Phase.CLIMB_HEAD)
		return
	if bone == &"body" and player.grip.world_normal().y > 0.7:
		# Over the edge onto the back's fur: crawl on from here (never let go on an edge).
		_enter(Phase.ON_BACK)
		return
	a.move = Vector2.ZERO if _hold_on() else Vector2(0, 1)


func _target_wp() -> WeakPoint:
	return quadratus.rump if quadratus.rump.state != WeakPoint.State.DESTROYED else quadratus.crown


func _on_back() -> void:
	var a := player.actions
	_want_weapon(PlayerCharacter.Weapon.SWORD)
	if _crown_closed():
		_enter(Phase.DESCEND)
		return
	if player.is_climbing():
		var bone := _grip_bone()
		if _grip_near_wp():
			_enter(Phase.STRIKE)
			return
		if bone in [&"head", &"neck"] and _target_wp() == quadratus.crown:
			_enter(Phase.CLIMB_HEAD)
			return
		a.grab_held = true
		if player.grip.world_normal().y < 0.6 and bone == &"body":
			# Hanging on a side (thrown off the top, a rescue grip): climb up again.
			a.move = Vector2.ZERO if _hold_on() else Vector2(0, 1)
			_look(quadratus.get_focus_point() - player.global_position)
			return
		# On the fur: to the rump weak point crawl (gripping); to the crown stand up on the
		# middle of the back and walk (crawling all of it does not fit in a kneel).
		if not _hold_on():
			if _target_wp() == quadratus.crown and bone == &"body":
				var local := (player.grip.body as BodySegment).target_transform.affine_inverse() * player.grip.world_point()
				if absf(local.x) < 1.8:
					a.grab_held = false
					return
				_look((player.grip.body as BodySegment).target_transform * Vector3(0, 2.0, local.z) - player.grip.world_point())
			else:
				_look(_target_wp().world_point() - player.grip.world_point())
			a.move = Vector2(0, 1)
		return
	var wp := _target_wp()
	var target := wp.world_point()
	var shaking := _hold_on()
	if shaking:
		# Crouch and grip the fur under the feet until it calms down.
		_grab_release += 1
		a.grab_held = _grab_release % 10 > 2
		return
	if wp == quadratus.crown:
		# Along the middle of the back, over the saddle, to the neck, then reach for the
		# fur on the back of the head.
		var body := quadratus._seg_by_bone[&"body"] as BodySegment
		var local := body.target_transform.affine_inverse() * player.global_position
		var goal := body.target_transform * Vector3(0, 2.5, -5.4)
		if local.z > 1.0:
			goal = body.target_transform * Vector3(0, 2.5, -1.0)
		if quadratus.region_of(player) == &"neck" or local.z < -5.0:
			_look(quadratus.crown.world_point() - player.global_position)
			a.move = Vector2(0, 0.5)
			_grab_release += 1
			a.grab_held = _grab_release % 24 > 4
			return
		a.grab_held = false
		_run_to(goal, 0.8)
		return
	a.grab_held = false
	var d := _flat(target - player.global_position)
	if d.length() > 0.7:
		_run_to(target, 0.6)
	elif player.stamina.ratio() < 0.9:
		# Standing on it between shakes: catch breath first.
		a.grab_held = false
	else:
		_grab_release += 1
		a.grab_held = _grab_release % 10 > 2


## Rump done, crown shut and it is standing: off the back, down a hind leg, bow again.
func _crown_closed() -> bool:
	return quadratus.rump.state == WeakPoint.State.DESTROYED and quadratus.crown.state == WeakPoint.State.PROTECTED and quadratus.buckle == Quadratus.Buckle.NONE


func _descend() -> void:
	var a := player.actions
	if not _crown_closed() and quadratus.buckle != Quadratus.Buckle.NONE:
		_reroute()
		return
	var body := quadratus._seg_by_bone[&"body"] as BodySegment
	var side := 1.0 if (body.target_transform.affine_inverse() * player.global_position).x >= 0.0 else -1.0
	if not player.is_climbing():
		# Walk / crouch-grip to the edge over a hind haunch, then hang on over the side.
		var edge := body.target_transform * Vector3(side * 3.3, 1.9, 4.8)
		_look(edge - player.global_position)
		a.move = Vector2(0, 0.6)
		a.grab_held = _hold_on() or _flat(edge - player.global_position).length() < 1.2
		return
	a.grab_held = true
	if _hold_on():
		return
	var bone := _grip_bone()
	if bone in [&"neck", &"head"]:
		# On the front: drop onto the back and walk to the rump from there.
		a.grab_held = false
		return
	# Down the haunch and the thigh; at the stone knee let go (a short drop).
	if player.global_position.y - quadratus.global_position.y < 6.5:
		a.grab_held = false
		return
	_look(quadratus.get_focus_point() - player.global_position)
	a.move = Vector2(0, -1)


func _climb_head() -> void:
	var a := player.actions
	a.grab_held = true
	if _crown_closed():
		_enter(Phase.DESCEND)
		return
	_look(quadratus.crown.world_point() - player.global_position)
	if not player.is_climbing():
		if player.state != PlayerCharacter.State.AIR and quadratus.region_of(player) != &"":
			_reroute()
		return
	if _grip_near_wp():
		_enter(Phase.STRIKE)
		return
	if _grip_bone() == &"head" and player.grip.world_normal().y > 0.7:
		# On the head top: crawl to the crown.
		var to := quadratus.crown.world_point() - player.grip.world_point()
		_look(to)
		a.move = Vector2(0, 0.7)
		return
	a.move = Vector2.ZERO if _hold_on() else Vector2(0, 1)


func _grip_near_wp() -> bool:
	if not player.is_climbing():
		return false
	var wp := _target_wp()
	return wp.state == WeakPoint.State.OPEN and player.grip.world_point().distance_to(wp.world_point()) < 1.4


func _strike() -> void:
	var a := player.actions
	a.grab_held = true
	_want_weapon(PlayerCharacter.Weapon.SWORD)
	if not player.is_climbing():
		a.attack_held = false
		_reroute()
		return
	var sw := player.sword
	var wp := _target_wp()
	if _crown_closed():
		a.attack_held = false
		_enter(Phase.DESCEND)
		return
	if wp.state == WeakPoint.State.DESTROYED:
		a.attack_held = false
		_reroute()
		return
	var hand := player.grip.world_point()
	var to := wp.world_point() - hand
	to -= player.grip.world_normal() * to.dot(player.grip.world_normal())
	var in_reach := player.grip.world_point().distance_to(wp.world_point()) < 0.9 * wp.radius
	if to.length() > 0.6 and sw.state == PlayerSword.State.READY and not _hold_on() and not (in_reach and phase_time > 2.0):
		_look(to)
		a.move = Vector2(0, 0.7)
		a.attack_held = false
		return
	if player.stamina.ratio() < 0.25 and not _hold_on() and sw.state == PlayerSword.State.READY:
		# Tired and calm: let go and stand on the back to recover.
		a.grab_held = false
		a.attack_held = false
		_enter(Phase.ON_BACK)
		return
	if _hold_on() and sw.state != PlayerSword.State.CHARGE:
		a.attack_held = false
		return
	match sw.state:
		PlayerSword.State.READY:
			a.attack_held = true
		PlayerSword.State.CHARGE:
			a.attack_held = sw.charge < 1.0
		_:
			a.attack_held = false


# --- helpers -----------------------------------------------------------------------------

func _reroute() -> void:
	if player.is_climbing():
		var bone := _grip_bone()
		if _grip_near_wp():
			_enter(Phase.STRIKE)
		elif bone in [&"neck", &"head"]:
			_enter(Phase.CLIMB_HEAD)
		elif bone == &"body" and player.grip.world_normal().y > 0.6:
			_enter(Phase.ON_BACK)
		else:
			_enter(Phase.CLIMB)
		return
	if quadratus.region_of(player) in [&"rump", &"back", &"neck", &"head"]:
		_enter(Phase.DESCEND if _crown_closed() else Phase.ON_BACK)
		return
	if phase != Phase.FALLEN:
		stats.falls += 1
		_log("off the route (%s)" % player.last_release_reason)
	if player.state == PlayerCharacter.State.GROUND:
		_after_ground()
	else:
		_enter(Phase.FALLEN)


func _after_ground() -> void:
	if _kneeling() and quadratus.buckle_t < quadratus.kneel_time - 3.0:
		_enter(Phase.TO_LEG)
	elif use_horse and is_instance_valid(horse) and horse.global_position.distance_to(player.global_position) < 25.0:
		_enter(Phase.MOUNT)
	else:
		_enter(Phase.POSITION)


func _want_weapon(w: PlayerCharacter.Weapon) -> void:
	if player.weapon != w:
		player.set_weapon(w)


func _hold_on() -> bool:
	var k := quadratus.intent.kind
	return k in quadratus._shake_kinds() or k == Quadratus.RECOVER or quadratus._stagger > 0.2 or quadratus._shake > 0.1 or player.shake_level > 0.35


func _evade() -> bool:
	for z in quadratus.get_danger_zones():
		var c: Vector3 = z[0]
		var r: float = float(z[1]) + 1.5
		var off := _flat(player.global_position - c)
		if off.length() < r:
			if not _evading:
				stats.evades += 1
				_log("evade %s" % quadratus.attack.kind)
			_evading = true
			var away := off.normalized() if off.length() > 0.2 else _flat(player.global_position - quadratus.global_position).normalized()
			_run_to(player.global_position + away * 5.0)
			return true
	_evading = false
	return false


## Runs to ``target`` going round the colossus' body, not under it.
func _run_around_to(target: Vector3) -> void:
	var inv := quadratus.global_transform.affine_inverse()
	var me := inv * player.global_position
	var goal := inv * target
	# Box around the legs and body (local x +-6, z -11..+9): pass on the outside.
	var inside_x := absf(me.x) < 6.5
	var crosses := (me.z < -9.0 and goal.z > -9.0) or (me.z > 7.0 and goal.z < 7.0) or (inside_x and me.z > -11.0 and me.z < 9.0)
	if crosses and absf(me.x) < 7.5 and _flat(target - player.global_position).length() > 3.0:
		var side := signf(me.x) if absf(me.x) > 0.5 else _side
		var via := Vector3(side * 9.0, 0, clampf(goal.z, -10.0, 10.0))
		var w := quadratus.global_transform * via
		w.y = player.global_position.y
		_run_to(w)
		return
	_run_to(target)


func _run_to(target: Vector3, speed := 1.0) -> void:
	var d := _flat(target - player.global_position)
	if d.length() < 0.05:
		return
	var dt := get_physics_process_delta_time()
	var moving := _flat(player.velocity).length() > 0.6
	if player.state == PlayerCharacter.State.GROUND and not moving and _detour <= 0.0:
		_blocked += dt
		if _blocked > 0.6:
			_detour = 1.0
			_detour_side = -_detour_side
			_blocked = 0.0
			stats.detours += 1
	else:
		_blocked = 0.0
	if _detour > 0.0:
		_detour -= dt
		d = d.rotated(Vector3.UP, _detour_side * PI * 0.5)
	_look(d)
	player.actions.move = Vector2(0, clampf(speed * d.length() / 0.6, 0.25, 1.0) if speed < 1.0 else 1.0)


func _look(dir: Vector3) -> void:
	var d := _flat(dir)
	if d.length() > 0.01:
		player.actions.view_basis = Basis.looking_at(d.normalized())
		player.actions.aim_origin = Vector3.INF


func _grip_bone() -> StringName:
	if player.grip and player.grip.body is BodySegment:
		return (player.grip.body as BodySegment).bone_name
	return &""


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _enter(p: Phase) -> void:
	if p == phase:
		return
	_log("%s -> %s" % [Phase.keys()[phase], Phase.keys()[p]])
	phase = p
	phase_time = 0.0
	_grab_release = 0
	_jumped = false
	if player.weapon == PlayerCharacter.Weapon.SWORD:
		player.actions.attack_held = false
	if p == Phase.POSITION:
		# Shoot at the hind leg on our side.
		var local := quadratus.global_transform.affine_inverse() * player.global_position
		_side = -1.0 if local.x < 0.0 else 1.0


func _stall() -> void:
	var what: String = Phase.keys()[phase]
	stats.stalls.append(what)
	_log("STALL in %s (%.0f s)" % [what, phase_time])
	phase_time = 0.0
	match phase:
		Phase.DEAD:
			_finish(false, "dead, no reset")
		Phase.CLIMB, Phase.ON_BACK, Phase.CLIMB_HEAD, Phase.STRIKE:
			_reroute()
		Phase.SHOOT, Phase.POSITION:
			_side = -_side
			_enter(Phase.POSITION)
		Phase.RIDE, Phase.MOUNT:
			use_horse = false
			_enter(Phase.DISMOUNT if player.is_riding() else Phase.POSITION)
		_:
			_after_ground()


func _on_struck(r: Dictionary) -> void:
	stats.strikes += 1
	if r.get("accepted", false):
		stats.weak_hits += 1
		_log("weak point hit %.0f (charge %.2f)" % [r.damage, r.power])
	else:
		stats.rejected += 1
		_log("strike rejected: %s" % r.reason)


func _finish(won: bool, why: String) -> void:
	result = {"won": won, "why": why, "time": time, "stats": stats.duplicate(true), "boss": quadratus.stats.duplicate(true), "resets": encounter.resets, "variant": "horse" if use_horse else "foot"}
	_log("FINISHED %s (%s) after %.1f s" % ["WIN" if won else "LOSS", why, time])
	phase = Phase.DONE
	player.actions.move = Vector2.ZERO
	player.actions.attack_held = false
	finished.emit(result)


func _log(s: String) -> void:
	var line := "[%6.1f] %s" % [time, s]
	events.append(line)
	if verbose:
		print(line)
