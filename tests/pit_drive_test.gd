extends SceneTree
## PIT ROAD: YOU DRIVE. Race control steers; the pedals are yours from the
## approach to the blend line. A test driver works them:
##   - a clean stop: on the limit, stopped in the stall: serviced, no penalty;
##   - speeding: over the limit on pit road is called, the stop is still made,
##     and the pass-through is served the next time down pit road (no stop);
##   - overshooting the stall: the crew pushes you back, 3 s on the stop;
##   - never stopping: "missed your stall", no service.
##   godot --headless --fixed-fps 60 -s tests/pit_drive_test.gd

var main: Node
var game: Node
var failures := 0
var ctl: Node
var race: Node3D
var p: Node3D
var said: Array = []


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1


func _pedals(thr: float, brk: float) -> void:
	if thr > 0.01:
		Input.action_press("accelerate", thr)
	else:
		Input.action_release("accelerate")
	if brk > 0.01:
		Input.action_press("brake", brk)
	else:
		Input.action_release("brake")


## One stop, driven: `over` m/s over the limit on pit road, `stop_at` metres
## past the stall mark to stop (negative: before it), or never stop.
## Returns what happened.
func _stop(over: float, stop_at: float, never_stop := false) -> Dictionary:
	main.autopilot = true
	p.want_pit = true
	p.pit_plan = "4"
	var n := 0
	while p.pit_state == 0 and n < 60 * 120:
		await physics_frame
		n += 1
	# From here, a human on the pedals.
	main.autopilot = false
	p.autopilot_forced = false
	var states := {}
	var max_v := 0.0
	var serviced := false
	var timer0 := 0.0
	var L: float = race.track.length
	var limit: float = ctl.pit_speed
	n = 0
	while p.pit_state != 0 and n < 60 * 120:
		var ss: float = p.s()
		var rel: float = fposmod(ctl.box_s(p) - ss + L * 0.5, L) - L * 0.5
		var in_zone: bool = race.track.in_pit_zone(ss)
		var target: float = limit + over if in_zone else limit - 0.5
		if p.pit_state == ctl.Pit.APPROACH:
			# Slow to the limit by the line.
			var to_line: float = fposmod(race.track.pit_in_s() - ss, L)
			target = sqrt(limit * limit + 2.0 * 7.0 * max(to_line - 20.0, 0.0))
		if p.pit_state == ctl.Pit.LANE and not never_stop:
			# Brake for the stall: aim to stop `stop_at` past the mark.
			var d_stop: float = rel + stop_at
			var stop_v: float = sqrt(max(2.0 * 6.0 * max(d_stop, 0.0), 0.0))
			target = min(target, stop_v)
			if d_stop <= 0.3:
				target = 0.0
		if p.pit_state == ctl.Pit.SERVICE:
			serviced = true
			if timer0 == 0.0:
				timer0 = p.pit_timer
			# Wait for the jack, then go.
			_pedals(1.0 if p.pit_timer <= 0.0 else 0.0, 0.0)
		elif target <= 0.0:
			_pedals(0.0, 1.0) # stopped in the box: stand on the brake
		elif p.v > target + 0.3:
			_pedals(0.0, clamp((p.v - target) / 4.0, 0.3, 1.0))
		else:
			_pedals(clamp(0.4 + (target - p.v) * 0.3, 0.0, 1.0), 0.0)
		var was: int = p.pit_state
		await physics_frame
		n += 1
		if was == ctl.Pit.LANE and p.pit_state == ctl.Pit.SERVICE and OS.get_environment("DEBUG_PD") != "":
			print("   [service: rel %.2f, v %.2f, target %.2f, thr %.2f brk %.2f]" % [rel, p.v, target, p.throttle, p.brake])
		states[p.pit_state] = true
		if in_zone and p.pit_state != ctl.Pit.SERVICE:
			max_v = max(max_v, p.v)
	_pedals(0.0, 0.0)
	main.autopilot = true
	return {"states": states, "serviced": serviced, "timer": timer0, "max_v": max_v, "penalty": p.penalty, "limit": limit}


func _run() -> void:
	game = root.get_node("Game")
	for i in 20:
		await physics_frame
	main.clear_checkpoint()
	game.settings.length = 1
	game.settings.field = 0
	game.settings.weather = 0
	game.settings.weekend = 0
	game.settings.cautions = 0
	game.settings.pit_drive = 1
	game.tracks[1].full_laps = 600
	main.mode = "race"
	main.session = "race"
	main._use_track(1)
	main._enter_track_select()
	main._enter_car_select()
	main._enter_countdown()
	main.autopilot = true
	race = main.race
	ctl = race.control
	ctl.message.connect(func(t, _k): said.append(t))
	await _frames(60 * 15)
	p = race.player

	var r := await _stop(-0.5, 0.0)
	_check(not said.any(func(t): return String(t).contains("PUSHES YOU BACK")), "(stopped in the box: no push-back)")
	print("   clean: %s, max %.1f m/s (limit %.1f), stop %.1f s, penalty '%s'" % [r.states.keys(), r.max_v, r.limit, r.timer, r.penalty])
	_check(r.serviced and r.penalty == "" and r.max_v <= r.limit + ctl.SPEED_TOLERANCE, "a clean stop: serviced, no penalty")
	var clean_t: float = r.timer
	await _frames(60 * 5)

	r = await _stop(3.0, 0.0)
	print("   speeding: max %.1f m/s, penalty '%s'" % [r.max_v, r.penalty])
	_check(r.serviced, "speeding: the stop is still made")
	_check(r.penalty == "PT", "and a pass-through is owed afterwards")
	# Served next time pit road is open: down it, no stop.
	var states := {}
	var n := 0
	while (p.penalty != "" or p.pit_state != 0 or not states.has(ctl.Pit.EXIT)) and n < 60 * 150:
		await physics_frame
		states[p.pit_state] = true
		n += 1
	print("   pass-through: states %s, penalty '%s', state now %d, %.0f s" % [states.keys(), p.penalty, p.pit_state, n / 60.0])
	_check(states.has(ctl.Pit.EXIT) and not states.has(ctl.Pit.SERVICE) and p.penalty == "", "the pass-through is served: down pit road, no stop")
	await _frames(60 * 5)

	said.clear()
	r = await _stop(-0.5, 5.0)
	var pushed := said.any(func(t): return String(t).contains("PUSHES YOU BACK"))
	print("   overshoot: stop %.1f s (clean %.1f), pushed back %s" % [r.timer, clean_t, pushed])
	# (the stop's own time varies with the crew: the push-back is what's checked)
	_check(r.serviced and pushed, "overshooting the stall: pushed back, %.0f s on the stop" % ctl.OVERSHOOT_TIME)
	await _frames(60 * 5)

	r = await _stop(-0.5, 0.0, true)
	print("   never stopped: %s" % str(r.states.keys()))
	_check(not r.serviced and r.states.has(ctl.Pit.EXIT), "never stopping: missed the stall, no service")
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame
