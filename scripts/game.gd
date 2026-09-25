extends Node
## Global game data: tracks, teams, input bindings, records and the arcade font.

const TITLE := "SPEEDWAY THUNDER"
const SUBTITLE := "STOCK CAR ARCADE  '99"
const MPS_TO_MPH := 2.23694
const FIELD_SIZE := 12
const RECORDS_PATH := "user://records.cfg"

## Oval layout: two straights of `straight` metres joined by 180 degree turns of
## `radius`. `bump` pushes the frontstretch outward (tri-oval / quad-oval doglegs).
var tracks: Array[Dictionary] = [
	{
		"name": "THUNDER BEACH INT'L SPEEDWAY",
		"short": "THUNDER BEACH",
		"kind": "SUPERSPEEDWAY",
		"level": "BEGINNER",
		"shape": "trioval",
		"straight": 900.0, "radius": 260.0, "bump": 110.0,
		"width": 20.0, "apron": 9.0, "infield": 14.0,
		"bank_turn": 31.0, "bank_straight": 4.0,
		"laps": 3, "draft": 1.0, "grid_player": 9,
		"sky_top": Color(0.18, 0.38, 0.78), "sky_horizon": Color(0.72, 0.84, 0.95),
		"grass": Color(0.24, 0.55, 0.18), "fog": Color(0.70, 0.80, 0.92),
		"lake": true,
	},
	{
		"name": "LONE STAR MOTOR SPEEDWAY",
		"short": "LONE STAR",
		"kind": "QUAD-OVAL SPEEDWAY",
		"level": "ADVANCED",
		"shape": "quadoval",
		"straight": 560.0, "radius": 190.0, "bump": 45.0,
		"width": 18.0, "apron": 8.0, "infield": 12.0,
		"bank_turn": 24.0, "bank_straight": 5.0,
		"laps": 4, "draft": 0.7, "grid_player": 9,
		"sky_top": Color(0.35, 0.45, 0.80), "sky_horizon": Color(0.98, 0.78, 0.55),
		"grass": Color(0.42, 0.52, 0.20), "fog": Color(0.93, 0.78, 0.62),
		"lake": false,
	},
	{
		"name": "THUNDER VALLEY SHORT TRACK",
		"short": "THUNDER VALLEY",
		"kind": "SHORT TRACK",
		"level": "EXPERT",
		"shape": "oval",
		"straight": 190.0, "radius": 78.0, "bump": 0.0,
		"width": 15.0, "apron": 6.0, "infield": 8.0,
		"bank_turn": 36.0, "bank_straight": 12.0,
		"laps": 8, "draft": 0.35, "grid_player": 9,
		"sky_top": Color(0.05, 0.05, 0.20), "sky_horizon": Color(0.25, 0.20, 0.40),
		"grass": Color(0.16, 0.36, 0.14), "fog": Color(0.12, 0.10, 0.22),
		"lake": false, "night": true,
	},
]

## Fictional teams. speed/accel/handling are multipliers around 1.0.
var teams: Array[Dictionary] = [
	{"num": "7", "driver": "BUCK RYDER", "sponsor": "THUNDER COLA", "c1": Color(0.85, 0.08, 0.10), "c2": Color(1, 1, 1), "cn": Color(1, 1, 1), "speed": 1.00, "accel": 1.00, "handling": 1.00},
	{"num": "22", "driver": "TRAVIS HAWK", "sponsor": "BIG RIG TIRES", "c1": Color(0.10, 0.25, 0.85), "c2": Color(1.0, 0.85, 0.1), "cn": Color(1.0, 0.85, 0.1), "speed": 1.02, "accel": 0.96, "handling": 0.99},
	{"num": "51", "driver": "RICKY VANCE", "sponsor": "SIZZLE BURGERS", "c1": Color(1.0, 0.80, 0.05), "c2": Color(0.9, 0.2, 0.1), "cn": Color(0.1, 0.1, 0.1), "speed": 0.98, "accel": 1.06, "handling": 1.01},
	{"num": "14", "driver": "WADE COLTER", "sponsor": "GATOR JUICE", "c1": Color(0.10, 0.60, 0.20), "c2": Color(0.1, 0.1, 0.1), "cn": Color(1, 1, 1), "speed": 0.99, "accel": 0.98, "handling": 1.04},
	{"num": "88", "driver": "SONNY PRUITT", "sponsor": "MOTORHEAD OIL", "c1": Color(0.08, 0.08, 0.10), "c2": Color(0.95, 0.45, 0.05), "cn": Color(0.95, 0.45, 0.05), "speed": 1.03, "accel": 0.97, "handling": 0.97},
	{"num": "31", "driver": "EARL TANNER", "sponsor": "CRUNCHY O'S", "c1": Color(0.95, 0.45, 0.70), "c2": Color(0.3, 0.1, 0.5), "cn": Color(1, 1, 1), "speed": 0.98, "accel": 1.02, "handling": 1.03},
	{"num": "5", "driver": "JEB MONROE", "sponsor": "HOG WILD BBQ", "c1": Color(0.55, 0.05, 0.10), "c2": Color(0.9, 0.8, 0.6), "cn": Color(0.9, 0.8, 0.6), "speed": 1.0, "accel": 1.0, "handling": 1.0},
	{"num": "43", "driver": "MACK DALTON", "sponsor": "SKY BLUE FREIGHT", "c1": Color(0.35, 0.70, 0.95), "c2": Color(0.1, 0.2, 0.6), "cn": Color(1, 1, 1), "speed": 1.0, "accel": 1.0, "handling": 1.0},
	{"num": "66", "driver": "DWAYNE STROUD", "sponsor": "ROCKET PARTS", "c1": Color(0.95, 0.95, 0.95), "c2": Color(0.8, 0.1, 0.1), "cn": Color(0.1, 0.1, 0.8), "speed": 1.0, "accel": 1.0, "handling": 1.0},
	{"num": "12", "driver": "KYLE BARROW", "sponsor": "PRAIRIE FEED", "c1": Color(0.60, 0.40, 0.15), "c2": Color(1, 1, 0.8), "cn": Color(1, 1, 0.8), "speed": 1.0, "accel": 1.0, "handling": 1.0},
	{"num": "9", "driver": "BOBBY LEE CRANE", "sponsor": "NITRO GUM", "c1": Color(0.45, 0.10, 0.70), "c2": Color(0.2, 0.9, 0.3), "cn": Color(0.2, 0.9, 0.3), "speed": 1.0, "accel": 1.0, "handling": 1.0},
	{"num": "28", "driver": "RUSTY HOLLIS", "sponsor": "SILVER BULLET TOOLS", "c1": Color(0.70, 0.72, 0.75), "c2": Color(0.1, 0.1, 0.1), "cn": Color(0.85, 0.1, 0.1), "speed": 1.0, "accel": 1.0, "handling": 1.0},
]
## The first N teams can be picked by the player.
const SELECTABLE_TEAMS := 6

