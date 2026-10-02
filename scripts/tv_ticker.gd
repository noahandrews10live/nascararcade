extends Control
## The TV broadcast package on your screen, like a live race telecast:
##   - the ticker across the top: a box with the flag, the lap and the stage, then
##     the running order scrolling by, every car with its position, number (in
##     its colours), name and the gap to the leader (or laps down, PIT, OUT).
##     When cars change places their cells slide past each other, with a green
##     arrow for the one moving up and a red one for the one going back; your
##     car is highlighted;
##   - a stage results board (the top 10) when a stage ends;
##   - "LEAD LAP: n CARS" and the stage countdown in the lap box.
## It sits in the HUD's coordinates (the HUD makes room at the top).

const H := 22.0 # bar height
const CELL := 112.0 # one car's cell
const BOX := 150.0 # the flag / lap box on the left
const SCROLL := 34.0 # pixels per second
const SLIDE := 3.0 # cells per second, when places change
const ARROW_TIME := 4.0

var main: Node
var hud: Control
var race: Node3D
var _slot := {} # car -> where its cell is drawn now (slot, eases to its position)
var _change := {} # car -> [time left, +1 up / -1 down]
var _last_pos := {} # car -> position last frame
var _gap_text := {} # car -> "+1.23" (refreshed twice a second)
var _gap_t := 0.0
var _scroll := 0.0
var _stage_board: Array = [] # [stage, [names]] while shown
var _stage_t := 0.0
var _stage_seen := 0


var _strip: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip = Control.new()
	_strip.clip_contents = true
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_strip)
	_strip.draw.connect(_draw_cells)


## The cells, in the strip's own coordinates (0 = the box's right edge).
func _draw_cells() -> void:
	if race == null or not is_instance_valid(race) or race.order.is_empty():
		return
	var f: Font = Game.arcade_font
	var room: float = _strip.size.x
	var total: float = race.order.size() * CELL
	var scrolling: bool = total > room
	for c in race.order:
		var slot: float = float(_slot.get(c, 0.0))
		var x: float = slot * CELL
		if scrolling:
			x = fposmod(slot * CELL - _scroll, total)
			if x > room - 1.0:
				x -= total # coming round again on the left
		if x > room or x + CELL < 0.0:
			continue
		_cell(c, x, 2.0, f)


func reset() -> void:
	_slot.clear()
	_change.clear()
	_last_pos.clear()
	_gap_text.clear()
	_scroll = 0.0
	_stage_board = []
	_stage_t = 0.0
	_stage_seen = 0


func active() -> bool:
	return main != null and race != null and is_instance_valid(race) and int(Game.settings.get("tv_graphics", 1)) == 1 \
		and main.state in [main.State.COUNTDOWN, main.State.RACE, main.State.FINISHED] and main.split_cams.is_empty() \
		and not race.order.is_empty() and hud.visible


func _process(delta: float) -> void:
	if main == null:
		return
	if main.race != race:
		race = main.race
		reset()
	var on := active()
	visible = on
	hud.ticker_on = on
	var want_top: float = H + 4.0 if on else 0.0
	if hud.top != want_top:
		hud.top = want_top
		hud._layout()
	if not on:
		return
	size = Vector2(hud.W, hud.H)
	# Where each car is, and who has just moved.
	var order: Array = race.order
	for i in order.size():
		var c: Node3D = order[i]
		var pos := i + 1
		if _last_pos.has(c) and int(_last_pos[c]) != pos and main.state == main.State.RACE:
			_change[c] = [ARROW_TIME, 1 if pos < int(_last_pos[c]) else -1]
		_last_pos[c] = pos
		var cur: float = float(_slot.get(c, float(i)))
		_slot[c] = move_toward(cur, float(i), SLIDE * delta)
	for c in _change.keys():
		_change[c][0] -= delta
		if _change[c][0] <= 0.0:
			_change.erase(c)
	_gap_t -= delta
	if _gap_t <= 0.0:
		_gap_t = 0.5
		_refresh_gaps()
	# Scroll when the field doesn't fit.
	var room: float = hud.W - BOX - 6.0
	var total: float = order.size() * CELL
	if total > room:
		_scroll = fposmod(_scroll + SCROLL * delta, total)
	else:
		_scroll = 0.0
	# Stage results.
	var ctl: Node = race.control
	if ctl and ctl.stage_results.size() > _stage_seen:
		_stage_seen = ctl.stage_results.size()
		var nums: Array = ctl.stage_results[-1]
		var names: Array = []
		for n in nums:
			for c in race.cars:
				if c.team.num == n:
					names.append(_name(c) + (" (YOU)" if c == race.player else ""))
		_stage_board = [_stage_seen, names]
		_stage_t = 8.0
	_stage_t = max(_stage_t - delta, 0.0)
	queue_redraw()


