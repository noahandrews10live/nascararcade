extends SceneTree
## How fast tyres go off: one car alone (the AI driving) on a long run at real
## wear (1x) and at the rate a short race uses, printing grip and lap time every
## few laps. Real Cup tyres lose roughly 1-3% of their grip (about 0.5-1.5 s a
## lap at a short track, 1-2 s at an intermediate) over a 50-80 lap run.
##   godot --headless --fixed-fps 60 -s tests/wear_bench.gd   (TRACK=n, SCALE=x)

var Track: GDScript
var Race: GDScript
const DT := 1.0 / 60.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Track = load("res://scripts/track.gd")
	Race = load("res://scripts/race.gd")
	var game := root.get_node("Game")
	var idx := int(OS.get_environment("TRACK")) if OS.get_environment("TRACK") != "" else 2
	var scale := float(OS.get_environment("SCALE")) if OS.get_environment("SCALE") != "" else 1.0
	var laps := int(OS.get_environment("LAPS")) if OS.get_environment("LAPS") != "" else 60
	var t: Node3D = Track.new()
	root.add_child(t)
	t.setup(game.tracks[idx])
	var race: Node3D = Race.new()
	root.add_child(race)
	race.setup(t, -1, laps + 2, 1)
	race.grid_up(0.0, 40.0)
	race.go_green()
	var c: Node3D = race.cars[0]
	c.burn_scale = scale
	c.fuel = 999.0
	c.tyre_failed.connect(func(car, wheel, kind): print("  ** tyre %d failed: %s at %.0f s (temp %.0f, carcass %.0f, wear %.2f, dmg %.2f, wall %.1f)" % [wheel, kind, race.time, car.tyre_temp[wheel], car.carcass_temp[wheel], car.tyre_wear4[wheel], car.total_damage(), car.wall_hit]))
	var last := 0
	var peak := [0.0, 0.0, 0.0, 0.0]
	var t0 := 0.0
	var sim := 0.0
	var first_lap := 0.0
	print("%s, wear x%.1f" % [game.tracks[idx].name, scale])
	while c.lap() < laps + 1 and sim < 6000.0:
		race.tick(DT)
		sim += DT
		c.fuel = 999.0
		for w in 4:
			peak[w] = max(peak[w], c.carcass_temp[w])
		if c.lap() != last:
			var lt := sim - t0
			t0 = sim
			last = c.lap()
			if last == 2:
				first_lap = lt
			if last >= 2 and (last % 10 == 1 or last == 2):
				print("  lap %3d  grip %.3f  wear %.3f  temps %s  lap %.2fs (+%.2f)" % [last - 1, c.tyre_grip(), c.tyre_wear, str(Array(c.tyre_temp).map(func(x): return int(x))) + " air " + str(Array(c.tyre_air).map(func(x): return snappedf(x, 0.01))) + " w4 " + str(Array(c.tyre_wear4).map(func(x): return snappedf(x, 0.01))), lt, lt - first_lap])
	print("  peak carcass temps %s" % str(peak.map(func(x): return int(x))))
	quit()
