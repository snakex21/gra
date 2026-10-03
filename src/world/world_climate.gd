class_name WorldClimate
extends RefCounted
## Pure, replayable climate. Only advance() changes the simulation clock; sample()
## has no random generator, node, renderer or wall-clock dependency.

const VERSION := 1
const DEFAULT_SEED := 146021
const DAY_SECONDS := 1800.0
const START_HOUR := 8.0
const WEATHER_SECONDS := 240.0
## Guard against corrupted saves; a century of simulation still fits comfortably.
const MAX_ELAPSED := 3155760000.0
const SEED_MODULUS := 2147483647
const DEFEATS_BEFORE_FINALE := 20.0
## [name, clouds, rain, fog, wind]. Values are strengths, not shader densities.
const WEATHER := [
	["clear", 0.16, 0.0, 0.12, 0.22],
	["overcast", 0.78, 0.0, 0.18, 0.32],
	["rain", 0.94, 0.88, 0.45, 0.56],
	["mist", 0.42, 0.0, 0.78, 0.12],
	["windy", 0.36, 0.0, 0.13, 0.80]
]

var seed := DEFAULT_SEED
var _elapsed := 0.0
## Kahan compensation prevents hours of 30/60/120 Hz updates drifting apart.
## It is serialized too, so a checkpoint continues the identical accumulator.
var _compensation := 0.0


func _init(world_seed: int = DEFAULT_SEED) -> void:
	if world_seed > 0 and world_seed < SEED_MODULUS:
		seed = world_seed


func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0 or _elapsed >= MAX_ELAPSED:
		return
	var corrected := delta - _compensation
	var total := _elapsed + corrected
	if total >= MAX_ELAPSED:
		_elapsed = MAX_ELAPSED
		_compensation = 0.0
		return
	_compensation = (total - _elapsed) - corrected
	_elapsed = total


## region_kind accepts the encounter name OR ForbiddenLands' regional profile.
## Progress changes the mood only; there are no gameplay forces or penalties.
func sample(region_kind: StringName = &"valley", defeated_count: int = 0, completed: bool = false) -> Dictionary:
	var solar_time := _elapsed + START_HOUR * DAY_SECONDS / 24.0
	var hour := fposmod(solar_time, DAY_SECONDS) * 24.0 / DAY_SECONDS
	var sun_height := sin((hour - 6.0) * TAU / 24.0)
	var daylight := smoothstep(-0.08, 0.50, sun_height)
	var period := floori(_elapsed / WEATHER_SECONDS)
	var blend := smoothstep(0.0, 1.0, fposmod(_elapsed, WEATHER_SECONDS) / WEATHER_SECONDS)
	var left := _weather_index(period)
	var right := _weather_index(period + 1)
	var a: Array = WEATHER[left]
	var b: Array = WEATHER[right]
	var cloud := lerpf(float(a[1]), float(b[1]), blend)
	var rain := lerpf(float(a[2]), float(b[2]), blend)
	var fog := lerpf(float(a[3]), float(b[3]), blend) + (1.0 - daylight) * 0.045
	var wind := lerpf(float(a[4]), float(b[4]), blend)
	var angle := lerp_angle(_random_unit(period, 1) * TAU, _random_unit(period + 1, 1) * TAU, blend)
	var weather_id: String = String(a[0] if blend < 0.5 else b[0])
	var progress := clampf(float(defeated_count) / DEFEATS_BEFORE_FINALE, 0.0, 1.0)
	var anomaly := 0.0
	if not completed:
		# A slow pulse grows with Dormin's returning power and ends at the finale.
		anomaly = pow(progress, 1.7) * (0.90 + sin(_elapsed * TAU / 420.0) * 0.10)
	cloud += anomaly * 0.14
	fog += anomaly * 0.12
	wind += anomaly * 0.10
	var haze := 0.0
	var exposure := 1.0
	var region := String(region_kind).to_lower()
	if region in ["phalanx", "worm", "desert", "dunes", "southern_desert", "western_dunes"]:
		# The same distant weather front becomes suspended sand in arid regions.
		haze = 0.10 + rain * 0.75 + fog * 0.20 + wind * 0.15
		rain = 0.0
		cloud *= 0.65
		fog *= 0.30
		if weather_id in ["rain", "mist"] or haze > 0.40:
			weather_id = "haze"
	elif region in ["dirge", "devil", "barba", "cave", "cavern", "hollowvault", "deeprelic", "western_cavern", "eastern_cave", "forest_tomb"]:
		exposure = 0.0
		rain = 0.0
		wind = 0.0
		fog = 0.14 + fog * 0.22
		weather_id = "mist" if fog > 0.18 else "clear"
	elif region in ["dormin", "temple", "temple_annex"]:
		exposure = 0.30
		rain *= 0.15
		wind *= 0.25
		fog *= 0.70
	elif region in ["avion", "hydrus", "pelagia", "lake", "eastern_lake", "northern_lake", "eastern_falls"]:
		fog += 0.07 + (1.0 - daylight) * 0.16
		wind *= 0.85
	elif region in ["spider", "forest", "forest_ruins"]:
		fog += 0.10
		rain *= 0.70
		wind *= 0.55
	elif region in ["gaius", "saru", "argus", "highland", "western_highland", "northern_bridges", "northern_fortress"]:
		wind += 0.12
		fog = maxf(0.0, fog - 0.04)
	elif region in ["phoenix", "crater", "eastern_crater"]:
		haze = 0.16 + wind * 0.16
		rain *= 0.25
		fog *= 0.45
	elif region in ["basaran", "geysers", "western_geysers"]:
		fog += 0.24
	return {
		"hour": hour, "day_index": floori(solar_time / DAY_SECONDS),
		"sun_height": sun_height, "daylight": daylight,
		"rain": clampf(rain, 0.0, 1.0), "cloud": clampf(cloud, 0.0, 1.0),
		"fog": clampf(fog, 0.0, 1.0), "haze": clampf(haze, 0.0, 1.0),
		"wind_strength": clampf(wind, 0.0, 1.0),
		"wind_direction": Vector3(cos(angle), 0.0, sin(angle)),
		"anomaly": clampf(anomaly, 0.0, 1.0), "exposure": exposure,
		"weather_id": weather_id
	}


