extends SceneTree
## The touch-native menus, driven by finger events like a phone:
##   - tapping the title opens the garage (tiles over your car);
##   - tapping a tile opens that mode; list menus are cards you tap;
##   - tapping a card's < > changes its value; a long list scrolls when dragged;
##   - BACK (top left) goes back;
##   - the course and car pickers have < > and GO;
##   - the first race on a phone teaches (steering first), once;
##   - AUTO GAS drives the pedals so you only steer.
##   ST_TOUCH=1 godot --headless --fixed-fps 60 -s tests/touch_ui_test.gd

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


func _touch(idx: int, p: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = root.get_final_transform() * p
	e.pressed = pressed
	Input.parse_input_event(e)


func _drag(idx: int, p: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = root.get_final_transform() * p
	Input.parse_input_event(e)


## A tap at `p` in the 640x480 menu frame's units.
func _tap_frame(p: Vector2) -> void:
	var c: Vector2 = main.ui_root.get_global_transform_with_canvas() * p
	_touch(0, c, true)
	await _frames(2)
	_touch(0, c, false)
	await _frames(6)


func _tap_canvas(p: Vector2) -> void:
	_touch(0, p, true)
	await _frames(2)
	_touch(0, p, false)
	await _frames(6)


func _button(action: String) -> Rect2:
	for b in main.touch._buttons:
		if b[2] == action:
			return b[0]
	return Rect2()


func _row_rect(id: String) -> Rect2:
	var m = main.menu
	for i in m.rows.size():
		if m.rows[i].get("id", "") == id:
			return Rect2(m._cards[i].position, m._cards[i].size)
	return Rect2()


func _run() -> void:
	var game: Node = root.get_node("Game")
	game.settings["tutorial_done"] = 0
	game.settings["auto_gas"] = 0
	game.settings["touch_tilt"] = false # drag steering: no motion sensor in a test
	main.touch.tilt = false
	game.settings["weather"] = 0 # (not whatever another test left saved)
	await _frames(30)
	main.showtime.skip_intro()
	await _frames(10)
	_check(main.touch.active, "a touch device starts with the touch controls")
	await _tap_canvas(Vector2(320, 240))
	_check(main.state == main.State.MODE_SELECT, "tapping the title opens the garage")
	_check(main._tiles.size() >= 8, "the garage shows the modes as tiles (%d)" % main._tiles.size())
	var labels := []
	for m in main._modes():
		labels.append(m[2])
	_check(not labels.has("2p") and not labels.has("editor"), "no keyboard-only modes on a phone")
	# Options tile.
	var opt_i: int = labels.find("options")
	var opt_rect: Rect2 = main._tiles[opt_i][0]
	await _tap_frame(opt_rect.get_center())
	_check(main.state == main.State.MENU and main.menu_kind == "options", "tapping OPTIONS opens the options")
	_check(main.menu.touch, "the options are cards")
	# Scroll to the GAS row if it's off screen, then tap its right arrow.
	var m = main.menu
	var gi := -1
	for i in m.rows.size():
		if m.rows[i].get("id", "") == "auto_gas":
			gi = i
	var guard := 0
	while not m._cards[gi].visible and guard < 20:
		# Finger up shows later rows, finger down earlier ones.
		var dir := -1.0 if gi >= m._scroll + m._visible_rows else 1.0
		var start: Vector2 = main.ui_root.get_global_transform_with_canvas() * Vector2(320, 240)
		_touch(1, start, true)
		for k in 6:
			_drag(1, start + Vector2(0, dir * 20.0 * (k + 1)))
			await _frames(1)
		_touch(1, start + Vector2(0, dir * 120.0), false)
		await _frames(4)
		guard += 1
	print("   GAS row %d, scroll %d, rows shown %d of %d, tries %d" % [gi, m._scroll, m._visible_rows, m.rows.size(), guard])
	_check(m._cards[gi].visible, "dragging the list scrolls down to the GAS row")
	var r: Rect2 = _row_rect("auto_gas")
	await _tap_frame(Vector2(r.end.x - 20.0, r.get_center().y))
	_check(int(game.settings.get("auto_gas", 0)) == 1, "tapping > on GAS turns AUTO GAS on")
	await _tap_frame(Vector2(r.position.x + r.size.x * 0.5 + 20.0, r.get_center().y))
	_check(int(game.settings.get("auto_gas", 0)) == 0, "tapping < turns it back")
	# Back.
	var back: Rect2 = _button("back")
	_check(back.size.x > 0.0, "menus have a BACK button")
	await _tap_canvas(back.get_center())
	await _frames(4)
	print("   after BACK: state %s, menu %s" % [main.state, main.menu_kind])
	_check(main.state == main.State.MODE_SELECT, "BACK returns to the garage")
	# Single race: course picker with < > and GO.
	var race_i: int = labels.find("race")
	await _tap_frame((main._tiles[race_i][0] as Rect2).get_center())
	_check(main.state == main.State.TRACK_SELECT, "SINGLE RACE opens the course picker")
	var tr0: int = game.selected_track
	await _tap_canvas(_button("steer_right").get_center())
	_check(game.selected_track != tr0, "> shows the next course")
	_check(_button("start").size.x > 0.0, "the picker has a GO button")
	await _tap_canvas(back.get_center())
	await _frames(4)
	# Quick race: the tutorial, and AUTO GAS.
	main._enter_mode_select()
	await _frames(4)
	game.settings["auto_gas"] = 1
	seed(22) # QUICK RACE picks a random track: make it the same one every run
	var quick_i := 0
	for i in main._modes().size():
		if main._modes()[i][2] == "quick":
			quick_i = i
	await _tap_frame((main._tiles[quick_i][0] as Rect2).get_center())
	print("   quick race at ", game.tracks[game.selected_track].name)
	_check(main.state == main.State.COUNTDOWN, "the QUICK RACE tile goes straight to the grid")
	_check(main.tutorial.active and main.tutorial.visible, "the first race on a phone teaches")
	_check(main.tutorial._text.text.begins_with("STEER"), "it starts with steering")
	while main.state != main.State.RACE:
		await physics_frame
	# Steer a little (drag), no pedals: AUTO GAS should get the car moving.
	var s0 := Vector2(200, 300)
	_touch(2, s0, true)
	for k in 90:
		_drag(2, s0 + Vector2(70.0 * sin(k * 0.15), 0))
		await physics_frame
	_touch(2, s0, false)
	for k in 240:
		await physics_frame
	var p = main.race.player
	print("   speed with AUTO GAS after 5.5 s: %.0f mph; tutorial step %d" % [p.speed() * 2.237, main.tutorial._step])
	_check(p.speed() * 2.237 > 60.0, "AUTO GAS drives the pedals")
	_check(_button("accelerate").size.x == 0.0 and _button("brake").size.x > 0.0, "with AUTO GAS there's only a brake pedal")
	_check(main.tutorial._step >= 1, "steering moves the lesson on")
	main.tutorial.finish()
	_check(int(game.settings.get("tutorial_done", 0)) == 1, "the tutorial is remembered as done")
	game.settings["auto_gas"] = 0
	game.settings["touch_tilt"] = false # drag steering: no motion sensor in a test
	main.touch.tilt = false
	game.settings["weather"] = 0 # (not whatever another test left saved)
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
