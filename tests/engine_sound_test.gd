extends SceneTree
## The engine sound is a cross-plane pushrod V8 that follows the rpm:
##   - its strongest tone is the firing frequency, 4 pulses per crank turn
##     (rpm / 15: 600 Hz at 9,000 rpm), not the 2 of a four-cylinder;
##   - one bank alone carries the half-order burble (rpm / 120) of the uneven
##     cross-plane firing;
##   - the tone rises in step with the rpm;
##   - sensible levels, no clipping; lifting at high rpm pops;
##   - the other cars' loop repeats without a click;
##   - cheap enough to run live.
## OUT=/dir also writes a rev-up, a lift and a pass-by as WAV files.
##   godot --headless -s tests/engine_sound_test.gd

const RATE := 11025.0
var failures := 0


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1


func _initialize() -> void:
	_run.call_deferred()


## Power of frequency f in the signal (Goertzel).
func _power(x: PackedFloat32Array, f: float, rate := RATE) -> float:
	var w := TAU * f / rate
	var c := 2.0 * cos(w)
	var s1 := 0.0
	var s2 := 0.0
	for v in x:
		var s0 := v + c * s1 - s2
		s2 = s1
		s1 = s0
	return (s1 * s1 + s2 * s2 - c * s1 * s2) / (x.size() * x.size())


## The strongest partial between lo and hi Hz (1 Hz steps near the candidates).
func _peak(x: PackedFloat32Array, lo: float, hi: float) -> float:
	var best := lo
	var bp := -1.0
	var f := lo
	while f <= hi:
		var p := _power(x, f)
		if p > bp:
			bp = p
			best = f
		f += 2.0
	return best


func _render(rpm: float, load: float, secs: float, bank := -1) -> PackedFloat32Array:
	var Synth = load("res://scripts/audio.gd")
	var v8 = Synth.V8.new(RATE, 3)
	for i in int(RATE * 0.3):
		v8.step(rpm, load)
	var out := PackedFloat32Array()
	for i in int(RATE * secs):
		var o: Vector2 = v8.step(rpm, load)
		out.append((o.x + o.y) * 0.5 if bank < 0 else (o.x if bank == 0 else o.y))
	return out


