extends Control
## The race debrief: what happened in your race and why, on three pages.
##   1 THE RACE: your position lap by lap (pit stops, cautions and incidents
##     marked) and where the places went: the start, passing on track, pit stops,
##     cautions, incidents.
##   2 PACE & CAR: your laps against the winner's and the race's fastest, how
##     your tyres fell off and how hot they got, whether the car was tight or
##     loose, lock-ups and wall hits.
##   3 KEY MOMENTS & COACH: the race in a few lines (lap, where, what), and the
##     crew chief's advice, each with a button to act on it (a setup change, the
##     difficulty, the steering help, the R&D shop).
## The coaching is a pure function of the race log (`coach()`), so it's tested
## without a screen.

signal action(a: Dictionary) # an APPLY button
signal done

const W := 640.0
const PAGES := ["THE RACE", "PACE & CAR", "KEY MOMENTS & COACH"]
const GOLD := Color(1.0, 0.85, 0.1)
const CYAN := Color(0.5, 0.9, 1.0)
const GOOD := Color(0.35, 1.0, 0.45)
const BAD := Color(1.0, 0.4, 0.3)
const DIM := Color(0.7, 0.75, 0.82)

var s: Dictionary # race_log.summary()
var ctx: Dictionary # mode, track, field, winner/fastest laps, career, settings
var page := 0
var tips: Array = []
var _applied := {}


func setup(summary: Dictionary, context: Dictionary) -> void:
	s = summary
	ctx = context
	tips = coach(s, ctx)
	size = Vector2(640, 480)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func turn(dir: int) -> void:
	page = clampi(page + dir, 0, PAGES.size() - 1)
	_build()


# --- the coach ----------------------------------------------------------------

