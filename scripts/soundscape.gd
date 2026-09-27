extends Node3D
## The world you hear: every nearby car's engine placed in 3D (with Doppler as
## they pass), the grandstands, and the echo off walls and stands.
##
## Sounds are synthesised once at startup into short seamless loops, then played
## by a small pool of 3D players that follow the cars nearest the camera. Your
## own engine stays on the live synth (audio.gd) so it answers the throttle
## instantly; it goes through the same "World" bus, so it echoes too.

const Synth := preload("res://scripts/audio.gd")
const RATE := 22000
const ENGINE_BASE_RPM := 7500.0 # the loop is recorded at this rpm (500 Hz firing), about race pace
const POOL := 8
const SOUND_SPEED := 343.0

var engine_loop: AudioStreamWAV
var crowd_loop: AudioStreamWAV
var players: Array[AudioStreamPlayer3D] = []
var assigned: Array = [] # car (or null) per player
var crowd: Array[AudioStreamPlayer3D] = []
var reverb: AudioEffectReverb
var cockpit_filter: AudioEffectLowPassFilter
var world_bus := -1
var level_db := 0.0 # quieter behind the menus
var excitement := 0.0 # 0..1: the crowd roars on wrecks, lead changes, the finish
var _prev_pos := {} # car -> last position, for Doppler
var _cam_prev := Vector3.ZERO
var _race: Node3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_bus()
	engine_loop = _make_engine_loop()
	crowd_loop = _make_crowd_loop()
	for i in POOL:
		var p := AudioStreamPlayer3D.new()
		p.stream = engine_loop
		p.bus = "World"
		p.unit_size = 9.0
		p.max_distance = 450.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		# Distance takes the top off: far cars are a low rumble.
		p.attenuation_filter_cutoff_hz = 9000.0
		p.attenuation_filter_db = -18.0
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED # done by hand below
		p.max_polyphony = 1
		add_child(p)
		players.append(p)
		assigned.append(null)


