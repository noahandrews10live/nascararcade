extends SceneTree
## Everything fits the screen, on any device shape: goes through the menus, a
## race, the pause screen and the pit call, and checks that
##   - every piece of text is inside the safe part of the screen (clear of a
##     notch, rounded corners and the home bar) and menu text inside its frame;
##   - every touch button is inside the safe area and doesn't cover any text.
## Set the device with the window size and:
##   ST_SAFE="l,t,r,b"      notch / home bar insets as fractions of the window
##   ST_CSS_PER_UNIT=0.92   CSS pixels per 640x480 unit (screen density)
##   TOUCH=1                show the touch controls
##   OUT=/dir               also save a screenshot of each screen (needs a renderer)
##   xvfb-run -s "-screen 0 1434x660x24" godot --rendering-driver opengl3 --resolution 1434x660 -s tests/fit_test.gd

var main: Node
var failures := 0
var out := OS.get_environment("OUT")
var touch_on := OS.get_environment("TOUCH") == "1"
var device := OS.get_environment("DEVICE")


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _g() -> Node:
	return root.get_node("Game")


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _press(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	await process_frame
	var r := InputEventAction.new()
	r.action = action
	r.pressed = false
	Input.parse_input_event(r)
	await process_frame


## Where a label's text actually is, in canvas units.
func _text_rect(l: Label) -> Rect2:
	var ls: LabelSettings = l.label_settings
	var font: Font = ls.font if ls and ls.font else l.get_theme_font("font")
	var fs: int = ls.font_size if ls else l.get_theme_font_size("font_size")
	var w := 0.0
	var lines := l.text.split("\n")
	for ln in lines:
		w = max(w, font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	if l.autowrap_mode != TextServer.AUTOWRAP_OFF:
		w = min(w, l.size.x)
	var h: float = l.get_minimum_size().y if l.autowrap_mode == TextServer.AUTOWRAP_OFF else l.size.y
	var x := 0.0
	match l.horizontal_alignment:
		HORIZONTAL_ALIGNMENT_CENTER:
			x = (l.size.x - w) * 0.5
		HORIZONTAL_ALIGNMENT_RIGHT:
			x = l.size.x - w
	var y := 0.0
	match l.vertical_alignment:
		VERTICAL_ALIGNMENT_CENTER:
			y = (l.size.y - h) * 0.5
		VERTICAL_ALIGNMENT_BOTTOM:
			y = l.size.y - h
	# Outlines draw a little outside the glyphs; the italic slant a little more.
	return l.get_global_transform() * Rect2(x, y, w, h)


func _labels(n: Node, acc: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Label and (n as Label).text.strip_edges() != "":
		acc.append(n)
	for c in n.get_children():
		_labels(c, acc)


func _in(r: Rect2, box: Rect2, tol := 3.0) -> bool:
	return box.grow(tol).encloses(r)


func _screen(name: String) -> void:
	await _frames(8)
	var sr: Rect2 = _g().safe_rect(root)
	var texts := []
	_labels(main.ui_root, texts)
	if main.pause_layer.visible:
		_labels(main.pause_layer, texts)
	var menu_texts := texts.duplicate()
	if main.hud.visible:
		_labels(main.hud, texts)
	var bad := []
	for l: Label in texts:
		if not _in(_text_rect(l), sr):
			bad.append("'%s' %s" % [l.text.left(24), str(_text_rect(l))])
	_check(bad.is_empty(), "%s: all text on the safe part of the screen %s" % [name, str(bad)])
	var frame_r: Rect2 = main.ui_root.get_global_transform() * Rect2(Vector2.ZERO, Vector2(640, 480))
	var outside := []
	for l: Label in menu_texts:
		if l.is_ancestor_of(main.ui_root) or not main.ui_root.is_ancestor_of(l):
			continue
		if not _in(_text_rect(l), frame_r, 6.0 * main.ui_root.scale.x):
			outside.append("'%s'" % l.text.left(24))
	_check(outside.is_empty(), "%s: menu text inside its frame %s" % [name, str(outside)])
	if main.touch.active:
		var off := []
		var covers := []
		for b in main.touch._buttons:
			var r: Rect2 = b[0]
			if not _in(r, sr, 1.0):
				off.append(b[1])
			for l: Label in texts:
				if r.grow(-2.0).intersects(_text_rect(l).grow(-2.0)):
					covers.append("%s over '%s'" % [b[1], l.text.left(20)])
		_check(off.is_empty(), "%s: touch buttons on the safe part of the screen %s" % [name, str(off)])
		_check(covers.is_empty(), "%s: touch buttons don't cover any text %s" % [name, str(covers)])
	if out != "":
		await RenderingServer.frame_post_draw
		root.get_node("Game").screen_image(root).save_png(out.path_join("%s_%s.png" % [device, name]))


func _run() -> void:
	await _frames(40)
	if touch_on:
		main.touch.active = true
		main.touch.visible = true
	print("%s: window %s, canvas %s, safe %s, frame scale %.2f, touch scale %.2f" % [device, str(root.size), str(root.get_visible_rect().size), str(_g().safe_rect(root)), main.ui_root.scale.x, _g().touch_scale()])
	var game := root.get_node("Game")
	game.settings.weather = 0
	game.settings.cautions = 1
	await _screen("title")
	main._enter_mode_select()
	await _screen("modes")
	main.mode = "race"
	main.session = "race"
	main._enter_race_setup()
	await _screen("race_setup")
	main._enter_options()
	await _screen("options")
	# The career hub and its confirm screens (with a throwaway career, then the
	# player's own put back).
	var had_career: Dictionary = game.career.duplicate(true)
	var had_season: Dictionary = game.season.duplicate(true)
	game.new_career(2)
	main._enter_career_hub()
	await _screen("career_hub")
	game.career.upgrades.engine = 2
	main._enter_rnd()
	await _screen("career_rnd")
	main._enter_career_confirm("restart")
	await _screen("career_restart")
	main._enter_career_confirm("retire")
	await _screen("career_retire")
	game.career = had_career
	game.season = had_season
	if had_career.is_empty():
		game.clear_career()
	else:
		game.save_career()
	if had_season.is_empty():
		game.clear_season()
	else:
		game.save_season()
	main.mode = "race"
	main._use_track(1)
	main._enter_track_select()
	await _screen("track_select")
	main._enter_car_select()
	await _screen("car_select")
	main._enter_countdown()
	main.autopilot = true
	await _frames(300)
	main.autopilot = false
	main.race.player.autopilot_forced = false
	await _screen("race")
	await _press("pause")
	await _screen("pause")
	await _press("pause")
	await _frames(5)
	var ctl = main.race.control
	if ctl:
		ctl.throw_caution("TEST", null)
		var waited := 0
		while main.pit_menu == null and waited < 60 * 8:
			await physics_frame
			waited += 1
		if main.pit_menu:
			await _screen("pit_call")
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
