extends SceneTree
## Physics bench: solo lap speeds, draft gain, and a full-field AI race per track.
##   godot --headless --path . -s tests/physics_test.gd   (TRACK=n to pick one)

var Track: GDScript
var Race: GDScript
const DT := 1.0 / 60.0
const MPH := 2.23694


func _initialize() -> void:
	_run.call_deferred()


func _solo(t: Node3D, drafting: bool) -> Dictionary:
	var race: Node3D = Race.new()
	root.add_child(race)
	race.setup(t, -1, 3, 2 if drafting else 1)
	race.grid_up(0.0, 40.0)
	var a: Node3D = race.cars[0]
	a.dist = 0.0
	a.d = race.lanes[0]
	a.ai_lane = race.lanes[0]
	if drafting:
		var b: Node3D = race.cars[1]
		b.dist = -9.0
		b.d = race.lanes[0]
		b.ai_lane = race.lanes[0]
	race.go_green()
	var vmax := 0.0
	var vmin := 999.0
	var lap_t := 0.0
	var t0 := -1.0
	var sim := 0.0
	var watch: Node3D = race.cars[1] if drafting else a
	while sim < 400.0:
		race.tick(DT)
		sim += DT
		if watch.lap() >= 1 and t0 < 0.0:
			t0 = sim
		if t0 > 0.0:
			vmax = max(vmax, watch.v)
			vmin = min(vmin, watch.v)
		if watch.lap() >= 2:
			lap_t = sim - t0
			break
	var res := {"lap": lap_t, "avg_mph": t.length / max(lap_t, 0.01) * MPH, "top_mph": vmax * MPH, "min_mph": vmin * MPH, "spun": watch.spinning, "wall": a.damage}
	race.free()
	return res


## Top-speed gain from drafting, measured with drag multipliers from the aero model.
func _draft_gain(t: Node3D) -> Vector2:
	var race: Node3D = Race.new()
	root.add_child(race)
	race.setup(t, -1, 3, 6)
	for i in race.cars.size():
		var c: Node3D = race.cars[i]
		c.dist = 500.0 - i * 7.0
		c.d = race.lanes[0]
	race._aero(10.0)
	var solo: float = race.cars[0].drag_mult
	var second: float = race.cars[1].drag_mult
	var last: float = race.cars[5].drag_mult
	race.free()
	# Top speed scales with (1/drag)^(1/3) when power-limited.
	var vs := 81.0
	return Vector2((vs * pow(solo / second, 1.0 / 3.0) - vs) * MPH, (vs * pow(solo / last, 1.0 / 3.0) - vs) * MPH)


func _run() -> void:
	Track = load("res://scripts/track.gd")
	Race = load("res://scripts/race.gd")
	var only := OS.get_environment("TRACK")
	var game := root.get_node("Game")
	for idx in game.tracks.size():
		if only != "" and int(only) != idx:
			continue
		var t: Node3D = Track.new()
		root.add_child(t)
		t.setup(game.tracks[idx])
		print("== ", game.tracks[idx].name, "  (%.2f mi)" % (t.length / 1609.34))
		var mn := 999.0
		for sp in t.speed_profile:
			mn = min(mn, sp)
		print("   profile min corner speed %.0f mph" % (mn * MPH))
		var solo := _solo(t, false)
		print("   solo lap %.2fs  avg %.1f mph  top %.1f  min %.1f  spun=%s" % [solo.lap, solo.avg_mph, solo.top_mph, solo.min_mph, solo.spun])
		var dr := _draft_gain(t)
		print("   draft: 1 car behind gains %.1f mph of top speed; in a 6-car line the last car gains %.1f mph" % [dr.x, dr.y])
		# Full field
		var race: Node3D = Race.new()
		root.add_child(race)
		race.setup(t, -1, 3, 40)
		race.grid_up(-150.0, 30.0)
		for i in 180:
			race.tick(DT)
		race.go_green()
		var spins := 0
		var outs := 0
		var hits := 0
		race.incident.connect(func(c, kind):
			if kind == "spin":
				spins += 1
			else:
				outs += 1)
		var sim := 0.0
		while sim < 240.0 and race.finish_count == 0:
			race.tick(DT)
			sim += DT
			for c in race.cars:
				if c.wall_hit > 3.0:
					hits += 1
		var leader: Node3D = race.order[0]
		var last: Node3D = race.order[race.order.size() - 1]
		print("   40-car race %.0fs: leader lap %d best %.2fs, spins %d, retired %d, wall hits %d, spread %.0f m" % [sim, leader.lap(), leader.best_lap, spins, outs, hits, leader.dist - last.dist])
		race.free()
		t.free()
	quit()
