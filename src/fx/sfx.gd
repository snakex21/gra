class_name Sfx
## Functional placeholder sounds, synthesised at runtime (no audio files, nothing taken
## from any game): heavy step, stomp, swing, impact, weak point hit, grip lost, defeat.
## Each sound is generated once (deterministic noise / sine mixes) and cached.
## ``Sfx.enabled = false`` turns everything off (benchmarks, tests).

static var enabled := true
static var _cache := {}

const RATE := 22050


static func play(owner: Node, kind: StringName, at: Vector3, volume_db := 0.0) -> void:
	if not enabled or owner == null or not owner.is_inside_tree():
		return
	var stream := _stream(kind)
	if stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = volume_db
	p.unit_size = 25.0 if kind in [&"stomp", &"defeat", &"step"] else 8.0
	p.max_distance = 400.0
	p.finished.connect(p.queue_free)
	var host: Node = owner.get_parent() if owner.get_parent() else owner
	host.add_child(p)
	p.global_position = at
	p.play()


static func _stream(kind: StringName) -> AudioStreamWAV:
	if _cache.has(kind):
		return _cache[kind]
	var s: AudioStreamWAV
	match kind:
		&"step":
			s = _make(0.45, func(t: float, n: float) -> float: return _low(n, t, 60.0) * exp(-t * 9.0) * 0.9)
		&"stomp":
			s = _make(1.2, func(t: float, n: float) -> float: return (_low(n, t, 45.0) * 0.8 + n * 0.25 * exp(-t * 18.0)) * exp(-t * 3.0))
		&"swing":
			s = _make(0.7, func(t: float, n: float) -> float: return n * 0.5 * sin(PI * t / 0.7) * (0.4 + 0.6 * sin(t * 40.0) * sin(t * 40.0)))
		&"impact":
			s = _make(0.35, func(t: float, n: float) -> float: return (n * 0.6 + sin(t * TAU * 90.0) * 0.4) * exp(-t * 14.0))
		&"weak_hit":
			s = _make(0.8, func(t: float, n: float) -> float: return (sin(t * TAU * 520.0) * 0.5 + sin(t * TAU * 780.0) * 0.3 + n * 0.3 * exp(-t * 30.0)) * exp(-t * 5.0))
		&"ricochet":
			# Arrow glancing off stone: a short falling ping.
			s = _make(0.25, func(t: float, n: float) -> float: return (sin(t * TAU * (2400.0 - 4000.0 * t)) * 0.45 + n * 0.25 * exp(-t * 60.0)) * exp(-t * 16.0))
		&"crack":
			# Stone armour cracking: a dry snap over a low knock.
			s = _make(0.5, func(t: float, n: float) -> float: return (n * 0.7 * exp(-t * 35.0) + _low(n, t, 80.0) * 0.5 * exp(-t * 10.0)))
		&"grip_lost":
			s = _make(0.3, func(t: float, n: float) -> float: return n * 0.4 * exp(-t * 12.0))
		&"defeat":
			s = _make(3.0, func(t: float, n: float) -> float: return (_low(n, t, 35.0) * 0.7 + sin(t * TAU * 55.0) * 0.3) * sin(PI * t / 3.0))
	_cache[kind] = s
	return s


## Deterministic noise from the sample index (no RNG state).
static func _noise(i: int) -> float:
	var x := sin(float(i) * 12.9898) * 43758.5453
	return (x - floor(x)) * 2.0 - 1.0


## Cheap "low rumble": a sine with noise-modulated amplitude.
static func _low(n: float, t: float, f: float) -> float:
	return sin(t * TAU * f) * (0.7 + 0.3 * n)


static func _make(length: float, f: Callable) -> AudioStreamWAV:
	var count := int(length * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t := float(i) / RATE
		var v := clampf(f.call(t, _noise(i)), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
