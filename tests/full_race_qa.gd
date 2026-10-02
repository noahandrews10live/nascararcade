extends SceneTree
## Full-race QA: a whole full-rules race (SHORT length: cautions, pit stops,
## stages, changeable weather, a full field) at one track, your car on
## autopilot, watching for anything a player would notice going wrong:
##   - the race starts, runs and reaches the results;
##   - every car finishes or is out, positions are whole and in order, nothing
##     goes NaN or flies off the world;
##   - no car sits stopped on track under green without a caution coming out;
##   - every caution goes back to green;
##   - your car never runs dry (the crew chief and the pit calls keep it in);
##   - the crew chief doesn't nag (a handful of calls, never the same twice);
##   - the debrief adds up (every place gained or lost has a cause) and has
##     advice.
##   TRACK=n ST_NO_INTRO=1 godot --headless --fixed-fps 60 -s tests/full_race_qa.gd

var main: Node
var game: Node
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
	game = root.get_node("Game")
	await _frames(20)
	var idx := int(OS.get_environment("TRACK")) if OS.get_environment("TRACK") != "" else 0
	main.clear_checkpoint()
	game.settings.length = 1
	game.settings.weekend = 0
	game.settings.cautions = 1
	game.settings.damage = 1
	game.settings.wear = 1
	game.settings.weather = 1
	game.settings.field = -1
	main.mode = "race"
	main.session = "race"
	main._use_track(idx)
	print("TRACK %d: %s, %d laps" % [idx, game.tracks[idx].name, game.race_laps(idx)])
	main._enter_countdown()
	main.autopilot = true
	var race: Node3D = main.race
	var ctl: Node = race.control
	var sim := 0.0
	var yellow_t := 0.0
	var longest_yellow := 0.0
	var rain_hold := 0.0
	var cautions := 0
	var was_yellow := false
	var stopped := {} # car -> seconds stopped on track under green
	var worst_stop := 0.0
	var worst_stop_car := ""
	var bad_numbers := false
	var dry := false
	var pit_calls := 0
	var limit: float = 60.0 * 60.0
	while main.state != main.State.RESULTS and sim < limit:
		await physics_frame
		sim += 1.0 / 60.0
		if main.paused and main.pit_menu and is_instance_valid(main.pit_menu):
			pit_calls += 1
			main._close_pit_menu() # take the call as it stands (the crew chief's)
		if main.state != main.State.RACE:
			continue
		var yellow: bool = ctl.flag == ctl.Flag.YELLOW
		if yellow and not was_yellow:
			cautions += 1
			yellow_t = 0.0
		if yellow and ctl.weather_hold:
			rain_hold += 1.0 / 60.0 # rain: held under yellow until it's dry (by design)
			yellow_t = 0.0 # (what counts is getting going again once it's dry)
		elif yellow:
			yellow_t += 1.0 / 60.0
			longest_yellow = max(longest_yellow, yellow_t)
		was_yellow = yellow
		var p: Node3D = race.player
		if p.fuel <= 0.0 and not p.finished:
			dry = true
		if int(sim * 60.0) % 30 == 0:
			for c in race.cars:
				if is_nan(c.dist) or is_nan(c.v) or abs(c.global_position.y) > 400.0:
					bad_numbers = true
				var on_track: bool = not c.out and not c.finished and c.pit_state == 0 and not c.pace_mode
				if on_track and not yellow and c.speed() < 3.0 and race.time > 20.0:
					stopped[c] = float(stopped.get(c, 0.0)) + 0.5
					if stopped[c] > worst_stop:
						worst_stop = stopped[c]
						worst_stop_car = "#%s at %s" % [c.team.num, race.track.place_name(c.s())]
				else:
					stopped[c] = 0.0
	var p: Node3D = race.player
	print("   sim %.0f s, %d cautions (longest %.0f s, %.0f s held for rain), %d pit calls, place %d of %d" % [sim, cautions, longest_yellow, rain_hold, pit_calls, race.position_of(p), race.cars.size()])
	_check(main.state == main.State.RESULTS, "the race reaches the results")
	_check(race.cars.all(func(c): return c.finished or c.out), "every car finished or is out")
	var places: Array = race.order.map(func(c): return race.position_of(c))
	_check(places == range(1, race.cars.size() + 1), "positions are 1..%d with no gaps or repeats" % race.cars.size())
	_check(not bad_numbers, "no NaNs, nothing thrown off the world")
	_check(worst_stop < 12.0, "no car sat stopped on track under green (worst %.1f s%s)" % [worst_stop, ", " + worst_stop_car if worst_stop_car != "" else ""])
	_check(longest_yellow < 150.0, "every caution went back to green (longest %.0f s, not counting rain holds)" % longest_yellow)
	_check(not dry, "your car never ran out of fuel")
	_check(main.game_over_reason == "", "your race wasn't ended early ('%s')" % main.game_over_reason)
	var calls: Array = main.crew_watch.log if main.crew_watch else []
	var texts := {}
	var repeats := 0
	for c in calls:
		if texts.has(c.text):
			repeats += 1
		texts[c.text] = true
	print("   crew chief: ", calls.map(func(c): return c.text))
	_check(calls.size() <= 12 and repeats == 0, "the crew chief doesn't nag (%d calls, %d repeats)" % [calls.size(), repeats])
	var sm: Dictionary = main.race_log.summary()
	var total := 0
	for k in sm.gained:
		total += int(sm.gained[k])
	_check(total == sm.start - sm.finish, "the debrief adds up (%+d = %d to %d: %s)" % [total, sm.start, sm.finish, str(sm.gained)])
	await _frames(70)
	main._enter_debrief()
	await _frames(3)
	_check(main.state == main.State.DEBRIEF and main.debrief.tips.size() >= 1, "the debrief has advice: %s" % (main.debrief.tips[0].text if main.debrief and not main.debrief.tips.is_empty() else ""))
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
