class_name CompanionController
extends Node
## Optional ground companion. All gameplay input goes through PlayerActions.
## Place inside GameWorld.region so the generic checkpoint captures this controller,
## its actor reference, timers, accepted decision and policy RNG. GameWorld is found
## through ancestors instead of recording a reference outside the simulation root.

const Policy := preload("res://src/companion/companion_policy.gd")
const NAV_INTERVAL := 0.1
const MODEL_TTL := 6.0
const PROBE_DISTANCE := 2.1
const MAX_ZONES := 16

var actor: PlayerCharacter
var policy := Policy.new()
var mode: StringName = &"programmed"
## Replay owns the whole frame: return without clearing, writing or advancing RNG.
var external_drive := false
var intent: StringName = &"follow"
var accepted_intent: StringName = &""
var accepted_left := 0.0
var decision_left := 0.0
var navigation_left := 0.0
var shot_left := 3.0
var draw_left := 0.0
var navigation_updates := 0
var navigation_rays := 0
var ground_safe := false
var near_cliff := false
var navigation_blocked := false
var threat := false
var support_available := false
var _nav_direction := Vector3.ZERO
var _nav_speed := 0.0
var _evade_direction := Vector3.ZERO
var _aim_direction := Vector3.ZERO
var _zones: Array = []
var _detour_direction := Vector3.ZERO
var _detour_left := 0.0


func setup(_game: GameWorld, p_actor: PlayerCharacter, seed_value: int) -> void:
	actor = p_actor
	policy = Policy.new(seed_value)
	process_physics_priority = -10
	intent = &"follow"
	accepted_intent = &""
	accepted_left = 0.0
	decision_left = 0.0
	navigation_left = 0.0
	shot_left = 3.0
	draw_left = 0.0
	_nav_direction = Vector3.ZERO
	_nav_speed = 0.0
	_detour_direction = Vector3.ZERO
	_detour_left = 0.0


func _ready() -> void:
	process_physics_priority = -10


func allowed_intents() -> Array[StringName]:
	return Policy.INTENTS.duplicate()


func accept_decision(value: StringName) -> void:
	if external_drive or value not in Policy.INTENTS:
		return
	accepted_intent = value
	accepted_left = MODEL_TTL
	# Respect the navigation rate even when an asynchronous model reply arrives.


func observation() -> Dictionary:
	var game := _world()
	var leader: PlayerCharacter = game.player() if game else null
	var boss: Colossus = game.colossus() if game else null
	var alive_actor := is_instance_valid(actor)
	var alive_leader := is_instance_valid(leader)
	var enemy_active := is_instance_valid(boss) and not boss.is_defeated()
	return {
		"health": actor.health if alive_actor else 0.0,
		"stamina": actor.stamina.ratio() if alive_actor else 0.0,
		"leader_distance": actor.global_position.distance_to(leader.global_position) if alive_actor and alive_leader else -1.0,
		"enemy_distance": actor.global_position.distance_to(boss.global_position) if alive_actor and enemy_active else -1.0,
		"threat": threat,
		"enemy_active": enemy_active,
		"leader_climbing": leader.is_climbing() if alive_leader else false,
		"support_available": support_available,
		"near_cliff": near_cliff,
		"mounted": actor.is_riding() if alive_actor else false,
		"player_downed": not alive_actor or actor.dead,
		"leader_downed": not alive_leader or leader.dead,
		"ground_safe": ground_safe,
		"navigation_blocked": navigation_blocked,
		"intent": String(intent),
	}