## The crew chief's advice from a race log: most useful first, at most four.
## Each tip is {"text", "action" (optional): {"kind", "label", ...}}.
static func coach(sm: Dictionary, cx: Dictionary) -> Array:
	var out: Array = []
	var g: Dictionary = sm.get("gained", {})
	var field: int = int(cx.get("field", 20))
	var fin: int = int(sm.get("finish", 0))
	var my_best: float = float(cx.get("my_best", 0.0))
	var win_best: float = float(cx.get("winner_best", 0.0))
	var avg_lap: float = float(cx.get("avg_lap", 30.0))
	# Incidents: where they happened most.
	var inc := int(sm.get("wall_hits", 0)) + int(sm.get("spins", 0))
	if inc >= 2 or int(g.get("INCIDENTS", 0)) <= -3:
		var spots := {}
		for e in sm.get("events", []):
			if e.kind in ["wall", "spin"] and String(e.get("where", "")) != "":
				spots[e.where] = int(spots.get(e.where, 0)) + 1
		var worst := ""
		var wn := 0
		for k in spots:
			if spots[k] > wn:
				wn = spots[k]
				worst = k
		var t := "Incidents cost you %d places (%d wall hits, %d spins)." % [max(-int(g.get("INCIDENTS", 0)), 0), int(sm.get("wall_hits", 0)), int(sm.get("spins", 0))]
		if worst != "" and wn >= 2:
			t += " %d were in %s: lift a little earlier going in and wait to turn." % [wn, worst]
		var tip := {"text": t}
		if float(cx.get("assist_level", 1.0)) < 1.0:
			tip.action = {"kind": "assists", "label": "MORE STEERING HELP"}
		out.append(tip)
	# Handling balance.
	var bal: float = float(sm.get("balance", 0.0))
	if bal > 0.06:
		out.append({"text": "The car was TIGHT: the front tyres were working harder than the rears in the corners (pushing up the track). One click looser will help it turn.",
			"action": {"kind": "setup", "key": "balance", "delta": 1, "label": "BALANCE: ONE CLICK LOOSER"}})
	elif bal < -0.06:
		out.append({"text": "The car was LOOSE: the rear tyres were near their limit before the fronts. One click tighter will settle it.",
			"action": {"kind": "setup", "key": "balance", "delta": -1, "label": "BALANCE: ONE CLICK TIGHTER"}})
	# Tyre heat.
	var pc: Array = sm.get("peak_carcass", [0, 0, 0, 0])
	var hot := 0
	for i in 4:
		if float(pc[i]) > float(pc[hot]):
			hot = i
	if float(pc[hot]) > 150.0:
		var names := ["left front", "right front", "left rear", "right rear"]
		out.append({"text": "Your %s ran hot (up to %d C; it lets go past about 175). Smoother into the corners, and less wheelspin off them, keeps it alive." % [names[hot], int(pc[hot])]})
	# Lock-ups.
	if int(sm.get("lockups", 0)) >= 6 and float(cx.get("assist_level", 1.0)) < 1.0:
		out.append({"text": "You locked the brakes %d times. Moving the brake bias one click rearward lets the fronts keep turning." % int(sm.lockups),
			"action": {"kind": "setup", "key": "bias", "delta": -1, "label": "BRAKE BIAS: ONE CLICK REARWARD"}})
	# Pit stops under green.
	for ps in sm.get("pit_stops", []):
		var lost: int = int(ps.after) - int(ps.before)
		if lost >= 5:
			out.append({"text": "Your stop on lap %d cost %d places. Under green a stop costs a lap's worth of cars; under a caution it costs only a few. Stretch the fuel if you can." % [int(ps.lap), lost]})
			break
	# The start.
	if int(g.get("START", 0)) <= -3:
		out.append({"text": "You lost %d places on the start. Get to full throttle as the leader goes, and hold your lane until the field strings out." % -int(g.START)})
	# Pace: the car or the field.
	if my_best > 0.0 and win_best > 0.0 and my_best > win_best * 1.006:
		var gap: float = my_best - win_best
		if cx.get("career", false):
			var best_area := ""
			var best_gain := 0.0
			var gains: Dictionary = cx.get("rnd_gain", {})
			for k in gains:
				if float(gains[k]) > best_gain:
					best_gain = float(gains[k])
					best_area = k
			if best_area != "":
				out.append({"text": "The winner's best lap was %.2f s faster. Here, the next %s level is worth about %.2f s a lap." % [gap, best_area.to_upper(), best_gain * avg_lap],
					"action": {"kind": "rnd", "label": "OPEN THE R&D SHOP"}})
		elif int(cx.get("difficulty", 1)) > 0 and fin > int(field * 0.6):
			out.append({"text": "The leaders were %.2f s a lap faster. Want a closer race? The field can be a notch easier." % gap,
				"action": {"kind": "difficulty", "delta": -1, "label": "MAKE THE FIELD A NOTCH EASIER"}})
	elif fin == 1 and float(cx.get("margin", 0.0)) > 3.0 and int(cx.get("difficulty", 1)) < 2 and not cx.get("career", false):
		out.append({"text": "You won by %.1f s. Ready for a tougher field?" % float(cx.margin),
			"action": {"kind": "difficulty", "delta": 1, "label": "MAKE THE FIELD TOUGHER"}})
	# Something to feel good about.
	if int(g.get("ON TRACK", 0)) >= 3:
		out.append({"text": "You passed %d cars under green: that's where races are won." % int(sm.get("passes_made", 0))})
	elif int(sm.get("led", 0)) > 0:
		out.append({"text": "You led %d laps." % int(sm.led)})
	if out.is_empty():
		out.append({"text": "A clean race. Keep the car under you and the places will come."})
	return out.slice(0, 4)


# --- drawing --------------------------------------------------------------------

func _clear() -> void:
	for c in get_children():
		c.queue_free()


func _lab(text: String, sz: int, col: Color, pos: Vector2, w := 0.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Game.make_label(text, sz, col, 4)
	l.position = pos
	l.horizontal_alignment = align
	if w > 0.0:
		l.size = Vector2(w, 0)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(l)
	return l


func _box(r: Rect2, col: Color) -> void:
	var c := ColorRect.new()
	c.position = r.position
	c.size = r.size
	c.color = col
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)


func _button(text: String, r: Rect2, cb: Callable, col := Color(0.18, 0.22, 0.3)) -> Button:
	var b := Button.new()
	b.text = text
	b.position = r.position
	b.size = r.size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", Game.arcade_font)
	b.add_theme_font_size_override("font_size", 13)
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.border_color = Color(1, 1, 1, 0.5)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	b.add_theme_stylebox_override("normal", sb)
	var sh := sb.duplicate()
	sh.bg_color = col.lightened(0.25)
	b.add_theme_stylebox_override("hover", sh)
	b.add_theme_stylebox_override("pressed", sh)
	b.pressed.connect(cb)
	# Taps and clicks come through tap() (touch would otherwise press it twice:
	# once as a touch, once as the mouse click the system makes from it).
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(b)
	return b


