extends Control
## A vertical list menu in the arcade style: up/down picks a row, left/right changes
## a row's value, START activates it. Rows are dictionaries:
##   {"label": "LAPS", "values": ["10", "20"], "index": 0, "id": "laps", "hint": "..."}
## Rows without "values" are actions. Emits `activated(id)` and `changed(id, index)`.
##
## On a touch screen it draws as big cards instead: tap a card to choose it, tap
## its < > arrows to change a value, drag to scroll a long list; BACK is the touch
## controls' button at the top left.

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
var _keys: Label
var _blink := 0.0
var touch := false # drawn as cards for fingers
var _cards: Array = [] # Panel per row (touch)
var _arrows: Array = [] # [left Label, right Label] per row (touch)
var _scroll := 0 # first row shown (touch)
var _visible_rows := 0
var _list_rect := Rect2()
const TOUCH_ROW := 48.0
const TOUCH_GAP := 6.0


func build(t: String, r: Array, start_cursor := 0) -> void:
	title = t
	rows = r
	cursor = clamp(start_cursor, 0, rows.size() - 1)
	for ch in get_children():
		ch.queue_free()
	_labels.clear()
	_values.clear()
	_cards.clear()
	_arrows.clear()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	touch = Game.touch_active or Game.touch_device()
	if touch:
		_build_touch()
		return
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
	_keys = keys
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


## Cards: the list fills the frame under the title (from `top` for menus that
## share the screen with other things, such as the pit call), scrolling if it
## doesn't fit.
func _build_touch() -> void:
	_title = Game.make_label(title, 28, Color(1.0, 0.85, 0.1), 8)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.size = Vector2(640, 36)
	_title.position = Vector2(0, 12)
	add_child(_title)
	var left: float = (640 - width) / 2 if left_override < 0 else left_override
	var w: float = max(width, 360.0) if left_override < 0 else float(width)
	if left_override < 0:
		left = (640.0 - w) * 0.5
	var y0: float = max(58.0, top - 36.0) if top < 200 else float(top)
	var bottom := 424.0
	_visible_rows = max(1, int((bottom - y0 + TOUCH_GAP) / (TOUCH_ROW + TOUCH_GAP)))
	_list_rect = Rect2(left, y0, w, _visible_rows * (TOUCH_ROW + TOUCH_GAP) - TOUCH_GAP)
	for i in rows.size():
		var card := Panel.new()
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.size = Vector2(w, TOUCH_ROW)
		add_child(card)
		_cards.append(card)
		var l := Game.make_label("", 17, Color.WHITE, 5)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.size = Vector2(w * 0.5, TOUCH_ROW)
		add_child(l)
		_labels.append(l)
		var v := Game.make_label("", 16, Color(0.5, 0.9, 1.0), 5)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		v.size = Vector2(w * 0.5 - 88.0, TOUCH_ROW)
		v.clip_text = true
		add_child(v)
		_values.append(v)
		var la := Game.make_label("<", 24, Color(1.0, 0.85, 0.1), 5)
		var ra := Game.make_label(">", 24, Color(1.0, 0.85, 0.1), 5)
		for a in [la, ra]:
			a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			a.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			a.size = Vector2(44, TOUCH_ROW)
			add_child(a)
		_arrows.append([la, ra])
	_hint = Game.make_label("", 12, Color(0.8, 0.85, 0.9), 3)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.size = Vector2(600, 30)
	_hint.position = Vector2(20, _list_rect.end.y + 8.0)
	add_child(_hint)
	_keep_cursor_visible()
	_refresh()


func _keep_cursor_visible() -> void:
	if cursor < _scroll:
		_scroll = cursor
	elif cursor >= _scroll + _visible_rows:
		_scroll = cursor - _visible_rows + 1
	_scroll = clamp(_scroll, 0, max(0, rows.size() - _visible_rows))


