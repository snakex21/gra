class_name Perf
## Tiny always-on counters for logic cost and physics query counts, by category.
## Cheap enough to leave enabled; read by the debug HUD and the performance test.

## Physics queries this sampling window: label -> count
## (&"climb_rays", &"grab_queries", &"camera_queries").
static var queries := {}
static var _usec := {}


static func count(label: StringName) -> void:
	queries[label] = queries.get(label, 0) + 1


static func begin() -> int:
	return Time.get_ticks_usec()


static func end(label: StringName, t0: int) -> void:
	_usec[label] = _usec.get(label, 0) + Time.get_ticks_usec() - t0


## Returns accumulated counters ({"usec": {...}, "queries": {...}}) and resets them.
static func take() -> Dictionary:
	var out := {"usec": _usec.duplicate(), "queries": queries.duplicate()}
	_usec.clear()
	queries.clear()
	return out
