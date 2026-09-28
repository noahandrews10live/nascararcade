extends SceneTree
## Life on a phone:
##   - the app going to the background (a call, another app) pauses the race and
##     mutes the sound; coming back leaves it paused;
##   - RESUME counts 3-2-1 back in, and the race only moves after the count;
##   - pausing again during the count stops it;
##   - online the race isn't paused (the others race on);
##   - BATTERY SAVER ON caps the frame rate at 30 and OFF lifts it; AUTO saves
##     on battery at 20% or less.
##   ST_NO_INTRO=1 godot --headless --fixed-fps 60 -s tests/phone_life_test.gd

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
		await process_frame


func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	ev = InputEventAction.new()
	ev.action = action
	ev.pressed = false
	Input.parse_input_event(ev)
	await process_frame


func _run() -> void:
	var game: Node = root.get_node("Game")
	await _frames(20)
	main.mode = "race"
	main.session = "practice"
	main._use_track(1)
	main._enter_countdown()
	main.autopilot = true
	var n := 0
	while main.state != main.State.RACE and n < 1200:
		await process_frame
		n += 1
	print("   racing after %d frames (state %d)" % [n, main.state])
	await _frames(60)
	# Off to another app.
	main._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	await _frames(2)
	_check(main.paused and main.pause_layer.visible, "going to the background pauses the race")
	_check(AudioServer.is_bus_mute(0), "and mutes the sound")
	var t0: float = main.race.time
	await _frames(120)
	_check(is_equal_approx(main.race.time, t0), "the race doesn't move while away")
	main._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await _frames(2)
	_check(not AudioServer.is_bus_mute(0) and main.paused, "back again: sound on, still paused")
	# RESUME: 3-2-1.
	await _press("pause")
	_check(main.resume_t > 2.5 and main.paused and not main.pause_layer.visible, "RESUME starts a 3-2-1 count")
	await _frames(60)
	_check(main.paused and is_equal_approx(main.race.time, t0), "the race waits through the count")
	await _press("pause")
	_check(main.resume_t == 0.0 and main.pause_layer.visible, "pausing during the count stops it")
	await _press("pause")
	await _frames(200)
	_check(not main.paused and main.race.time > t0, "after the count the race runs again")
	# Online nobody waits.
	main.mode = "online"
	_check(not main.auto_pause() and not main.paused, "online the race isn't paused")
	main.mode = "race"
	# Battery saver.
	game.settings.battery = 2
	main._battery_t = 0.0
	await _frames(2)
	_check(Engine.max_fps == 30 and main.battery_saver_on, "BATTERY SAVER ON: 30 fps")
	game.settings.battery = 0
	main._battery_t = 0.0
	await _frames(2)
	_check(Engine.max_fps == 0 and not main.battery_saver_on, "OFF: the full frame rate")
	var b: Array = game.battery()
	print("   this machine's battery: ", b)
	game.settings.battery = 1
	_check(game.battery_saving() == (b[1] and b[0] >= 0 and b[0] <= 20), "AUTO saves only on battery at 20% or less")
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
