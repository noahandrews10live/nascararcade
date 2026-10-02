extends Control
## Your first race on a phone: a few short prompts at the moments they matter,
## then never again. Steering (tilt or drag), the gas, braking into the first
## turn, the draft, and the course map. Each prompt shows until you've done the
## thing or a few seconds have passed, whichever is later.

var main: Node
var active := false
var _step := -1
var _t := 0.0
var _done_t := 0.0
var _box: Panel
var _text: Label
var _steered := 0.0

const STEPS := ["steer", "gas", "brake", "draft", "map"]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box = Panel.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.1, 0.82)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = Color(1.0, 0.85, 0.1)
	_box.add_theme_stylebox_override("panel", sb)
	add_child(_box)
	_text = Game.make_label("", 18, Color.WHITE, 5)
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_text)
	visible = false


## Should this race teach? The first race on a touch screen, in a normal mode.
static func wanted(mode: String) -> bool:
	return int(Game.settings.get("tutorial_done", 0)) == 0 and (Game.touch_active or Game.touch_device()) \
		and not mode in ["online", "challenge", "2p"]


func begin() -> void:
	active = true
	_step = -1
	_t = 0.0
	_steered = 0.0
	_next()


func finish() -> void:
	if active:
		Game.settings["tutorial_done"] = 1
		Game.save_settings()
	active = false
	visible = false


func _next() -> void:
	_step += 1
	_t = 0.0
	_done_t = 0.0
	if _step >= STEPS.size():
		finish()
		return
	var auto := int(Game.settings.get("auto_gas", 0)) == 1
	if STEPS[_step] == "gas" and auto:
		_next() # the car does the gas
		return
	_text.text = _prompt(STEPS[_step], auto)
	visible = true


func _prompt(step: String, auto: bool) -> String:
	var tilt: bool = bool(Game.settings.get("touch_tilt", true))
	match step:
		"steer":
			return "STEER: TILT YOUR PHONE LIKE A WHEEL" if tilt else "STEER: DRAG YOUR THUMB LEFT AND RIGHT ON THE %s SIDE" % ("RIGHT" if int(Game.settings.get("hand", 0)) == 1 else "LEFT")
		"gas":
			return "GAS: HOLD YOUR THUMB ANYWHERE ON THE %s HALF OF THE SCREEN" % ("LEFT" if int(Game.settings.get("hand", 0)) == 1 else "RIGHT")
		"brake":
			return "TURN COMING: TAP THE RED BRAKE BY THE SPEEDOMETER" if not auto else "AUTO GAS SLOWS FOR THE TURNS. TAP THE RED BRAKE TO BRAKE HARDER"
		"draft":
			return "TUCK IN BEHIND A CAR TO DRAFT: YOU GO FASTER IN ITS WAKE"
		"map":
			return "THE MAP UNDER YOUR POSITION SHOWS EVERY CAR. YOU'RE THE FLASHING ONE. GOOD LUCK!"
	return ""


func update(delta: float) -> void:
	if not active or main.race == null or main.race.player == null:
		return
	var p: Node3D = main.race.player
	var racing: bool = main.state == main.State.RACE
	_t += delta
	var done := false
	match STEPS[_step]:
		"steer":
			_steered += abs(p.steer_in) * delta
			done = _steered > 0.35 and racing
		"gas":
			done = p.throttle > 0.5 and _t > 2.0
		"brake":
			done = p.brake > 0.3 or _t > 9.0
		"draft":
			done = p.draft > 0.3 or _t > 9.0
		"map":
			done = _t > 6.0
	if done:
		_done_t += delta
		if _done_t > 1.2:
			_next()
	_layout()


func _layout() -> void:
	var sr: Rect2 = Game.safe_rect(get_viewport())
	var w: float = min(520.0, sr.size.x - 40.0)
	var h := 64.0
	var pos := Vector2(sr.get_center().x - w * 0.5, sr.position.y + sr.size.y * 0.2)
	_box.position = pos
	_box.size = Vector2(w, h)
	_text.position = pos + Vector2(12, 0)
	_text.size = Vector2(w - 24, h)
	# Gently pulse so it's noticed without shouting.
	_box.modulate.a = 0.85 + 0.15 * sin(Time.get_ticks_msec() / 250.0)
