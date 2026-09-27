extends SceneTree
## Calibrates the AUTO field model: script time per frame (what the game
## measures in a race) at several field sizes on this machine.
##   ST_NO_INTRO=1 godot --headless --fixed-fps 60 -s tests/field_cal_bench.gd

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game: Node = root.get_node("Game")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	for fi in game.FIELDS.size():
		game.settings.field = fi
		main.mode = "race"
		main.session = "race"
		main._use_track(0)
		main._enter_countdown()
		main.autopilot = true
		var n := 0
		while main._frame_ms.size() < 900 and n < 3000:
			await process_frame
			n += 1
		var proc := 0.0
		var phys := 0.0
		var t0 := Time.get_ticks_usec()
		for i in 300:
			await process_frame
			proc += main.frame_timer.busy_ms
		var wall := (Time.get_ticks_usec() - t0) / 300000.0
		print("%d cars: our work %.2f ms, wall %.2f ms per frame" % [main.race.cars.size(), proc / 300.0, wall])
		main._enter_title()
		await process_frame
	quit(0)
