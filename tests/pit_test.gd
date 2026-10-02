extends SceneTree
## Pit road with a barrier, and the player's stop:
##   - the walls: along pit road the barrier splits the apron from pit road (a car
##     on the track side can't get onto pit road through it, one on pit road can't
##     get out), with the pit wall inside;
##   - a green-flag stop: the car leaves the track before the barrier starts, stays
##     on the pit side of it all along pit road, stops at its box and comes out
##     past the end of the barrier, without hitting anything hard;
##   - the pit road light: red under yellow until pit road opens;
##   - the stop panel follows the stop, and the summary comes off pit road;
##   - the jack drop: a human player waits for the gas (the crew pushes them off
##     after a second and a half), jumping it costs time;
##   - a quick caution's stop replay puts the car back where it was and unpauses;
##   - the war wagons and stall markings are built.
##   godot --headless --fixed-fps 60 -s tests/pit_test.gd

var main: Node
var failures := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	var game := root.get_node("Game")
	await _frames(20)
	game.settings.length = 1
	game.settings.field = 0
	game.settings.weather = 0
	game.settings.weekend = 0
	game.settings.cautions = 2
	var ti := int(OS.get_environment("TRACK")) if OS.get_environment("TRACK") != "" else 1
	game.tracks[ti].full_laps = 600
	main.mode = "race"
	main.session = "race"
	main._use_track(ti)
	main._enter_track_select()
	main._enter_car_select()
	main._enter_countdown()
	main.autopilot = true
	var race = main.race
	var ctl = race.control
	var t = main.track
	ctl.debris_rate = 0.0
	await _frames(60 * 12)

	# The walls.
	var b: float = t.pit_barrier_d()
	var mid: float = 0.0 # the start/finish line is in the middle of pit road
	var w_track: Vector2 = t.walls_for(mid, b + 3.0)
	var w_pit: Vector2 = t.walls_for(mid, t.pit_lane_d())
	var w_away: Vector2 = t.walls_for(t.length * 0.5, b + 3.0)
	print("   barrier %.1f lane %.1f wall %.1f apron %.1f" % [b, t.pit_lane_d(), t.pit_wall_d(), t.apron_edge()])
	_check(is_equal_approx(w_track.x, b + 0.3), "on the track side the barrier is the inside wall")
	_check(is_equal_approx(w_pit.y, b - 0.3) and is_equal_approx(w_pit.x, t.pit_wall_d() + 0.3), "on pit road: barrier outside, pit wall inside")
	_check(is_equal_approx(w_away.x, t.inner_wall()), "away from pit road the inside wall is the track's")
	_check(t.pit_wall_d() > t.inner_wall() - 0.01 or t.pit_wall_d() > -t.infield_clear(), "the pit wall is inside the infield")
	_check(t.pit_light != null, "the pit road light is built")
	var rd: Node = main.race_day
	_check(rd != null and rd._pit_boxes_built, "the war wagons and stalls are built")

	# A green-flag stop.
	var p = race.player
	p.fuel = 0.25
	p.tyre_wear = 0.3
	p.want_pit = true
	p.pit_plan = "4"
	var seen := {}
	var max_hit := 0.0
	var wrong_side := 0
	var panel_seen := false
	var summary_seen := false
	var t0 := 0
	while t0 < 60 * 150:
		await physics_frame
		t0 += 1
		seen[p.pit_state] = true
		max_hit = max(max_hit, p.wall_hit)
		var ss: float = p.s()
		if p.pit_state in [ctl.Pit.LANE, ctl.Pit.SERVICE] and t.in_pit_zone(ss) and t.in_pit_barrier(ss) and p.d > b:
			wrong_side += 1
		if p.pit_state == ctl.Pit.SERVICE and main.pit_show.active() and not main.pit_show.stop.is_empty():
			panel_seen = true
		if main.pit_show._summary_t > 0.0:
			summary_seen = true
		if seen.has(ctl.Pit.SERVICE) and p.pit_state == ctl.Pit.NONE:
			break
	print("   states %s max wall hit %.1f wrong side %d frames, %s" % [seen.keys(), max_hit, wrong_side, main.pit_show._summary])
	_check(seen.has(ctl.Pit.LANE) and seen.has(ctl.Pit.SERVICE) and seen.has(ctl.Pit.EXIT) and p.pit_state == ctl.Pit.NONE, "the stop goes approach - pit road - box - exit - back on track")
	_check(wrong_side == 0, "on pit road the car is always on the pit side of the barrier")
	_check(max_hit < 4.0, "no hard hits on the way in or out (%.1f m/s)" % max_hit)
	_check(p.fuel > 0.9, "fuel went in")
	_check(panel_seen, "the stop panel is up while the car is in its box")
	_check(summary_seen, "the stop's summary is shown off pit road")

	# A human player's jack drop.
	main.autopilot = false
	await physics_frame
	p.autopilot_forced = false
	p.set_meta("released", false)
	p.remove_meta("released")
	p.pit_state = ctl.Pit.SERVICE
	p.pit_timer = 0.05
	p.v = 0.0
	await _frames(30)
	_check(p.pit_state == ctl.Pit.SERVICE, "after the jack drops the car waits for the player's gas")
	p.set_meta("released", true)
	await _frames(3)
	_check(p.pit_state != ctl.Pit.SERVICE and abs(float(p.get_meta("reaction", -1.0)) - 0.5) < 0.2, "the gas releases it and the reaction is timed (%.2f s)" % float(p.get_meta("reaction", -1.0)))
	p.pit_state = ctl.Pit.SERVICE
	p.pit_timer = 0.05
	await _frames(60 * 2)
	_check(p.pit_state != ctl.Pit.SERVICE, "nobody on the gas: the crew pushes them off")
	# Jumping the jack.
	main.pit_show._was_state = ctl.Pit.EXIT
	p.pit_state = ctl.Pit.SERVICE
	p.pit_timer = 0.8
	p.v = 0.0
	await _frames(2)
	var before: float = p.pit_timer
	Input.action_press("accelerate")
	await process_frame
	await physics_frame
	Input.action_release("accelerate")
	_check(main.pit_show._jumped and p.pit_timer > before + 1.0, "pressing the gas before the jack drops costs %.1f s" % main.pit_show.JUMP_PENALTY)
	while p.pit_state != ctl.Pit.NONE and t0 < 60 * 300:
		p.set_meta("released", true)
		await physics_frame
		t0 += 1
	main.autopilot = true

	# The light: red under yellow until pit road opens.
	await _frames(30)
	ctl.throw_caution("test", null)
	await _frames(10)
	var red_seen: bool = not ctl.pit_open and not ctl._light_open
	_check(red_seen, "the pit road light goes red when the caution comes out")

	# A quick-caution stop replay.
	p.set_meta("stop", {"total": 11.0, "tyre_t": 9.0, "fuel_t": 7.0, "repair": 0.0, "corners": [0, 1, 2, 3], "fuel_add": 0.5, "wedge": 0})
	var was_dist: float = p.dist
	var was_d: float = p.d
	main.pit_show.start_show(p)
	_check(main.paused and main.pit_show.showing and p.pit_state == ctl.Pit.SERVICE, "the replay shows the car in its box with the race paused")
	_check(abs(p.d - (t.pit_lane_d() - 1.6)) < 0.01, "in the box lane")
	var k := 0
	while main.pit_show.showing and k < 60 * 15:
		await process_frame
		k += 1
	_check(not main.pit_show.showing and not main.paused, "the replay ends by itself and the race goes on (%.1f s)" % (k / 60.0))
	_check(abs(p.dist - was_dist) < 2.0 + p.v * 0.1 and abs(p.d - was_d) < 0.5 and p.pit_state != ctl.Pit.SERVICE, "the car is back where it was (%.2f m, %.2f m)" % [p.dist - was_dist, p.d - was_d])

	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)
