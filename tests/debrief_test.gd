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


func _run() -> void:
	game = root.get_node("Game")
	await _frames(20)
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
	_check(main.debrief.page == 2 and main.debrief.tips.size() >= 1, "the coach page has advice (%d tips)" % main.debrief.tips.size())
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
