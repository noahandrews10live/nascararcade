extends Node
## Tiny software synth: your engine, passing cars, tyre squeal, crunches and beeps.
## Everything is generated at runtime so the project needs no audio assets.

const RATE := 11025.0
## Per-sample filter constants were tuned at 22050 Hz; K rescales them.
const K := 22050.0 / RATE
const CRASH_DECAY := 0.9993 # 0.99965 per sample at 22050 Hz

var player: AudioStreamPlayer
var playback: AudioStreamGeneratorPlayback

# Parameters set by the game every frame
var engine_rpm := 0.0
var engine_load := 0.0
var engine_on := false
var squeal := 0.0
var pass_volume := 0.0
var pass_pitch := 1.0
var wind := 0.0 # 0..1: rushing air, rising with speed
var master := 0.8

var _v8: V8
var _pass_ph := 0.0
var _sq_ph := 0.0
var _lp := 0.0
var _lp2 := 0.0
var _rpm_s := 0.0
var _crash := 0.0
var _crash_lp := 0.0
var _wind_lp := 0.0
var _wind_lp2 := 0.0
var _beeps: Array = [] # [freq, remaining_samples, volume]
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_v8 = V8.new(RATE)
	player = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.12
	player.stream = gen
	player.volume_db = -4.0
	# Web exports default to sample playback, which cannot play a generator stream.
	player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	if AudioServer.get_bus_index("World") >= 0:
		player.bus = "World" # your own car echoes off the walls too
	add_child(player)
	player.play()
	playback = player.get_stream_playback()


func crash(strength: float) -> void:
	_crash = max(_crash, clamp(strength, 0.0, 1.0))


func beep(freq: float, seconds: float, vol := 0.35) -> void:
	_beeps.append([freq, int(seconds * RATE), vol])


func _process(_delta: float) -> void:
	if playback == null:
		return
	var frames := playback.get_frames_available()
	if frames <= 0:
		return
	var buf := PackedVector2Array()
	buf.resize(frames)
	var target_rpm := engine_rpm if engine_on else 0.0
	for i in frames:
		_rpm_s += (target_rpm - _rpm_s) * 0.0015 * K
		var s := 0.0
		var eng := Vector2.ZERO
		if _rpm_s > 200.0:
			eng = _v8.step(_rpm_s, engine_load) * 0.55
		if pass_volume > 0.01:
			var pf := 140.0 * pass_pitch
			_pass_ph = fmod(_pass_ph + pf / RATE, 1.0)
			var saw := _pass_ph * 2.0 - 1.0
			_lp2 += (saw - _lp2) * 0.12 * K
			s += _lp2 * pass_volume * 0.3
		if squeal > 0.02:
			_sq_ph = fmod(_sq_ph + (820.0 + sin(_sq_ph * 40.0) * 20.0) / RATE, 1.0)
			s += (sin(_sq_ph * TAU) * 0.6 + _rng.randf_range(-0.4, 0.4)) * squeal * 0.12
		if wind > 0.01:
			_wind_lp += (_rng.randf_range(-1.0, 1.0) - _wind_lp) * 0.2 * K
			_wind_lp2 += (_wind_lp - _wind_lp2) * 0.05 * K
			s += (_wind_lp - _wind_lp2) * wind * 0.5
		if _crash > 0.001:
			_crash_lp += (_rng.randf_range(-1.0, 1.0) - _crash_lp) * 0.3 * K
			s += _crash_lp * _crash * 0.9
			_crash *= CRASH_DECAY
		if _beeps.size() > 0:
			var b: Array = _beeps[0]
			var t := float(b[1])
			s += (1.0 if fmod(t * b[0] / RATE, 1.0) < 0.5 else -1.0) * b[2]
			b[1] -= 1
			if b[1] <= 0:
				_beeps.pop_front()
		# The two banks' exhausts come out either side of the car.
		buf[i] = Vector2(clamp((s + eng.x) * master, -1.0, 1.0), clamp((s + eng.y) * master, -1.0, 1.0))
	playback.push_buffer(buf)