func to_dict() -> Dictionary:
	return {"version": VERSION, "seed": seed, "elapsed": _elapsed, "compensation": _compensation}


## Resets before reading. Missing/unknown climate uses the old save's play_time.
## True means a supported, valid saved clock was recovered. Optional malformed
## seed/compensation values use safe defaults without discarding a valid clock.
func from_dict(data: Dictionary, legacy_elapsed: float = 0.0) -> bool:
	seed = DEFAULT_SEED
	_elapsed = legacy_elapsed if is_finite(legacy_elapsed) and legacy_elapsed >= 0.0 and legacy_elapsed <= MAX_ELAPSED else 0.0
	_compensation = 0.0
	var version: Variant = data.get("version")
	if not _finite_number(version) or float(version) != VERSION:
		return false
	var saved_seed: Variant = data.get("seed")
	if _finite_number(saved_seed) and float(saved_seed) == floor(float(saved_seed)) and float(saved_seed) > 0.0 and float(saved_seed) < SEED_MODULUS:
		seed = int(saved_seed)
	var elapsed: Variant = data.get("elapsed")
	if not _finite_number(elapsed) or float(elapsed) < 0.0 or float(elapsed) > MAX_ELAPSED:
		return false
	_elapsed = float(elapsed)
	var compensation: Variant = data.get("compensation")
	if _finite_number(compensation) and absf(float(compensation)) <= _elapsed * 1.0e-14:
		_compensation = float(compensation)
	return true


static func _finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


func _weather_index(period: int) -> int:
	# A new game begins in clear weather; the future sequence depends on its seed.
	return 0 if period == 0 else mini(WEATHER.size() - 1, floori(_random_unit(period, 0) * WEATHER.size()))


func _random_unit(period: int, channel: int) -> float:
	# Integer arithmetic remains below 2^63; this hash doesn't touch global RNG.
	var value := posmod(seed + posmod(period, SEED_MODULUS) * 65437 + channel * 104729, SEED_MODULUS)
	value = value ^ (value >> 13)
	value = posmod(value * 48271 + 1, SEED_MODULUS)
	value = value ^ (value >> 11)
	value = posmod(value * 69621 + 1, SEED_MODULUS)
	return float(value) / float(SEED_MODULUS)
