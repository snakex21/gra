extends Node
## Pure-model tests: no GPU, art import, file writes, world nodes or wall-clock
## dependency in the climate. The only OS timer is this test's failure watchdog.

const Climate = preload("res://src/world/world_climate.gd")
const SCALARS := ["hour", "sun_height", "daylight", "rain", "cloud", "fog", "haze", "wind_strength", "anomaly", "exposure"]
var failures := 0
var assertions := 0
var deadline := Time.get_ticks_msec() + 30000


func _process(_delta: float) -> void:
	if Time.get_ticks_msec() > deadline:
		push_error("World climate test timed out or stopped after a runtime error")
		get_tree().quit(1)


func _ready() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error(message)


func same_sample(a: Dictionary, b: Dictionary, tolerance: float = 1.0e-8) -> bool:
	for key: String in SCALARS:
		if absf(float(a[key]) - float(b[key])) > tolerance:
			return false
	return a.day_index == b.day_index and a.weather_id == b.weather_id and (a.wind_direction as Vector3).distance_to(b.wind_direction) <= tolerance


func run() -> void:
	test_clock()
	test_frame_partition()
	test_weather()
	test_save()
	test_corrupt_save()
	test_regions_and_progress()
	print("WORLD_CLIMATE failures=%d assertions=%d; day wrap, 30/60/120Hz, seeded smooth weather, pure sampling, binary/JSON continuation, legacy/corrupt recovery, desert/cave/lake/highland and Dormin finale" % [failures, assertions])
	get_tree().quit(1 if failures else 0)


func test_clock() -> void:
	var climate := Climate.new()
	check(climate.sample().hour == 8.0 and climate.sample().day_index == 0, "New world did not start at 08:00 on day zero")
	climate.advance(300.0)
	check(climate.sample().hour == 12.0 and climate.sample().daylight > 0.99, "Noon did not occur after 300 simulation seconds")
	climate.advance(899.99)
	check(climate.sample().hour > 23.99 and climate.sample().daylight < 0.01, "Late night did not remain dark before wrapping")
	climate.advance(0.01)
	check(absf(float(climate.sample().hour)) < 1.0e-9 and climate.sample().day_index == 1, "Midnight did not wrap cleanly to the next day")
	climate.advance(600.0)
	check(climate.sample().hour == 8.0 and climate.sample().day_index == 1, "A full 1800-second day did not return to 08:00")
	var saved := var_to_bytes(climate.to_dict())
	for delta: float in [0.0, -1.0, INF, -INF, NAN]:
		climate.advance(delta)
	check(var_to_bytes(climate.to_dict()) == saved, "Invalid/paused deltas changed the clock")
	climate.advance(Climate.DAY_SECONDS * 13.0)
	check(climate.sample().hour == 8.0 and climate.sample().day_index == 14, "Multi-day delta lost complete days")
	climate.advance(Climate.MAX_ELAPSED * 2.0)
	check(climate.to_dict().elapsed == Climate.MAX_ELAPSED and is_finite(climate.sample().hour), "Excessive clock delta was not safely bounded")


func test_frame_partition() -> void:
	var reference := Climate.new(71039)
	reference.advance(3600.0)
	var expected := reference.sample(&"hydrus", 14)
	for fps: int in [30, 60, 120]:
		var climate := Climate.new(71039)
		for frame in 3600 * fps:
			climate.advance(1.0 / fps)
		check(absf(float(climate.to_dict().elapsed) - 3600.0) <= 1.0e-9, "Clock drifted at %d Hz" % fps)
		check(same_sample(climate.sample(&"hydrus", 14), expected), "Weather/daylight depends on frame partition at %d Hz" % fps)
	var uneven := Climate.new(71039)
	for frame in 18000:
		uneven.advance(0.03125)
		uneven.advance(0.125)
		uneven.advance(0.04375)
	check(same_sample(uneven.sample(&"hydrus", 14), expected), "Uneven deltas changed climate at the same simulation time")


