class_name ColossusBrain
extends RefCounted
## Stable decision interface: observation in, intent out.
##
## Implementations (utility AI now, possibly a small learned model later) must be pure
## decision makers. They never move bones or bodies and never enforce fairness: the
## colossus' hand-designed encounter rules filter every intent, so no brain can make a
## fight unwinnable (e.g. by never exposing a weak point).


## Called at the colossus' think rate (not every frame).
func decide(_obs: ColossusObservation) -> ColossusIntent:
	return ColossusIntent.make(ColossusIntent.IDLE)


## One-line summary for debug overlays and A/B logs.
func debug_text() -> String:
	return ""
