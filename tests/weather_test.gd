extends SceneTree
## Weather and time of day in full races:
##   - an oval in the rain: caution, held until dry, then green and a finish;
##   - the road course in the rain: the AI goes to wet tyres, wet laps are slower;
##   - the clock moves through the race.
##   godot --headless --fixed-fps 60 -s tests/weather_test.gd

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


func _start(tidx: int, laps: int) -> void:
	var game := root.get_node("Game")
	game.tracks[tidx].full_laps = laps * 10
	game.settings.length = 1
	game.settings.field = 0
	game.settings.weather = 2
	game.settings.weekend = 0
	main.mode = "race"
	main.session = "race"
	main._use_track(tidx)
	main._enter_track_select()
	main._enter_car_select()
	main._enter_countdown()
	main.autopilot = true


func _run() -> void:
	for i in 20:
		await physics_frame
	# --- oval in the rain
	print("== oval, rain")
	_start(1, 8)
	var w: Node = main.race.weather
	var h0: float = w.hour
	var saw_rain_caution := false
	var saw_hold := false
	var went_green_dry := false
	var sim := 0.0
	while main.state != main.State.RESULTS and sim < 1500.0:
		await physics_frame
		sim += 1.0 / 60.0
		var ctl = main.race.control
		if ctl.flag == ctl.Flag.YELLOW and w.average_wet() > 0.2:
			saw_rain_caution = true
		if ctl.weather_hold:
			saw_hold = true
		if saw_hold and ctl.flag == ctl.Flag.GREEN and w.average_wet() < 0.1:
			went_green_dry = true
	print("   clock %.2f -> %.2f h, finished in %.0fs sim" % [h0, w.hour, sim])
	_check(saw_rain_caution, "rain brings out the caution on an oval")
	_check(saw_hold, "the field is held while the track is wet")
	_check(went_green_dry, "green flag once the track has dried")
	_check(main.state == main.State.RESULTS, "the race still finishes")
	_check(w.hour > h0 + 0.2, "the time of day moves on through the race")
	# --- road course in the rain
	print("== road course, rain")
	_start(10, 3)
	w = main.race.weather
	var wets := 0
	var best_wet := 0.0
	sim = 0.0
	while main.state != main.State.RESULTS and sim < 1500.0:
		await physics_frame
		sim += 1.0 / 60.0
	for c in main.race.cars:
		if c.tyre_compound == "wet":
			wets += 1
	var lead: Node3D = main.race.order[0]
	best_wet = lead.best_lap
	print("   cars on wets at the end: %d of %d, leader's best lap %.1fs" % [wets, main.race.cars.size(), best_wet])
	_check(wets >= main.race.cars.size() / 2, "the AI switches to wet tyres in the rain")
	_check(best_wet > 112.0, "wet laps are slower than dry (~108 s)")
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
