extends Node
## The score, synthesised live like the engine (no audio files): a four-voice
## band (pad, bass, lead, drums) playing short cues.
##   "anthem"  - the intro: broad major chords that swell, timpani on the one;
##   "menu"    - a laid-back groove behind the menus;
##   "lastlap" - driving minor-key pulse, four on the floor, a noise riser that
##               climbs with `intensity`;
##   "victory" - a bright fanfare: arpeggios over big chords and drums;
##   "caution" - a low, tense pulse while the field circulates under yellow;
##   "qualify" - a light, steady groove for qualifying runs;
##   "results" - a warm wind-down behind the results.
## A driven guitar plays power chords in the rock cues, brass stabs punctuate the
## anthem and victory, and claps sit on two and four.
## play(cue) cross-fades; stop() fades out. Races run without music (like TV)
## apart from cautions and the last lap.

const RATE := 11025.0
const BPM := 124.0

var player: AudioStreamPlayer
var playback: AudioStreamGeneratorPlayback
var cue := ""
var intensity := 0.0 # 0..1, the last-lap build
var volume := 0.55

var _gain := 0.0
var _target_gain := 0.0
var _t := 0.0 # seconds into the cue
var _ph := PackedFloat32Array() # oscillator phases
var _lp := [0.0, 0.0, 0.0, 0.0, 0.0]
var _gtr_env := 0.0
var _brass_env := 0.0
var _clap_env := 0.0
var _kick_env := 0.0
var _kick_ph := 0.0
var _snare_env := 0.0
var _hat_env := 0.0
var _step := -1
var _rng := RandomNumberGenerator.new()

# Chords as semitones from A (220 Hz). Each cue: [chords per bar, bars].
const CUES := {
	"anthem": [[2, 6, 9], [9, 13, 16], [11, 14, 18], [7, 11, 14]], # D  A  Bm  G
	"menu": [[0, 4, 7], [5, 9, 12], [9, 12, 16], [7, 11, 14]], # A  D  F#m  E
	"lastlap": [[0, 3, 7], [0, 3, 7], [8, 12, 15], [10, 14, 17]], # Am  Am  F  G
	"victory": [[2, 6, 9], [7, 11, 14], [9, 13, 16], [2, 6, 9]], # D  G  A  D
	"caution": [[0, 3, 7], [0, 3, 7], [5, 8, 12], [7, 10, 14]], # Am  Am  Dm  Em
	"qualify": [[0, 4, 7], [7, 11, 14], [9, 12, 16], [5, 9, 12]], # A  E  F#m  D
	"results": [[5, 9, 12], [0, 4, 7], [9, 12, 16], [7, 11, 14]], # D  A  F#m  E
}
## How loud each cue sits (the in-race ones stay under the engines).
const CUE_GAIN := {"caution": 0.55, "qualify": 0.6, "results": 0.8}
## Tempo relative to BPM (the caution cue plods along at half speed).
const CUE_TEMPO := {"caution": 0.5, "results": 0.8}
const GUITAR := ["lastlap", "victory", "qualify"]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	player = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.15
	player.stream = gen
	player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	player.volume_db = -3.0
	add_child(player)
	player.play()
	playback = player.get_stream_playback()
	_ph.resize(16)


func play(name: String) -> void:
	if name == cue and _target_gain > 0.0:
		return
	if cue != name:
		_t = 0.0
		_step = -1
	cue = name
	_target_gain = CUE_GAIN.get(name, 1.0)


func stop() -> void:
	_target_gain = 0.0


func _note(semi: float) -> float:
	return 220.0 * pow(2.0, semi / 12.0)


