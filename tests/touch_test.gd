extends SceneTree
## Touch controls, with real touch events:
##   - in the menus a tap on the screen moves on (title -> the garage);
##   - in a race the GAS pedal opens the throttle and BRAKE brakes;
##   - dragging a thumb on the left steers (right drag = right, left = left);
##   - a keyboard press hides the touch controls again.
##   godot --headless --fixed-fps 60 -s tests/touch_test.gd

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


## Touch events are in window pixels; our layout is in canvas units.
func _to_window(p: Vector2) -> Vector2:
	return root.get_final_transform() * p


func _touch(idx: int, p: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = _to_window(p)
	e.pressed = pressed
	Input.parse_input_event(e)


func _drag(idx: int, p: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = _to_window(p)
	Input.parse_input_event(e)


func _button(action: String) -> Rect2:
	for b in main.touch._buttons:
		if b[2] == action:
			return b[0]
	return Rect2()


func _run() -> void:
	await _frames(60)
	var t: Control = main.touch
	# --- menus
	_touch(0, Vector2(320, 240), true) # any touch wakes the controls
	_touch(0, Vector2(320, 240), false)
	await _frames(3)
	_check(t.active and t.visible, "the touch controls appear on the first touch")
	var state0 = main.state
	_touch(1, Vector2(320, 240), true)
	await _frames(2)
	_touch(1, Vector2(320, 240), false)
	await _frames(20)
	print("   state %s -> %s" % [state0, main.state])
	_check(main.state != state0, "tapping the title screen moves on")
	# --- a race
	main._use_track(1)
	main._enter_track_select()
	main._enter_car_select()
	main._enter_countdown()
	main.autopilot = false
	await _frames(300)
	var p = main.race.player
	var gas := _button("accelerate")
	_check(gas.size.x > 0.0, "the race has a GAS pedal")
	_touch(2, gas.get_center(), true)
	await _frames(10)
	await main.get_tree().physics_frame
	print("   throttle with the pedal held: %.2f" % p.throttle)
	_check(p.throttle > 0.9, "holding GAS opens the throttle")
	_touch(2, gas.get_center(), false)
	var brk := _button("brake")
	_touch(3, brk.get_center(), true)
	await _frames(10)
	await main.get_tree().physics_frame
	_check(p.brake > 0.9 and p.throttle < 0.1, "holding BRAKE brakes (and the gas is off)")
	_touch(3, brk.get_center(), false)
	# Drag steering (tilt is off here: no motion sensor in a test).
	var start := Vector2(120, 330)
	_touch(4, start, true)
	_drag(4, start + Vector2(70, 0))
	await _frames(6)
	await main.get_tree().physics_frame
	var right: float = p.steer_in
	_drag(4, start - Vector2(50, 0))
	await _frames(6)
	await main.get_tree().physics_frame
	var left: float = p.steer_in
	_touch(4, start, false)
	await _frames(6)
	await main.get_tree().physics_frame
	var centre: float = p.steer_in
	print("   steering: drag right %.2f, drag left %.2f, let go %.2f" % [right, left, centre])
	_check(right > 0.9, "dragging right steers right (full lock at the end of the travel)")
	_check(left < -0.6 and left > -0.8, "dragging left steers left in proportion")
	_check(abs(centre) < 0.01, "letting go centres the steering")
	# Tilt: full lock at a small angle, finer near the centre, a dead zone at straight.
	var TC = t.get_script()
	var game := root.get_node("Game")
	game.settings["tilt_sens"] = 1
	var s12: float = TC.tilt_steer(12.0)
	var s6: float = TC.tilt_steer(6.0)
	var s05: float = TC.tilt_steer(0.5)
	var sm12: float = TC.tilt_steer(-12.0)
	print("   tilt (NORMAL): 0.5 deg %.2f, 6 deg %.2f, 12 deg %.2f, -12 deg %.2f" % [s05, s6, s12, sm12])
	_check(is_equal_approx(s12, 1.0) and is_equal_approx(sm12, -1.0), "12 degrees of tilt is full lock (NORMAL)")
	_check(s6 > 0.3 and s6 < 0.5, "half the tilt gives less than half the lock (precise round the centre)")
	_check(s05 == 0.0, "a tiny wobble does nothing")
	game.settings["tilt_sens"] = 3
	_check(is_equal_approx(TC.tilt_steer(6.0), 1.0), "VERY QUICK: 6 degrees is full lock")
	game.settings["tilt_sens"] = 1
	# A key press hands control back to the keyboard.
	var k := InputEventKey.new()
	k.keycode = KEY_UP
	k.pressed = true
	Input.parse_input_event(k)
	await _frames(3)
	_check(not t.visible, "using the keyboard hides the touch controls")
	var k2 := InputEventKey.new()
	k2.keycode = KEY_UP
	k2.pressed = false
	Input.parse_input_event(k2)
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