func test_weather() -> void:
	var a := Climate.new(417)
	var b := Climate.new(417)
	var other := Climate.new(418)
	var diverged := false
	var ids := {}
	var largest_jump := 0.0
	for step in 24001:
		var state: Dictionary = a.sample(&"valley", 8)
		if step % 60 == 0:
			check(state == b.sample(&"valley", 8), "Equal seed/time produced different weather at step %d" % step)
			diverged = diverged or not same_sample(state, other.sample(&"valley", 8))
			ids[state.weather_id] = true
			check_bounds(state)
		var before := var_to_bytes(a.to_dict()) if step % 1000 == 0 else PackedByteArray()
		if not before.is_empty():
			for region: StringName in [&"valley", &"worm", &"cave", &"hydrus"]:
				a.sample(region, 20, true)
			check(var_to_bytes(a.to_dict()) == before, "sample() mutated persistent climate state")
		a.advance(0.1)
		b.advance(0.1)
		other.advance(0.1)
		var next: Dictionary = a.sample(&"valley", 8)
		for key: String in ["rain", "cloud", "fog", "wind_strength", "anomaly"]:
			largest_jump = maxf(largest_jump, absf(float(state[key]) - float(next[key])))
		largest_jump = maxf(largest_jump, (state.wind_direction as Vector3).distance_to(next.wind_direction))
	check(diverged, "A changed persisted seed did not change future weather")
	check(ids.size() >= 4 and ids.has("rain") and ids.has("mist"), "Long weather trace did not exercise distinct fronts")
	check(largest_jump < 0.006, "Weather crossed a hard boundary: largest 0.1-second change %.9f" % largest_jump)
	# Looking far ahead, changing region and advancing the model must not consume
	# the gameplay's random generator, even while the weather front changes.
	seed(83427)
	var expected := randf()
	seed(83427)
	a.advance(321.13)
	for region: StringName in [&"valley", &"phalanx", &"dormin"]:
		a.sample(region, 19)
	check(randf() == expected, "WorldClimate consumed the game's global random generator")


func check_bounds(state: Dictionary) -> void:
	check(state.hour >= 0.0 and state.hour < 24.0 and state.sun_height >= -1.0 and state.sun_height <= 1.0, "Solar values escaped their documented ranges")
	var bounded := true
	for key: String in ["daylight", "rain", "cloud", "fog", "haze", "wind_strength", "anomaly", "exposure"]:
		bounded = bounded and state[key] >= 0.0 and state[key] <= 1.0 and is_finite(float(state[key]))
	check(bounded, "Climate strength was not a finite normalized value")
	var direction: Vector3 = state.wind_direction
	check(absf(direction.length() - 1.0) < 1.0e-6 and direction.y == 0.0, "Wind direction was not a horizontal unit vector")


func test_save() -> void:
	var original := Climate.new(921331)
	for frame in 1203:
		original.advance(1.0 / 60.0)
	var stored := original.to_dict()
	var restored := Climate.new(2)
	check(restored.from_dict(bytes_to_var(var_to_bytes(stored))), "Binary climate dictionary was rejected")
	check(var_to_bytes(restored.to_dict()) == var_to_bytes(stored), "Binary roundtrip changed saved clock/seed/compensation")
	var json_restored := Climate.new(3)
	check(json_restored.from_dict(JSON.parse_string(JSON.stringify(stored))), "JSON numeric fields were rejected")
	check(same_sample(json_restored.sample(), original.sample()), "JSON roundtrip changed displayed climate")
	for frame in 20000:
		var delta := 1.0 / 60.0 if frame % 3 == 0 else 0.0173
		original.advance(delta)
		restored.advance(delta)
		json_restored.advance(delta)
	check(var_to_bytes(restored.to_dict()) == var_to_bytes(original.to_dict()), "Saved compensation failed identical binary continuation")
	check(same_sample(json_restored.sample(&"hydrus", 16), original.sample(&"hydrus", 16)), "JSON climate diverged after continuation")
	var legacy := Climate.new()
	check(not legacy.from_dict({}, 1234.567), "Missing old climate was incorrectly accepted as a new climate save")
	var migrated := Climate.new()
	migrated.advance(1234.567)
	check(same_sample(legacy.sample(&"valley", 6), migrated.sample(&"valley", 6)), "Legacy play_time did not recover day/weather position")
	var pure_before := var_to_bytes(original.to_dict())
	var leaked := original.to_dict()
	leaked.elapsed = 999.0
	leaked.seed = 1
	check(var_to_bytes(original.to_dict()) == pure_before, "Mutating returned serialization changed the climate model")


