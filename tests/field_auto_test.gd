extends SceneTree
## Field size on AUTO: as many cars as the device runs smoothly.
##   - AUTO is the default, and old saves (20 / 30 / 40, no AUTO) move to it;
##   - how a race ran picks the next size: down at once, up a size at a time;
##   - a race on AUTO starts with that many cars, and learns after 20 s;
##   - the RACE SETUP row offers AUTO and every size.
##   ST_NO_INTRO=1 godot --headless --fixed-fps 60 -s tests/field_auto_test.gd

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1


func _run() -> void:
	var game: Node = root.get_node("Game")
	# An old save: FIELD SIZE 40 from before AUTO.
	var old := ConfigFile.new()
	old.load(game.SETTINGS_PATH)
	var cf := ConfigFile.new()
	cf.set_value("settings", "field", 2)
	cf.save(game.SETTINGS_PATH)
	game.load_settings()
	_check(int(game.settings.field) == -1, "an old save moves to AUTO")
	game.save_settings()
	game.settings.field = 1
	game.save_settings()
	game.load_settings()
	_check(int(game.settings.field) == 1, "a size chosen after that stays chosen")
	# The model. A reference-speed machine with 20 cars: 2.5 + 2.6 ms.
	var G = game.get_script()
	_check(G.auto_field_for(20, 5.1, 16.7, 20) == 25, "a fast device at 20 cars moves up one size (to %d)" % G.auto_field_for(20, 5.1, 16.7, 20))
	_check(G.auto_field_for(25, 5.8, 16.7, 25) == 30 and G.auto_field_for(30, 6.4, 16.7, 30) == 40, "and keeps going up race by race to 40")
	var slow: int = G.auto_field_for(40, 7.7 * 1.6, 16.7, 40) # 1.6x slower than the reference
	_check(slow < 40 and slow >= 20, "a slower device at 40 cars drops at once (to %d)" % slow)
	_check(G.auto_field_for(40, 4.0, 26.0, 40) <= 30, "dropping frames (38 fps) means fewer cars whatever the script time")
	_check(G.auto_field_for(20, 30.0, 40.0, 20) == 20, "never under 20")
	# A race on AUTO.
	game.settings.field = -1
	game.settings.auto_field = 25
	_check(game.field_size() == 25, "AUTO uses the learned size")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.mode = "race"
	main.session = "race"
	main._use_track(0)
	main._enter_race_setup()
	var labels := []
	for r in main.menu.rows:
		if String(r.get("id", "")) == "field":
			labels = r.get("values", [])
	print("   FIELD SIZE values: ", labels)
	_check(labels.size() == 5 and String(labels[0]).begins_with("AUTO") and String(labels[0]).contains("25"), "RACE SETUP offers AUTO (25 CARS) and every size")
	main._enter_countdown()
	main.autopilot = true
	await process_frame
	_check(main.race.cars.size() == 25, "the race starts with 25 cars (%d)" % main.race.cars.size())
	var n := 0
	while main._frame_ms.size() < 1201 and n < 4000:
		await process_frame
		n += 1
	print("   after 20 s: %.2f ms script per frame, AUTO now %d" % [main._script_ms / max(main._frame_ms.size(), 1), int(game.settings.auto_field)])
	_check(int(game.settings.auto_field) in game.FIELDS, "20 s in, AUTO has learned from this race")
	old.save(game.SETTINGS_PATH)
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
