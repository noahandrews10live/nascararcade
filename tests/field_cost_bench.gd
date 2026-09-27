extends SceneTree
## CPU cost of the race simulation by field size: N cars racing (the physics,
## AI, drafting and contact of race.tick), 30 s after the green, per frame.
##   godot --headless -s tests/field_cost_bench.gd     (SIZES=20,25,30 TRACK=1)

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var g: Node = root.get_node("Game")
	var sizes: Array = []
	for x in (OS.get_environment("SIZES") if OS.get_environment("SIZES") != "" else "20,25,30,35,40").split(","):
		sizes.append(int(x))
	var tidx := int(OS.get_environment("TRACK")) if OS.get_environment("TRACK") != "" else 1
	for n in sizes:
		var t = load("res://scripts/track.gd").new()
		root.add_child(t)
		t.setup(g.tracks[tidx])
		var race = load("res://scripts/race.gd").new()
		root.add_child(race)
		race.setup(t, -1, 50, n)
		race.enable_rules()
		race.grid_up(-150.0, 30.0)
		for i in 180:
			race.tick(1.0 / 60.0)
		race.go_green()
		for i in 300:
			race.tick(1.0 / 60.0)
		var t0 := Time.get_ticks_usec()
		var frames := 60 * 30
		var worst := 0
		for i in frames:
			var a := Time.get_ticks_usec()
			race.tick(1.0 / 60.0)
			worst = max(worst, Time.get_ticks_usec() - a)
		var per: float = float(Time.get_ticks_usec() - t0) / frames / 1000.0
		print("CARS %2d: %.2f ms per frame (worst %.1f ms)" % [n, per, worst / 1000.0])
		race.queue_free()
		t.queue_free()
		await process_frame
	quit(0)
