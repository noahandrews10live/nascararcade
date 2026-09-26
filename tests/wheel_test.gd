extends SceneTree
## The force-feedback helper: the game starts it, streams forces to it and gets a
## status back ("NONE" here: no wheel attached), and stops it on exit.
##   godot --headless -s tests/wheel_test.gd   (build native/ first: native/build.sh)

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1


func _run() -> void:
	var game := root.get_node("Game")
	var Wheel: GDScript = load("res://scripts/wheel.gd")
	var w: Node = Wheel.new()
	root.add_child(w)
	game.wheel.enabled = true
	w.start_helper()
	_check(w.helper_pid > 0, "the helper starts")
	var t := 0.0
	while w.status == "" and t < 5.0:
		w.update(null, 1.0 / 60.0)
		await process_frame
		await create_timer(1.0 / 60.0).timeout
		t += 1.0 / 60.0
	print("   helper says: '%s'" % w.status)
	_check(w.status == "NONE" or w.status.begins_with("OK"), "the helper reports back (no wheel here)")
	_check(w.read().has("steer"), "wheel input reads without a device")
	w.stop_helper()
	game.wheel.enabled = false
	await create_timer(0.5).timeout
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
