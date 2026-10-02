extends Control
## REPORT A PROBLEM (from the pause screen, the options or the debrief): what
## kind of problem (one tap), a note if you like, then SEND. It goes with a
## small screenshot of the moment, the race so far and your settings, so the
## problem can be seen and replayed - and nothing personal. Kept on the device
## until it's sent, so it isn't lost offline.

signal closed

const TAGS := ["HANDLING", "CONTROLS", "GRAPHICS", "CRASH", "RULES", "MENUS", "SOUND", "OTHER"]
const TAG_NAMES := ["CAR HANDLING", "CONTROLS", "LOOKS WRONG", "CRASH / FREEZE", "RACE RULES", "MENUS", "SOUND", "SOMETHING ELSE"]
const GOLD := Color(1.0, 0.85, 0.2)
const DIM := Color(0.65, 0.72, 0.82)

var image: Image # the moment, taken before this screen opened
var state := {}
var cloud: Node
var tags: Array = []
var note: LineEdit
var _status: Label
var _send: Button
var _chips := {}
var sent := false
var saved_path := ""


func setup(img: Image, st: Dictionary, cl: Node) -> void:
	image = img
	state = st
	cloud = cl
	_build()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.position = Vector2(-2000, -2000)
	dim.size = Vector2(5000, 5000)
	add_child(dim)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.1, 0.97)
	bg.position = Vector2(30, 20)
	bg.size = Vector2(580, 440)
	add_child(bg)
	_lab("REPORT A PROBLEM", 22, GOLD, Vector2(48, 30))
	_lab("WHAT WENT WRONG?  TAP ONE OR MORE", 12, DIM, Vector2(48, 66))
	# The kinds of problem, two rows of four.
	for i in TAGS.size():
		var r := Rect2(48 + (i % 4) * 136, 86 + (i / 4) * 46, 128, 38)
		var b := _button(TAG_NAMES[i], r, _toggle.bind(TAGS[i]))
		_chips[TAGS[i]] = b
	_lab("ANYTHING ELSE? (OPTIONAL)", 12, DIM, Vector2(48, 186))
	note = LineEdit.new()
	note.position = Vector2(48, 204)
	note.size = Vector2(544, 36)
	note.max_length = 500
	note.placeholder_text = "e.g. the car spun on its own in turn 3"
	note.add_theme_font_override("font", Game.arcade_font)
	note.add_theme_font_size_override("font_size", 14)
	add_child(note)
	# The screenshot that goes with it.
	if image:
		var thumb := TextureRect.new()
		thumb.texture = ImageTexture.create_from_image(image)
		thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		thumb.position = Vector2(48, 252)
		thumb.size = Vector2(200, 120)
		add_child(thumb)
	var what := "SENDS: THIS SCREENSHOT, %s, YOUR SETTINGS AND THE KIND OF DEVICE. NOTHING PERSONAL." % ("THE RACE SO FAR" if state.has("race") else "WHERE YOU ARE IN THE GAME")
	_lab(what, 11, DIM, Vector2(262, 256), 330)
	_status = _lab("", 13, Color.WHITE, Vector2(262, 330), 330)
	_send = _button("SEND", Rect2(330, 396, 130, 46), _do_send, Color(0.15, 0.4, 0.2))
	_button("CANCEL", Rect2(470, 396, 122, 46), func(): close())


func _lab(text: String, sz: int, col: Color, pos: Vector2, w := 0.0) -> Label:
	var l := Game.make_label(text, sz, col, 4)
	if w > 0.0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size = Vector2(w, 0)
	l.position = pos
	add_child(l)
	return l


func _button(text: String, r: Rect2, cb: Callable, col := Color(0.18, 0.22, 0.3)) -> Button:
	var b := Button.new()
	b.text = text
	b.position = r.position
	b.size = r.size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", Game.arcade_font)
	b.add_theme_font_size_override("font_size", 12)
	for st in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col.lightened(0.2) if st != "normal" else col
		sb.border_color = Color(1, 1, 1, 0.45)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(6)
		b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(cb)
	add_child(b)
	return b


func _toggle(tag: String) -> void:
	if sent:
		return
	if tags.has(tag):
		tags.erase(tag)
	else:
		tags.append(tag)
	var b: Button = _chips[tag]
	var on := tags.has(tag)
	var sb: StyleBoxFlat = b.get_theme_stylebox("normal").duplicate()
	sb.bg_color = Color(0.45, 0.35, 0.05) if on else Color(0.18, 0.22, 0.3)
	sb.border_color = GOLD if on else Color(1, 1, 1, 0.45)
	b.add_theme_stylebox_override("normal", sb)


## The report as it goes to the server.
func payload() -> Dictionary:
	var img64 := ""
	if image:
		img64 = Marshalls.raw_to_base64(image.save_jpg_to_buffer(0.6))
	return {"note": note.text.strip_edges() if note else "", "tags": tags.duplicate(), "state": state, "image": img64, "version": Game.VERSION}


func _do_send() -> void:
	if sent:
		return
	sent = true
	_send.disabled = true
	_status.text = "SENDING..."
	saved_path = cloud.send_report(payload(), func(ok: bool, ref: String):
		if not is_instance_valid(self):
			return
		if ok:
			_status.text = "SENT - THANK YOU!%s" % ("  (REPORT #%s)" % ref if ref != "" else "")
			_status.label_settings.font_color = Color(0.4, 1.0, 0.45)
		else:
			_status.text = "NO CONNECTION: SAVED ON THIS PHONE. IT GOES NEXT TIME YOU'RE ONLINE."
			_status.label_settings.font_color = GOLD
		get_tree().create_timer(2.0).timeout.connect(func():
			if is_instance_valid(self):
				close()))


func close() -> void:
	closed.emit()
	queue_free()
