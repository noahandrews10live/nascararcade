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
	_loops = [[], []]
	for l in 2:
		_loops[l].resize(BANDS.size())
	_make_fx()


func crash(strength: float) -> void:
	_crash = max(_crash, clamp(strength, 0.0, 1.0))


func beep(freq: float, seconds: float, vol := 0.35) -> void:
	_beeps.append([freq, int(seconds * RATE), vol])


# --- the engine from baked loops ------------------------------------------------
# Rendering the V8 sample by sample costs about a millisecond a frame (several on
# a phone's browser). So it's rendered once, a little each frame while you're in
# the menus, into short seamless loops at eight rpm points, on and off the
# throttle; the audio mixer then pitch-shifts and cross-fades them for next to
# nothing. Until they're ready the live synth plays, as before.

const BANDS := [1500.0, 2600.0, 3700.0, 4800.0, 5900.0, 7000.0, 8100.0, 9200.0]
const BAKE_PER_FRAME := 700 # V8 samples rendered per frame while baking
const LOOP_S := [0.45, 0.9] # loop length on / off the throttle (off is longer: the pops repeat less)
var _loops: Array = [] # [on: Array[AudioStreamWAV], off: Array[AudioStreamWAV]]
var _players: Array = [] # [on: Array[AudioStreamPlayer], off: ...]
var _bake_v8: V8
var _bake_job := 0 # 0 .. 2 * BANDS.size(); on loops first, then off
var _bake_buf := PackedFloat32Array()
var _bake_need := 0
var _bake_warm := 0
var _baked := false
var _load_s := 1.0
var baking_enabled := true
# Wind, squeal and the passing car: loops as well.
var _fx: Dictionary = {}


func loops_ready() -> bool:
	return _baked


func _bake_step() -> void:
	if _baked or not baking_enabled:
		return
	var nb := BANDS.size()
	var band: int = _bake_job % nb
	var off: bool = _bake_job >= nb
	var rpm: float = BANDS[band]
	var ld := 0.0 if off else 1.0
	if _bake_v8 == null:
		_bake_v8 = V8.new(RATE, 11 + _bake_job)
		# Whole engine cycles (two revs) so the loop's seam falls on a cycle.
		var cyc: float = RATE * 120.0 / rpm
		var ncyc: float = max(1.0, round(LOOP_S[1 if off else 0] * RATE / cyc))
		_bake_need = int(round(ncyc * cyc))
		_bake_warm = int(RATE * 0.25)
		_bake_buf.resize(0)
	if _bake_warm > 0: # settle the engine first, spread over frames too
		var w: int = min(BAKE_PER_FRAME * 2, _bake_warm)
		for i in w:
			_bake_v8.step(rpm, ld)
		_bake_warm -= w
		return
	var fade := int(RATE * 0.04)
	var total := _bake_need + fade
	var start := _bake_buf.size() / 2
	var todo: int = min(BAKE_PER_FRAME, total - start)
	for i in todo:
		var o: Vector2 = _bake_v8.step(rpm, ld) * 0.55
		_bake_buf.append(o.x)
		_bake_buf.append(o.y)
	if _bake_buf.size() / 2 >= total:
		_loops[1 if off else 0][band] = _stereo_loop(_bake_buf, _bake_need, fade)
		_bake_buf = PackedFloat32Array()
		_bake_v8 = null
		_bake_job += 1
		if _bake_job >= nb * 2:
			_start_loops()


