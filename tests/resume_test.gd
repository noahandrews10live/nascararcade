extends SceneTree
## Carrying on an interrupted race:
##   - each lap under green in a full race saves a checkpoint;
##   - after the app is closed mid-race, the garage leads with RESUME RACE;
##   - resuming rebuilds the race with every car back where it was (distance,
##     fuel, tyres, damage, the clock) and counts 3-2-1 before it runs;
##   - quitting a race on purpose throws the checkpoint away.
##   ST_NO_INTRO=1 godot --headless --fixed-fps 60 -s tests/resume_test.gd

var main: Node
var failures := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	var game: Node = root.get_node("Game")
	main.clear_checkpoint()
	await _frames(20)
	game.settings.field = 0 # 20 cars
	game.settings.cautions = 0
	game.tracks[2].full_laps = 100 # 10 laps at SHORT
	main.mode = "race"
	main.session = "race"
	main._use_track(2)
	main._enter_countdown()
	main.autopilot = true
	var n := 0
	while main.resume_info().is_empty() and n < 60 * 90:
		await process_frame
		n += 1
	var info: Dictionary = main.resume_info()
	_check(not info.is_empty(), "a lap under green saves a checkpoint (after %.0f s)" % (n / 60.0))
	await _frames(30)
	main.save_checkpoint() # the moment the app dies
	info = main.resume_info()
	var d: Dictionary = info.data
	var me: Dictionary = {}
	for c in d.cars:
		if c.player:
			me = c
	var saved_time: float = float(d.time)
	print("   saved: lap %d of %d, %s, clock %.1f s, my fuel %.1f" % [info.lap, info.laps, game.ordinal(info.place), saved_time, float(me.fuel)])
	# The app is closed; later it's opened again.
	main._enter_title()
	await _frames(5)
	main._enter_mode_select()
	await _frames(5)
	var modes: Array = main._modes()
	_check(String(modes[0][2]) == "resume", "the garage leads with RESUME RACE: %s" % String(modes[0][1]))
	main._start_mode("resume")
	await _frames(3)
	var p: Node3D = main.race.player
	_check(main.race.cars.size() == d.cars.size(), "the same %d cars" % main.race.cars.size())
	_check(absf(p.dist - float(me.dist)) < 1.0 and absf(p.fuel - float(me.fuel)) < 0.01, "you're back where you were (%.0f m, fuel %.1f)" % [p.dist, p.fuel])
	var same := 0
	for i in main.race.cars.size():
		if absf(main.race.cars[i].dist - float(d.cars[i].dist)) < 1.0 and int(main.race.cars[i].get_meta("team_idx", -1)) == int(d.cars[i].team):
			same += 1
	_check(same == main.race.cars.size(), "and so is every other car (%d of %d)" % [same, main.race.cars.size()])
	_check(absf(main.race.time - saved_time) < 0.1 and main.race.laps == int(d.laps), "the race clock and length carry on")
	_check(main.paused and main.resume_t > 2.0, "a 3-2-1 before it runs")
	await _frames(240)
	_check(not main.paused and main.race.time > saved_time + 0.5 and p.dist > float(me.dist) + 20.0, "then the race carries on")
	# Quitting on purpose.
	main.paused = true
	var ev := InputEventAction.new()
	ev.action = "quit_race"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(3)
	_check(main.resume_info().is_empty(), "quitting a race throws the checkpoint away")
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
