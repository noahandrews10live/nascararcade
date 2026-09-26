extends Control
## Touch controls for phones and tablets (and touchscreen laptops). Appears on
## the first touch, hides again when a keyboard or gamepad is used.
##
## Racing:
##   - steering by tilting the device like a wheel (when the browser gives us the
##     motion sensor), or by dragging a thumb left/right anywhere on the left side;
##   - big GAS and BRAKE pedals on the right, pressure-free (press = full);
##   - small buttons for pause, camera, pit and switching tilt/drag steering.
## Menus, results and replays: a D-pad and A (select) / B (back) buttons.
##
## Everything is sent as ordinary input actions (InputEventAction), so the game
## can't tell a thumb from a key or a gamepad button.

const DRAG_RANGE := 70.0 # thumb travel (in 640x480 units) for full lock
const TILT_RANGE := 28.0 # degrees of wheel-like rotation for full lock

var main: Node
var active := false # shown once the screen has been touched
var tilt := false # steer by tilting (if the device has a motion sensor)
var _fingers := {} # index -> {"zone": String, "start": Vector2, "pos": Vector2}
var _held := {} # action -> strength currently pressed
var _buttons: Array = [] # [Rect2, label, action or callable, zone]
var _steer := 0.0
var _tilt_value := 0.0
var _tilt_ok := false
var _tilt_center := 0.0
var _js_window = null
var _last_racing := false
var _font: Font
var _race_time := 0.0 # seconds since the race controls came up


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = Game.arcade_font
	tilt = bool(Game.settings.get("touch_tilt", true))
	if OS.has_feature("web"):
		_js_window = JavaScriptBridge.get_interface("window")
	# Phones and tablets start with the controls showing.
	active = OS.has_feature("web_android") or OS.has_feature("web_ios") or OS.has_feature("mobile")
	visible = active


func _racing() -> bool:
	if main == null or main.race == null or main.paused or main.photo_mode or main.autopilot:
		return false
	return main.state in [main.State.COUNTDOWN, main.State.RACE, main.State.FINISHED] and main.split_cams.is_empty()


## Tilt from the page (see the web page's motion handler): -1..1 and whether the
## sensor is actually delivering.
func _read_tilt() -> void:
	if _js_window == null:
		_tilt_ok = false
		return
	var ok = _js_window.stTiltOk
	_tilt_ok = ok == true
	if _tilt_ok:
		var a = _js_window.stTiltAngle
		_tilt_value = float(a) if a != null else 0.0


func _layout() -> void:
	var sz := get_viewport_rect().size
	var W := sz.x
	var H := sz.y
	_buttons.clear()
	if _racing():
		var pedal_top := H * 0.36
		var pedal_h := H * 0.36
		_buttons.append([Rect2(W - 118, pedal_top, 108, pedal_h), "GAS", "accelerate", "gas"])
		_buttons.append([Rect2(W - 232, pedal_top + pedal_h * 0.3, 104, pedal_h * 0.7), "BRAKE", "brake", "brake"])
		var x := W - 58.0
		_buttons.append([Rect2(x, 96, 48, 34), "II", "pause", "tap"])
		_buttons.append([Rect2(x, 136, 48, 34), "CAM", "camera", "tap"])
		if main.race.control:
			_buttons.append([Rect2(x, 176, 48, 34), "PIT", "pit", "tap"])
		_buttons.append([Rect2(x - 56, 96, 50, 34), "TILT" if tilt else "DRAG", "_toggle_tilt", "tap"])
	else:
		# D-pad bottom left, A/B bottom right.
		var c := Vector2(78, H - 82)
		_buttons.append([Rect2(c + Vector2(-24, -72), Vector2(48, 48)), "^", "menu_up", "tap"])
		_buttons.append([Rect2(c + Vector2(-24, 24), Vector2(48, 48)), "v", "menu_down", "tap"])
		_buttons.append([Rect2(c + Vector2(-72, -24), Vector2(48, 48)), "<", "steer_left", "tap"])
		_buttons.append([Rect2(c + Vector2(24, -24), Vector2(48, 48)), ">", "steer_right", "tap"])
		_buttons.append([Rect2(W - 96, H - 124, 72, 72), "A", "start", "tap"])
		_buttons.append([Rect2(W - 176, H - 84, 60, 60), "B", "back", "tap"])
		if main and main.paused:
			_buttons.append([Rect2(W - 116, H - 180, 92, 44), "RESUME", "pause", "tap"])
			_buttons.append([Rect2(W - 176, H - 150, 60, 44), "QUIT", "quit_race", "tap"])


func _toggle_tilt() -> void:
	tilt = not tilt
	Game.settings["touch_tilt"] = tilt
	Game.save_settings()
	_tilt_center = _tilt_value
	main._sub("STEERING: " + ("TILT THE DEVICE" if tilt else "DRAG ON THE LEFT"), 2.0)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		if not active:
			active = true
			visible = true
		_touch(event)
		get_viewport().set_input_as_handled()
	elif active and (event is InputEventKey or event is InputEventJoypadButton) and event.is_pressed() and not event.is_echo():
		# Someone picked up a keyboard or controller.
		active = false
		visible = false
		_release_all()


