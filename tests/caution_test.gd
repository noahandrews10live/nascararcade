extends SceneTree
## Quick cautions in a real race:
##   - the race pauses for the player's pit call, with a crew chief's advice and a
##     predicted restart spot for every choice;
##   - yellow to green takes about 15 seconds of race time (the pause aside);
##   - the AI decides for itself: worn cars pit far more than fresh ones;
##   - the restart order: cars that stayed out in the order they held when the
##     caution came out, then the cars that pitted in the order they got off pit
##     road, then the free pass car and the lapped cars; lined up double file;
##   - the player's stop is actually made (a 2-tire stop changes the right sides);
##   - the lap the field was lined up in doesn't count as a best lap.
##   godot --headless --fixed-fps 60 -s tests/caution_test.gd

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


func _run() -> void:
	var game := root.get_node("Game")
	await _frames(20)
	game.settings.length = 1
	game.settings.field = 0
	game.settings.weather = 0
	game.settings.weekend = 0
	game.settings.cautions = 1
	game.tracks[1].full_laps = 600
	main.mode = "race"
	main.session = "race"
	main._use_track(1)
	main._enter_track_select()
	main._enter_car_select()
	main._enter_countdown()
	main.autopilot = true
	var race = main.race
	var ctl = race.control
	ctl.debris_rate = 0.0
	await _frames(60 * 40)
	var p = race.player
	# Half the field on worn tyres, the other half on fresh ones.
	var worn := {}
	var k := 0
	for c in race.order:
		if c == p:
			continue
		worn[c] = k % 2 == 0
		c.tyre_wear = 0.55 if worn[c] else 0.02
		k += 1
	p.tyre_wear = 0.4
	# A lapped car for the free pass.
	var lapped: Node3D = race.order[race.order.size() - 1]
	if lapped == p:
		lapped = race.order[race.order.size() - 2]
	lapped.dist -= race.track.length
	lapped.lap_idx = lapped.lap()
	await _frames(2)
	var greens := []
	ctl.flag_changed.connect(func(f): if f == "GREEN": greens.append(race.time))
	var t0: float = race.time
	ctl.throw_caution("TEST", null)
	var freeze: Array = ctl._freeze.duplicate()
	main.autopilot = false
	p.autopilot_forced = false
	# --- the pit call
	var waited := 0
	while main.pit_menu == null and waited < 60 * 6:
		await physics_frame
		waited += 1
	_check(main.pit_menu != null and main.paused, "the race pauses for the player's pit call")
	if main.pit_menu == null:
		_finish()
		return
	var info: Dictionary = main._pit_info
	print("   advice %s, estimates %s" % [info.advice, str(info.estimate)])
	_check(info.options.has(info.advice), "the crew chief makes a call")
	_check(info.estimate.size() == info.options.size() and int(info.estimate[""]) <= int(info.estimate["4"]), "every choice shows a restart spot (staying out keeps you further up)")
	var t_pause: float = race.time
	await _frames(120) # the race waits
	_check(is_equal_approx(race.time, t_pause), "the race clock stops while the player decides")
	# Choose 2 tires and confirm.
	var idx2: int = info.options.find("2")
	main.pit_menu.set_value("plan", idx2)
	main._pit_hint()
	var rs_before: float = p.tyre_wear4[1]
	# Each car's stop time as the stops are called (making the stop repairs the
	# damage, which changes what _stop_time would say afterwards).
	var stop_t := {}
	for c in race.cars:
		for o in ["4", "2", "F", "W"]:
			stop_t[[c, o]] = ctl._stop_time(c, o)
	await _press("start")
	await _frames(3)
	_check(main.pit_menu == null and not main.paused, "confirming the call resumes the race")
	# --- the stops and the order
	var calls: Dictionary = ctl._calls
	var pit_worn := 0
	var pit_fresh := 0
	var n_worn := 0
	var n_fresh := 0
	for c in worn:
		if not calls.has(c):
			continue
		if worn[c]:
			n_worn += 1
			pit_worn += int(calls[c] != "")
		else:
			n_fresh += 1
			pit_fresh += int(calls[c] != "")
	print("   pitted: %d of %d on worn tyres, %d of %d on fresh" % [pit_worn, n_worn, pit_fresh, n_fresh])
	_check(float(pit_worn) / max(n_worn, 1) > float(pit_fresh) / max(n_fresh, 1) + 0.3, "the AI pits for worn tyres far more than on fresh ones")
	_check(calls.get(p, "?") == "2" and p.tyre_wear4[1] < 0.01 and rs_before > 0.1, "the player's 2-tire stop is made")
	var order: Array = race.order.filter(func(c): return not c.towed and not c.out)
	var lead = order[0]
	# Stay-outs first, in their order at the caution.
	var stay: Array = order.filter(func(c): return calls.get(c, "") == "" and ctl._laps_down(c, lead) == 0 and c != lapped)
	var last_idx := -1
	var stay_ok := true
	for c in stay:
		var fi: int = freeze.find(c)
		if fi < last_idx:
			stay_ok = false
		last_idx = fi
	var first_pitter := 999
	var last_stay := -1
	for i in order.size():
		var c = order[i]
		if c == lapped:
			continue
		if calls.get(c, "") == "" and ctl._laps_down(c, lead) == 0:
			last_stay = max(last_stay, i)
		elif calls.get(c, "") != "" and ctl._laps_down(c, lead) == 0:
			first_pitter = min(first_pitter, i)
	_check(stay_ok and (first_pitter == 999 or last_stay < first_pitter), "cars that stayed out restart ahead, in their order at the caution")
	var pitters: Array = order.filter(func(c): return calls.get(c, "") != "" and ctl._laps_down(c, lead) == 0)
	# When each got off pit road: where it went in (the order at the caution) plus the stop.
	var entry_rank := {}
	var n := 0
	for c in freeze:
		if calls.get(c, "") != "" and ctl._laps_down(c, freeze[0]) == 0:
			entry_rank[c] = n
			n += 1
	var exit_ok := true
	for i in range(1, pitters.size()):
		var a = pitters[i - 1]
		var b = pitters[i]
		var ta: float = entry_rank.get(a, 0) * 0.45 + float(stop_t.get([a, calls[a]], 0.0))
		var tb: float = entry_rank.get(b, 0) * 0.45 + float(stop_t.get([b, calls[b]], 0.0))
		if tb + 0.01 < ta:
			exit_ok = false
	_check(exit_ok, "cars that pitted come out in the order they get off pit road")
	_check(ctl._laps_down(lapped, lead) == 0, "the free pass car gets its lap back")
	var two_wide := true
	for i in min(10, order.size()):
		var c = order[i]
		if abs(c.d - race.lanes[i % 2]) > 0.5:
			two_wide = false
	_check(two_wide, "the field lines up double file")
	# --- green
	var sim := 0
	while greens.is_empty() and sim < 60 * 40:
		await physics_frame
		sim += 1
	var took: float = (greens[0] if not greens.is_empty() else 999.0) - t0
	print("   yellow to green: %.1f s of race time" % took)
	_check(took <= 17.0 and took >= 13.0, "yellow to green takes about 15 seconds")
	# The first lap after the restart isn't a best lap.
	await _frames(60 * 12)
	var bad_best := false
	for c in race.cars:
		if c.best_lap > 0.0 and c.best_lap < 20.0:
			bad_best = true
	_check(not bad_best, "no bogus best laps from lining up")
	_finish()


func _finish() -> void:
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
