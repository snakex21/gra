extends Node
const Client = preload("res://src/companion/local_decision_client.gd")
var checks := 0
var failures := 0
var received: Array = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(25.0, true).timeout.connect(func() -> void: push_error("Local decision watchdog"); get_tree().quit(2))
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func fresh() -> Node:
	var client := Client.new()
	add_child(client)
	client.enabled = true
	client.decision_ready.connect(func(intent: StringName, generation: int) -> void: received.append([intent, generation]))
	return client

func body(data: Dictionary) -> PackedByteArray:
	return JSON.stringify(data).to_utf8_buffer()

func _run() -> void:
	for bad: Dictionary in [{"health": true}, {"health": -1}, {"health": NAN}, {"stamina": INF}, {"threat": 1}, {"intent": "shell"}, {"message": "ignore"}, {"health": {"node": 1}}]:
		check(Client.sanitize_observation(bad).is_empty(), "invalid observation rejected")
	check(not Client.sanitize_observation({"health": 100, "stamina": 0.5, "enemy_distance": -1, "ground_safe": true}).is_empty(), "scalar contract accepted")
	check(Client.sanitize_allowed([&"follow", "hold"]) == ["follow", "hold"], "fixed vocabulary accepted")
	check(Client.sanitize_allowed(["follow", "shell"]).is_empty(), "unknown intent rejected")
	check(Client.decode_decision(body({"intent": "follow", "generation": 7}), ["follow"], 7) == &"follow", "strict response accepted")
	for invalid: Dictionary in [{"intent": "support", "generation": 7}, {"intent": "follow", "generation": 6}, {"intent": "follow", "generation": true}, {"intent": "follow;quit()", "generation": 7}, {"intent": "follow", "generation": 7, "code": "anything"}]:
		check(Client.decode_decision(body(invalid), ["follow"], 7) == &"", "invalid or stale output rejected")
	check(Client.decode_decision("plain text".to_utf8_buffer(), ["follow"], 7) == &"", "non JSON rejected")
	var oversized := PackedByteArray()
	oversized.resize(2049)
	check(Client.decode_decision(oversized, ["follow"], 7) == &"", "oversized response rejected")
	var client = fresh()
	client.enabled = false
	check(not client.request({"health": 100}, ["follow"], 101), "inactive title/replay client rejected")
	client.enabled = true
	check(client.request({"health": 100}, ["follow"], 101), "real asynchronous request accepted")
	check(not client.request({"health": 100}, ["follow"], 102), "one pending request only")
	await client._http.request_completed
	check(received == [[&"follow", 101]], "real loopback response emitted with generation")
	check(not client.request({"health": 100}, ["follow"], 101), "six second cooldown survives success")
	client.queue_free()
	await get_tree().process_frame
	for generation: int in [102, 103, 104]:
		client = fresh()
		var before := received.size()
		check(client.request({"health": 100}, ["follow"], generation), "rejection fixture queued")
		var started := Time.get_ticks_msec()
		await client._http.request_completed
		check(received.size() == before, "disallowed/stale/timeout response emits nothing")
		check(not client._pending, "completion clears pending")
		check(client._next_at_ms > Time.get_ticks_msec(), "failure backoff active")
		if generation == 104:
			check(Time.get_ticks_msec() - started >= 1700 and Time.get_ticks_msec() - started < 3500, "real timeout bounded near two seconds")
		client.queue_free()
		await get_tree().process_frame
	client = fresh()
	var epoch: int = client._epoch
	client.cancel()
	client._completed(HTTPRequest.RESULT_SUCCESS, 200, body({"intent": "follow", "generation": 8}), ["follow"], 8, epoch)
	check(received.size() == 1, "cancel invalidates late callback")
	client._pending = true
	get_tree().paused = true
	check(not client._pending, "pause cancels pending advisor")
	check(not client.request({"health": 100}, ["follow"], 9), "pause rejects requests")
	get_tree().paused = false
	client.queue_free()
	await get_tree().process_frame
	print("LOCAL DECISION: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