func _run() -> void:
	var peaks := {}
	for rpm: float in [4500.0, 7500.0, 9000.0]:
		var x := _render(rpm, 1.0, 0.5)
		var fire := rpm / 15.0
		var four := rpm / 30.0
		var pf := _power(x, fire)
		var p4 := _power(x, four)
		var pk := _peak(x, fire * 0.6, fire * 1.5)
		peaks[rpm] = pk
		var rms := 0.0
		var mx := 0.0
		for v in x:
			rms += v * v
			mx = max(mx, abs(v))
		rms = sqrt(rms / x.size())
		print("   %d rpm: firing %.0f Hz power %s, four-cylinder %.0f Hz %s, peak near firing %.0f Hz, rms %.2f, max %.2f" % [rpm, fire, str(pf), four, str(p4), pk, rms, mx])
		_check(pf > p4 * 3.0, "%d rpm: the V8 firing frequency dominates (not a four-cylinder's)" % rpm)
		_check(abs(pk - fire) < fire * 0.04, "%d rpm: the main tone is at the firing frequency" % rpm)
		_check(rms > 0.08 and rms < 0.6 and mx < 1.0, "%d rpm: sensible level, no clipping" % rpm)
	_check(abs(peaks[9000.0] / peaks[4500.0] - 2.0) < 0.08, "the tone follows the rpm (9,000 is an octave above 4,500)")
	# One bank on its own: the uneven cross-plane pulses give it half-order content.
	var lb := _render(3000.0, 0.6, 1.0, 0)
	var half := _power(lb, 3000.0 / 120.0 * 3.0) + _power(lb, 3000.0 / 120.0 * 5.0)
	var even := _power(lb, 3000.0 / 15.0)
	print("   one bank at 3,000 rpm: odd half-orders %s vs firing %s" % [str(half), str(even)])
	_check(half > even * 0.05, "one bank burbles: the uneven cross-plane firing shows")
	# Lifting at high rpm: occasional big cracks.
	var lift := _render(8500.0, 0.0, 2.0)
	var cracks := 0
	var mean := 0.0
	for v in lift:
		mean += abs(v)
	mean /= lift.size()
	var hold := 0
	for v in lift:
		hold -= 1
		if abs(v) > mean * 4.0 and hold <= 0:
			cracks += 1
			hold = int(RATE * 0.02)
	print("   lifting at 8,500 rpm for 2 s: %d cracks" % cracks)
	_check(cracks >= 2, "lifting at high rpm crackles and pops")
	# The other cars' loop: no click at the seam.
	var sc = load("res://scripts/soundscape.gd").new()
	var wav: AudioStreamWAV = sc._make_engine_loop()
	var d: PackedByteArray = wav.data
	var n := d.size() / 2
	var step_max := 0.0
	var step_mean := 0.0
	for i in range(1, n):
		var st: float = abs(d.decode_s16(i * 2) - d.decode_s16(i * 2 - 2))
		step_max = max(step_max, st)
		step_mean += st
	step_mean /= n
	var seam: float = abs(d.decode_s16(0) - d.decode_s16((n - 1) * 2))
	print("   loop: %d samples, seam step %d, typical step %.0f, largest %d" % [n, seam, step_mean, step_max])
	_check(seam < step_max * 0.9 and seam < step_mean * 4.0, "the other cars' engine loop repeats without a click")
	sc.free()
	# Cost: samples per millisecond of script time (the live synth needs ~11 per ms).
	var Synth = load("res://scripts/audio.gd")
	var v8 = Synth.V8.new(RATE, 1)
	var t0 := Time.get_ticks_usec()
	for i in 11025:
		v8.step(8000.0, 1.0)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("   one second of engine: %.1f ms of script time" % ms)
	_check(ms < 250.0, "cheap enough to run live")
	# Your own engine from the loops baked in the menus.
	var syn = Synth.new()
	root.add_child(syn)
	await process_frame
	var steps := 0
	while not syn.loops_ready() and steps < 2000:
		syn._bake_step()
		steps += 1
	_check(syn.loops_ready(), "the engine loops bake in the menus (%d frames)" % steps)
	var bw: AudioStreamWAV = syn._loops[0][3]
	var wd := bw.data
	var wn: int = bw.loop_end
	var wmax := 0.0
	for i in range(1, wn):
		wmax = max(wmax, abs(wd.decode_s16(i * 4) - wd.decode_s16((i - 1) * 4)))
	var wseam: float = abs(wd.decode_s16(0) - wd.decode_s16((wn - 1) * 4))
	_check(wseam <= wmax, "a baked loop repeats without a click (seam step %d, largest step in the loop %d)" % [wseam, wmax])
	syn.engine_on = true
	syn.engine_rpm = 6500.0
	syn.engine_load = 1.0
	for i in 60:
		syn._update_loops(1.0 / 60.0)
	var loud := []
	for b in syn.BANDS.size():
		var pl: AudioStreamPlayer = syn._players[0][b]
		if not pl.stream_paused and pl.volume_db > -30.0:
			loud.append("%d rpm x%.2f" % [syn.BANDS[b], pl.pitch_scale])
	print("   6,500 rpm on the gas plays: ", loud)
	_check(loud.size() == 2 and absf(syn._players[0][4].pitch_scale * syn.BANDS[4] - 6500.0) < 60.0, "6,500 rpm blends the 5,900 and 7,000 loops, each pitched to 6,500")
	syn.engine_load = 0.0
	for i in 60:
		syn._update_loops(1.0 / 60.0)
	_check(syn._players[0][4].stream_paused and not syn._players[1][4].stream_paused, "lifting swaps to the off-throttle loops")
	syn.queue_free()
	var out := OS.get_environment("OUT")
	if out != "":
		_save(out)
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)


## A lap-like demo: idle, rev up through the gears, lift, then a car passing.
func _save(out: String) -> void:
	var Synth = load("res://scripts/audio.gd")
	var v8 = Synth.V8.new(RATE, 5)
	var samples := PackedVector2Array()
	var rpm := 3000.0
	var t := 0.0
	var gear := 1
	var dt := 1.0 / RATE
	while t < 9.0:
		var load := 1.0
		if t < 1.2:
			load = 0.2
			rpm = 3000.0 + sin(t * 6.0) * 150.0
		elif t < 6.5:
			rpm += (9200.0 - rpm) * dt * (1.4 / gear)
			if rpm > 9000.0 and gear < 4:
				gear += 1
				rpm = 7000.0
		else:
			load = 0.0
			rpm = max(4500.0, rpm - 2600.0 * dt)
		samples.append(v8.step(rpm, load) * 0.8)
		t += dt
	_write(samples, out.path_join("v8_rev.wav"))
	print("wrote ", out.path_join("v8_rev.wav"))


func _write(s: PackedVector2Array, path: String) -> void:
	var data := PackedByteArray()
	data.resize(s.size() * 4)
	for i in s.size():
		data.encode_s16(i * 4, int(clamp(s[i].x, -1.0, 1.0) * 32000.0))
		data.encode_s16(i * 4 + 2, int(clamp(s[i].y, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = int(RATE)
	w.stereo = true
	w.data = data
	w.save_to_wav(path)
