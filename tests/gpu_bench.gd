extends SceneTree
## A repeatable benchmark route: a 20-car race on one track, the chase camera,
## 20 seconds after the start. Prints frame times (avg, 95th percentile, worst)
## and what the GPU is asked to draw per frame (draw calls, objects, triangles).
## The frame times only mean something on the real device; the draw counts are
## the same anywhere, so they compare changes and renderers on any machine.
##   xvfb-run -a godot --rendering-method mobile -s tests/gpu_bench.gd
##   (TRACK=n, SECONDS=n; on a phone build, the same route runs from the code.)

var main: Node


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	var game := root.get_node("Game")
	for i in 20:
		await process_frame
	seed(11)
	game.settings.field = 0
	game.settings.weather = 0
	game.settings.weekend = 0
	game.settings.cautions = 0
	main.mode = "race"
	main.session = "race"
	main._use_track(int(OS.get_environment("TRACK")) if OS.get_environment("TRACK") != "" else 1)
	main._enter_countdown()
	main.autopilot = true
	while main.state != main.State.RACE:
		await process_frame
	var secs: float = float(OS.get_environment("SECONDS")) if OS.get_environment("SECONDS") != "" else 20.0
	var times: Array[float] = []
	var calls := 0
	var objects := 0
	var prims := 0
	var frames := 0
	var t0 := Time.get_ticks_usec()
	var last := t0
	while main.race.time < secs + 3.0:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
		calls += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		objects += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
		prims += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		frames += 1
	times.sort()
	var avg := 0.0
	for x in times:
		avg += x
	avg /= max(times.size(), 1)
	var p95: float = times[int(times.size() * 0.95)] if times.size() > 0 else 0.0
	print("BENCH renderer=%s quality=%d frames=%d avg=%.1fms p95=%.1fms worst=%.1fms draw_calls=%d objects=%d triangles=%dk" % [
		RenderingServer.get_current_rendering_method(), game.quality_level(), frames, avg, p95, times[-1] if times.size() > 0 else 0.0,
		calls / max(frames, 1), objects / max(frames, 1), prims / max(frames, 1) / 1000])
	quit()
