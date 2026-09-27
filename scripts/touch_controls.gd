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
	active = Game.touch_device()
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
		# Pedals stay big enough for a thumb on tablets, and sit lower when the
		# screen is upright (hands hold a tablet near the bottom).
		var pr: float = PEDAL_R * max(k, 0.8)
		var upright := sr.size.y > sr.size.x
		var gas_c := Vector2(R - 20.0 * k - pr, T + sr.size.y * (0.7 if upright else 0.58))
		var brake_c := gas_c + Vector2(-pr * 2.0 - 22.0 * k, pr * 0.5)
		if _one_thumb():
			# AUTO GAS: no gas pedal; the brake sits where the gas was.
			_buttons.append([Rect2(gas_c - Vector2.ONE * pr, Vector2.ONE * pr * 2.0), "BRAKE", "brake", "brake"])
		else:
			_buttons.append([Rect2(gas_c - Vector2.ONE * pr, Vector2.ONE * pr * 2.0), "GAS", "accelerate", "gas"])
			_buttons.append([Rect2(brake_c - Vector2.ONE * pr, Vector2.ONE * pr * 2.0), "BRAKE", "brake", "brake"])
		# Small buttons beside the course map (which sits under the position
		# readout, top right).
		var bw := 48.0 * k
		var bh := 34.0 * k
		var gap := 6.0 * k
		var mr: Rect2 = main.hud.map_rect() if main.hud else Rect2(sr.size.x - 134.0, 92.0, 120.0, 120.0)
		var x: float = L + mr.position.x - 12.0 - bw
		var y: float = T + mr.position.y - 5.0
		_buttons.append([Rect2(x, y, bw, bh), "II", "pause", "tap"])
		_buttons.append([Rect2(x, y + bh + gap, bw, bh), "CAM", "camera", "tap"])
		_buttons.append([Rect2(x, y + (bh + gap) * 2.0, bw, bh), "CLIP", "clip", "tap"])
		if main.race.control:
			_buttons.append([Rect2(x, y + (bh + gap) * 3.0, bw, bh), "PIT", "pit", "tap"])
	elif main and main.paused and main.pit_menu == null:
		# The pause screen: just RESUME and QUIT, under "PAUSED".
		var c := sr.get_center()
		var w := 120.0 * k
		var h := 46.0 * k
		_buttons.append([Rect2(c.x - w - 10.0 * k, c.y + 16.0, w, h), "RESUME", "pause", "tap"])
		_buttons.append([Rect2(c.x + 10.0 * k, c.y + 16.0, w, h), "QUIT", "quit_race", "tap"])
		# Steering: tilt or drag, and re-centre the tilt.
		var y2 := c.y + 16.0 + h + 12.0 * k
		_buttons.append([Rect2(c.x - w - 10.0 * k, y2, w, h * 0.8), "TILT STEER" if tilt else "DRAG STEER", "_toggle_tilt", "tap"])
		if tilt and _tilt_ok:
			_buttons.append([Rect2(c.x + 10.0 * k, y2, w, h * 0.8), "CENTRE", "_recenter", "tap"])
	elif main:
		# Menus are touched directly (cards, tiles); a BACK button top left, and
		# on the course and car pickers < > to browse and GO to choose.
		var bw := 84.0 * k
		var bh := 38.0 * k
		if main.state != main.State.TITLE and not (main.state == main.State.MODE_SELECT):
			var back := Rect2(L + 8.0, T + 8.0, bw, bh)
			_buttons.append([back, "< BACK", "back", "tap"])
			reserve.append(back.grow(4.0))
		if main.state in [main.State.TRACK_SELECT, main.State.CAR_SELECT]:
			var aw := 52.0 * k
			var ah := 88.0 * k
			var mid: float = T + sr.size.y * 0.42
			var la := Rect2(L + 8.0, mid - ah * 0.5, aw, ah)
			var ra := Rect2(R - 8.0 - aw, mid - ah * 0.5, aw, ah)
			var go := Rect2(R - 12.0 - 120.0 * k, B - 12.0 - 56.0 * k, 120.0 * k, 56.0 * k)
			_buttons.append([la, "<", "steer_left", "tap"])
			_buttons.append([ra, ">", "steer_right", "tap"])
			_buttons.append([go, "GO", "start", "tap"])
			reserve.append(la.grow(4.0))
			reserve.append(ra.grow(4.0))
			reserve.append(go.grow(4.0))
	Game.touch_reserve = reserve if visible else []


## AUTO GAS is on: one thumb (or none, with tilt) drives. Drag steering then
## works anywhere on the screen, not just the left half.
func _one_thumb() -> bool:
	return int(Game.settings.get("auto_gas", 0)) == 1


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
			if _racing():
				if p.x < get_viewport_rect().size.x * 0.5 or _one_thumb():
					_fingers[idx] = {"zone": "steer", "start": p, "pos": p}
			else:
				# Menus: a tap, a swipe or a drag (scrolling a list); decided on release.
				_fingers[idx] = {"zone": "ui", "start": p, "pos": p, "last": p, "t": Time.get_ticks_msec()}
		else:
			var f: Dictionary = _fingers.get(idx, {})
			_fingers.erase(idx)
			if f.get("zone", "") == "ui" and main:
				var mv: Vector2 = p - f.start
				var quick: bool = Time.get_ticks_msec() - int(f.t) < 450
				if mv.length() < 14.0 * max(_k, 0.6):
					if not main.ui_tap(p):
						main.ui_continue()
				elif quick and abs(mv.x) > abs(mv.y) * 1.3 and abs(mv.x) > 40.0:
					# Swipe: the content follows the finger, so a swipe left shows the next one.
					_tap("steer_right" if mv.x < 0.0 else "steer_left")
	elif _fingers.has(idx):
		var f2: Dictionary = _fingers[idx]
		if f2.zone == "ui" and main:
			main.ui_drag(p.y - f2.last.y, p)
			f2.last = p
		f2.pos = p


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
