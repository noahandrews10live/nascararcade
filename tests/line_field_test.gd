extends SceneTree
## The racing line with a full field: 25 AI cars race on each flat track (where
## the line is used) and it checks that they
##   - actually use the line when they have clear road (share of car-time on it),
##   - still pass each other (position changes per car per minute),
##   - don't crash much more than on the lanes (spins and hard wall hits),
##   - lap at a sensible pace: the best lap in the pack within 6% of one car
##     alone on the line.
##   godot --headless -s tests/line_field_test.gd      (TRACKS=7,8 SECS=150)

var failures := 0


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var g: Node = root.get_node("Game")
	g.debug_seed = 11
	var tracks: Array = []
	var env := OS.get_environment("TRACKS")
	if env != "":
		for x in env.split(","):
			tracks.append(int(x))
	else:
		tracks = [7, 8, 10]
	var secs := int(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 200
	for ti in tracks:
		var t = load("res://scripts/track.gd").new()
		root.add_child(t)
		t.setup(g.tracks[ti])
		if not t.has_line():
			print("%s: no racing line (banked), skipped" % t.cfg.short)
			t.queue_free()
			continue
		var solo := await _solo_lap(t)
		var race = load("res://scripts/race.gd").new()
		root.add_child(race)
		race.setup(t, -1, 50, 25)
		race.grid_up(-150.0, 30.0)
		for i in 180:
			race.tick(1.0 / 60.0)
		race.go_green()
		var box := {"incidents": 0, "best": 1e9} # (lambdas capture by value)
		race.incident.connect(func(_c, _k): box.incidents += 1)
		var on_line := 0
		var samples := 0
		var swaps := 0
		var prev_order: Array = race.order.duplicate()
		race.lap_completed.connect(func(_c, _n, lt): box.best = min(box.best, lt) if lt > 0.0 else box.best)
		for i in secs * 60:
			race.tick(1.0 / 60.0)
			if i % 30 == 0:
				for c in race.cars:
					samples += 1
					if c.get_meta("on_line", false):
						on_line += 1
				# Overtakes: neighbours that swapped since the last look.
				var pos := {}
				for k in race.order.size():
					pos[race.order[k]] = k
				for k in prev_order.size() - 1:
					var a = prev_order[k]
					var b = prev_order[k + 1]
					if pos.has(a) and pos.has(b) and pos[b] < pos[a]:
						swaps += 1
				prev_order = race.order.duplicate()
		var share: float = float(on_line) / max(samples, 1)
		var passes_pm: float = float(swaps) / 25.0 / (secs / 60.0)
		var incidents: int = box.incidents
		var best_lap: float = box.best
		print("%s: on line %.0f%%, passes %.2f per car per min, incidents %d, best lap %.2f s (alone %.2f s)" % [t.cfg.short, share * 100.0, passes_pm, incidents, best_lap, solo])
		_check(share > 0.08, "%s: cars use the line when they have room" % t.cfg.short)
		_check(passes_pm > 0.05, "%s: they still pass each other" % t.cfg.short)
		_check(incidents <= 12, "%s: incidents stay reasonable (%d)" % [t.cfg.short, incidents])
		_check(best_lap < solo * 1.06, "%s: the pack laps near a lone car's pace" % t.cfg.short)
		race.queue_free()
		t.queue_free()
		await process_frame
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)


## One AI car alone: its best of three laps (the first from a rolling start).
func _solo_lap(t: Node3D) -> float:
	var race = load("res://scripts/race.gd").new()
	root.add_child(race)
	race.setup(t, -1, 4, 1)
	race.grid_up(0.0, 30.0)
	race.go_green()
	var box := {"best": 1e9}
	race.lap_completed.connect(func(_c, _n, lt): box.best = min(box.best, lt) if lt > 0.0 else box.best)
	var c = race.cars[0]
	var guard := 0
	while c.lap() < 3 and guard < 60 * 400:
		race.tick(1.0 / 60.0)
		guard += 1
	race.queue_free()
	await process_frame
	return box.best