func _physics_process(delta: float) -> void:
	if external_drive:
		return
	if not is_instance_valid(actor):
		return
	actor.actions.clear()
	actor.actions.aim_origin = Vector3.INF
	var game := _world()
	var leader: PlayerCharacter = game.player() if game else null
	if not game or game.region_kind == &"" or game.phase != GameWorld.Phase.PLAYING or mode not in [&"programmed", &"local_model"] or actor.dead or not is_instance_valid(leader) or leader.dead:
		_nav_speed = 0.0
		draw_left = 0.0
		return
	accepted_left = maxf(0.0, accepted_left - delta)
	decision_left -= delta
	shot_left = maxf(0.0, shot_left - delta)
	navigation_left -= delta
	if navigation_left <= 0.000001:
		# Never catch up with a burst of physics queries after a slow frame.
		navigation_left = NAV_INTERVAL
		_update_navigation(game, leader)
	if decision_left <= 0.0:
		intent = policy.decide(observation())
		decision_left = policy.decision_interval()
	if mode == &"local_model" and accepted_left > 0.0:
		intent = accepted_intent
	# Safety takes precedence over either policy; no model can override it.
	if threat:
		intent = &"evade"
	elif _flat(actor.global_position - leader.global_position).length() > 22.0:
		intent = &"regroup"
	if actor.state not in [PlayerCharacter.State.GROUND, PlayerCharacter.State.AIR]:
		# No mount calls, climbing autopilot, underwater diving or forced dismount.
		draw_left = 0.0
		return
	if _nav_speed > 0.0 and _nav_direction.length_squared() > 0.01:
		actor.actions.view_basis = Basis.looking_at(_nav_direction)
		actor.actions.move = Vector2(0.0, _nav_speed)
	var shooting := draw_left > 0.0
	if support_available and not threat and intent == &"support" and shot_left <= 0.0 and actor.state == PlayerCharacter.State.GROUND:
		if actor.weapon != PlayerCharacter.Weapon.BOW:
			actor.actions.press_switch_weapon()
		else:
			draw_left = actor.bow.draw_time + 0.08
			shot_left = policy.shot_interval()
			shooting = true
	if shooting and support_available and not threat and _aim_direction.length_squared() > 0.01:
		actor.actions.move = Vector2.ZERO
		actor.actions.view_basis = Basis.looking_at(_aim_direction)
		actor.actions.aim_origin = actor.bow.bow_point(actor)
		actor.actions.attack_held = true
		draw_left = maxf(0.0, draw_left - delta)
	elif shooting:
		# Put the bow away through the regular action, cancelling an unsafe draw.
		if actor.weapon == PlayerCharacter.Weapon.BOW and actor.bow.is_aiming():
			actor.actions.press_switch_weapon()
		draw_left = 0.0
	elif actor.weapon == PlayerCharacter.Weapon.BOW and actor.bow.is_aiming():
		# Keep the aim for the release frame; movement must not turn the arrow sideways.
		if support_available and not threat and _aim_direction.length_squared() > 0.01:
			actor.actions.view_basis = Basis.looking_at(_aim_direction)
			actor.actions.aim_origin = actor.bow.bow_point(actor)
		else:
			actor.actions.press_switch_weapon()


