extends SceneTree
## Top speeds in the draft on the superspeedways, driven for real: a car alone,
## a two-car tandem, and a 10-car line nose to tail (no lane changes), two laps
## each at full throttle. Prints each case's fastest speed.
##   godot --headless --fixed-fps 60 -s tests/draft_speed_bench.gd

const MPH := 2.23694
const DT := 1.0 / 60.0


func _initialize() -> void:
	_run.call_deferred()


func _case(t: Node3D, n: int, laps: float) -> Array:
	var Race: GDScript = load("res://scripts/race.gd")
	var race: Node3D = Race.new()
	root.add_child(race)
	race.setup(t, -1, 9, n)
	race.debug_no_lane_changes = true
	for i in race.cars.size():
		var c: Node3D = race.cars[i]
		c.dist = 800.0 - i * 6.2
		c.d = race.lanes[0]
		c.ai_lane = c.d
		c.v = 80.0
		c.yaw = 0.0
		c.lap_idx = c.lap()
		c.sync_visual()
	race.go_green()
	var best := []
	best.resize(n)
	best.fill(0.0)
	var thr_sum := [0.0, 0.0]
	var lift := [0.0, 0.0, 0.0, 0.0]
	var steps := int(laps * t.length / 85.0 / DT)
	for s in steps:
		race.tick(DT)
		for i in n:
			best[i] = max(best[i], race.cars[i].speed() * MPH)
		if n > 1:
			thr_sum[0] += race.cars[1].throttle
			thr_sum[1] += 1.0
			var c1: Node3D = race.cars[1]
			var kk: float = abs(t.curvature_at(fposmod(c1.dist, t.length))) if t.has_method("curvature_at") else 0.0
			var bucket: int = 0 if kk > 0.001 else 1
			lift[bucket * 2] += 1.0 if c1.throttle < 0.95 else 0.0
			lift[bucket * 2 + 1] += 1.0
	if n > 1 and OS.get_environment("DIAG") == "1":
		var o: Array = race.cars.duplicate()
		o.sort_custom(func(a, b): return a.dist > b.dist)
		var lead: Node3D = o[0]
		print("   car 2 average throttle %.2f; lifting in corners %.0f%%, on straights %.0f%%" % [thr_sum[0] / max(thr_sum[1], 1.0), 100.0 * lift[0] / max(lift[1], 1.0), 100.0 * lift[2] / max(lift[3], 1.0)])
		var sec: Node3D = o[1]
		print("   2nd: throttle %.2f brake %.2f drag %.3f air %s front %.3f" % [sec.throttle, sec.brake, sec.drag_mult, str(sec.get_meta("air", Vector4.ZERO)), sec.df_front_mult])
		var tail: Node3D = o[o.size() - 1]
		print("   tail: v %.1f mph throttle %.2f drag %.3f air %s spun %s out %s damage %.2f" % [tail.speed() * MPH, tail.throttle, tail.drag_mult, str(tail.get_meta("air", Vector4.ZERO)), tail.spinning, tail.out, tail.total_damage()])
		print("   leader air %s drag %.3f  gaps: %s" % [str(lead.get_meta("air", Vector4.ZERO)), lead.drag_mult, ", ".join(range(1, o.size()).map(func(k): return "%.1f" % (o[k - 1].dist - o[k].dist)))])
	race.free()
	return best


func _run() -> void:
	var game: Node = root.get_node("Game")
	var Track: GDScript = load("res://scripts/track.gd")
	for idx in [0, 3]:
		var t: Node3D = Track.new()
		root.add_child(t)
		t.setup(game.tracks[idx])
		var solo: Array = _case(t, 1, 2.0)
		var two: Array = _case(t, 2, 2.0)
		var line: Array = _case(t, 10, 2.0)
		var top := 0.0
		for v in line:
			top = max(top, v)
		print("%s: solo %.1f mph | tandem lead %.1f, pusher %.1f | 10-car line: fastest %.1f  (by position: %s)" % [game.tracks[idx].name, solo[0], two[0], two[1], top, ", ".join(line.map(func(v): return "%.0f" % v))])
		t.free()
	quit(0)
