class_name WormMineralPlate
extends ArmorPlate
## Brittle mineral armour accepts charged steel or a real fast arrow.
var enabled := false
var arrow_target: ArrowTarget
var sword_hits := 0
var arrow_hits := 0
signal mineral_hit(source: StringName)

func try_hit(at: Vector3, power: float, source: StringName) -> Dictionary:
	if not enabled:
		return {"accepted": false, "reason": &"buried", "damage": 0.0}
	var result := super(at, power, &"sword" if source == &"arrow" else source)
	if result.accepted:
		if source == &"arrow": arrow_hits += 1
		else: sword_hits += 1
		mineral_hit.emit(source)
	return result

func connect_arrow() -> void:
	arrow_target = ArrowTarget.create(segment, local_point + Vector3.BACK * 0.3, Vector3.BACK, radius, &"worm_mineral")
	arrow_target.max_incidence_deg = 110.0
	arrow_target.hit.connect(func(info: Dictionary) -> void:
		var speed: float = (info.arrow.vel as Vector3).length()
		try_hit(world_point(), clampf((speed - 22.0) / 36.0, 0, 1), &"arrow"))

func reset() -> void:
	super()
	sword_hits = 0
	arrow_hits = 0