## A Gen 3 Cup engine: a 358 cubic inch pushrod V8 with a cross-plane crank,
## firing 1-8-4-3-6-5-7-2 (odd cylinders on the left bank). Each firing kicks the
## resonances of its bank's exhaust. On one bank the kicks come unevenly (270,
## 180, 90 and 180 degrees apart), which is the V8's burble at low rpm and turns
## into the howl at 9,000. Off the throttle it crackles and pops.
## step() gives one sample per call: x = left bank, y = right bank.
class V8:
	# Crank angle of each firing in the 720-degree cycle, and its bank (0 = left).
	const FIRING := [[0.0, 0], [90.0, 1], [180.0, 1], [270.0, 0], [360.0, 1], [450.0, 0], [540.0, 0], [630.0, 1]]
	# No two cylinders are quite alike.
	const CYL_GAIN := [1.0, 0.93, 1.05, 0.97, 1.02, 0.95, 1.04, 0.98]
	# Exhaust resonances (Hz, damping per sample at 11,025 Hz, level): the
	# collector's boom, the pipe, and the rasp.
	const FORMANTS := [[125.0, 0.992, 1.0], [360.0, 0.976, 0.9], [900.0, 0.955, 0.7], [2100.0, 0.9, 0.45]]

	var rate: float
	var _theta := 0.0
	var _cycle := 0.0
	var _next := 0
	var _a1 := PackedFloat32Array()
	var _a2 := PackedFloat32Array()
	var _g := PackedFloat32Array()
	var _y1 := PackedFloat32Array() # per bank x formant
	var _y2 := PackedFloat32Array()
	var _kick := [0.0, 0.0]
	var _rasp := [0.0, 0.0]
	var _rasp_decay := 0.0
	var _pop := 0.0
	var _pop_decay := 0.0
	var _dc := [0.0, 0.0]
	var _dc_k := 0.0
	var rng := RandomNumberGenerator.new()

	func _init(sample_rate: float, seed_v := 1) -> void:
		rate = sample_rate
		rng.seed = seed_v
		for f in FORMANTS:
			# Keep each resonance's ring time the same at any sample rate.
			var r: float = pow(float(f[1]), 11025.0 / rate)
			_a1.append(2.0 * r * cos(TAU * float(f[0]) / rate))
			_a2.append(-r * r)
			_g.append((1.0 - r) * float(f[2]) * 6.0)
		_y1.resize(2 * FORMANTS.size())
		_y2.resize(2 * FORMANTS.size())
		_rasp_decay = exp(-1.0 / (0.0012 * rate))
		_pop_decay = exp(-1.0 / (0.006 * rate))
		_dc_k = 1.0 - exp(-TAU * 30.0 / rate)

	func step(rpm: float, load: float) -> Vector2:
		_theta += rpm * 6.0 / rate # degrees of crank per sample
		_kick[0] = 0.0
		_kick[1] = 0.0
		while _theta >= _cycle + float(FIRING[_next][0]):
			var bank: int = FIRING[_next][1]
			var a: float = (0.18 + 0.82 * load) * float(CYL_GAIN[_next]) * (1.0 + rng.randf_range(-0.1, 0.1))
			_kick[bank] += a
			_rasp[bank] = max(float(_rasp[bank]), a)
			# Lifting at high rpm: unburnt fuel cracks in the pipes.
			if load < 0.15 and rpm > 5200.0 and rng.randf() < 0.012:
				_pop = 1.0
			_next += 1
			if _next == FIRING.size():
				_next = 0
				_cycle += 720.0
				if _cycle > 72000.0:
					_theta -= _cycle
					_cycle = 0.0
		var out := [0.0, 0.0]
		var nf := FORMANTS.size()
		for b in 2:
			var e: float = _kick[b] + float(_rasp[b]) * rng.randf_range(-0.35, 0.35) + _pop * rng.randf_range(-1.0, 1.0) * 1.5
			_rasp[b] = float(_rasp[b]) * _rasp_decay
			var sum := 0.0
			for k in nf:
				var j := b * nf + k
				var y := _a1[k] * _y1[j] + _a2[k] * _y2[j] + e * _g[k]
				_y2[j] = _y1[j]
				_y1[j] = y
				sum += y
			# Take out any DC, then let it saturate a little.
			_dc[b] = float(_dc[b]) + (sum - float(_dc[b])) * _dc_k
			out[b] = tanh((sum - float(_dc[b])) * 1.3 + _pop * rng.randf_range(-1.0, 1.0) * 0.9)
		_pop *= _pop_decay
		# Each side hears mostly its own bank.
		return Vector2(out[0] + out[1] * 0.55, out[1] + out[0] * 0.55) * 0.65