func _make_bus() -> void:
	world_bus = AudioServer.get_bus_index("World")
	if world_bus < 0:
		AudioServer.add_bus()
		world_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(world_bus, "World")
		AudioServer.set_bus_send(world_bus, "Master")
		reverb = AudioEffectReverb.new()
		reverb.room_size = 0.55
		reverb.damping = 0.6
		reverb.spread = 0.8
		reverb.dry = 1.0
		reverb.wet = 0.08
		reverb.predelay_msec = 40.0
		AudioServer.add_bus_effect(world_bus, reverb)
		cockpit_filter = AudioEffectLowPassFilter.new()
		cockpit_filter.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(world_bus, cockpit_filter)
	else:
		reverb = AudioServer.get_bus_effect(world_bus, 0)
		cockpit_filter = AudioServer.get_bus_effect(world_bus, 1)


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clamp(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = samples.size()
	return w


## The race engine at 7,500 rpm and nearly full throttle, from the same V8 as
## your own car (audio.gd): 25 engine cycles, the end cross-faded into the start
## so it loops without a click. Each car's player pitches it to that car's rpm.
func _make_engine_loop() -> AudioStreamWAV:
	var v8 = Synth.V8.new(RATE, 7)
	var n := RATE * 2 / 5 # 0.4 s = 25 cycles at 7,500 rpm
	var fade := RATE / 20
	for i in RATE: # let the exhaust ring up first
		v8.step(ENGINE_BASE_RPM, 0.9)
	var raw := PackedFloat32Array()
	raw.resize(n + fade)
	for i in n + fade:
		var o: Vector2 = v8.step(ENGINE_BASE_RPM, 0.9)
		raw[i] = (o.x + o.y) * 0.5
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = raw[i]
		if i < fade:
			var t := float(i) / fade
			out[i] = raw[i] * t + raw[n + i] * (1.0 - t)
	return _wav(out)


## A crowd: many voices as band-limited noise with slow swells, cross-faded at
## the seam.
func _make_crowd_loop() -> AudioStreamWAV:
	var n := RATE * 4
	var fade := RATE / 4
	var raw := PackedFloat32Array()
	raw.resize(n + fade)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var a := 0.0
	var b := 0.0
	for i in raw.size():
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		a += (x - a) * 0.25 # low pass ~1.2 kHz
		b += (a - b) * 0.03 # take out the rumble below ~100 Hz
		var swell := 0.7 + 0.2 * sin(t * 1.7) + 0.1 * sin(t * 4.3 + 1.0)
		raw[i] = (a - b) * swell * 1.6
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = raw[i]
	for i in fade:
		var k := float(i) / fade
		out[i] = raw[n + i] * (1.0 - k) + raw[i] * k
	return _wav(out)


## Place the grandstand voices (called once the track is built).
func build_crowd(track: Node3D) -> void:
	for p in crowd:
		p.queue_free()
	crowd.clear()
	if track == null:
		return
	var spots: Array = track.crowd_spots() if track.has_method("crowd_spots") else []
	for spot in spots:
		var p := AudioStreamPlayer3D.new()
		p.stream = crowd_loop
		p.bus = "World"
		p.unit_size = 40.0
		p.max_distance = 900.0
		p.volume_db = -14.0
		p.position = spot
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(p)
		p.play(randf() * 3.0)
		crowd.append(p)


func cheer(amount: float) -> void:
	excitement = max(excitement, clamp(amount, 0.0, 1.0))


func stop_all() -> void:
	for i in POOL:
		players[i].stop()
		assigned[i] = null
	_prev_pos.clear()


## Called every frame with the race (or null), the camera, the car you're riding
## in (skipped: the live synth plays it) and whether the camera is inside a car.
func update(race: Node3D, cam: Camera3D, own: Node3D, inside: bool, delta: float) -> void:
	excitement = max(excitement - delta * 0.12, 0.0)
	for p in crowd:
		p.volume_db = lerp(-16.0, -2.0, excitement) + level_db
		p.pitch_scale = 1.0 + excitement * 0.12
	cockpit_filter.cutoff_hz = 2600.0 if inside else 20000.0
	if race == null or cam == null or delta <= 0.0:
		stop_all()
		return
	if race != _race:
		stop_all() # a new race: the old cars are gone
		_race = race
	var cam_pos: Vector3 = cam.global_position
	var cam_vel: Vector3 = (cam_pos - _cam_prev) / delta
	if cam_vel.length() > 250.0:
		cam_vel = Vector3.ZERO # a camera cut, not motion
	_cam_prev = cam_pos
	# The nearest cars get a voice; a car keeps its player while it stays near.
	var near: Array = []
	for c in race.cars:
		if c == own or c.towed or not c.visible:
			continue
		var dd: float = c.global_position.distance_squared_to(cam_pos)
		if dd < 400.0 * 400.0:
			near.append([dd, c])
	near.sort_custom(func(x, y): return x[0] < y[0])
	var want := {}
	for k in min(POOL, near.size()):
		want[near[k][1]] = true
	for i in POOL:
		var a = assigned[i]
		# (A car freed with its race compares oddly against null: check validity first.)
		if not is_instance_valid(a) or not want.has(a):
			if a != null or players[i].playing:
				players[i].stop()
			assigned[i] = null
	for c in want:
		if assigned.has(c):
			continue
		var slot := assigned.find(null)
		if slot < 0:
			break
		assigned[slot] = c
		_prev_pos[c] = c.global_position
		players[slot].global_position = c.global_position
		players[slot].play(randf() * 0.5)
	# Pitch from rpm and Doppler; loudness from throttle.
	for i in POOL:
		var c = assigned[i]
		if c == null:
			continue
		var p := players[i]
		var pos: Vector3 = c.global_position
		var vel: Vector3 = (pos - _prev_pos.get(c, pos)) / delta
		if vel.length() > 200.0:
			vel = Vector3.ZERO
		_prev_pos[c] = pos
		p.global_position = pos
		var to_cam: Vector3 = (cam_pos - pos).normalized()
		var src: float = vel.dot(to_cam) # towards the listener
		var lis: float = cam_vel.dot(to_cam) # listener moving away
		var doppler: float = clamp((SOUND_SPEED - lis) / max(SOUND_SPEED - src, 60.0), 0.5, 2.0)
		p.pitch_scale = clamp(c.rpm() / ENGINE_BASE_RPM, 0.3, 2.0) * doppler
		p.volume_db = lerp(-8.0, 2.0, clamp(c.throttle, 0.0, 1.0)) + level_db
	# Echo: stronger beside walls and grandstands, wider under the stands.
	var track: Node3D = race.track
	var wall := 0.0
	var stands := 0.0
	if own and track:
		wall = clamp(1.0 - (track.width * 0.5 - abs(own.d)) / 6.0, 0.0, 1.0)
		if track.has_method("near_stands"):
			stands = track.near_stands(own.s())
	reverb.wet = 0.06 + 0.12 * wall + 0.22 * stands
	reverb.room_size = 0.45 + 0.35 * stands