func _refresh_gaps() -> void:
	var order: Array = race.order
	if order.is_empty():
		return
	var lead: Node3D = order[0]
	var L: float = race.track.length
	for i in order.size():
		var c: Node3D = order[i]
		var t := ""
		if c.out:
			t = "OUT"
		elif c.finished and i > 0:
			t = "FIN"
		elif c.pit_state != 0:
			t = "PIT"
		elif i == 0:
			t = "LEADER"
		else:
			var dd: float = lead.dist - c.dist
			var laps := int(floor(dd / L))
			t = ("-%d LAP%s" % [laps, "" if laps == 1 else "S"]) if laps >= 1 else ("+%.3f" % (dd / max(lead.speed(), 20.0)) if dd / max(lead.speed(), 20.0) < 10.0 else "+%.1f" % (dd / max(lead.speed(), 20.0)))
		_gap_text[c] = t


func _name(c: Node3D) -> String:
	var d: String = String(c.team.driver)
	return d.get_slice(" ", d.get_slice_count(" ") - 1)


## Lead-lap cars (for the box).
func _lead_lap() -> int:
	var lead: Node3D = race.order[0]
	var n := 0
	for c in race.order:
		if not c.out and lead.dist - c.dist < race.track.length:
			n += 1
	return n


func _draw() -> void:
	if race == null or race.order.is_empty():
		return
	var f: Font = Game.arcade_font
	var W: float = hud.W
	var y := 2.0
	# The bar.
	draw_rect(Rect2(0, y, W, H), Color(0.04, 0.05, 0.09, 0.88))
	draw_rect(Rect2(0, y + H - 2, W, 2), Color(1.0, 0.8, 0.15, 0.9))
	# The box: flag colour, lap, stage.
	var ctl: Node = race.control
	var p: Node3D = race.player
	var flag_col := Color(0.1, 0.65, 0.2)
	var flag_txt := "GREEN"
	if ctl:
		flag_col = [Color(0.1, 0.65, 0.2), Color(0.95, 0.8, 0.05), Color(0.92, 0.92, 0.92), Color(0.12, 0.12, 0.12)][ctl.flag]
		flag_txt = ["GREEN", "CAUTION", "WHITE FLAG", "CHECKERED"][ctl.flag]
		if ctl.flag == ctl.Flag.GREEN and ctl.stage <= ctl.stage_ends.size():
			var to_go: int = int(ctl.stage_ends[ctl.stage - 1]) - race.order[0].lap()
			flag_txt = "STAGE %d: %d TO GO" % [ctl.stage, max(to_go, 0)]
		elif ctl.flag == ctl.Flag.GREEN:
			flag_txt = "FINAL STAGE"
		elif ctl.flag == ctl.Flag.YELLOW and ctl.one_to_go:
			flag_txt = "ONE TO GO"
		elif ctl.flag == ctl.Flag.YELLOW and ctl.stage_break:
			flag_txt = "STAGE BREAK"
	draw_rect(Rect2(0, y, 6, H), flag_col)
	var lap: int = mini(race.order[0].lap() + 1, race.laps)
	draw_string(f, Vector2(10, y + 10), "LAP %d/%d" % [lap, race.laps], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
	draw_string(f, Vector2(10, y + 20), flag_txt, HORIZONTAL_ALIGNMENT_LEFT, BOX - 14, 8, flag_col.lightened(0.3) if ctl and ctl.flag != ctl.Flag.CHECKERED else Color(0.85, 0.85, 0.85))
	draw_string(f, Vector2(82, y + 10), "LEAD LAP %d" % _lead_lap(), HORIZONTAL_ALIGNMENT_LEFT, BOX - 86, 8, Color(0.65, 0.75, 0.9))
	# The running order: drawn by the strip (which clips to its rectangle).
	_strip.position = Vector2(BOX, 0)
	_strip.size = Vector2(maxf(W - BOX, 0.0), H + 4.0)
	_strip.queue_redraw()
	# Fade the cells under the box edge.
	draw_rect(Rect2(BOX - 2, y, 2, H), Color(1.0, 0.8, 0.15, 0.7))
	# Stage results board.
	if _stage_t > 0.0 and _stage_board.size() == 2:
		var names: Array = _stage_board[1]
		var bw := 190.0
		var bx: float = W - bw - 10.0
		var by: float = hud.map_rect().end.y + 12.0
		var bh: float = 22.0 + names.size() * 13.0
		var a: float = clamp(_stage_t, 0.0, 1.0)
		draw_rect(Rect2(bx, by, bw, bh), Color(0.04, 0.05, 0.09, 0.88 * a))
		draw_rect(Rect2(bx, by, bw, 18), Color(0.85, 0.65, 0.05, a))
		draw_string(f, Vector2(bx + 6, by + 13), "STAGE %d RESULTS" % int(_stage_board[0]), HORIZONTAL_ALIGNMENT_LEFT, bw - 12, 11, Color(0.05, 0.05, 0.05, a))
		for i in names.size():
			var col := Color(1.0, 0.9, 0.4, a) if String(names[i]).ends_with("(YOU)") else Color(1, 1, 1, a)
			draw_string(f, Vector2(bx + 6, by + 31 + i * 13), "%2d  %s" % [i + 1, names[i]], HORIZONTAL_ALIGNMENT_LEFT, bw - 12, 10, col)


func _cell(c: Node3D, x: float, y: float, f: Font) -> void:
	var pos: int = race.order.find(c) + 1
	var me: bool = c == race.player or c == race.player2
	var w: float = CELL - 2.0
	var bg := Color(0.12, 0.14, 0.22, 0.95)
	if me:
		bg = Color(0.55, 0.42, 0.05, 0.95)
	var ch: Array = _change.get(c, [])
	if not ch.is_empty():
		var k: float = clamp(float(ch[0]) / ARROW_TIME, 0.0, 1.0)
		var tint := Color(0.1, 0.55, 0.2) if int(ch[1]) > 0 else Color(0.6, 0.12, 0.1)
		bg = bg.lerp(tint, 0.6 * k)
	_strip.draw_rect(Rect2(x + 1, y + 2, w, H - 5), bg)
	# Position.
	_strip.draw_rect(Rect2(x + 1, y + 2, 18, H - 5), Color(1, 1, 1, 0.92) if pos > 1 else Color(1.0, 0.85, 0.2))
	_strip.draw_string(f, Vector2(x + 1, y + 15), str(pos), HORIZONTAL_ALIGNMENT_CENTER, 18, 11, Color(0.05, 0.05, 0.08))
	# Car number in its colours.
	var c1: Color = c.team.c1
	var c2: Color = c.team.get("cn", Color.WHITE)
	_strip.draw_rect(Rect2(x + 21, y + 4, 20, H - 9), c1)
	_strip.draw_string(f, Vector2(x + 21, y + 14), String(c.team.num), HORIZONTAL_ALIGNMENT_CENTER, 20, 9, c2)
	# Name and gap.
	_strip.draw_string(f, Vector2(x + 44, y + 11), _name(c), HORIZONTAL_ALIGNMENT_LEFT, w - 46, 9, Color.WHITE)
	var gap: String = _gap_text.get(c, "")
	var gcol := Color(0.7, 0.85, 1.0)
	if gap == "PIT":
		gcol = Color(1.0, 0.75, 0.2)
	elif gap == "OUT":
		gcol = Color(1.0, 0.35, 0.3)
	_strip.draw_string(f, Vector2(x + 44, y + 19), gap, HORIZONTAL_ALIGNMENT_LEFT, w - 58, 8, gcol)
	# Up / down arrow.
	if not ch.is_empty():
		var up: bool = int(ch[1]) > 0
		var ax: float = x + w - 8
		var ay: float = y + 12
		var col := Color(0.35, 1.0, 0.45) if up else Color(1.0, 0.35, 0.3)
		if up:
			_strip.draw_colored_polygon(PackedVector2Array([Vector2(ax, ay - 5), Vector2(ax - 5, ay + 3), Vector2(ax + 5, ay + 3)]), col)
		else:
			_strip.draw_colored_polygon(PackedVector2Array([Vector2(ax, ay + 5), Vector2(ax - 5, ay - 3), Vector2(ax + 5, ay - 3)]), col)