func _layout_touch() -> void:
	var w := _list_rect.size.x
	for i in rows.size():
		var slot := i - _scroll
		var shown := slot >= 0 and slot < _visible_rows
		var y := _list_rect.position.y + slot * (TOUCH_ROW + TOUCH_GAP)
		var x := _list_rect.position.x
		_cards[i].visible = shown
		_labels[i].visible = shown
		_values[i].visible = shown and rows[i].has("values")
		_arrows[i][0].visible = shown and rows[i].has("values")
		_arrows[i][1].visible = shown and rows[i].has("values")
		_cards[i].position = Vector2(x, y)
		_labels[i].position = Vector2(x + 14.0, y)
		_values[i].position = Vector2(x + w * 0.5 + 44.0, y)
		_arrows[i][0].position = Vector2(x + w * 0.5, y)
		_arrows[i][1].position = Vector2(x + w - 44.0, y)
		if not rows[i].has("values"):
			_labels[i].size.x = w - 28.0
			_labels[i].horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		else:
			_labels[i].size.x = w * 0.5 - 14.0
			_labels[i].horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT


## A finger on the menu at `p` (this menu's own units). Returns true if it hit
## something.
func tap(p: Vector2) -> bool:
	if not visible or rows.is_empty() or not touch:
		return false
	for i in rows.size():
		if not _cards[i].visible:
			continue
		var rect := Rect2(_cards[i].position, _cards[i].size).grow(2.0)
		if not rect.has_point(p):
			continue
		var r: Dictionary = rows[i]
		if r.get("disabled", false):
			return true
		cursor = i
		if r.has("values"):
			var dir := 1
			if p.x < rect.position.x + rect.size.x * 0.5 + 50.0:
				dir = -1 if p.x >= rect.position.x + rect.size.x * 0.5 - 4.0 else 1
			r.index = posmod(r.get("index", 0) + dir, r.values.size())
			_refresh()
			changed.emit(r.get("id", ""), r.index)
		else:
			_refresh()
			activated.emit(r.get("id", ""))
		return true
	return false


## Drag the list by `dy` (menu units; up is negative): a row at a time.
func drag(dy: float) -> void:
	if not touch:
		return
	var rows_moved := int(round(-dy / (TOUCH_ROW + TOUCH_GAP)))
	if rows_moved == 0:
		return
	_scroll = clamp(_scroll + rows_moved, 0, max(0, rows.size() - _visible_rows))
	_refresh()


func _refresh_touch() -> void:
	_layout_touch()
	for i in rows.size():
		var r: Dictionary = rows[i]
		var sel := i == cursor
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.05, 0.07, 0.12, 0.85) if not r.get("disabled", false) else Color(0.03, 0.03, 0.05, 0.6)
		if sel:
			sb.bg_color = Color(0.12, 0.14, 0.22, 0.92)
		sb.set_corner_radius_all(8)
		sb.set_border_width_all(2 if sel else 1)
		sb.border_color = Color(1.0, 0.85, 0.1) if sel else Color(1, 1, 1, 0.16)
		_cards[i].add_theme_stylebox_override("panel", sb)
		_labels[i].text = String(r.label)
		_labels[i].label_settings.font_color = Color(1.0, 0.85, 0.1) if sel else (Color(0.55, 0.55, 0.6) if r.get("disabled", false) else Color.WHITE)
		if r.has("values"):
			_values[i].text = String(r.values[r.get("index", 0)])
	if rows.size() > 0:
		var more := ""
		if _scroll > 0 or _scroll + _visible_rows < rows.size():
			more = "  (DRAG FOR MORE)" if rows[cursor].get("hint", "") == "" else ""
		_hint.text = String(rows[cursor].get("hint", "")) + more


func _refresh() -> void:
	if touch:
		_refresh_touch()
		return
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
		if touch:
			_keep_cursor_visible()
		_refresh()
		return true
	if event.is_action_pressed("menu_down"):
		cursor = posmod(cursor + 1, rows.size())
		if touch:
			_keep_cursor_visible()
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
	if _keys:
		_keys.visible = not Game.touch_active # the keyboard keys mean nothing on a phone