func test_corrupt_save() -> void:
	var climate := Climate.new(77)
	for corrupt: Variant in [null, "10", true, [], {}, INF, -INF, NAN, -1.0, Climate.MAX_ELAPSED + 1.0]:
		check(not climate.from_dict({"version": 1, "seed": 22, "elapsed": corrupt}, 73.25), "Corrupt elapsed was accepted: %s" % str(corrupt))
		check(climate.to_dict().elapsed == 73.25, "Corrupt elapsed did not use legacy play_time")
	for corrupt: Variant in [null, "1", true, [], {}, INF, NAN, 0, 2, 1.5]:
		check(not climate.from_dict({"version": corrupt, "elapsed": 21.0}, 42.0), "Unknown/non-numeric climate version was accepted")
		check(climate.to_dict().elapsed == 42.0 and climate.to_dict().seed == Climate.DEFAULT_SEED, "Unsupported version retained stale climate fields")
	for corrupt: Variant in [null, "abc", [], {}, true, INF, NAN, 0, -1, 1.5, Climate.SEED_MODULUS]:
		check(climate.from_dict({"version": 1, "elapsed": 231.5, "seed": corrupt, "compensation": []}), "Invalid optional fields discarded a valid clock")
		check(climate.to_dict().seed == Climate.DEFAULT_SEED and climate.to_dict().compensation == 0.0, "Invalid optional fields did not receive defaults")
	check(climate.from_dict({"version": 1.0, "elapsed": 91.5, "seed": 123.0, "compensation": 9.0}), "Valid JSON numeric seed/version were not supported")
	check(climate.to_dict().seed == 123 and climate.to_dict().compensation == 0.0, "Excessive compensation corrupted a valid clock")
	check(climate.from_dict({"version": 1, "elapsed": 0.0, "compensation": 1.0e-9}), "Fresh saved clock was rejected")
	climate.advance(1.0e-12)
	check(climate.to_dict().elapsed >= 0.0 and climate.to_dict().compensation == 0.0, "Corrupt tiny compensation moved the fresh clock backwards")
	check(not climate.from_dict({}, NAN) and climate.to_dict().elapsed == 0.0, "Invalid legacy time did not default to a fresh clock")
	check(not climate.from_dict({}, -5.0) and climate.to_dict().elapsed == 0.0, "Negative legacy time was retained")


func test_regions_and_progress() -> void:
	var climate := Climate.new(417)
	# Find a wet moment from the real deterministic sequence, not a mocked sample.
	for step in 100:
		if climate.sample().rain > 0.50:
			break
		climate.advance(30.0)
	var valley := climate.sample()
	check(valley.rain > 0.50, "Regional test did not reach a genuine rain front")
	var desert := climate.sample(&"phalanx")
	check(desert.rain == 0.0 and desert.haze > 0.40 and desert.weather_id == "haze", "Desert converted a rain front incorrectly")
	check(desert == climate.sample(&"southern_desert") and desert == climate.sample(&"worm"), "Boss/profile aliases diverged in an arid region")
	var cave := climate.sample(&"dirge")
	check(cave.rain == 0.0 and cave.wind_strength == 0.0 and cave.exposure == 0.0, "Outdoor precipitation/wind leaked into a cave")
	check(cave == climate.sample(&"western_cavern") and cave == climate.sample(&"devil"), "Cave aliases had different weather")
	check(climate.sample(&"hydrus").fog > valley.fog and climate.sample(&"hydrus").wind_strength < valley.wind_strength, "Lakes did not receive their own mist/wind profile")
	check(climate.sample(&"gaius").wind_strength > valley.wind_strength, "Highland did not receive stronger atmospheric wind")
	check(climate.sample(&"spider").wind_strength < valley.wind_strength and climate.sample(&"spider").fog > valley.fog, "Forest did not soften wind and retain mist")
	check(climate.sample(&"unknown") == valley, "Unknown region did not use the valley profile")
	var previous := 0.0
	for victories in 21:
		var state := climate.sample(&"valley", victories)
		check(state.anomaly >= previous and state.anomaly <= 1.0, "Dormin mood did not grow with victories")
		previous = state.anomaly
	check(climate.sample(&"valley", -10).anomaly == 0.0 and climate.sample(&"valley", 20).anomaly > 0.79, "Dormin progress was not safely bounded")
	var returned := climate.sample(&"valley", 21, true)
	check(returned.anomaly == 0.0 and returned == valley, "Finale did not remove Dormin's climate distortion")
	check(climate.sample(&"valley", 20).cloud >= valley.cloud and climate.sample(&"valley", 20).fog > valley.fog, "Victories did not affect the world atmosphere")