var selected_track := 0
var selected_team := 0
var scanlines := true

var arcade_font: FontVariation
var records := ConfigFile.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	arcade_font = FontVariation.new()
	arcade_font.base_font = ThemeDB.fallback_font
	arcade_font.variation_embolden = 0.9
	# Slant the glyphs for that italic arcade cabinet look.
	arcade_font.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.22, 1), Vector2.ZERO)
	records.load(RECORDS_PATH)


func _setup_input() -> void:
	# ints are keyboard keys, "btn:N" joypad buttons, "axis:N+/-" joypad axes.
	var binds := {
		"accelerate": [KEY_UP, KEY_W, KEY_Z, "btn:%d" % JOY_BUTTON_A, "axis:%d+" % JOY_AXIS_TRIGGER_RIGHT],
		"brake": [KEY_DOWN, KEY_S, KEY_X, "btn:%d" % JOY_BUTTON_B, "axis:%d+" % JOY_AXIS_TRIGGER_LEFT],
		"steer_left": [KEY_LEFT, KEY_A, "btn:%d" % JOY_BUTTON_DPAD_LEFT, "axis:%d-" % JOY_AXIS_LEFT_X],
		"steer_right": [KEY_RIGHT, KEY_D, "btn:%d" % JOY_BUTTON_DPAD_RIGHT, "axis:%d+" % JOY_AXIS_LEFT_X],
		"menu_up": [KEY_UP, KEY_W, "btn:%d" % JOY_BUTTON_DPAD_UP],
		"menu_down": [KEY_DOWN, KEY_S, "btn:%d" % JOY_BUTTON_DPAD_DOWN],
		"start": [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, "btn:%d" % JOY_BUTTON_START, "btn:%d" % JOY_BUTTON_A],
		"back": [KEY_BACKSPACE, "btn:%d" % JOY_BUTTON_B],
		"camera": [KEY_C, "btn:%d" % JOY_BUTTON_Y],
		"pause": [KEY_ESCAPE, KEY_P, "btn:%d" % JOY_BUTTON_BACK],
		"quit_race": [KEY_Q],
		"toggle_scanlines": [KEY_F2],
		"toggle_fullscreen": [KEY_F11],
	}
	for action in binds:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.25)
		for b in binds[action]:
			var ev: InputEvent
			if b is String and b.begins_with("axis:"):
				var jm := InputEventJoypadMotion.new()
				jm.axis = int(b.substr(5, b.length() - 6)) as JoyAxis
				jm.axis_value = -1.0 if b.ends_with("-") else 1.0
				ev = jm
			elif b is String:
				var jb := InputEventJoypadButton.new()
				jb.button_index = int(b.substr(4)) as JoyButton
				ev = jb
			else:
				var k := InputEventKey.new()
				k.physical_keycode = b as Key
				ev = k
			InputMap.action_add_event(action, ev)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		var w := get_window()
		w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN


func track() -> Dictionary:
	return tracks[selected_track]


func get_record(track_idx: int, key: String) -> float:
	return records.get_value("track_%d" % track_idx, key, 0.0)


## Stores `value` if it beats the existing record (lower is better). Returns true on a new record.
func submit_record(track_idx: int, key: String, value: float) -> bool:
	var old := get_record(track_idx, key)
	if old > 0.0 and old <= value:
		return false
	records.set_value("track_%d" % track_idx, key, value)
	records.save(RECORDS_PATH)
	return true


static func format_time(t: float) -> String:
	if t <= 0.0:
		return "--'--\"--"
	var m := int(t / 60.0)
	var s := int(t) % 60
	var cs := int(fmod(t, 1.0) * 100.0)
	return "%d'%02d\"%02d" % [m, s, cs]


static func ordinal(n: int) -> String:
	if n % 100 in [11, 12, 13]:
		return "%dTH" % n
	match n % 10:
		1: return "%dST" % n
		2: return "%dND" % n
		3: return "%dRD" % n
	return "%dTH" % n


func make_label(text: String, size: int, color := Color.WHITE, outline := 6) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font = arcade_font
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = outline
	ls.outline_color = Color(0, 0, 0)
	ls.shadow_size = 0
	ls.shadow_color = Color(0, 0, 0, 0.6)
	ls.shadow_offset = Vector2(3, 3)
	l.label_settings = ls
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
