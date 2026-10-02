extends SceneTree
## Touch controls, with real touch events:
##   - in the menus a tap on the screen moves on (title -> the garage);
##   - in a race holding anywhere on the right half is the gas (no button), and
##     the BRAKE beside the speedometer brakes;
##   - CAMERA, SAVE CLIP and PIT THIS LAP are on the pause screen;
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
	# --- a race (with the pedals: AUTO GAS off)
	root.get_node("Game").settings["auto_gas"] = 0
	main._use_track(1)
	main._enter_track_select()
	main._enter_car_select()
	main._enter_countdown()
	main.autopilot = false
	await _frames(300)
	var p = main.race.player
	var vw: Vector2 = t.get_viewport_rect().size
	_check(_button("accelerate").size.x == 0.0, "there's no GAS button")
	for a in ["camera", "clip", "pit"]:
		_check(_button(a).size.x == 0.0, "no %s button on the race screen (it's on the pause screen)" % a)
	# Gas: hold anywhere on the right half (somewhere no button is).
	var gas_at := Vector2(vw.x * 0.62, vw.y * 0.45)
	_touch(2, gas_at, true)
	await _frames(10)
	await main.get_tree().physics_frame
	print("   throttle holding the right half: %.2f" % p.throttle)
	_check(p.throttle > 0.9, "holding anywhere on the right half opens the throttle")
	_touch(2, gas_at, false)
	await _frames(4)
	await main.get_tree().physics_frame
	_check(p.throttle < 0.1, "letting go lifts")
	var brk := _button("brake")
	var sp: Rect2 = main.hud.speedo_rect()
	var sr: Rect2 = root.get_node("Game").safe_rect(t.get_viewport())
	print("   brake %s, speedometer %s" % [brk, Rect2(sp.position + sr.position, sp.size)])
	_check(brk.size.x > 0.0 and brk.end.x <= sr.position.x + sp.position.x + 1.0 and brk.get_center().x > vw.x * 0.5, "the BRAKE is just left of the speedometer")
	_check(brk.position.y < sr.position.y + sp.end.y and brk.end.y > sr.position.y + sp.position.y, "level with it")
	_touch(3, brk.get_center(), true)
	await _frames(10)
	await main.get_tree().physics_frame
	_check(p.brake > 0.9 and p.throttle < 0.1, "holding BRAKE brakes (and the gas is off)")
	_touch(3, brk.get_center(), false)
	# The pause screen has the camera, a clip and the pit call.
	var pause := _button("pause")
	_touch(5, pause.get_center(), true)
	_touch(5, pause.get_center(), false)
	await _frames(4)
	_check(main.paused, "II pauses")
	var cam0: int = main.cam_mode
	var camb := _button("camera")
	var clipb := _button("_clip")
	var pitb := _button("_pit")
	_check(camb.size.x > 0.0 and clipb.size.x > 0.0 and pitb.size.x > 0.0, "the pause screen has CAMERA, SAVE CLIP and PIT THIS LAP")
	_touch(6, camb.get_center(), true)
	_touch(6, camb.get_center(), false)
	await _frames(4)
	_check(main.cam_mode != cam0, "CAMERA changes the camera")
	var pit0: bool = p.want_pit
	_touch(7, pitb.get_center(), true)
	_touch(7, pitb.get_center(), false)
	await _frames(4)
	_check(p.want_pit != pit0, "PIT THIS LAP calls the stop")
	_touch(7, pitb.get_center(), true)
	_touch(7, pitb.get_center(), false)
	await _frames(4)
	_check(p.want_pit == pit0, "and again cancels it")
	main.cam_mode = cam0
	_touch(5, _button("pause").get_center(), true)
	_touch(5, _button("pause").get_center(), false)
	var wait := 0
	while main.paused and wait < 300:
		await _frames(1)
		wait += 1
	_check(not main.paused, "RESUME (after the count back in)")
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
