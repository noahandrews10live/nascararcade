extends SceneTree
## Accessibility and controllers on a phone:
##   - LARGE TEXT grows the small print (not the big titles);
##   - LEFT-HANDED puts the pedals under the left thumb and steering on the right;
##   - MAP DOTS: HIGH CONTRAST draws the map without team colours;
##   - pushing a controller's stick hides the touch controls;
##   - OPTIONS offers all of them.
##   ST_TOUCH=1 ST_NO_INTRO=1 godot --headless --fixed-fps 60 -s tests/access_test.gd

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


func _touch(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.position = pos
	ev.pressed = pressed
	Input.parse_input_event(ev)
	await process_frame


func _button(label: String) -> Rect2:
	for b in main.touch._buttons:
		if b[1] == label:
			return b[0]
	return Rect2()


func _run() -> void:
	var game: Node = root.get_node("Game")
	await _frames(20)
	game.settings.big_text = 0
	var small: int = game.make_label("x", 12).label_settings.font_size
	game.settings.big_text = 1
	var big: int = game.make_label("x", 12).label_settings.font_size
	var title: int = game.make_label("x", 40).label_settings.font_size
	_check(small == 12 and big > 12 and title == 40, "LARGE TEXT: 12 becomes %d, a 40 title stays %d" % [big, title])
	game.settings.big_text = 0
	# Options rows.
	main._enter_options()
	await _frames(3)
	var ids: Array = main.menu.rows.map(func(r): return String(r.get("id", "")))
	_check(ids.has("big_text") and ids.has("map_contrast") and ids.has("hand") and ids.has("battery"), "OPTIONS has LARGE TEXT, MAP DOTS, CONTROLS and BATTERY SAVER")
	# A race with the touch controls.
	main.mode = "race"
	main.session = "practice"
	main._use_track(1)
	main._enter_countdown()
	await _touch(Vector2(300, 200), true)
	await _touch(Vector2(300, 200), false)
	await _frames(30)
	var w: float = root.get_visible_rect().size.x
	game.settings.auto_gas = 0
	game.settings.hand = 0
	await _frames(3)
	var gas_r: Rect2 = _button("BRAKE")
	_check(gas_r.get_center().x > w * 0.5, "right-handed: the pedals are on the right")
	game.settings.hand = 1
	await _frames(3)
	gas_r = _button("BRAKE")
	_check(gas_r.size.x > 0.0 and gas_r.get_center().x < w * 0.5, "LEFT-HANDED: the pedals are on the left")
	# Steering from the right half.
	var s0 := Vector2(w * 0.75, 200)
	await _touch(s0, true)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = s0 + Vector2(80, 0)
	drag.relative = Vector2(80, 0)
	Input.parse_input_event(drag)
	await _frames(3)
	var has_steer := false
	for f in main.touch._fingers.values():
		if f.get("zone", "") == "steer":
			has_steer = true
	_check(has_steer, "and steering is on the right")
	await _touch(s0 + Vector2(80, 0), false)
	game.settings.hand = 0
	# High-contrast map.
	game.settings.map_contrast = 1
	main.hud.queue_redraw()
	await _frames(5)
	_check(main.hud.high_contrast, "MAP DOTS: HIGH CONTRAST draws the map")
	game.settings.map_contrast = 0
	# A controller's stick.
	_check(main.touch.active, "touch controls are showing")
	var jm := InputEventJoypadMotion.new()
	jm.axis = JOY_AXIS_LEFT_X
	jm.axis_value = 0.9
	Input.parse_input_event(jm)
	await _frames(3)
	_check(not main.touch.active and not main.touch.visible, "pushing a controller's stick hides them")
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
