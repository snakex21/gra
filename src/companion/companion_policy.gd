class_name CompanionPolicy
extends RefCounted
## Small deterministic fallback. RNG and ordinary fields are checkpointed by WorldSnapshot.

const INTENTS: Array[StringName] = [&"follow", &"hold", &"support", &"evade", &"regroup"]

var rng := RandomNumberGenerator.new()
var decisions := 0
var follow_side := 1.0
var follow_distance := 4.5


func _init(seed_value: int = 48193) -> void:
	rng.seed = seed_value
	follow_side = -1.0 if rng.randf() < 0.5 else 1.0
	follow_distance = rng.randf_range(4.0, 5.5)


func decide(obs: Dictionary) -> StringName:
	decisions += 1
	if bool(obs.get("player_downed", false)) or bool(obs.get("leader_downed", false)):
		return &"hold"
	if bool(obs.get("threat", false)):
		return &"evade"
	if float(obs.get("leader_distance", 0.0)) > 18.0 and not bool(obs.get("leader_climbing", false)):
		return &"regroup"
	if bool(obs.get("enemy_active", false)):
		if float(obs.get("health", 100.0)) < 35.0:
			return &"evade"
		if bool(obs.get("support_available", false)) and rng.randf() < 0.64:
			return &"support"
	if float(obs.get("leader_distance", 0.0)) > 6.5:
		return &"follow"
	return &"hold" if rng.randf() < 0.24 else &"follow"


func decision_interval() -> float:
	return rng.randf_range(4.0, 6.0)


func shot_interval() -> float:
	return rng.randf_range(7.5, 10.0)
