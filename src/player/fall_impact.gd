class_name FallImpact
extends RefCounted
## Landing consequences from the impact speed along the surface normal (relative to the
## surface, so landing on a moving colossus counts the relative speed).
## Simple on purpose: one health value, three tiers.
##   < safe_speed            nothing           (~2.3 m drop)
##   < hard_speed            stagger + damage  (~5 m drop)
##   >= hard_speed           knocked down + heavy damage, can be fatal above lethal_speed

enum Tier { NONE, HARD, SEVERE }

var safe_speed := 10.0
var hard_speed := 15.5
var lethal_speed := 27.0
var max_health := 100.0


func tier(impact_speed: float) -> Tier:
	if impact_speed < safe_speed:
		return Tier.NONE
	if impact_speed < hard_speed:
		return Tier.HARD
	return Tier.SEVERE


## Damage in health points for a given impact speed (linear between safe and lethal).
func damage(impact_speed: float) -> float:
	if impact_speed < safe_speed:
		return 0.0
	return max_health * clampf((impact_speed - safe_speed) / (lethal_speed - safe_speed), 0.0, 1.0)


## Drop height that produces a given impact speed under ``gravity`` (for docs/tests).
static func height_for_speed(speed: float, gravity: float) -> float:
	return speed * speed / (2.0 * gravity)
