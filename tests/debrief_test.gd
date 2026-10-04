extends SceneTree
## The race debrief:
##   - a real race (autopilot) is recorded: laps, positions, events with where
##     they happened, and every place gained or lost put down to a cause;
##   - after the results, CONTINUE shows the debrief; its pages turn; CONTINUE
##     goes on to where the results used to;
##   - the crew chief's advice fits the race (made-up races: a tight car, a crash
##     -fest, a costly green-flag stop, a slow career car, a runaway win);
##   - APPLY changes the garage setup, and that track remembers it.
##   SHOTS=dir writes screenshots of the three pages (run with a renderer).
##   ST_NO_INTRO=1 godot --headless --fixed-fps 60 -s tests/debrief_test.gd

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


func _press(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	await process_frame
	var r := InputEventAction.new()
	r.action = action
	r.pressed = false
	Input.parse_input_event(r)
	await process_frame


func _shot(name: String) -> void:
	var dir := OS.get_environment("SHOTS")
	if dir == "":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(dir.path_join(name + ".png"))


func _coach_cases() -> void:
	var D: GDScript = load("res://scripts/debrief.gd")
	var base := {"gained": {"START": 0, "ON TRACK": 0, "PIT STOPS": 0, "CAUTIONS": 0, "INCIDENTS": 0}, "events": [], "finish": 10,
		"peak_carcass": [90, 120, 95, 125], "pit_stops": [], "balance": 0.0, "lockups": 0, "wall_hits": 0, "spins": 0}
	var cx := {"field": 20, "my_best": 15.3, "winner_best": 15.3, "avg_lap": 15.6, "difficulty": 1, "assist_level": 0.5}
	var tight := base.duplicate(true)
	tight.balance = 0.12
	var t: Array = D.coach(tight, cx)
	_check(t.any(func(x): return x.text.contains("TIGHT") and x.get("action", {}).get("key", "") == "balance" and int(x.action.delta) == 1), "a tight car: 'one click looser', with a button")
	var crash := base.duplicate(true)
	crash.wall_hits = 3
	crash.gained.INCIDENTS = -6
	crash.events = [{"kind": "wall", "where": "TURN 2"}, {"kind": "wall", "where": "TURN 2"}, {"kind": "spin", "where": "TURN 4"}]
	t = D.coach(crash, cx)
	_check(t[0].text.contains("TURN 2") and t[0].text.contains("6 places"), "crashes: names the corner where most happened (%s)" % t[0].text.substr(0, 60))
	_check(t[0].has("action") and t[0].action.kind == "assists", "and offers more steering help (assists were MILD)")
	var pit := base.duplicate(true)
	pit.pit_stops = [{"lap": 30, "before": 4, "after": 15}]
	t = D.coach(pit, cx)
	_check(t.any(func(x): return x.text.contains("lap 30") and x.text.contains("11 places")), "a costly green-flag stop is called out")
	var slow := base.duplicate(true)
	var ccx := cx.duplicate()
	ccx.my_best = 15.8
	ccx.career = true
	ccx.rnd_gain = {"chassis": 0.006, "engine": 0.0015}
	t = D.coach(slow, ccx)
	_check(t.any(func(x): return x.text.contains("CHASSIS") and x.get("action", {}).get("kind", "") == "rnd"), "a slow career car: the R&D area worth most here, and the shop")
	var ncx := cx.duplicate()
	ncx.my_best = 15.8
	slow.finish = 17
	t = D.coach(slow, ncx)
	_check(t.any(func(x): return x.get("action", {}).get("kind", "") == "difficulty" and int(x.action.delta) == -1), "off the pace outside career: offers an easier field")
	var won := base.duplicate(true)
	won.finish = 1
	var wcx := cx.duplicate()
	wcx.margin = 6.0
	t = D.coach(won, wcx)
	_check(t.any(func(x): return x.get("action", {}).get("kind", "") == "difficulty" and int(x.action.delta) == 1), "a runaway win: offers a tougher field")
	t = D.coach(base, cx)
	_check(t.size() >= 1 and t.size() <= 4, "always something to say, never more than four")


## SHOTS: the three pages from a made-up 40-lap race (a real race is too slow
## to run with a software renderer).
func _shots_only() -> void:
	var laps: Array = []
	var pos := 18
	for i in 40:
		pos = clampi(pos + [-1, -1, 0, 1, -2, 0][i % 6] + (6 if i == 22 else 0) - (3 if i == 30 else 0), 1, 24)
		laps.append({"lap": i + 1, "pos": pos, "time": 15.4 + 0.012 * (i % 20) + (3.0 if i == 22 else 0.0), "gap": 0.2 * pos,
			"grip": 1.0 - 0.004 * (i % 20), "wear": 0.01 * (i % 20), "fuel": 70.0 - i, "flag": "Y" if i in [12, 13, 14] else "G",
			"temps": [95, 118, 92, 112], "pit": i == 13})
	var sm := {"start": 18, "finish": 9, "laps": laps,
		"events": [{"lap": 1, "kind": "start", "text": "Started 18th", "where": "", "pos": 18},
			{"lap": 12, "kind": "caution", "text": "Caution: #24 GORDON SPUN IN TURN 2", "where": "TURN 2", "pos": 14},
			{"lap": 14, "kind": "pit", "text": "Pit stop: 14th to 11th", "where": "", "pos": 11},
			{"lap": 23, "kind": "contact", "text": "#7 ran into you in TURN 3", "where": "TURN 3", "pos": 10},
			{"lap": 23, "kind": "spin", "text": "Spun in TURN 3", "where": "TURN 3", "pos": 16, "why": "CONTACT WITH #7"},
			{"lap": 40, "kind": "finish", "text": "Finished 9th", "where": "", "pos": 9}],
		"gained": {"START": 3, "ON TRACK": 9, "PIT STOPS": 3, "CAUTIONS": 0, "INCIDENTS": -6},
		"passes_made": 14, "passes_lost": 5, "wall_hits": 0, "spins": 1, "lockups": 2, "contacts": {"7": 2, "11": 1},
		"peak_temp": [101, 131, 96, 120], "peak_carcass": [98, 150, 92, 124], "balance": 0.07, "pit_stops": [{"lap": 14, "before": 14, "after": 11}],
		"cautions": 1, "led": 0, "green_laps": laps.filter(func(l): return l.flag == "G" and not l.pit).map(func(l): return l.time)}
	var cx := {"field": 24, "my_best": 15.41, "winner_best": 15.33, "fastest": 15.31, "fastest_by": "#24", "margin": 1.2, "avg_lap": 15.55,
		"difficulty": 1, "assist_level": 0.5, "career": true, "rnd_gain": {"chassis": 0.006, "engine": 0.0015}}
	main._clear_screen()
	main.hud.visible = false
	var d: Control = load("res://scripts/debrief.gd").new()
	main.screen.add_child(d)
	d.setup(sm, cx)
	await _frames(5)
	await _shot("debrief_1")
	d.turn(1)
	await _frames(3)
	await _shot("debrief_2")
	d.turn(1)
	await _frames(3)
	await _shot("debrief_3")
	quit(0)


func _run() -> void:
	game = root.get_node("Game")
	await _frames(20)
	if OS.get_environment("SHOTS") != "":
		await _shots_only()
		return
	_coach_cases()
	main.clear_checkpoint()
	game.settings.weather = 0
	game.settings.field = 0
	game.settings.weekend = 0
	game.settings.cautions = 1
	game.tracks[2].full_laps = 60 # 6 laps at SHORT
	game.settings.length = 1
	main.mode = "race"
	main.session = "race"
	main._use_track(2)
	main._enter_countdown()
	main.autopilot = true
	var n := 0
	while main.state != main.State.RESULTS and n < 60 * 400:
		await physics_frame
		if main.paused and main.pit_menu:
			main.pit_menu.confirm() if main.pit_menu.has_method("confirm") else null
		n += 1
	_check(main.state == main.State.RESULTS, "the race reaches the results (%.0f s)" % (n / 60.0))
	var sm: Dictionary = main.race_log.summary()
	print("   log: start %d finish %d, %d laps, %d events, gained %s" % [sm.start, sm.finish, sm.laps.size(), sm.events.size(), str(sm.gained)])
	_check(sm.laps.size() >= 5 and sm.start > 0 and sm.finish > 0, "every lap and the start and finish are recorded")
	var total := 0
	for k in sm.gained:
		total += int(sm.gained[k])
	_check(total == sm.start - sm.finish, "every place gained or lost has a cause (%+d = %d to %d)" % [total, sm.start, sm.finish])
	_check(sm.events.any(func(e): return e.kind == "finish") and sm.events.all(func(e): return e.has("where") and e.has("lap")), "key moments carry the lap and where")
	await _frames(70)
	await _press("start")
	await _frames(5)
	_check(main.state == main.State.DEBRIEF and main.debrief != null, "CONTINUE on the results opens the debrief")
	await _shot("debrief_1")
	main.debrief.turn(1)
	await _frames(3)
	_check(main.debrief.page == 1, "NEXT turns the page")
	await _shot("debrief_2")
	main.debrief.turn(1)
	await _frames(3)
	await _shot("debrief_3")
	var lc: Array = sm.get("order_by_lap", [])
	_check(main.debrief.page == 2 and lc.size() >= 2 and lc[-1].size() == main.race.cars.size(), "the lap chart: the whole field's order, every lap (%d laps)" % lc.size())
	main.debrief.turn(1)
	await _frames(3)
	await _shot("debrief_4")
	_check(main.debrief.page == 3 and main.debrief.tips.size() >= 1, "the coach page has advice (%d tips)" % main.debrief.tips.size())
	# APPLY: a setup change, remembered for this track only.
	var bal0: int = int(game.setup.balance)
	main._on_debrief_action({"kind": "setup", "key": "balance", "delta": 1, "label": "TEST"})
	_check(int(game.setup.balance) == clampi(bal0 + 1, -3, 3), "APPLY changes the garage setup")
	main._use_track(1)
	game.setup.balance = -2
	game.remember_setup(1)
	main._use_track(2)
	_check(int(game.setup.balance) == clampi(bal0 + 1, -3, 3), "and the track remembers it (back from another track's setup)")
	await _frames(40)
	await _press("start")
	await _frames(5)
	_check(main.state != main.State.DEBRIEF, "CONTINUE leaves the debrief")
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
