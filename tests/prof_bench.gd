extends SceneTree
## Where the game's own time goes in a race (no rendering): run with ST_PROF=1.
## Prints the busy time per frame (scripts + physics, as frame_timer measures it)
## and each profiled section's share, biggest first.
##   ST_PROF=1 godot --headless --fixed-fps 60 -s tests/prof_bench.gd   (FIELD=n, TRACK=n, SIM=level)

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
	game.settings.field = int(OS.get_environment("FIELD")) if OS.get_environment("FIELD") != "" else 1
	if OS.get_environment("SIM") != "":
		game.sim_level = int(OS.get_environment("SIM"))
	main.mode = "race"
	main.session = "race"
	main._use_track(int(OS.get_environment("TRACK")) if OS.get_environment("TRACK") != "" else 1)
	main._enter_countdown()
	main.autopilot = true
	while main.state != main.State.RACE:
		await process_frame
	for i in 60:
		await process_frame
	game.prof.clear()
	var n := 0
	var busy := 0.0
	while n < 60 * 30:
		await process_frame
		busy += main.frame_timer.busy_ms
		n += 1
	print("PROF %d cars, sim level %d: %.2f ms busy per frame" % [main.race.cars.size(), main.race.sim_level, busy / n])
	var keys: Array = game.prof.keys()
	keys.sort_custom(func(a, b): return game.prof[a] > game.prof[b])
	for k in keys:
		print("PROF   %-26s %6.3f ms/frame" % [k, game.prof[k] / 1000.0 / n])
	quit(0)
