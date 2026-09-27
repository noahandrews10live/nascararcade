extends SceneTree
## CPU cost of the synthesised sound: the engine (V8 model and effects) and the
## music, per second of audio and per 60 fps frame, before and after the engine
## loops are baked and the music cue is recorded.
##   godot --headless -s tests/audio_cost_bench.gd

func _initialize() -> void:
	_run.call_deferred()


func _time(node: Node, reps := 5) -> float:
	var t0 := Time.get_ticks_usec()
	for r in reps:
		node._render(int(node.RATE))
	return (Time.get_ticks_usec() - t0) / 1000.0 / reps


func _say(what: String, ms_s: float) -> void:
	print("%s: %.1f ms per second of audio = %.2f ms per frame at 60 fps" % [what, ms_s, ms_s / 60.0])


func _run() -> void:
	var Synth: GDScript = load("res://scripts/audio.gd")
	var s = Synth.new()
	root.add_child(s)
	s.engine_on = true
	s.engine_rpm = 8000.0
	s.engine_load = 1.0
	s.wind = 0.6
	s.pass_volume = 0.3
	await process_frame
	_say("ENGINE (live synth)", _time(s))
	var steps := 0
	var worst := 0
	while not s.loops_ready():
		var t0 := Time.get_ticks_usec()
		s._bake_step()
		worst = max(worst, Time.get_ticks_usec() - t0)
		steps += 1
	print("ENGINE bake: %d menu frames (%.1f s at 60 fps), worst frame %.2f ms" % [steps, steps / 60.0, worst / 1000.0])
	var t1 := Time.get_ticks_usec()
	for i in 60:
		s._update_loops(1.0 / 60.0)
	var upd := (Time.get_ticks_usec() - t1) / 1000.0
	_say("ENGINE (baked loops)", _time(s) + upd)
	var Music: GDScript = load("res://scripts/music.gd")
	var m = Music.new()
	root.add_child(m)
	m.play("lastlap")
	m.intensity = 0.8
	await process_frame
	_say("MUSIC (live, lastlap)", _time(m))
	m.play("caution")
	await process_frame
	var n := 0
	while not m.cached("caution") and n < 40:
		m._render(int(m.RATE))
		n += 1
	print("   caution recorded after %d s of play: %s" % [n, m.cached("caution")])
	await create_timer(0.5).timeout
	print("   the recording plays: ", m._loop_player.playing)
	_say("MUSIC (recorded cue)", _time(m))
	quit(0)
