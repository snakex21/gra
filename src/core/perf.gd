class_name Perf
## Tiny always-on counters for logic cost and physics query counts, by category.
## Cheap enough to leave enabled; read by the debug HUD and the performance tests.
##
## Totals only grow. Each reader takes the difference since its own last take(), so the
## HUD sampling twice a second does not steal the numbers a test is measuring.

## Physics queries this sampling window: label -> count
## (&"climb_rays", &"grab_queries", &"camera_queries", ...).
static var queries := {}
static var _usec := {}
static var _snapshots := {}  # reader -> [usec totals, query totals]


static func count(label: StringName) -> void:
	queries[label] = queries.get(label, 0) + 1


static func begin() -> int:
	return Time.get_ticks_usec()


static func end(label: StringName, t0: int) -> void:
	_usec[label] = _usec.get(label, 0) + Time.get_ticks_usec() - t0


## Returns the counters accumulated since ``reader``'s previous take():
## {"usec": {...}, "queries": {...}}.
static func take(reader: StringName = &"default") -> Dictionary:
	var snap: Array = _snapshots.get(reader, [{}, {}])
	var out := {"usec": _diff(_usec, snap[0]), "queries": _diff(queries, snap[1])}
	_snapshots[reader] = [_usec.duplicate(), queries.duplicate()]
	return out


static func _diff(now: Dictionary, before: Dictionary) -> Dictionary:
	var d := {}
	for k in now:
		var v: int = now[k] - int(before.get(k, 0))
		if v != 0:
			d[k] = v
	return d
