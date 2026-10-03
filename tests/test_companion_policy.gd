extends Node

const Policy := preload("res://src/companion/companion_policy.gd")
var failures := 0


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _ready() -> void:
	var first := Policy.new(733)
	var second := Policy.new(733)
	var other := Policy.new(734)
	var obs := {"health": 90.0, "enemy_active": true, "support_available": true, "leader_distance": 4.0}
	var a: Array = []
	var b: Array = []
	var c: Array = []
	for i in 64:
		a.append([first.decide(obs), first.decision_interval(), first.shot_interval()])
		b.append([second.decide(obs), second.decision_interval(), second.shot_interval()])
		c.append([other.decide(obs), other.decision_interval(), other.shot_interval()])
	check(a == b, "Same companion seed diverged")
	check(a != c, "Different companion seeds produced identical behavior")
	for choice in a:
		check(choice[0] in Policy.INTENTS and choice[1] >= 4.0 and choice[1] <= 6.0 and choice[2] >= 7.5, "Unbounded or unknown fallback decision")
	check(first.decide({"threat": true}) == &"evade", "Fallback ignored a telegraphed threat")
	check(first.decide({"leader_distance": 45.0}) == &"regroup", "Fallback did not regroup with a distant host")
	check(first.decide({"leader_downed": true}) == &"hold", "Fallback acted while the leader was downed")
	check(first.decide({"leader_distance": 40.0, "leader_climbing": true, "enemy_active": true, "support_available": true}) != &"regroup", "Fallback mistook the host's climbing height for losing the host")
	# Exercise the actual generic codec, including script allocation and RNG state.
	var codec := WorldSnapshot.new()
	var reference: Variant = codec._encode(first)
	codec.objects = bytes_to_var(var_to_bytes(codec.objects))
	for object: Dictionary in codec.objects:
		codec.decoded.append(RandomNumberGenerator.new() if object.get("rng", false) else load(object.script).new())
	for i in codec.objects.size():
		var object: Dictionary = codec.objects[i]
		if object.get("rng", false):
			codec.decoded[i].seed = object.seed
			codec.decoded[i].state = object.state
		else:
			codec._apply_fields(codec.decoded[i], object.fields)
	var restored: Variant = codec._decode(reference)
	check(restored.follow_side == first.follow_side and restored.follow_distance == first.follow_distance and restored.decisions == first.decisions, "Codec lost companion preferences/counters")
	for i in 64:
		check(restored.decide(obs) == first.decide(obs) and restored.decision_interval() == first.decision_interval() and restored.shot_interval() == first.shot_interval(), "Policy RNG diverged after binary generic checkpoint")
	print("COMPANION_POLICY failures=%d; seeded variety, bounds, safety, real binary codec RNG continuation" % failures)
	get_tree().quit(1 if failures else 0)
