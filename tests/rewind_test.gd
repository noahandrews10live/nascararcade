extends SceneTree
## REWIND: after a crash that brings out a caution, going back five seconds puts
## every car where it was, cancels the caution, counts 3-2-1 and races on; the
## pit call offers it when it was your crash; uses run out; the lap doesn't count
## as a record; it isn't offered online.
##   ST_NO_INTRO=1 godot --headless --fixed-fps 60 -s tests/rewind_test.gd

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
	main.clear_checkpoint()
	game.settings.weather = 0
	game.settings.field = 0
	game.settings.weekend = 0
	game.settings.cautions = 1
	game.settings.rewinds = 1
	main.mode = "race"
	main.session = "race"
	main._use_track(1)
	main._enter_countdown()
	main.autopilot = true
	while main.state != main.State.RACE:
		await physics_frame
	await _frames(60 * 30)
	var race: Node3D = main.race
	var ctl: Node = race.control
	var p: Node3D = race.player
	_check(main.rewind.left == 3 and main.rewind.available(), "3 rewinds, and one is available")
	# Where everyone is now; then six seconds on, a crash and a caution.
	var t0: float = race.time
	var snap := {}
	for c in race.cars:
		snap[c] = c.dist
	await _frames(60 * 6)
	main.autopilot = false
	p.autopilot_forced = false
	p.ai = false
	var cautions: int = ctl.caution_count
	p.damage.front = 0.6
	ctl.throw_caution("ACCIDENT", p)
	main._offer_rewind()
	await _frames(60 * 6)
	_check(ctl.flag == ctl.Flag.YELLOW, "the crash brings out the caution")
	var n := 0
	while not (main.pit_menu and is_instance_valid(main.pit_menu)) and n < 60 * 20:
		await physics_frame
		n += 1
	_check(main.pit_menu and main.pit_menu.rows.any(func(r): return r.id == "rewind"), "your crash: the pit call offers REWIND")
	main.pit_menu.activated.emit("rewind")
	await _frames(2)
	_check(main.pit_menu == null and ctl.flag == ctl.Flag.GREEN and ctl.caution_count == cautions, "REWIND: the caution never happened")
	_check(race.time <= t0 + 1.01 and race.time > t0 - 1.0, "the clock went back to five seconds before the crash (%.1f, crash at %.1f)" % [race.time, t0 + 6.0])
	_check(p.damage.front < 0.1 and abs(p.dist - (snap[p] + (race.time - t0) * p.v)) < 250.0, "your car is back where it was, undamaged")
	_check(main.paused and main.resume_t > 0.0, "and it counts you back in")
	_check(p.get_meta("lap_void", false), "that lap won't count as a record")
	_check(main.rewind.left == 2, "one use gone (%d left)" % main.rewind.left)
	_check(main.race_log.events.any(func(e): return e.kind == "rewind"), "the debrief knows")
	await _frames(60 * 4)
	_check(not main.paused and main.state == main.State.RACE, "racing again")
	# Out of uses.
	main.rewind.left = 0
	_check(not main.rewind.available() and not main.do_rewind(), "none left: no rewind")
	# Online never, nor in split screen or the daily challenge.
	var m0: String = main.mode
	var counts := []
	for m in ["online", "2p", "race", "career"]:
		main.mode = m
		counts.append(main.rewind_uses())
	main.mode = m0
	_check(counts == [0, 0, 3, 3], "none online or in split screen; 3 in a race or a career (%s)" % str(counts))
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
