extends Control
## Track editor: build a layout from straights and turns, see it drawn live, then
## test-drive it or save it as a mod (user://mods/tracks/*.json).
##
## The front stretch (with the start/finish line) and the back stretch are sized
## automatically so the track closes; the pieces must turn a full 360 degrees.
##   UP/DOWN pick a row   LEFT/RIGHT change it   E/Q pick which value on a turn
##   START on an action row

signal test_drive(cfg: Dictionary)
signal closed

const Track := preload("res://scripts/track.gd")
const NAMES := ["SILVER LAKE SPEEDWAY", "IRON HILLS RACEWAY", "COASTAL MOTOR SPEEDWAY", "PINE RIDGE OVAL", "MESA GRANDE RACEWAY", "BLUEWATER SPEEDWAY", "HIGH DESERT MILE", "RIVERBEND ROAD COURSE"]

var pieces: Array = [
	{"r": 200.0, "a": 90.0, "b": 24.0},
	{"r": 200.0, "a": 90.0, "b": 24.0},
	{"r": 200.0, "a": 90.0, "b": 24.0},
	{"r": 200.0, "a": 90.0, "b": 24.0},
]
var name_idx := 0
var width := 18.0
var hp := 950.0
var cursor := 0
var field := 0 # which value of a turn: 0 radius, 1 angle, 2 banking
var status := ""
var _outline := PackedVector2Array()
var _rows: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rebuild()


func cfg() -> Dictionary:
	var segs: Array = [{"s": "auto1"}]
	var half: int = pieces.size() / 2
	for i in pieces.size():
		if i == half:
			segs.append({"s": "auto2"})
		segs.append(pieces[i].duplicate())
	var bank_avg := 0.0
	var rad_min := 1e9
	var turns := 0
	for p in pieces:
		if p.has("r"):
			bank_avg += float(p.b)
			rad_min = min(rad_min, float(p.r))
			turns += 1
	bank_avg /= max(turns, 1)
	var road := false
	for p in pieces:
		if p.has("a") and float(p.a) < 0.0:
			road = true
	return {
		"name": NAMES[name_idx], "short": NAMES[name_idx].split(" ")[0] + " " + NAMES[name_idx].split(" ")[1],
		"kind": "CUSTOM " + ("ROAD COURSE" if road else "OVAL"), "level": "CUSTOM",
		"segments": segs, "radius": rad_min, "width": width, "apron": 8.0 if not road else 3.0,
		"infield": 12.0 if not road else 10.0, "bank_turn": bank_avg, "bank_straight": 3.0,
		"laps": 4, "draft": clamp(bank_avg / 30.0, 0.15, 1.0) if not road else 0.15,
		"hp": hp, "road": road, "race_laps": 20, "full_laps": 200,
	}


func turning() -> float:
	var t := 0.0
	for p in pieces:
		if p.has("a"):
			t += float(p.a)
	return t


func _rebuild() -> void:
	_rows.clear()
	_rows.append({"id": "name", "label": "NAME", "value": NAMES[name_idx]})
	_rows.append({"id": "width", "label": "TRACK WIDTH", "value": "%d M" % int(width)})
	for i in pieces.size():
		var p: Dictionary = pieces[i]
		if p.has("s"):
			_rows.append({"id": "piece", "i": i, "label": "%d  STRAIGHT" % (i + 1), "value": "%d M" % int(p.s)})
		else:
			var parts := ["R %dM" % int(p.r), "%s %d DEG" % ["LEFT" if float(p.a) >= 0.0 else "RIGHT", int(abs(float(p.a)))], "BANK %d" % int(p.b)]
			parts[field] = "<" + parts[field] + ">" if cursor == _rows.size() else parts[field]
			_rows.append({"id": "piece", "i": i, "label": "%d  TURN" % (i + 1), "value": "  ".join(parts)})
	_rows.append({"id": "add_s", "label": "ADD STRAIGHT", "value": ""})
	_rows.append({"id": "add_t", "label": "ADD TURN", "value": ""})
	_rows.append({"id": "del", "label": "REMOVE PIECE", "value": ""})
	_rows.append({"id": "drive", "label": "TEST DRIVE", "value": ""})
	_rows.append({"id": "save", "label": "SAVE AS A MOD", "value": ""})
	_rows.append({"id": "back", "label": "BACK", "value": ""})
	cursor = clamp(cursor, 0, _rows.size() - 1)
	# Live outline (only the geometry; no meshes).
	var t: Node3D = Track.new()
	t.cfg = cfg()
	t.width = width
	_outline = PackedVector2Array()
	if abs(turning() - 360.0) < 0.5:
		_outline = t._segments_outline()
	t.free()
	queue_redraw()


