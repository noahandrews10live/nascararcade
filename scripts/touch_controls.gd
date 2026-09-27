extends Control
## Touch controls for phones and tablets (and touchscreen laptops). Appears on
## the first touch, hides again when a keyboard or gamepad is used.
##
## Racing:
##   - steering by tilting the device like a wheel (when the browser gives us the
##     motion sensor), or by dragging a thumb left/right anywhere on the left side;
##   - round GAS (green) and BRAKE (red) pedals on the right, pressure-free (press = full);
##   - small buttons for pause, camera, pit and switching tilt/drag steering.
## Menus, results and replays: a D-pad and A (select) / B (back) buttons.
##
## Everything is sent as ordinary input actions (InputEventAction), so the game
## can't tell a thumb from a key or a gamepad button.

const DRAG_RANGE := 70.0 # thumb travel (in 640x480 units) for full lock
## Degrees of wheel-like rotation for full lock, per TILT STEERING setting
## (GENTLE / NORMAL / QUICK / VERY QUICK). Small, so nobody has to twist an arm.
const TILT_RANGES := [18.0, 12.0, 9.0, 6.0]
const TILT_DEAD := 0.8 # degrees of dead zone round straight ahead
const TILT_CURVE := 1.35 # >1: finer control round the centre, still full lock at the range
const TILT_SMOOTH := 0.045 # seconds: takes the jitter out of the sensor

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
var _tilt_smooth := 0.0 # filtered steering from the tilt
var _was_paused := false
var _js_window = null
var _last_racing := false
var _font: Font
var _race_time := 0.0 # seconds since the race controls came up
var _k := 1.0 # size of the controls (1 = phone-sized; smaller on bigger screens)
var _portrait := false # the page says the phone is upright: the race waits (paused)


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
	var portrait = _js_window.stPortrait
	_portrait = portrait == true
	var ok = _js_window.stTiltOk
	var was_ok := _tilt_ok
	_tilt_ok = ok == true
	if _tilt_ok:
		var a = _js_window.stTiltAngle
		_tilt_value = float(a) if a != null else 0.0
		if not was_ok:
			_tilt_center = _tilt_value # first reading: however it's held is straight


## Radius of the round GAS and BRAKE pedals.
const PEDAL_R := 38.0


func _layout() -> void:
	# Everything stays inside the safe part of the screen (clear of a notch,
	# rounded corners and the home bar), and is sized for thumbs: k shrinks it on
	# screens with more room than a phone.
	var sr := Game.safe_rect(get_viewport())
	var k := Game.touch_scale()
	_k = k
	var L := sr.position.x
	var T := sr.position.y
	var R := sr.end.x
	var B := sr.end.y
	_buttons.clear()
	var reserve: Array = []
	if _racing():
		# Round pedals under the right thumb: green GAS, red BRAKE just to its left.
		var pr := PEDAL_R * k
		var gas_c := Vector2(R - 20.0 * k - pr, T + sr.size.y * 0.54)
		var brake_c := gas_c + Vector2(-pr * 2.0 - 22.0 * k, pr * 0.5)
		_buttons.append([Rect2(gas_c - Vector2.ONE * pr, Vector2.ONE * pr * 2.0), "GAS", "accelerate", "gas"])
		_buttons.append([Rect2(brake_c - Vector2.ONE * pr, Vector2.ONE * pr * 2.0), "BRAKE", "brake", "brake"])
		# Small buttons under the position readout (top right).
		var bw := 48.0 * k
		var bh := 34.0 * k
		var gap := 6.0 * k
		var x := R - 10.0 - bw
		var y := T + 96.0
		_buttons.append([Rect2(x, y, bw, bh), "II", "pause", "tap"])
		_buttons.append([Rect2(x, y + bh + gap, bw, bh), "CAM", "camera", "tap"])
		if main.race.control:
			_buttons.append([Rect2(x, y + (bh + gap) * 2.0, bw, bh), "PIT", "pit", "tap"])
		_buttons.append([Rect2(x - bw - gap - 2.0 * k, y, bw + 2.0 * k, bh), "TILT" if tilt else "DRAG", "_toggle_tilt", "tap"])
		if tilt and _tilt_ok:
			_buttons.append([Rect2(x - bw - gap - 2.0 * k, y + bh + gap, bw + 2.0 * k, bh), "CTR", "_recenter", "tap"])
	elif main and main.paused and main.pit_menu == null:
		# The pause screen: just RESUME and QUIT, under "PAUSED".
		var c := sr.get_center()
		var w := 120.0 * k
		var h := 46.0 * k
		_buttons.append([Rect2(c.x - w - 10.0 * k, c.y + 16.0, w, h), "RESUME", "pause", "tap"])
		_buttons.append([Rect2(c.x + 10.0 * k, c.y + 16.0, w, h), "QUIT", "quit_race", "tap"])
	else:
		# D-pad bottom left, A/B bottom right.
		var d := 48.0 * k
		var c := Vector2(L + 8.0 * k + d * 1.5, B - 8.0 * k - d * 1.5)
		_buttons.append([Rect2(c + Vector2(-0.5, -1.5) * d, Vector2(d, d)), "^", "menu_up", "tap"])
		_buttons.append([Rect2(c + Vector2(-0.5, 0.5) * d, Vector2(d, d)), "v", "menu_down", "tap"])
		_buttons.append([Rect2(c + Vector2(-1.5, -0.5) * d, Vector2(d, d)), "<", "steer_left", "tap"])
		_buttons.append([Rect2(c + Vector2(0.5, -0.5) * d, Vector2(d, d)), ">", "steer_right", "tap"])
		reserve.append(Rect2(c - Vector2.ONE * d * 1.5, Vector2.ONE * d * 3.0).grow(6.0))
		var a := Rect2(R - 16.0 * k - 72.0 * k, B - 36.0 * k - 72.0 * k, 72.0 * k, 72.0 * k)
		var bb := Rect2(a.position.x - 8.0 * k - 60.0 * k, B - 16.0 * k - 60.0 * k, 60.0 * k, 60.0 * k)
		_buttons.append([a, "A", "start", "tap"])
		_buttons.append([bb, "B", "back", "tap"])
		reserve.append(a.merge(bb).grow(6.0))
	Game.touch_reserve = reserve if visible else []