## A tap or click at p (this screen's coordinates): presses the button there.
## Always takes it (a miss shouldn't skip the debrief).
func tap(p: Vector2) -> bool:
	for c in get_children():
		if c is Button and Rect2(c.position, c.size).grow(4).has_point(p):
			c.pressed.emit()
			return true
	return true


func _build() -> void:
	_clear()
	_box(Rect2(14, 8, 612, 464), Color(0.02, 0.03, 0.06, 0.86))
	var st: int = int(s.get("start", 0))
	var fin: int = int(s.get("finish", 0))
	var head := "FINISHED %s" % Game.ordinal(fin) if fin > 0 else "RACE DEBRIEF"
	if st > 0 and fin > 0 and st != fin:
		head += "   (STARTED %s, %s%d)" % [Game.ordinal(st), "+" if st > fin else "", st - fin]
	_lab("RACE DEBRIEF", 12, CYAN, Vector2(28, 14))
	_lab(head, 24, GOLD, Vector2(28, 28))
	# Page tabs.
	for i in PAGES.size():
		_lab(("> " if i == page else "") + PAGES[i], 11, GOLD if i == page else DIM, Vector2(360 + 0.0, 16 + i * 14))
	match page:
		0:
			_page_race()
		1:
			_page_pace()
		2:
			_page_moments()
	# Navigation.
	if page > 0:
		_button("< BACK", Rect2(28, 428, 110, 34), func(): turn(-1))
	if page < PAGES.size() - 1:
		_button("NEXT >", Rect2(150, 428, 110, 34), func(): turn(1))
	_button("CONTINUE", Rect2(476, 428, 136, 34), func(): done.emit(), Color(0.15, 0.4, 0.2))


func _page_race() -> void:
	var chart := DebriefChart.new()
	chart.position = Vector2(28, 70)
	chart.size = Vector2(330, 200)
	chart.setup(s, int(ctx.get("field", 20)))
	add_child(chart)
	_lab("YOUR POSITION, LAP BY LAP", 11, DIM, Vector2(28, 272))
	_lab("P PIT STOP    YELLOW CAUTION    X INCIDENT", 10, DIM, Vector2(28, 286))
	# Where the places went.
	_lab("WHERE YOU GAINED AND LOST", 13, CYAN, Vector2(376, 72))
	var y := 94.0
	var g: Dictionary = s.get("gained", {})
	for k in ["START", "ON TRACK", "PIT STOPS", "CAUTIONS", "INCIDENTS"]:
		var v: int = int(g.get(k, 0))
		_lab(k, 13, Color.WHITE, Vector2(376, y))
		var col := GOOD if v > 0 else (BAD if v < 0 else DIM)
		_lab(("+%d" % v) if v > 0 else str(v), 15, col, Vector2(560, y - 1), 50, HORIZONTAL_ALIGNMENT_RIGHT)
		# A bar either side of a centre line.
		var bw: float = clamp(abs(v) * 7.0, 0.0, 70.0)
		_box(Rect2(470 if v >= 0 else 470 - bw, y + 4, bw, 9), col)
		_box(Rect2(469, y + 2, 2, 13), DIM)
		y += 24.0
	y += 6.0
	var lines: Array = [
		"Passed %d cars on track, passed by %d" % [int(s.get("passes_made", 0)), int(s.get("passes_lost", 0))],
		"Led %d laps" % int(s.get("led", 0)),
		"%d pit stops, %d cautions" % [s.get("pit_stops", []).size(), int(s.get("cautions", 0))],
	]
	for l in lines:
		_lab(l, 12, Color.WHITE, Vector2(376, y), 240)
		y += 20.0
	# The best thing the crew chief has to say, here too.
	if not tips.is_empty():
		_box(Rect2(28, 310, 584, 106), Color(0.1, 0.13, 0.2, 0.8))
		_lab("CREW CHIEF", 11, GOLD, Vector2(40, 318))
		_lab(String(tips[0].text), 14, Color.WHITE, Vector2(40, 334), 560)