## Interleaved stereo samples -> a looping WAV, its tail cross-faded into its head.
func _stereo_loop(buf: PackedFloat32Array, n: int, fade: int) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(n * 4)
	for i in n:
		for ch in 2:
			var v: float = buf[i * 2 + ch]
			if i < fade:
				var t := float(i) / fade
				v = v * t + buf[(n + i) * 2 + ch] * (1.0 - t)
			data.encode_s16((i * 2 + ch) * 2, int(clamp(v, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = int(RATE)
	w.stereo = true
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w


func _mono_loop(samples: PackedFloat32Array) -> AudioStreamWAV:
	var buf := PackedFloat32Array()
	buf.resize(samples.size() * 2)
	for i in samples.size():
		buf[i * 2] = samples[i]
		buf[i * 2 + 1] = samples[i]
	var fade := int(RATE * 0.05)
	return _stereo_loop(buf, samples.size() - fade, fade)


func _player(stream: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = -80.0
	if AudioServer.get_bus_index("World") >= 0:
		p.bus = "World"
	add_child(p)
	p.play()
	p.stream_paused = true
	return p


func _start_loops() -> void:
	_players = [[], []]
	for l in 2:
		for b in BANDS.size():
			_players[l].append(_player(_loops[l][b]))
	_baked = true


## Wind (rushing air), tyre squeal and the tone of a car going by, as loops.
func _make_fx() -> void:
	var n := int(RATE * 2.0)
	var wind := PackedFloat32Array()
	var sq := PackedFloat32Array()
	var ps := PackedFloat32Array()
	wind.resize(n)
	sq.resize(n)
	ps.resize(n)
	var a := 0.0
	var b := 0.0
	var ph := 0.0
	var pph := 0.0
	var lp := 0.0
	for i in n:
		a += (_rng.randf_range(-1.0, 1.0) - a) * 0.2 * K
		b += (a - b) * 0.05 * K
		wind[i] = (a - b) * 0.5
		ph = fmod(ph + (820.0 + sin(ph * 40.0) * 20.0) / RATE, 1.0)
		sq[i] = (sin(ph * TAU) * 0.6 + _rng.randf_range(-0.4, 0.4)) * 0.12
		pph = fmod(pph + 140.0 / RATE, 1.0)
		lp += ((pph * 2.0 - 1.0) - lp) * 0.12 * K
		ps[i] = lp * 0.3
	_fx = {"wind": _player(_mono_loop(wind)), "squeal": _player(_mono_loop(sq)), "pass": _player(_mono_loop(ps))}


func _set_level(p: AudioStreamPlayer, gain: float) -> void:
	if gain < 0.004:
		if not p.stream_paused:
			p.stream_paused = true
		return
	p.volume_db = linear_to_db(gain) - 4.0
	if p.stream_paused:
		p.stream_paused = false


func _update_loops(delta: float) -> void:
	var target_rpm := engine_rpm if engine_on else 0.0
	_rpm_s += (target_rpm - _rpm_s) * (1.0 - exp(-delta * 36.0))
	_load_s += (engine_load - _load_s) * (1.0 - exp(-delta * 12.0))
	var nb := BANDS.size()
	var gains := [PackedFloat32Array(), PackedFloat32Array()]
	gains[0].resize(nb)
	gains[1].resize(nb)
	if _rpm_s > 200.0:
		var i := 0
		while i < nb - 2 and _rpm_s >= BANDS[i + 1]:
			i += 1
		var t: float = clamp((_rpm_s - BANDS[i]) / (BANDS[i + 1] - BANDS[i]), 0.0, 1.0)
		var on: float = sqrt(clamp(_load_s, 0.0, 1.0))
		var off: float = sqrt(1.0 - clamp(_load_s, 0.0, 1.0))
		gains[0][i] = sqrt(1.0 - t) * on
		gains[0][i + 1] = sqrt(t) * on
		gains[1][i] = sqrt(1.0 - t) * off
		gains[1][i + 1] = sqrt(t) * off
	for l in 2:
		for b in nb:
			var p: AudioStreamPlayer = _players[l][b]
			if gains[l][b] > 0.004:
				p.pitch_scale = clamp(_rpm_s / BANDS[b], 0.25, 4.0)
			_set_level(p, gains[l][b] * master)
	_set_level(_fx.wind, wind * master)
	_set_level(_fx.squeal, (squeal if squeal > 0.02 else 0.0) * master)
	_set_level(_fx["pass"], (pass_volume if pass_volume > 0.01 else 0.0) * master)
	if pass_volume > 0.01:
		_fx["pass"].pitch_scale = clamp(pass_pitch, 0.3, 3.0)


func _process(delta: float) -> void:
	if playback == null:
		return
	if not _baked and not engine_on:
		_bake_step() # a little each frame in the menus
	if _baked:
		_update_loops(delta)
	var frames := playback.get_frames_available()
	if frames <= 0:
		return
	if _baked and _crash <= 0.001 and _beeps.is_empty():
		var quiet := PackedVector2Array()
		quiet.resize(frames)
		playback.push_buffer(quiet) # nothing live to play
		return
	playback.push_buffer(_render(frames))


## The next `frames` samples of everything the synth plays.
func _render(frames: int) -> PackedVector2Array:
	var buf := PackedVector2Array()
	buf.resize(frames)
	var target_rpm := engine_rpm if engine_on else 0.0
	var live := not _baked # once the loops play, only crashes and beeps are live
	for i in frames:
		var s := 0.0
		var eng := Vector2.ZERO
		if live:
			_rpm_s += (target_rpm - _rpm_s) * 0.0015 * K
			if _rpm_s > 200.0:
				eng = _v8.step(_rpm_s, engine_load) * 0.55
		if live and pass_volume > 0.01:
			var pf := 140.0 * pass_pitch
			_pass_ph = fmod(_pass_ph + pf / RATE, 1.0)
			var saw := _pass_ph * 2.0 - 1.0
			_lp2 += (saw - _lp2) * 0.12 * K
			s += _lp2 * pass_volume * 0.3
		if live and squeal > 0.02:
			_sq_ph = fmod(_sq_ph + (820.0 + sin(_sq_ph * 40.0) * 20.0) / RATE, 1.0)
			s += (sin(_sq_ph * TAU) * 0.6 + _rng.randf_range(-0.4, 0.4)) * squeal * 0.12
		if live and wind > 0.01:
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
	return buf


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
