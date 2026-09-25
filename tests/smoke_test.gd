extends SceneTree
## Headless smoke test: builds every track and runs a full race with the player
## car on autopilot, checking the game flow reaches the results screen.
##   godot --headless --fixed-fps 60 --path . -s tests/smoke_test.gd

var main: Node
var failures := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		failures += 1


func _run() -> void:
	await _frames(30)
	_check(main.state == main.State.TITLE, "boots into attract mode")
	var lead0: float = main.race.order[0].dist
	await _frames(60)
	_check(main.race.order[0].dist > lead0 + 20.0, "attract race is running")

	var only := OS.get_environment("TRACK")
	for idx in root.get_node("Game").tracks.size():
		if only != "" and int(only) != idx:
			continue
		print("TRACK ", idx, ": ", root.get_node("Game").tracks[idx].name)
		main._use_track(idx)
		var t: Node3D = main.track
		var ksum := 0.0
		for k in t.curv:
			ksum += k * (t.length / t.n)
		_check(abs(ksum - TAU) < 0.2, "track turns left through 360 deg (%.2f rad), length %.0f m" % [ksum, t.length])
		main._enter_track_select()
		main._enter_car_select()
		main._enter_countdown()
		main.autopilot = true
		var start_time: float = main.time_left
		var lap_log: Array = []
		main.race.lap_completed.connect(func(c, n, lt):
			if c == main.race.player:
				lap_log.append("lap %d %.2fs (clock %.1f)" % [n, lt, main.time_left]))
		var sim := 0.0
		var walls := 0
		while main.state != main.State.RESULTS and sim < 600.0:
			await physics_frame
			sim += 1.0 / 60.0
			if main.race.player.wall_hit > 2.0:
				walls += 1
		var p: Node3D = main.race.player
		print("  start clock %.0f, bonus %.0f" % [start_time, main.lap_bonus])
		for l in lap_log:
			print("  ", l)
		print("  finished=%s place=%d best=%.2f wall_hits=%d reason='%s' sim=%.0fs" % [p.finished, main.race.position_of(p), p.best_lap, walls, main.game_over_reason, sim])
		_check(main.state == main.State.RESULTS, "reached results screen")
		_check(p.finished and main.game_over_reason == "", "autopilot finished before the clock ran out")
		main.autopilot = false
		main._enter_title()
		await _frames(10)
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
