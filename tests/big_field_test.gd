extends SceneTree
## 40 cars, and AI AGGRESSION:
##   - FIELD SIZE 40: forty cars on the grid, every one with its own pit box,
##     and a stretch of racing with nothing thrown off the world;
##   - CALM draws a field of patient drivers, HARD one that forces passes.
##   godot --headless --fixed-fps 60 -s tests/big_field_test.gd

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


func _race(field_idx: int, aggr: int) -> void:
	main.clear_checkpoint()
	game.settings.length = 1
	game.settings.field = field_idx
	game.settings.ai_aggr = aggr
	game.settings.weather = 0
	game.settings.weekend = 0
	game.settings.cautions = 1
	game.tracks[0].full_laps = 600
	main.mode = "race"
	main.session = "race"
	main._use_track(0)
	main._enter_track_select()
	main._enter_car_select()
	main._enter_countdown()
	main.autopilot = true


func _mean_aggr() -> float:
	var t := 0.0
	var n := 0
	for c in main.race.cars:
		if not c.is_player:
			t += c.ai_aggression
			n += 1
	return t / max(n, 1)


func _run() -> void:
	game = root.get_node("Game")
	for i in 20:
		await physics_frame
	await _race(2, 1)
	var race = main.race
	_check(race.cars.size() == 40, "FIELD SIZE 40: forty cars (%d)" % race.cars.size())
	var boxes := {}
	for c in race.cars:
		boxes[snapped(race.control.box_s(c), 0.1)] = true
	_check(boxes.size() == 40, "every car has its own pit box")
	var bad := false
	var t0 := Time.get_ticks_msec()
	while race.time < 60.0:
		await physics_frame
		for c in race.cars:
			if is_nan(c.dist) or is_nan(c.v) or abs(c.global_position.y) > 400.0:
				bad = true
	print("   40 cars, a minute of racing at Thunder Beach: %d out, %.1f s real time" % [race.cars.filter(func(c): return c.out).size(), (Time.get_ticks_msec() - t0) / 1000.0])
	_check(not bad, "a minute of 40-car racing, nothing thrown off the world")
	var normal: float = _mean_aggr()
	main._enter_title()
	await process_frame
	await _race(0, 0)
	var calm: float = _mean_aggr()
	main._enter_title()
	await process_frame
	await _race(0, 2)
	var hard: float = _mean_aggr()
	print("   mean aggression: calm %.2f, normal %.2f, hard %.2f" % [calm, normal, hard])
	_check(calm < 0.4 and hard > 0.7 and calm < normal and normal < hard, "AI AGGRESSION: calm, normal, hard fields")
	game.settings.ai_aggr = 1
	game.settings.field = -1
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
