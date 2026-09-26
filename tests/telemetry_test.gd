extends SceneTree
## Chassis telemetry bench: one car alone on a superspeedway, an intermediate and a
## short track. Records body roll and pitch, tyre loads, bump stop contact, tyre
## temperatures and lap time, and checks them against realistic ranges.
##   godot --headless --fixed-fps 60 -s tests/telemetry_test.gd   (TRACK=n for one)

var Track: GDScript
var Race: GDScript
const DT := 1.0 / 60.0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1


func _run() -> void:
	Track = load("res://scripts/track.gd")
	Race = load("res://scripts/race.gd")
	var game := root.get_node("Game")
	var only := OS.get_environment("TRACK")
	for idx in [0, 1, 2]:
		if only != "" and int(only) != idx:
			continue
		var t: Node3D = Track.new()
		root.add_child(t)
		t.setup(game.tracks[idx])
		var race: Node3D = Race.new()
		root.add_child(race)
		race.setup(t, -1, 5, 1)
		race.grid_up(0.0, 30.0)
		var c: Node3D = race.cars[0]
		c.dist = 0.0
		race.go_green()
		print("== ", game.tracks[idx].name)
		var max_roll := 0.0
		var max_dive := 0.0
		var max_squat := 0.0
		var corner_samples := 0
		var outside_share := 0.0
		var bump_frames := 0
		var frames := 0
		var lap_t := 0.0
		var t0 := -1.0
		var sim := 0.0
		var min_z := 0.0
		while sim < 300.0 and c.lap() < 3:
			race.tick(DT)
			sim += DT
			if c.lap() >= 1 and t0 < 0.0:
				t0 = sim
			if c.lap() >= 2 and lap_t == 0.0:
				lap_t = sim - t0
			if c.lap() < 1:
				continue
			frames += 1
			max_roll = max(max_roll, abs(c.chassis_roll))
			max_dive = max(max_dive, -c.chassis_pitch)
			max_squat = max(max_squat, c.chassis_pitch)
			min_z = min(min_z, c.chassis_z)
			var k: float = t.curvature_at(c.s())
			if abs(k) > 0.002:
				var nw: PackedFloat32Array = c._nw
				var right: float = nw[1] + nw[3]
				var left: float = nw[0] + nw[2]
				outside_share += right / max(left + right, 1.0)
				corner_samples += 1
			for i in 4:
				if c._defl[i] > c.BUMP_GAP:
					bump_frames += 1
					break
		var share: float = outside_share / max(corner_samples, 1)
		var temps: Array = []
		if c.get("tyre_temp") != null:
			for x in c.tyre_temp:
				temps.append(snapped(x, 1.0))
		print("   lap %.2fs  roll max %.1f deg  dive %.1f / squat %.1f deg  heave min %.0f mm" % [lap_t, rad_to_deg(max_roll), rad_to_deg(max_dive), rad_to_deg(max_squat), min_z * 1000.0])
		print("   right-side load in the turns %.0f%%  on bump stops %.0f%% of the lap  tyre temps %s" % [share * 100.0, 100.0 * bump_frames / max(frames, 1), str(temps)])
		_check(lap_t > 0.0, "completes laps")
		# Superspeedways ride on the bump stops (huge downforce), so they roll least.
		_check(max_roll > deg_to_rad(0.5) and max_roll < deg_to_rad(6.0), "body roll is realistic (0.5-6 deg)")
		_check(share > 0.55 and share < 0.8, "the outside (right) tyres carry more load in the turns")
		_check(not c.spinning and c.total_damage() < 0.05, "clean run")
		var tt: PackedFloat32Array = c.tyre_temp
		_check(tt[1] + tt[3] > tt[0] + tt[2], "right-side tyres run hotter (ovals turn left)")
		_check(tt[1] > 70.0 and tt[1] < 150.0, "right front is in its working window (70-150 C)")
		race.free()
		t.free()
	_wreck_tests(game)
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)


## Sideways at superspeedway speed the roof acts as a wing and the car takes off;
## turned backwards the roof flaps pop up and keep it down; a slow spin stays on
## its wheels.
func _wreck_tests(game: Node) -> void:
	var t: Node3D = Track.new()
	root.add_child(t)
	t.setup(game.tracks[0])
	print("== wrecks (", game.tracks[0].name, ")")
	for case in [["sideways at 200 mph", 90.0, PI * 0.5, true], ["backwards at 190 mph", 85.0, PI, false], ["half spin at 60 mph", 27.0, 1.6, false]]:
		var race: Node3D = Race.new()
		root.add_child(race)
		race.setup(t, -1, 5, 1)
		race.grid_up(0.0, 30.0)
		race.go_green()
		var c: Node3D = race.cars[0]
		c.ai = false
		c.assisted = false
		c.dist = t.length * 0.5
		c.d = 0.0
		c.v = case[1] * cos(case[2])
		c.vy = case[1] * sin(case[2])
		c.yaw = case[2]
		c.throttle = 0.0
		c.brake = 0.0
		var went := false
		var flaps := false
		var peak := 0.0
		for i in 600:
			race.tick(DT)
			went = went or c.tumbling
			flaps = flaps or c.roof_flaps
			if c.tumbling:
				var su: Array = c._surface_under(c.t_pos, c.s())
				peak = max(peak, (c.t_pos - (su[2] as Vector3)).dot(su[3]))
		print("   %s: airborne/tumbled=%s  roof flaps=%s  peak height %.1f m  settled=%s" % [case[0], went, flaps, peak, not c.tumbling])
		if case[3]:
			_check(went, "%s: the car gets airborne" % case[0])
		elif case[2] == PI:
			_check(flaps, "%s: roof flaps deploy" % case[0])
		else:
			_check(not went, "%s: stays on its wheels" % case[0])
		race.free()
	t.free()
