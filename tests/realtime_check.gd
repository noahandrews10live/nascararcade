extends SceneTree
## Does the race keep real time on a slow device? Run it with a renderer (e.g.
## xvfb-run on software rendering, a stand-in for a struggling phone): every 5 s
## of wall clock it prints how far the race clock moved, the frame rate and the
## physics governor's level. OLD_CAP=1 puts back the old 2-tick catch-up cap.
##   xvfb-run -a godot --resolution 1280x720 -s tests/realtime_check.gd

var main: Node


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	for i in 10:
		await process_frame
	var game: Node = root.get_node("Game")
	game.settings.weekend = 0
	game.settings.weather = 0
	game.settings.field = 1
	if OS.get_environment("QUALITY") != "":
		game.quality = int(OS.get_environment("QUALITY"))
	if OS.get_environment("SIM") != "":
		game.sim_level = int(OS.get_environment("SIM"))
	main.mode = "race"
	main.session = "race"
	main._use_track(1)
	main._enter_countdown()
	main.autopilot = true
	while main.state != main.State.RACE:
		await process_frame
	if OS.get_environment("OLD_CAP") != "":
		Engine.max_physics_steps_per_frame = 2
		main._fixed_fps = true # (and no governor, as before)
	var t0 := Time.get_ticks_msec()
	var r0: float = main.race.time
	var w0 := t0
	var wr: float = r0
	var frames := 0
	while Time.get_ticks_msec() - t0 < int(OS.get_environment("SECS") if OS.get_environment("SECS") != "" else "40") * 1000:
		await process_frame
		frames += 1
		var now := Time.get_ticks_msec()
		if now - w0 >= 5000:
			var real := (now - w0) / 1000.0
			print("RT  %4.0f s: race clock %.2f s per real second, %.1f fps, governor level %d" % [(now - t0) / 1000.0, (main.race.time - wr) / real, frames / real, main.race.sim_level])
			w0 = now
			wr = main.race.time
			frames = 0
	print("RT  overall: race clock %.2f s per real second" % ((main.race.time - r0) / ((Time.get_ticks_msec() - t0) / 1000.0)))
	quit()
