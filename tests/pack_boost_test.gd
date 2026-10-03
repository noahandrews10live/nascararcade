extends SceneTree
## Every green packs the field together (the heaviest physics of the race), so
## on a real device the governor goes to its cheapest level for the first
## PACK_BOOST seconds after the start and each restart, then hands back the level
## it had. (Headless runs have no governor; this test turns it on.)
##   godot --headless --fixed-fps 60 -s tests/pack_boost_test.gd

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
	var game = root.get_node("Game")
	for i in 20:
		await physics_frame
	main.clear_checkpoint()
	game.settings.weekend = 0
	game.settings.weather = 0
	game.settings.cautions = 1
	game.sim_level = 0
	main.mode = "race"
	main.session = "race"
	main._use_track(1)
	main._enter_track_select()
	main._enter_car_select()
	main._enter_countdown()
	main.autopilot = true
	main._fixed_fps = false # (the governor on, as on a device)
	var race = main.race
	var ctl = race.control
	ctl.debris_rate = 0.0
	while not race.running:
		await physics_frame
	await _frames(10)
	_check(game.sim_level == 0, "(the boost isn't remembered as the device's level)")
	print("   at the start: level %d" % race.sim_level)
	_check(race.sim_level == race.MAX_SIM_LEVEL, "the start: the cheapest level while the pack is together")
	while race.time < main.PACK_BOOST + 1.0:
		await physics_frame
	await _frames(5)
	print("   after %.0f s: level %d" % [race.time, race.sim_level])
	_check(race.sim_level == 0, "then back to the level it had")
	# A restart: the same again.
	ctl.throw_caution("test", null)
	var n := 0
	while ctl.flag == ctl.Flag.YELLOW or n < 60:
		if main.pit_menu and is_instance_valid(main.pit_menu):
			main._close_pit_menu()
		if main.pit_show and main.pit_show.showing:
			main.pit_show._end_show()
		await physics_frame
		n += 1
		if n > 60 * 150:
			break
	await _frames(10)
	print("   after the restart: level %d" % race.sim_level)
	_check(ctl.flag != ctl.Flag.YELLOW and race.sim_level == race.MAX_SIM_LEVEL, "a restart: the cheapest level again")
	while race.time < float(ctl.green_at) + main.PACK_BOOST + 1.0:
		await physics_frame
	_check(main._boost_from == -1, "and hands back again after %.0f s" % main.PACK_BOOST)
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
