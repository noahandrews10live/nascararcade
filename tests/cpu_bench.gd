extends SceneTree
## CPU cost of a race, the way phones feel it: the whole game (main scene, 40
## cars, race day, broadcast, music, sound) through 60 s of a full-rules race,
## timed per frame without rendering.
##   godot --headless --fixed-fps 60 -s tests/cpu_bench.gd

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
	game.settings.field = 3 if game.FIELDS.size() > 3 else game.FIELDS.size() - 1
	main.mode = "race"
	main.session = "race"
	main._use_track(1)
	main._enter_countdown()
	main.autopilot = true
	while main.state != main.State.RACE:
		await process_frame
	for i in 120:
		await process_frame
	var n := 0
	var t0 := Time.get_ticks_usec()
	var worst := 0
	var last := t0
	while n < 60 * 60:
		await process_frame
		var now := Time.get_ticks_usec()
		worst = max(worst, now - last)
		last = now
		n += 1
	var per: float = float(Time.get_ticks_usec() - t0) / n / 1000.0
	print("CPU: %.2f ms per frame over %d frames (%d cars), worst %.1f ms" % [per, n, main.race.cars.size(), worst / 1000.0])
	quit(0)
