extends Node
## Tiny software synth: engine drone, passing cars, tyre squeal, crunches and beeps.
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
var master := 0.8

var _ph1 := 0.0
var _ph2 := 0.0
var _ph3 := 0.0
var _pass_ph := 0.0
var _sq_ph := 0.0
var _lp := 0.0
var _lp2 := 0.0
var _rpm_s := 0.0
var _crash := 0.0
var _crash_lp := 0.0
var _beeps: Array = [] # [freq, remaining_samples, volume]
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	player = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.12
	player.stream = gen
	player.volume_db = -4.0
	# Web exports default to sample playback, which cannot play a generator stream.
	player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
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
		if _rpm_s > 200.0:
			# V8 burble: pulse wave at firing frequency with a sub harmonic, low passed.
			var f := _rpm_s / 60.0 * 2.0
			_ph1 = fmod(_ph1 + f / RATE, 1.0)
			_ph2 = fmod(_ph2 + f * 0.5 / RATE, 1.0)
			_ph3 = fmod(_ph3 + f * 1.505 / RATE, 1.0)
			var pulse := (1.0 if _ph1 < 0.32 else -0.6) + (0.7 if _ph2 < 0.5 else -0.7) * 0.6
			pulse += (_ph3 * 2.0 - 1.0) * 0.25
			var cut := minf(1.0, (0.08 + engine_load * 0.25) * K)
			_lp += (pulse - _lp) * cut
			s += _lp * (0.22 + engine_load * 0.12)
		if pass_volume > 0.01:
			var pf := 140.0 * pass_pitch
			_pass_ph = fmod(_pass_ph + pf / RATE, 1.0)
			var saw := _pass_ph * 2.0 - 1.0
			_lp2 += (saw - _lp2) * 0.12 * K
			s += _lp2 * pass_volume * 0.3
		if squeal > 0.02:
			_sq_ph = fmod(_sq_ph + (820.0 + sin(_sq_ph * 40.0) * 20.0) / RATE, 1.0)
			s += (sin(_sq_ph * TAU) * 0.6 + _rng.randf_range(-0.4, 0.4)) * squeal * 0.12
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
		s = clamp(s * master, -1.0, 1.0)
		buf[i] = Vector2(s, s)
	playback.push_buffer(buf)