func _update_navigation(game: GameWorld, leader: PlayerCharacter) -> void:
	navigation_updates += 1
	_detour_left = maxf(0.0, _detour_left - NAV_INTERVAL)
	var boss := game.colossus()
	_zones.clear()
	if is_instance_valid(boss) and not boss.is_defeated() and boss.has_method(&"get_danger_zones"):
		var zones: Array = boss.call(&"get_danger_zones")
		for i in mini(MAX_ZONES, zones.size()):
			_zones.append(zones[i])
	threat = false
	_evade_direction = Vector3.ZERO
	for zone in _zones:
		if not zone is Array or zone.size() < 2:
			continue
		var away := _flat(actor.global_position - (zone[0] as Vector3))
		if away.length() < float(zone[1]) + 1.4:
			threat = true
			_evade_direction += away.normalized() if away.length() > 0.1 else _flat(actor.global_position - boss.global_position).normalized()
	if threat and _evade_direction.length_squared() < 0.01:
		_evade_direction = _flat(leader.facing).normalized()
	var leader_direction := _flat(leader.velocity).normalized()
	if leader_direction.length_squared() < 0.01:
		leader_direction = _flat(leader.facing).normalized()
	if leader_direction.length_squared() < 0.01:
		leader_direction = Vector3.FORWARD
	var side := leader_direction.cross(Vector3.UP) * policy.follow_side
	var target := leader.global_position - leader_direction * policy.follow_distance + side * 2.0
	var effective := accepted_intent if mode == &"local_model" and accepted_left > 0.0 else intent
	if _flat(actor.global_position - leader.global_position).length() > 22.0:
		effective = &"regroup"
	if threat:
		target = actor.global_position + _evade_direction.normalized() * 6.0
	elif effective == &"evade" and is_instance_valid(boss) and not boss.is_defeated():
		var away := _flat(actor.global_position - boss.global_position).normalized()
		target = actor.global_position + away * 5.0
	elif effective == &"support" and is_instance_valid(boss) and not boss.is_defeated():
		# Stay beside the host, outside stomping range; never approach a weak point.
		var away := _flat(leader.global_position - boss.global_position).normalized()
		target = leader.global_position + away * 6.0 + side * 4.0
	elif effective == &"hold":
		target = actor.global_position
	var toward := _flat(target - actor.global_position)
	_nav_speed = 0.0
	_nav_direction = Vector3.ZERO
	navigation_blocked = false
	near_cliff = false
	ground_safe = _floor_safe(actor.global_position)
	if toward.length() > 1.5 and ground_safe:
		var desired := toward.normalized()
		# Commit briefly to a chosen side instead of oscillating against a wall.
		if _detour_left > 0.0 and not threat and _direction_safe(_detour_direction):
			_nav_direction = _detour_direction
		elif _direction_safe(desired):
			_nav_direction = desired
		else:
			for angle in [65.0 * policy.follow_side, -65.0 * policy.follow_side, 100.0 * policy.follow_side, -100.0 * policy.follow_side]:
				var candidate := desired.rotated(Vector3.UP, deg_to_rad(angle))
				if _direction_safe(candidate):
					_nav_direction = candidate
					_detour_direction = candidate
					_detour_left = 1.1
					break
		navigation_blocked = _nav_direction == Vector3.ZERO
		if not navigation_blocked:
			_nav_speed = clampf((toward.length() - 1.0) / 3.0, 0.25, 1.0)
	support_available = false
	_aim_direction = Vector3.ZERO
	if ground_safe and not threat and is_instance_valid(boss) and not boss.is_defeated() and actor.state == PlayerCharacter.State.GROUND:
		var target_point := boss.get_focus_point()
		var origin := actor.global_position + Vector3.UP * 0.55
		var distance := origin.distance_to(target_point)
		if distance >= 12.0 and distance <= 80.0 and _flat(actor.global_position - leader.global_position).length() <= 24.0:
			var hit := _ray(origin, target_point, Layers.WORLD | Layers.COLOSSUS)
			# A clear line or the boss' own segment are both legitimate targets.
			var clear := hit.is_empty() or boss.owns_body(hit.get("collider"))
			if clear:
				_aim_direction = PlayerBow.launch_direction(origin, target_point, actor.bow.max_speed)
				support_available = _aim_direction.length_squared() > 0.01


func _direction_safe(direction: Vector3) -> bool:
	var ahead := actor.global_position + direction * PROBE_DISTANCE
	var right := direction.cross(Vector3.UP) * 0.42
	if not _floor_safe(ahead) or not _floor_safe(ahead + right) or not _floor_safe(ahead - right):
		near_cliff = true
		return false
	for offset in [Vector3.ZERO, right, -right]:
		var start: Vector3 = actor.global_position + offset + Vector3.UP * 0.1
		if not _ray(start, start + direction * PROBE_DISTANCE, Layers.SOLID).is_empty():
			return false
	for zone in _zones:
		if zone is Array and zone.size() >= 2:
			var center := zone[0] as Vector3
			var radius := float(zone[1]) + 1.0
			var current_distance := _flat(actor.global_position - center).length()
			var next_distance := _flat(ahead - center).length()
			if next_distance < radius and next_distance < current_distance:
				return false
	return true


func _floor_safe(point: Vector3) -> bool:
	var hit := _ray(point + Vector3.UP * 0.4, point + Vector3.DOWN * 2.3, Layers.WORLD)
	if hit.is_empty():
		return false
	return (hit.normal as Vector3).y >= 0.66 and (hit.position as Vector3).y >= actor.global_position.y - 1.35


func _ray(from: Vector3, to: Vector3, mask: int) -> Dictionary:
	navigation_rays += 1
	var exclude: Array[RID] = [actor.get_rid()]
	return ClimbQuery.ray(actor.get_world_3d().direct_space_state, from, to, exclude, mask, &"companion_navigation_rays")


func _world() -> GameWorld:
	var node := get_parent()
	for _depth in 4:
		if node is GameWorld:
			return node
		if node == null:
			return null
		node = node.get_parent()
	return null


static func _flat(value: Vector3) -> Vector3:
	return Vector3(value.x, 0.0, value.z)
