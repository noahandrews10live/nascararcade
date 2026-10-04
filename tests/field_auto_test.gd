extends SceneTree
## Field size on AUTO: as many cars as the device runs smoothly.
##   - AUTO is the default, and old saves (20 / 30 / 40, no AUTO) move to it;
##   - how a race ran picks the next size: down at once, up a size at a time;
##   - a race on AUTO starts with that many cars, and learns after 20 s;
##   - the RACE SETUP row offers AUTO and every size;
##   - no race ever has more than 40 cars, and phones and browsers stop at 25.
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
	_check(G.auto_field_for(25, 5.8, 16.7, 25) == 40, "a reference-speed computer at 25 moves up to 40")
	_check(G.auto_field_for(40, 7.7 * 1.3, 16.7, 40) == 25, "a computer that can't quite hold 40 drops back to 25")
	var slow: int = G.auto_field_for(25, 5.75 * 2.2, 16.7, 25) # 2.2x slower than the reference
	_check(slow == 20, "a slower device at 25 cars drops at once (to %d)" % slow)
	_check(G.auto_field_for(25, 4.0, 26.0, 25) == 20, "dropping frames (38 fps) means fewer cars whatever the script time")
	game.settings.field = -1
	game.settings.auto_field = 40
	_check(game.field_size() == 40, "on a computer AUTO can be 40")
	OS.set_environment("ST_TOUCH", "1")
	_check(game.field_size() == 25, "on a phone AUTO is held to 25")
	OS.set_environment("ST_TOUCH", "")
	game.settings.field = 9 # an out-of-range fixed size
	_check(game.field_size() == 40, "a fixed size past the list is the biggest, 40")
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
	_check(labels.size() == 4 and String(labels[0]).begins_with("AUTO") and String(labels[0]).contains("25") and String(labels[3]).contains("40"), "RACE SETUP offers AUTO (25 CARS) and every size up to 40")
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
	# Every mode stops at 40, whatever it asks for.
	var r2 = load("res://scripts/race.gd").new()
	root.add_child(r2)
	r2.setup(main.track, -1, 2, 60)
	_check(r2.cars.size() == 40, "a race asked for 60 cars gets 40 (%d)" % r2.cars.size())
	r2.queue_free()
	old.save(game.SETTINGS_PATH)
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
