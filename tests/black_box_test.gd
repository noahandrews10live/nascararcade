extends SceneTree
## The black box (B, or TIMING when paused): the timing screen.
##   - B opens and closes it;
##   - the sectors are timed, and add up to the lap;
##   - your best in each sector is kept;
##   - the gaps to the cars ahead and behind, and fuel in laps.
##   godot --headless --fixed-fps 60 -s tests/black_box_test.gd

var main: Node
var game: Node
var failures := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1


func _run() -> void:
	game = root.get_node("Game")
	for i in 20:
		await physics_frame
	main.clear_checkpoint()
	game.settings.length = 1
	game.settings.field = 0
	game.settings.weather = 0
	game.settings.weekend = 0
	game.settings.cautions = 0
	game.tracks[1].full_laps = 600
	main.mode = "race"
	main.session = "race"
	main._use_track(1)
	main._enter_track_select()
	main._enter_car_select()
	main._enter_countdown()
	main.autopilot = true
	var race = main.race
	var p: Node3D = race.player
	while not race.running:
		await physics_frame
	# B opens it.
	var ev := InputEventAction.new()
	ev.action = "black_box"
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	await process_frame
	_check(main.black_box.visible, "B opens the black box")
	# Three laps: the sectors timed.
	var l0: int = p.lap()
	while p.lap() < l0 + 3:
		await physics_frame
	await physics_frame
	var r: Dictionary = main.black_box.reading()
	var sl: Array = r.sec_last
	var total: float = sl[0] + sl[1] + sl[2]
	print("   last lap %.3f s; sectors %.2f + %.2f + %.2f = %.3f; best %s" % [p.last_lap, sl[0], sl[1], sl[2], total, str(r.sec_best)])
	_check(sl[0] > 0.0 and sl[1] > 0.0 and sl[2] > 0.0, "three sectors timed")
	_check(abs(total - p.last_lap) < 0.1, "and they add up to the lap")
	var sane: bool = true
	for k in 3:
		sane = sane and r.sec_best[k] > sl[k] * 0.8 and r.sec_best[k] <= sl[k] + 0.001
	_check(sane, "your best in each sector is kept (and only whole sectors count)")
	print("   P%d of %d, ahead %s %.2f s, behind %s %.2f s, fuel %.1f laps" % [r.pos, r.of, r.ahead.team.num if r.ahead else "-", r.gap_ahead, r.behind.team.num if r.behind else "-", r.gap_behind, r.fuel_laps])
	_check(r.pos >= 1 and (r.ahead == null or r.gap_ahead >= 0.0) and (r.behind == null or r.gap_behind >= 0.0), "the gaps ahead and behind")
	_check(r.fuel_laps > 1.0 and r.last > 0.0 and r.best > 0.0, "fuel in laps, last and best laps")
	Input.parse_input_event(ev)
	await process_frame
	await process_frame
	_check(not main.black_box.visible, "B again closes it")
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