func _page_pace() -> void:
	var y := 72.0
	_lab("PACE", 13, CYAN, Vector2(28, y))
	y += 22.0
	var rows: Array = []
	var my_best: float = float(ctx.get("my_best", 0.0))
	if my_best > 0.0:
		rows.append(["YOUR BEST LAP", Game.format_time(my_best), ""])
	var greens: Array = s.get("green_laps", [])
	if greens.size() >= 2:
		var sum := 0.0
		for v in greens:
			sum += float(v)
		rows.append(["YOUR AVERAGE GREEN LAP", Game.format_time(sum / greens.size()), ""])
		var mean := sum / greens.size()
		var var_ := 0.0
		for v in greens:
			var_ += pow(float(v) - mean, 2.0)
		rows.append(["CONSISTENCY", "+/- %.2f s" % sqrt(var_ / greens.size()), ""])
	var wb: float = float(ctx.get("winner_best", 0.0))
	if wb > 0.0:
		rows.append(["WINNER'S BEST", Game.format_time(wb), ("+%.2f" % (my_best - wb)) if my_best > 0.0 else ""])
	var fb: float = float(ctx.get("fastest", 0.0))
	if fb > 0.0:
		rows.append(["FASTEST LAP (%s)" % String(ctx.get("fastest_by", "")), Game.format_time(fb), ("+%.2f" % (my_best - fb)) if my_best > 0.0 else ""])
	for r in rows:
		_lab(r[0], 12, Color.WHITE, Vector2(28, y))
		_lab(r[1], 13, GOLD, Vector2(220, y - 1))
		_lab(r[2], 12, BAD if r[2].begins_with("+") and r[2] != "+0.00" else GOOD, Vector2(300, y))
		y += 20.0
	# Tyres: the fall-off over your longest green run, and the heat.
	var y2 := 72.0
	_lab("TYRES", 13, CYAN, Vector2(376, y2))
	y2 += 22.0
	var run := _longest_run()
	if run.size() >= 6:
		var a: float = (float(run[1]) + float(run[2]) + float(run[3])) / 3.0
		var b: float = (float(run[-1]) + float(run[-2]) + float(run[-3])) / 3.0
		_lab("Over your longest run (%d laps) you lost %.2f s a lap" % [run.size(), b - a], 12, Color.WHITE, Vector2(376, y2), 236)
		y2 += 36.0
	var pc: Array = s.get("peak_carcass", [0, 0, 0, 0])
	var names := ["LF", "RF", "LR", "RR"]
	_lab("HOTTEST EACH TYRE GOT", 11, DIM, Vector2(376, y2))
	y2 += 16.0
	for i in 4:
		var tc: float = float(pc[i])
		var col := GOOD if tc < 130.0 else (Color(1, 0.8, 0.2) if tc < 160.0 else BAD)
		var x: float = 376.0 + (i % 2) * 118.0
		var yy: float = y2 + (i / 2) * 24.0
		_box(Rect2(x, yy, 108, 20), Color(col.r, col.g, col.b, 0.25))
		_lab("%s  %d C" % [names[i], int(tc)], 13, col, Vector2(x + 8, yy + 1))
	# Handling.
	y = max(y, y2 + 56.0) + 10.0
	_lab("HOW THE CAR HANDLED", 13, CYAN, Vector2(28, y))
	y += 22.0
	var bal: float = clamp(float(s.get("balance", 0.0)), -0.2, 0.2)
	_box(Rect2(28, y + 6, 300, 6), Color(0.3, 0.33, 0.4))
	_box(Rect2(28 + 150 + bal / 0.2 * 150 - 4, y, 8, 18), GOLD)
	_lab("TIGHT", 10, DIM, Vector2(28, y + 20))
	_lab("NEUTRAL", 10, DIM, Vector2(156, y + 20))
	_lab("LOOSE", 10, DIM, Vector2(296, y + 20))
	var hl: Array = ["%d wall hits, %d spins" % [int(s.get("wall_hits", 0)), int(s.get("spins", 0))], "%d lock-ups" % int(s.get("lockups", 0))]
	var cc: Dictionary = s.get("contacts", {})
	if not cc.is_empty():
		var parts: Array = []
		for k in cc:
			parts.append("#%s (%d)" % [k, int(cc[k])])
		hl.append("Contact with " + ", ".join(parts.slice(0, 4)))
	var yh := y
	for l in hl:
		_lab(l, 12, Color.WHITE, Vector2(376, yh), 236)
		yh += 18.0


func _longest_run() -> Array:
	var best: Array = []
	var cur: Array = []
	for l in s.get("laps", []):
		if l.flag == "G" and not l.get("pit", false) and float(l.time) > 0.0:
			cur.append(float(l.time))
		else:
			if cur.size() > best.size():
				best = cur
			cur = []
	if cur.size() > best.size():
		best = cur
	return best