func _touch(event: InputEvent) -> void:
	var p: Vector2 = event.position
	var idx: int = event.index
	if event is InputEventScreenTouch:
		if event.pressed:
			for b in _buttons:
				if (b[0] as Rect2).grow(6).has_point(p):
					_fingers[idx] = {"zone": b[3], "action": b[2], "start": p, "pos": p}
					if b[3] == "tap":
						_tap(b[2])
					return
			if _racing() and p.x < get_viewport_rect().size.x * 0.5:
				_fingers[idx] = {"zone": "steer", "start": p, "pos": p}
		else:
			_fingers.erase(idx)
	elif _fingers.has(idx):
		_fingers[idx].pos = p


func _tap(action) -> void:
	if action is String and action.begins_with("_"):
		call(action)
		return
	_send(action, 1.0)
	_release.call_deferred(action)


func _release(action: String) -> void:
	await get_tree().process_frame
	_send(action, 0.0)


func _send(action: String, strength: float) -> void:
	var was: float = _held.get(action, 0.0)
	if is_equal_approx(was, strength):
		return
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = strength > 0.0
	ev.strength = strength
	Input.parse_input_event(ev)
	if strength > 0.0:
		_held[action] = strength
	else:
		_held.erase(action)


func _release_all() -> void:
	for a in _held.keys():
		_send(a, 0.0)
	_fingers.clear()


func _process(delta: float) -> void:
	if not active:
		return
	var racing := _racing()
	_race_time += delta
	if racing != _last_racing:
		_release_all()
		_last_racing = racing
		_race_time = 0.0
		if racing:
			_tilt_center = _tilt_value # hold it how you like: that's straight ahead
	_layout()
	_read_tilt()
	if racing:
		var gas := 0.0
		var brake := 0.0
		var drag := 0.0
		var dragging := false
		for f in _fingers.values():
			match f.zone:
				"gas":
					gas = 1.0
				"brake":
					brake = 1.0
				"steer":
					dragging = true
					drag = clamp((f.pos.x - f.start.x) / DRAG_RANGE, -1.0, 1.0)
		if tilt and _tilt_ok and not dragging:
			var a: float = _tilt_value - _tilt_center
			a = sign(a) * max(abs(a) - 2.0, 0.0) # a small dead zone
			_steer = clamp(a / TILT_RANGE, -1.0, 1.0)
		else:
			_steer = drag
		_send("accelerate", gas)
		_send("brake", brake)
		_send("steer_right", max(_steer, 0.0))
		_send("steer_left", max(-_steer, 0.0))
	queue_redraw()


func _draw() -> void:
	if not active:
		return
	for b in _buttons:
		var r: Rect2 = b[0]
		var pressed := false
		for f in _fingers.values():
			if f.get("action", "") == b[2]:
				pressed = true
		var col := Color(1, 1, 1, 0.28 if pressed else 0.14)
		if b[3] == "gas":
			col = Color(0.3, 1.0, 0.4, 0.42 if pressed else 0.2)
		elif b[3] == "brake":
			col = Color(1.0, 0.3, 0.25, 0.42 if pressed else 0.2)
		draw_rect(r, col)
		draw_rect(r, Color(1, 1, 1, 0.45), false, 2.0)
		var fs := 18 if r.size.y > 40 else 12
		draw_string(_font, Vector2(r.position.x, r.get_center().y + fs * 0.35), String(b[1]), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, Color(1, 1, 1, 0.85))
	if _racing():
		# The thumb's steering knob, and the steering amount along the bottom.
		for f in _fingers.values():
			if f.zone == "steer":
				draw_circle(f.start, 34.0, Color(1, 1, 1, 0.08))
				draw_arc(f.start, 34.0, 0, TAU, 32, Color(1, 1, 1, 0.35), 2.0)
				draw_circle(Vector2(f.start.x + _steer * DRAG_RANGE, f.start.y), 18.0, Color(1, 1, 1, 0.4))
		var W := get_viewport_rect().size.x
		var y := get_viewport_rect().size.y - 8.0
		draw_line(Vector2(W * 0.5 - 60, y), Vector2(W * 0.5 + 60, y), Color(1, 1, 1, 0.2), 4.0)
		draw_line(Vector2(W * 0.5, y), Vector2(W * 0.5 + _steer * 60.0, y), Color(1, 0.85, 0.2, 0.8), 4.0)
		if tilt and not _tilt_ok and _race_time < 6.0:
			draw_string(_font, Vector2(0, get_viewport_rect().size.y * 0.3), "NO TILT SENSOR HERE: DRAG ON THE LEFT TO STEER", HORIZONTAL_ALIGNMENT_CENTER, W, 12, Color(1, 1, 1, 0.75))