func handle(event: InputEvent) -> bool:
	if not visible:
		return false
	var row: Dictionary = _rows[cursor]
	if event.is_action_pressed("menu_up") or event.is_action_pressed("menu_down"):
		cursor = posmod(cursor + (1 if event.is_action_pressed("menu_down") else -1), _rows.size())
		field = 0
		_rebuild()
		return true
	if event.is_action_pressed("shift_up") or event.is_action_pressed("shift_down"):
		field = posmod(field + (1 if event.is_action_pressed("shift_up") else -1), 3)
		_rebuild()
		return true
	var dir := 0
	if event.is_action_pressed("steer_left"):
		dir = -1
	elif event.is_action_pressed("steer_right"):
		dir = 1
	if dir != 0:
		match row.id:
			"name":
				name_idx = posmod(name_idx + dir, NAMES.size())
			"width":
				width = clamp(width + dir, 12.0, 26.0)
			"piece":
				var p: Dictionary = pieces[row.i]
				if p.has("s"):
					p.s = clamp(float(p.s) + dir * 50.0, 50.0, 1500.0)
				else:
					match field:
						0:
							p.r = clamp(float(p.r) + dir * 10.0, 30.0, 600.0)
						1:
							p.a = clamp(float(p.a) + dir * 10.0, -180.0, 180.0)
							if abs(float(p.a)) < 5.0:
								p.a = 10.0 * dir
						2:
							p.b = clamp(float(p.b) + dir, 0.0, 36.0)
		_rebuild()
		return true
	if event.is_action_pressed("start"):
		match row.id:
			"add_s":
				pieces.insert(min(cursor - 2, pieces.size()) if cursor >= 2 else pieces.size(), {"s": 200.0})
			"add_t":
				pieces.append({"r": 150.0, "a": 90.0, "b": 12.0})
			"del":
				if pieces.size() > 2:
					pieces.pop_back()
			"drive":
				if _valid():
					test_drive.emit(cfg())
			"save":
				if _valid():
					var path: String = Game.save_track_mod(cfg())
					Game.add_track(cfg())
					status = "SAVED: " + path
			"back":
				closed.emit()
		_rebuild()
		return true
	if event.is_action_pressed("back"):
		closed.emit()
		return true
	return false


func _valid() -> bool:
	if abs(turning() - 360.0) > 0.5:
		status = "THE TURNS MUST ADD UP TO 360 DEGREES (NOW %d)" % int(turning())
		return false
	if _outline.size() < 10:
		status = "THIS LAYOUT DOESN'T CLOSE - TRY LONGER OR WIDER TURNS"
		return false
	status = ""
	return true


func _draw() -> void:
	var f := Game.arcade_font
	draw_rect(Rect2(0, 0, 640, 480), Color(0.02, 0.03, 0.08, 0.85))
	draw_string(f, Vector2(20, 34), "TRACK EDITOR", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 0.85, 0.1))
	var y := 60.0
	for i in _rows.size():
		var r: Dictionary = _rows[i]
		var sel := i == cursor
		var col := Color(1, 0.85, 0.1) if sel else Color.WHITE
		draw_string(f, Vector2(20, y), ("> " if sel else "  ") + String(r.label), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
		draw_string(f, Vector2(150, y), String(r.value), HORIZONTAL_ALIGNMENT_LEFT, 250, 12, Color(0.5, 0.9, 1.0))
		y += 20.0
	var tcol := Color(0.3, 1.0, 0.4) if abs(turning() - 360.0) < 0.5 else Color(1.0, 0.5, 0.3)
	draw_string(f, Vector2(420, 60), "TURNING %d / 360" % int(turning()), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, tcol)
	# Map of the layout.
	var box := Rect2(420, 76, 200, 200)
	draw_rect(box, Color(0, 0, 0, 0.5))
	if _outline.size() > 2:
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for p in _outline:
			mn = mn.min(p)
			mx = mx.max(p)
		var sc: float = 180.0 / max(mx.x - mn.x, mx.y - mn.y, 1.0)
		var pts := PackedVector2Array()
		for k in range(0, _outline.size(), 4):
			pts.append(box.position + Vector2(10, 10) + (_outline[k] - mn) * sc)
		pts.append(pts[0])
		draw_polyline(pts, Color(0.9, 0.9, 0.95), 3.0)
		draw_circle(pts[0], 4.0, Color(1, 0.2, 0.2))
	else:
		draw_string(f, box.position + Vector2(20, 100), "NOT CLOSED YET", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.5, 0.3))
	draw_string(f, Vector2(420, 296), "E/Q: RADIUS / ANGLE / BANK", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.75, 0.8))
	if status != "":
		draw_string(f, Vector2(20, 470), status, HORIZONTAL_ALIGNMENT_LEFT, 600, 10, Color(1, 0.8, 0.4))