func _page_moments() -> void:
	_lab("KEY MOMENTS", 13, CYAN, Vector2(28, 72))
	var y := 92.0
	var shown := 0
	for e in s.get("events", []):
		if shown >= 7:
			break
		if e.kind == "stage":
			continue
		var col := Color.WHITE
		match String(e.kind):
			"wall", "spin", "tyre", "out", "contact":
				col = BAD
			"caution":
				col = Color(1, 0.85, 0.25)
			"pit":
				col = CYAN
			"finish", "start":
				col = GOLD
		_lab("LAP %d" % int(e.lap), 11, DIM, Vector2(28, y + 1))
		_lab(String(e.text), 12, col, Vector2(84, y), 250)
		y += 22.0
		shown += 1
	_lab("CREW CHIEF", 13, GOLD, Vector2(350, 72))
	var ty := 92.0
	for i in tips.size():
		var tip: Dictionary = tips[i]
		var l := _lab(String(tip.text), 12, Color.WHITE, Vector2(350, ty), 262)
		var lines: int = int(ceil(l.get_minimum_size().y / 15.0))
		ty += max(lines, 1) * 15.0 + 4.0
		if tip.has("action"):
			var a: Dictionary = tip.action
			var key := str(i)
			if _applied.has(key):
				_lab("DONE: " + String(a.label), 11, GOOD, Vector2(350, ty))
				ty += 20.0
			else:
				_button(String(a.label), Rect2(350, ty, 262, 26), func():
					_applied[key] = true
					action.emit(a)
					_build(), Color(0.35, 0.28, 0.08))
				ty += 32.0
		ty += 6.0


## The position chart: P1 at the top; pit laps, caution laps and incidents
## marked; the start and finish labelled.
class DebriefChart extends Control:
	var laps: Array = []
	var events: Array = []
	var field := 20
	var start_pos := 0

	func setup(sm: Dictionary, f: int) -> void:
		laps = sm.get("laps", [])
		events = sm.get("events", [])
		field = max(f, 2)
		start_pos = int(sm.get("start", 0))
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.08, 0.1, 0.16, 0.9))
		var n: int = laps.size()
		if n < 1:
			draw_string(Game.arcade_font, Vector2(10, size.y * 0.5), "NO LAPS COMPLETED", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.75, 0.8))
			return
		var px := func(i: float) -> float: return 20.0 + (size.x - 30.0) * i / float(max(n, 1))
		var py := func(p: float) -> float: return 10.0 + (size.y - 20.0) * (p - 1.0) / float(field - 1)
		# Grid lines every 5 places.
		for p in range(5, field + 1, 5):
			var yy: float = py.call(p)
			draw_line(Vector2(18, yy), Vector2(size.x - 4, yy), Color(1, 1, 1, 0.08))
			draw_string(Game.arcade_font, Vector2(0, yy + 4), str(p), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.6, 0.65, 0.7))
		draw_string(Game.arcade_font, Vector2(2, 14), "1", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.6, 0.65, 0.7))
		# Caution laps.
		for i in n:
			if laps[i].flag == "Y":
				draw_rect(Rect2(px.call(i), 0, px.call(i + 1) - px.call(i), size.y), Color(1, 0.85, 0.2, 0.18))
		# The line.
		var pts := PackedVector2Array()
		if start_pos > 0:
			pts.append(Vector2(px.call(0), py.call(start_pos)))
		for i in n:
			pts.append(Vector2(px.call(i + 1), py.call(float(laps[i].pos))))
		if pts.size() >= 2:
			draw_polyline(pts, Color(1.0, 0.85, 0.1), 2.5, true)
		for p in pts:
			draw_circle(p, 2.5, Color(1, 0.9, 0.3))
		# Pit stops and incidents, on the lap they happened.
		for e in events:
			var li: int = clampi(int(e.lap), 1, n)
			var x: float = px.call(li - 0.5)
			var yy: float = py.call(float(laps[li - 1].pos))
			if e.kind == "pit":
				draw_string(Game.arcade_font, Vector2(x - 4, yy - 6), "P", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.9, 1.0))
			elif e.kind in ["wall", "spin", "tyre", "out"]:
				draw_string(Game.arcade_font, Vector2(x - 4, yy + 14), "X", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.4, 0.3))
