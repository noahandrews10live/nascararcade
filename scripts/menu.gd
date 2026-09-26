extends Control
## A vertical list menu in the arcade style: up/down picks a row, left/right changes
## a row's value, START activates it. Rows are dictionaries:
##   {"label": "LAPS", "values": ["10", "20"], "index": 0, "id": "laps", "hint": "..."}
## Rows without "values" are actions. Emits `activated(id)` and `changed(id, index)`.

signal activated(id: String)
signal changed(id: String, index: int)
signal cancelled

var rows: Array = []
var cursor := 0
var title := ""
var top := 96
var row_h := 30
var width := 480
var left_override := -1
var _labels: Array = []
var _values: Array = []
var _hint: Label
var _title: Label
var _blink := 0.0


func build(t: String, r: Array, start_cursor := 0) -> void:
	title = t
	rows = r
	cursor = clamp(start_cursor, 0, rows.size() - 1)
	for ch in get_children():
		ch.queue_free()
	_labels.clear()
	_values.clear()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title = Game.make_label(title, 34, Color(1.0, 0.85, 0.1), 8)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.size = Vector2(640, 40)
	_title.position = Vector2(0, 22)
	add_child(_title)
	var panel := ColorRect.new()
	panel.color = Color(0, 0, 0, 0.62)
	var left := (640 - width) / 2 if left_override < 0 else left_override
	panel.position = Vector2(left - 16, top - 12)
	panel.size = Vector2(width + 32, rows.size() * row_h + 24)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	for i in rows.size():
		var l := Game.make_label("", 18, Color.WHITE, 5)
		l.position = Vector2(left, top + i * row_h)
		add_child(l)
		_labels.append(l)
		var v := Game.make_label("", 18, Color(0.5, 0.9, 1.0), 5)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.size = Vector2(width * 0.55, 24)
		v.position = Vector2(left + width * 0.45, top + i * row_h)
		add_child(v)
		_values.append(v)
	_hint = Game.make_label("", 12, Color(0.8, 0.85, 0.9), 3)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.size = Vector2(640, 20)
	_hint.position = Vector2(0, top + rows.size() * row_h + 22)
	if left_override >= 0:
		_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_hint.position.x = left_override
	add_child(_hint)
	var keys := Game.make_label("UP/DOWN  SELECT     LEFT/RIGHT  CHANGE     START  OK     BACKSPACE  BACK", 11, Color(0.7, 0.7, 0.75), 3)
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keys.size = Vector2(640, 20)
	keys.position = Vector2(0, 452)
	add_child(keys)
	_refresh()


func value(id: String) -> int:
	for r in rows:
		if r.get("id", "") == id:
			return r.get("index", 0)
	return 0


func value_text(id: String) -> String:
	for r in rows:
		if r.get("id", "") == id and r.has("values"):
			return r.values[r.get("index", 0)]
	return ""


func set_value(id: String, idx: int) -> void:
	for r in rows:
		if r.get("id", "") == id:
			r.index = idx
	_refresh()


func _refresh() -> void:
	for i in rows.size():
		var r: Dictionary = rows[i]
		var sel := i == cursor
		_labels[i].text = ("> " if sel else "  ") + String(r.label)
		_labels[i].label_settings.font_color = Color(1.0, 0.85, 0.1) if sel else (Color(0.55, 0.55, 0.6) if r.get("disabled", false) else Color.WHITE)
		if r.has("values"):
			var t: String = r.values[r.get("index", 0)]
			_values[i].text = ("<  %s  >" % t) if sel else t
		else:
			_values[i].text = ""
	if rows.size() > 0:
		_hint.text = rows[cursor].get("hint", "")


func handle(event: InputEvent) -> bool:
	if not visible or rows.is_empty():
		return false
	if event.is_action_pressed("menu_up"):
		cursor = posmod(cursor - 1, rows.size())
		_refresh()
		return true
	if event.is_action_pressed("menu_down"):
		cursor = posmod(cursor + 1, rows.size())
		_refresh()
		return true
	var r: Dictionary = rows[cursor]
	if r.has("values") and (event.is_action_pressed("steer_left") or event.is_action_pressed("steer_right")):
		var dir := -1 if event.is_action_pressed("steer_left") else 1
		r.index = posmod(r.get("index", 0) + dir, r.values.size())
		_refresh()
		changed.emit(r.get("id", ""), r.index)
		return true
	if event.is_action_pressed("start") and not r.get("disabled", false):
		activated.emit(r.get("id", ""))
		return true
	if event.is_action_pressed("back"):
		cancelled.emit()
		return true
	return false


func _process(delta: float) -> void:
	_blink += delta