func _process(_delta: float) -> void:
	if playback == null:
		return
	var frames := playback.get_frames_available()
	if frames <= 0:
		return
	var buf := PackedVector2Array()
	buf.resize(frames)
	if cue == "" or (_gain <= 0.0005 and _target_gain == 0.0):
		_gain = 0.0
		playback.push_buffer(buf) # silence
		return
	var chords: Array = CUES[cue]
	var beat := 60.0 / (BPM * float(CUE_TEMPO.get(cue, 1.0)))
	var bar := beat * 4.0
	for i in frames:
		_gain = move_toward(_gain, _target_gain, 1.0 / (RATE * (0.4 if _target_gain > _gain else 1.6)))
		var ci := int(_t / bar) % chords.size()
		var chord: Array = chords[ci]
		var step := int(_t / (beat * 0.25)) # sixteenths
		if step != _step:
			_step = step
			_trigger(step % 16)
		var s := 0.0
		# Pad: each chord note on two detuned saws, gently filtered.
		var pad := 0.0
		for k in 3:
			var f := _note(float(chord[k]) - 12.0)
			_ph[k * 2] = fmod(_ph[k * 2] + f / RATE, 1.0)
			_ph[k * 2 + 1] = fmod(_ph[k * 2 + 1] + f * 1.006 / RATE, 1.0)
			pad += (_ph[k * 2] * 2.0 - 1.0) + (_ph[k * 2 + 1] * 2.0 - 1.0)
		var swell := 1.0
		if cue == "anthem":
			swell = clamp(_t / 6.0, 0.15, 1.0)
		var cut := 0.08 + 0.1 * swell + (0.08 * intensity if cue == "lastlap" else 0.0)
		_lp[0] += (pad - _lp[0]) * cut
		s += _lp[0] * 0.05 * swell
		# Bass: the root, pumping on the sixteenths in the last-lap cue.
		var bf := _note(float(chord[0]) - 24.0)
		_ph[6] = fmod(_ph[6] + bf / RATE, 1.0)
		var bass := 1.0 if _ph[6] < 0.5 else -1.0
		_lp[1] += (bass - _lp[1]) * 0.06
		var pump := 1.0
		if cue == "lastlap":
			pump = 1.0 - fmod(_t / (beat * 0.25), 1.0) * 0.7
		s += _lp[1] * 0.11 * pump * (0.6 if cue == "menu" else 1.0)
		# Lead: arpeggio through the chord (victory and last lap).
		if cue == "victory" or (cue == "lastlap" and intensity > 0.4):
			var arp: float = float(chord[step % 3]) + (12.0 if (step / 3) % 2 == 0 else 24.0)
			_ph[7] = fmod(_ph[7] + _note(arp - 12.0) / RATE, 1.0)
			var tri: float = 1.0 - 4.0 * abs(_ph[7] - 0.5)
			var env: float = 1.0 - fmod(_t / (beat * 0.25), 1.0) * 0.8
			s += tri * env * (0.08 if cue == "victory" else 0.05 * intensity)
		# Guitar: a power chord (root, fifth, octave) through a fuzz, chugging
		# eighths that ring out on the accents.
		if cue in GUITAR and (cue != "lastlap" or intensity > 0.15):
			var r := float(chord[0]) - 12.0
			var g := 0.0
			for k2 in 3:
				var fq := _note(r + [0.0, 7.0, 12.0][k2])
				_ph[8 + k2] = fmod(_ph[8 + k2] + fq * (1.0 + 0.003 * k2) / RATE, 1.0)
				g += _ph[8 + k2] * 2.0 - 1.0
			g = tanh(g * 3.5 * (0.4 + _gtr_env))
			_lp[3] += (g - _lp[3]) * 0.25
			s += _lp[3] * _gtr_env * (0.09 if cue != "qualify" else 0.05)
			_gtr_env *= 0.99975 if _gtr_env > 0.7 else 0.9994
		# Brass: a bright stab of the whole chord.
		if _brass_env > 0.002:
			var b := 0.0
			for k3 in 3:
				var fb := _note(float(chord[k3]))
				_ph[11 + k3] = fmod(_ph[11 + k3] + fb / RATE, 1.0)
				b += _ph[11 + k3] * 2.0 - 1.0
			_lp[4] += (b - _lp[4]) * (0.05 + 0.25 * _brass_env)
			s += _lp[4] * _brass_env * 0.07
			_brass_env *= 0.99965
		if _clap_env > 0.001:
			s += _rng.randf_range(-1.0, 1.0) * _clap_env * 0.16
			_clap_env *= 0.9955
		# Drums.
		if _kick_env > 0.001:
			_kick_ph += (45.0 + 110.0 * _kick_env * _kick_env) / RATE
			s += sin(_kick_ph * TAU) * _kick_env * 0.5
			_kick_env *= 0.9975
		if _snare_env > 0.001:
			s += _rng.randf_range(-1.0, 1.0) * _snare_env * 0.22
			_snare_env *= 0.9965
		if _hat_env > 0.001:
			var n := _rng.randf_range(-1.0, 1.0)
			_lp[2] += (n - _lp[2]) * 0.5
			s += (n - _lp[2]) * _hat_env * 0.12
			_hat_env *= 0.985
		# The last-lap riser: noise sweeping up as the finish nears.
		if cue == "lastlap" and intensity > 0.0:
			s += _rng.randf_range(-1.0, 1.0) * 0.05 * intensity * intensity * (0.5 + 0.5 * sin(_t * TAU * (2.0 + intensity * 6.0)))
		s = tanh(s * 1.4) * volume * _gain
		buf[i] = Vector2(s, s)
		_t += 1.0 / RATE
	playback.push_buffer(buf)


func _trigger(st: int) -> void:
	if cue in GUITAR and st % 2 == 0:
		_gtr_env = 1.0 if st % 8 == 0 else 0.45
	match cue:
		"anthem":
			if st == 0:
				_kick_env = 1.0
				_kick_ph = 0.0
				_brass_env = 1.0
			if st == 6 and int(_t / (60.0 / BPM * 4.0)) % 2 == 1:
				_brass_env = 0.8
		"menu":
			if st == 0 or st == 10:
				_kick_env = 0.7
				_kick_ph = 0.0
			if st == 4 or st == 12:
				_snare_env = 0.5
			if st % 4 == 2:
				_hat_env = 0.6
		"lastlap":
			if st % 4 == 0:
				_kick_env = 1.0
				_kick_ph = 0.0
			if st == 4 or st == 12:
				_snare_env = 0.9
			if st % 2 == 0:
				_hat_env = 0.5 + 0.5 * intensity
			if intensity > 0.7 and st % 2 == 1:
				_snare_env = max(_snare_env, 0.35 * intensity) # the snare roll into the flag
		"victory":
			if st == 0 or st == 8:
				_kick_env = 1.0
				_kick_ph = 0.0
			if st == 0:
				_brass_env = 1.0
			if st == 4 or st == 12:
				_snare_env = 0.8
				_clap_env = 1.0
			if st % 2 == 0:
				_hat_env = 0.6
		"caution":
			# A heartbeat: two soft kicks, and a tick.
			if st == 0 or st == 3:
				_kick_env = 0.6
				_kick_ph = 0.0
			if st == 8:
				_hat_env = 0.3
		"qualify":
			if st == 0 or st == 8:
				_kick_env = 0.8
				_kick_ph = 0.0
			if st == 4 or st == 12:
				_snare_env = 0.55
			if st % 2 == 0:
				_hat_env = 0.45
		"results":
			if st == 0:
				_kick_env = 0.6
				_kick_ph = 0.0
			if st == 4 or st == 12:
				_clap_env = 0.7
			if st % 4 == 2:
				_hat_env = 0.35
