class_name LocalDecisionClient
extends Node
## Optional advisor, outside the simulation/checkpoint tree. No polling, automatic
## retries, blocking inference or endpoint configuration. The controller stays live.

signal decision_ready(intent: StringName, generation: int)
const ENDPOINT := "http://127.0.0.1:8766/decision"
const VOCABULARY := [&"follow", &"hold", &"support", &"evade", &"regroup"]
const NUMBER_LIMITS := {"health": Vector2(0, 100), "stamina": Vector2(0, 1), "leader_distance": Vector2(0, 10000), "enemy_distance": Vector2(-1, 10000)}
const BOOL_KEYS := ["threat", "enemy_active", "leader_climbing", "support_available", "near_cliff", "mounted", "player_downed", "leader_downed", "ground_safe", "navigation_blocked"]
const TIMEOUT := 2.0
const MIN_INTERVAL_MS := 6000

var enabled := false:
	set(value):
		enabled = value
		if not value:
			cancel()
var _http: HTTPRequest
var _epoch := 0
var _pending := false
var _next_at_ms := 0
var _failures := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_EXIT_TREE:
		cancel()


func request(observation: Dictionary, allowed: Array, generation: int) -> bool:
	if not enabled or not is_inside_tree() or get_tree().paused or _pending or generation < 0 or generation > 2147483647 or Time.get_ticks_msec() < _next_at_ms:
		return false
	var clean := sanitize_observation(observation)
	var intents := sanitize_allowed(allowed)
	if clean.is_empty() or intents.is_empty():
		return false
	_epoch += 1
	var epoch := _epoch
	var task := HTTPRequest.new()
	task.timeout = TIMEOUT
	task.body_size_limit = 2048
	task.max_redirects = 0
	task.use_threads = true
	add_child(task)
	_http = task
	_pending = true
	_next_at_ms = Time.get_ticks_msec() + MIN_INTERVAL_MS
	task.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		_completed(result, code, body, intents, generation, epoch)
		task.queue_free(), CONNECT_ONE_SHOT)
	var error := task.request(ENDPOINT, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, JSON.stringify({"observation": clean, "allowed": intents, "generation": generation}))
	if error != OK:
		cancel()
		_backoff()
		return false
	return true


func cancel() -> void:
	_epoch += 1
	_pending = false
	if is_instance_valid(_http):
		_http.cancel_request()
		_http.queue_free()
	_http = null


func _completed(result: int, code: int, body: PackedByteArray, allowed: Array, generation: int, epoch: int) -> void:
	if epoch != _epoch:
		return
	_pending = false
	_http = null
	if not enabled or not is_inside_tree() or get_tree().paused:
		return
	var intent := decode_decision(body, allowed, generation) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else &""
	if intent == &"":
		_backoff()
		return
	_failures = 0
	decision_ready.emit(intent, generation)


func _backoff() -> void:
	_failures = mini(5, _failures + 1)
	_next_at_ms = maxi(_next_at_ms, Time.get_ticks_msec() + mini(60000, MIN_INTERVAL_MS * (1 << (_failures - 1))))


static func sanitize_allowed(values: Array) -> Array[String]:
	var result: Array[String] = []
	if values.is_empty() or values.size() > VOCABULARY.size():
		return result
	for value: Variant in values:
		if not (value is String or value is StringName) or not VOCABULARY.has(StringName(value)):
			return []
		if not result.has(String(value)):
			result.append(String(value))
	return result


static func sanitize_observation(data: Dictionary) -> Dictionary:
	var result := {}
	if data.size() > NUMBER_LIMITS.size() + BOOL_KEYS.size() + 1:
		return result
	for key: Variant in data:
		if not (key is String or key is StringName):
			return {}
		var name := String(key)
		var value: Variant = data[key]
		if NUMBER_LIMITS.has(name):
			if not typeof(value) in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
				return {}
			var limits: Vector2 = NUMBER_LIMITS[name]
			if float(value) < limits.x or float(value) > limits.y:
				return {}
			result[name] = float(value)
		elif BOOL_KEYS.has(name):
			if not value is bool:
				return {}
			result[name] = value
		elif name == "intent":
			if not (value is String or value is StringName) or not VOCABULARY.has(StringName(value)):
				return {}
			result[name] = String(value)
		else:
			return {}
	return result


static func decode_decision(body: PackedByteArray, allowed: Array, generation: int) -> StringName:
	if body.size() == 0 or body.size() > 2048:
		return &""
	var parser := JSON.new()
	if parser.parse(body.get_string_from_utf8()) != OK:
		return &""
	var data: Variant = parser.data
	if not data is Dictionary or data.size() != 2 or not data.has("intent") or not data.has("generation"):
		return &""
	var saved_generation: Variant = data.generation
	if not typeof(saved_generation) in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(saved_generation)) or float(saved_generation) != generation:
		return &""
	if not data.intent is String:
		return &""
	var intent := StringName(data.intent)
	return intent if VOCABULARY.has(intent) and allowed.has(String(intent)) else &""