## Steering (-1..1) for the phone turned `a` degrees from straight: a small dead
## zone, a gentle curve for precision round the centre, full lock at the range the
## TILT STEERING option sets.
static func tilt_steer(a: float) -> float:
	a = wrapf(a, -180.0, 180.0)
	var range_deg: float = TILT_RANGES[clamp(int(Game.settings.get("tilt_sens", 1)), 0, TILT_RANGES.size() - 1)]
	var x: float = clamp((abs(a) - TILT_DEAD) / (range_deg - TILT_DEAD), 0.0, 1.0)
	return sign(a) * pow(x, TILT_CURVE)


## Whatever angle the phone is at now becomes straight ahead.
func _recenter() -> void:
	_tilt_center = _tilt_value
	_tilt_smooth = 0.0
	main._sub("STEERING CENTRED", 1.2)


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
		Game.touch_reserve = []
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
	Game.touch_active = active
	if main and main.pause_keys:
		main.pause_keys.visible = not active # the pause screen gets buttons instead
	if not active:
		return
	var racing := _racing()
	_race_time += delta
	# Coming back from a pause or the pit call: however the phone's held now is straight.
	var paused_now: bool = main != null and main.paused
	if _was_paused and not paused_now:
		_tilt_center = _tilt_value
		_tilt_smooth = 0.0
	_was_paused = paused_now
	if racing != _last_racing:
		_release_all()
		_last_racing = racing
		_race_time = 0.0
		if racing:
			_tilt_center = _tilt_value # hold it how you like: that's straight ahead
	_read_tilt()
	# Phones race in landscape only: turning the phone upright pauses the race
	# (the page covers the screen with a "turn your phone" card meanwhile).
	if _portrait and racing:
		_release_all()
		_tap("pause")
		return
	_layout()
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
					drag = clamp((f.pos.x - f.start.x) / (DRAG_RANGE * _k), -1.0, 1.0)
		if tilt and _tilt_ok and not dragging:
			var target: float = tilt_steer(_tilt_value - _tilt_center)
			_tilt_smooth += (target - _tilt_smooth) * (1.0 - exp(-delta / TILT_SMOOTH))
			_steer = _tilt_smooth
		else:
			_tilt_smooth = drag
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
		if b[3] == "gas" or b[3] == "brake":
			var hue := Color(0.15, 0.85, 0.3) if b[3] == "gas" else Color(0.95, 0.15, 0.12)
			var c := r.get_center()
			var rad := r.size.x * 0.5 * (0.94 if pressed else 1.0)
			draw_circle(c, rad, Color(hue, 0.75 if pressed else 0.45))
			draw_arc(c, rad, 0, TAU, 48, Color(hue.lightened(0.5), 0.9), 3.0, true)
			var pfs := maxi(10, roundi(14.0 * _k))
			draw_string(_font, Vector2(r.position.x, c.y + pfs * 0.35), String(b[1]), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, pfs, Color(1, 1, 1, 0.9))
			continue
		var col := Color(1, 1, 1, 0.28 if pressed else 0.14)
		draw_rect(r, col)
		draw_rect(r, Color(1, 1, 1, 0.45), false, 2.0)
		var fs := maxi(10, roundi((18.0 if r.size.y > 40.0 * _k else 12.0) * _k))
		draw_string(_font, Vector2(r.position.x, r.get_center().y + fs * 0.35), String(b[1]), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, Color(1, 1, 1, 0.85))
	if _racing():
		# The thumb's steering knob, and the steering amount along the bottom.
		for f in _fingers.values():
			if f.zone == "steer":
				draw_circle(f.start, 34.0 * _k, Color(1, 1, 1, 0.08))
				draw_arc(f.start, 34.0 * _k, 0, TAU, 32, Color(1, 1, 1, 0.35), 2.0)
				draw_circle(Vector2(f.start.x + _steer * DRAG_RANGE * _k, f.start.y), 18.0 * _k, Color(1, 1, 1, 0.4))
		var sr := Game.safe_rect(get_viewport())
		var cx := sr.get_center().x
		var y := sr.end.y - 8.0
		draw_line(Vector2(cx - 60, y), Vector2(cx + 60, y), Color(1, 1, 1, 0.2), 4.0)
		draw_line(Vector2(cx, y), Vector2(cx + _steer * 60.0, y), Color(1, 0.85, 0.2, 0.8), 4.0)
		if tilt and not _tilt_ok and _race_time < 6.0:
			draw_string(_font, Vector2(sr.position.x, sr.position.y + 84.0), "NO TILT SENSOR HERE: DRAG ON THE LEFT TO STEER", HORIZONTAL_ALIGNMENT_CENTER, sr.size.x, 12, Color(1, 1, 1, 0.75))
