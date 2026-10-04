extends Control
## In-race HUD: time, lap, position, speedo/tach, draft meter, minimap and big messages.

const CrewWatch := preload("res://scripts/crew_watch.gd")

var race: Node3D
var track: Node3D
## Layout size in HUD units (the HUD is scaled to fit its view; split screen uses a
## wide, short layout). Set before the HUD enters the tree.
var W := 640.0
var H := 480.0
var auto_size := true # follow the window's shape (off in split screen, which sets W/H)
var _items: Array = [] # [label, offset, corner]
var player_idx := 1 # 1 = race.player, 2 = race.player2
var control: Node = null # race_control.gd in Single Race mode
var time_left := 0.0
var show_timer := true
## Room at the top for the TV ticker (the HUD's top row moves down by this).
var top := 0.0
## The TV ticker is showing: it carries the flag and the running order, so the
## flag banner and the top-5 board step aside.
var ticker_on := false
## Room the rear-view mirror takes at the top centre (mirror.gd sets it): the flag
## banner, goals ticker and crew calls sit below it.
var mirror_room := 0.0

var l_time_cap: Label
var l_time: Label
var l_lap_cap: Label
var l_lap: Label
var l_laptime: Label
var l_pos_cap: Label
var l_pos: Label
var l_pos_of: Label
var l_speed: Label
var l_mph: Label
var l_gear: Label
var l_draft: Label
var l_msg: Label
var l_sub: Label
var l_board: Label

var l_spot: Label
var l_flag: Label
var spot_time := 0.0
var l_crew: Label
var l_auto: Label # the car is driving itself: why (main sets auto_reason)
var auto_reason := ""
var l_goal: Label # in-race goals ticker (goals.gd), under the flag banner
var goals: Node = null
var crew_time := 0.0
var crew_urgent := false
var msg_time := 0.0
var msg_scale_t := 0.0
var sub_time := 0.0
var blink := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	l_time_cap = _add(Game.make_label("TIME", 16, Color(1, 0.9, 0.2), 5), Vector2(0, 6), 1)
	l_time = _add(Game.make_label("60", 52, Color(1, 0.9, 0.2), 8), Vector2(0, 20), 1)
	l_lap_cap = _add(Game.make_label("LAP", 16, Color(0.4, 0.9, 1.0), 5), Vector2(14, 8), 0)
	l_lap = _add(Game.make_label("1/3", 34, Color.WHITE, 7), Vector2(14, 22), 0)
	l_laptime = _add(Game.make_label("", 14, Color(0.8, 1.0, 0.8), 4), Vector2(14, 64), 0)
	l_pos_cap = _add(Game.make_label("POSITION", 16, Color(0.4, 0.9, 1.0), 5), Vector2(-14, 8), 2)
	l_pos = _add(Game.make_label("12TH", 40, Color(1.0, 0.35, 0.2), 8), Vector2(-14, 22), 2)
	l_pos_of = _add(Game.make_label("OF 12", 14, Color.WHITE, 4), Vector2(-14, 70), 2)
	l_speed = _add(Game.make_label("0", 44, Color.WHITE, 8), Vector2(-70, -64), 3)
	l_mph = _add(Game.make_label("MPH", 16, Color(1, 0.9, 0.2), 5), Vector2(-20, -40), 3)
	l_gear = _add(Game.make_label("1", 26, Color(0.4, 1.0, 0.4), 6), Vector2(-122, -104), 3)
	l_draft = _add(Game.make_label("DRAFT", 18, Color(0.3, 1.0, 1.0), 5), Vector2(-150, -130), 3)
	l_board = _add(Game.make_label("", 11, Color.WHITE, 3), Vector2(10, 108), 0)
	l_msg = Game.make_label("", 48, Color(1, 0.9, 0.2), 8)
	l_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l_msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l_msg.size = Vector2(W, 80)
	l_msg.position = Vector2(0, H * 0.31)
	l_msg.pivot_offset = Vector2(W * 0.5, 40)
	add_child(l_msg)
	l_spot = Game.make_label("", 20, Color(1.0, 0.95, 0.5), 6)
	l_spot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l_spot.size = Vector2(W, 30)
	l_spot.position = Vector2(0, H - 88)
	add_child(l_spot)
	l_flag = Game.make_label("", 18, Color.BLACK, 0)
	l_flag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l_flag.size = Vector2(240, 24)
	l_flag.position = Vector2(W * 0.5 - 120, 4)
	add_child(l_flag)
	l_sub = Game.make_label("", 22, Color.WHITE, 6)
	l_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l_sub.size = Vector2(W, 30)
	l_sub.position = Vector2(0, H * 0.46)
	l_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(l_sub)
	# The crew chief's calls: a bar under the flag, so they're read at a glance.
	l_crew = Game.make_label("", 15, Color(1.0, 0.9, 0.55), 4)
	l_crew.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l_crew.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l_crew.visible = false
	add_child(l_crew)
	l_auto = Game.make_label("", 15, Color(0.55, 0.9, 1.0), 5)
	l_auto.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l_auto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l_auto.visible = false
	add_child(l_auto)
	l_goal = Game.make_label("", 13, Color(0.85, 0.95, 1.0), 4)
	l_goal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l_goal.clip_text = true
	l_goal.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l_goal.visible = false
	add_child(l_goal)
	_layout()


## corner: 0 top-left, 1 top-centre, 2 top-right, 3 bottom-right
func _add(l: Label, p: Vector2, corner: int) -> Label:
	add_child(l)
	_items.append([l, p, corner])
	_place(l, p, corner)
	return l


## Puts everything where it belongs for the current W x H (the Modern look can be
## any shape, from a phone in landscape to an ultrawide).
func _layout() -> void:
	for it in _items:
		_place(it[0], it[1], it[2])
	l_msg.size = Vector2(W, 80)
	l_msg.position = Vector2(0, H * 0.31)
	l_msg.pivot_offset = Vector2(W * 0.5, 40)
	l_spot.size = Vector2(W, 30)
	# On narrow screens the gauges at the bottom reach the middle: go above them.
	# (Above the TV booth's captions, which sit at the bottom.)
	l_spot.position = Vector2(0, H - (112.0 if W >= 820.0 else 132.0))
	var br := _banner_rect()
	l_flag.size = br.size
	l_flag.position = br.position
	l_sub.size = Vector2(W - 40.0, 30)
	l_sub.position = Vector2(20, H * 0.46)
	if l_crew:
		var band := top_band()
		var cw: float = clamp(band.y - band.x, 200.0, 460.0)
		l_crew.size = Vector2(cw, 0)
		l_crew.position = Vector2(max((band.x + band.y - cw) * 0.5, band.x), 58 + top + mirror_room)
	if l_auto:
		l_auto.size = Vector2(W - 80.0, 0)
		l_auto.position = Vector2(40, H * 0.22)
	if l_goal:
		var gb := top_band()
		l_goal.size = Vector2(max(gb.y - gb.x, 160.0), 20)
		l_goal.position = Vector2(gb.x, 32 + top + mirror_room)


func _place(l: Label, p: Vector2, corner: int) -> void:
	match corner:
		0:
			l.position = p + Vector2(0, top if p.y >= 0.0 else 0.0)
		1:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.size = Vector2(W, 0)
			l.position = Vector2(0, p.y + top)
		2:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			l.size = Vector2(200, 0)
			l.position = Vector2(W - 200 + p.x, p.y + top)
		3:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			l.size = Vector2(120, 0)
			l.position = Vector2(W - 120 + p.x, H + p.y)


func message(text: String, seconds := 2.0, color := Color(1, 0.9, 0.2)) -> void:
	l_msg.text = text
	l_msg.label_settings.font_color = color
	msg_time = seconds
	msg_scale_t = 0.0


func sub_message(text: String, seconds := 2.0) -> void:
	l_sub.text = text
	sub_time = seconds


func spotter(text: String) -> void:
	l_spot.text = "SPOTTER:  " + text
	spot_time = 1.8


## The air around a car, for the meter and the cues: tow from the car ahead,
## push from behind, side-draft, how fast it's closing on the car ahead (mph),
## and whether it's time to pull out and pass (`cue`, `out_side` -1 inside / +1
## outside: the side with room).
static func air(p: Node3D, r: Node3D) -> Dictionary:
	var v4: Vector4 = p.get_meta("air", Vector4.ZERO)
	var ahead: Node3D = null
	var gap := 1e9
	var nbl: Array = p.nb
	for q in range(0, nbl.size(), 2):
		var g: float = nbl[q + 1]
		if g > 0.0 and g < gap and abs(nbl[q].d - p.d) < 2.0:
			gap = g
			ahead = nbl[q]
	var closing := 0.0
	if ahead:
		closing = (p.v - ahead.v) * 2.237
	var state := ""
	if v4.z > 0.35:
		state = "SIDE DRAFT"
	elif p.draft > 0.35:
		state = "DRAFT"
	elif v4.y > 0.4:
		state = "PUSH"
	var yellow: bool = r.control != null and r.control.flag == r.control.Flag.YELLOW
	var cue: bool = not yellow and ahead != null and p.draft > 0.55 and closing > 2.5 and gap < 16.0
	var out_side := 1
	if cue:
		# Pull to whichever side has room: no car alongside there.
		var room_in := true
		var room_out := true
		for q in range(0, nbl.size(), 2):
			var o: Node3D = nbl[q]
			if abs(float(nbl[q + 1])) < 8.0 and o != ahead:
				if o.d < p.d and p.d - o.d < 4.5:
					room_in = false
				elif o.d > p.d and o.d - p.d < 4.5:
					room_out = false
		if not room_in and not room_out:
			cue = false
		out_side = 1 if room_out else -1
	return {"tow": v4.x, "push": v4.y, "side": v4.z, "wall": v4.w, "closing": closing, "gap": gap, "state": state, "cue": cue, "out_side": out_side}


## A car alongside: chevrons at the side of the screen it's on, stronger the
## more it overlaps (what a spotter's "car inside!" tells you).
func _draw_alongside(p: Node3D) -> void:
	var left := 0.0
	var right := 0.0
	var nbl: Array = p.nb
	for q in range(0, nbl.size(), 2):
		var o: Node3D = nbl[q]
		var gap: float = nbl[q + 1]
		var lat: float = o.d - p.d
		if abs(gap) < 6.0 and abs(lat) > 1.2 and abs(lat) < 5.5 and not o.out:
			var amt: float = clamp(1.0 - (abs(gap) - 1.0) / 5.0, 0.0, 1.0)
			if lat < 0.0:
				left = max(left, amt) # inside (driving anticlockwise, the inside is on the left)
			else:
				right = max(right, amt)
	var cy: float = H * 0.55
	for side in [[left, -1.0], [right, 1.0]]:
		var a: float = side[0]
		if a <= 0.0:
			continue
		var x: float = 22.0 if side[1] < 0.0 else W - 22.0
		var col := Color(1.0, 0.75, 0.15, 0.35 + 0.55 * a)
		for k in 2:
			var xo: float = x + side[1] * -k * 12.0
			var tip := Vector2(xo + side[1] * 10.0, cy)
			draw_colored_polygon(PackedVector2Array([tip, Vector2(xo - side[1] * 2.0, cy - 22.0), Vector2(xo - side[1] * 8.0, cy - 22.0), Vector2(tip.x - side[1] * 10.0, cy), Vector2(xo - side[1] * 8.0, cy + 22.0), Vector2(xo - side[1] * 2.0, cy + 22.0)]), col)


## A call from the crew chief (urgent ones in red, and they blink).
func crew_call(text: String, urgent := false) -> void:
	l_crew.text = "CREW CHIEF:  " + text
	l_crew.label_settings.font_color = Color(1.0, 0.45, 0.35) if urgent else Color(1.0, 0.9, 0.55)
	crew_time = 7.0 if urgent else 5.0
	crew_urgent = urgent


func clear_messages() -> void:
	auto_reason = ""
	crew_time = 0.0
	if l_crew:
		l_crew.visible = false
	msg_time = 0.0
	sub_time = 0.0
	l_msg.text = ""
	l_sub.text = ""


func _process(delta: float) -> void:
	if auto_size and l_msg:
		# Fill the screen, less any notch, rounded corners or home bar.
		var sr: Rect2 = Game.safe_rect(get_viewport())
		if not sr.size.is_equal_approx(Vector2(W, H)) or not sr.position.is_equal_approx(position):
			W = sr.size.x
			H = sr.size.y
			position = sr.position
			size = sr.size
			_layout()
	blink += delta
	if msg_time > 0.0:
		msg_time -= delta
		msg_scale_t = min(msg_scale_t + delta * 6.0, 1.0)
		var sc: float = 1.0 + (1.0 - msg_scale_t) * 1.5
		l_msg.scale = Vector2(sc, sc)
		l_msg.visible = true
	else:
		l_msg.visible = false
	if sub_time > 0.0:
		sub_time -= delta
		l_sub.visible = int(blink * 4.0) % 2 == 0 or sub_time > 1.0
	else:
		l_sub.visible = false
	if crew_time > 0.0:
		crew_time -= delta
		l_crew.visible = not crew_urgent or crew_time < 4.0 or int(blink * 4.0) % 2 == 0
	elif l_crew.visible:
		l_crew.visible = false
	if spot_time > 0.0:
		spot_time -= delta
		l_spot.visible = true
	else:
		l_spot.visible = false
	if race == null or race.player == null:
		return
	var p: Node3D = race.player if player_idx == 1 or race.player2 == null else race.player2
	l_board.visible = H > 440.0 and not ticker_on
	l_auto.visible = auto_reason != "" and player_idx == 1 and race.running and not race.player.finished
	if l_auto.visible:
		l_auto.text = auto_reason
	# In-race goals: one line, the goal just done in gold.
	var gt: Dictionary = goals.ticker() if goals and is_instance_valid(goals) and player_idx == 1 else {}
	l_goal.visible = String(gt.get("text", "")) != "" and not l_crew.visible
	if l_goal.visible:
		l_goal.text = gt.text
		l_goal.label_settings.font_color = Color(1.0, 0.82, 0.2) if gt.gold else Color(0.85, 0.95, 1.0)
	# Flag / race-control strip (Single Race mode); the TV ticker shows it instead.
	l_flag.visible = control != null and not ticker_on
	if control:
		l_flag.text = flag_text(p)
	l_time.text = "%d" % ceil(max(time_left, 0.0))
	var low := time_left < 10.0
	l_time.label_settings.font_color = Color(1, 0.2, 0.15) if low else Color(1, 0.9, 0.2)
	l_time.visible = show_timer and (not low or int(blink * 4.0) % 2 == 0)
	l_time_cap.visible = show_timer
	var lap_now: int = clamp(p.lap() + 1, 1, race.laps)
	l_lap.text = "%d/%d" % [lap_now, race.laps]
	var cur: float = race.time - p.lap_start_time if p.lap() >= 0 else 0.0
	l_laptime.text = "LAP  %s\nBEST %s" % [Game.format_time(cur), Game.format_time(p.best_lap)]
	var pos: int = race.position_of(p)
	l_pos.text = Game.ordinal(pos)
	l_pos_of.text = "OF %d" % race.cars.size()
	l_speed.text = "%d" % int(p.speed() * Game.MPS_TO_MPH)
	l_gear.text = "R" if p.v < -0.1 else str(p.gear)
	var a := air(p, race)
	l_draft.visible = a.state != "" or a.cue
	if a.cue:
		l_draft.text = "PULL OUT!"
		l_draft.label_settings.font_color = Color(0.4, 1.0, 0.4)
		l_draft.visible = int(blink * 6.0) % 2 == 0
	elif a.state != "":
		l_draft.text = String(a.state) + ("  CLOSING +%d" % int(a.closing) if a.state == "DRAFT" and a.closing >= 1.0 else "")
		l_draft.label_settings.font_color = {"DRAFT": Color(0.3, 1.0, 1.0), "PUSH": Color(1.0, 0.8, 0.25), "SIDE DRAFT": Color(1.0, 0.4, 0.3)}[a.state]
	# mini leaderboard of the top 5
	var lines := PackedStringArray()
	var show: Array[int] = []
	for i in min(5, race.order.size()):
		show.append(i)
	var ppos: int = race.position_of(p) - 1
	if control and ppos > 4:
		show = [0, 1, 2]
		for i in range(ppos - 1, min(ppos + 2, race.order.size())):
			show.append(i)
	for i in show:
		var c: Node3D = race.order[i]
		var tag := ""
		if control and c.pit_state != 0:
			tag = " PIT"
		elif control and c.out:
			tag = " OUT"
		lines.append("%d  #%-3s %s%s" % [i + 1, c.team.num, "YOU" if c.is_player else c.team.driver.get_slice(" ", 1), tag])
	l_board.text = "\n".join(lines)
	queue_redraw()


## "STAGE 1  ENDS LAP 15", "CAUTION - PITS OPEN", "WHITE FLAG"... (and your
## pit request).
func flag_text(p: Node3D) -> String:
	var names := ["GREEN", "CAUTION", "WHITE FLAG", "CHECKERED"]
	var txt: String = names[control.flag]
	if control.flag == control.Flag.YELLOW:
		if control.one_to_go:
			txt = "ONE TO GO"
		elif control.pit_open:
			txt = "CAUTION - PITS OPEN"
	elif control.flag == control.Flag.GREEN and control.stage <= control.stage_ends.size():
		txt = "STAGE %d  ENDS LAP %d" % [control.stage, control.stage_ends[control.stage - 1]]
	elif control.flag == control.Flag.GREEN:
		txt = "FINAL STAGE"
	if p.want_pit and p.pit_state == 0:
		txt += "   PIT: " + {"4": "4T", "2": "2T", "F": "FUEL", "W": "WETS"}.get(p.pit_plan, "")
	return txt


func _draw() -> void:
	if race == null or race.player == null or track == null:
		return
	var p: Node3D = race.player if player_idx == 1 or race.player2 == null else race.player2
	if control:
		var fc: Color = [Color(0.1, 0.8, 0.2), Color(1.0, 0.85, 0.05), Color(0.95, 0.95, 0.95), Color(0.9, 0.9, 0.9)][control.flag]
		if not ticker_on:
			draw_rect(_banner_rect(), fc)
		if control.flag == control.Flag.CHECKERED:
			for i in 24:
				for j in 2:
					if (i + j) % 2 == 0:
						if not ticker_on:
							var br := _banner_rect()
							if i * 10 < br.size.x:
								draw_rect(Rect2(br.position.x + i * 10, br.position.y + j * 12, 10, 12), Color(0.05, 0.05, 0.05))
	# Tachometer arc (LED segments)
	var center := Vector2(W - 65, H - 55)
	var radius := 58.0
	var segs := 24
	var frac: float = clamp((p.rpm() - 2000.0) / 7600.0, 0.0, 1.0)
	for i in segs:
		var t := float(i) / segs
		var a0: float = lerp(PI * 0.95, PI * 1.95, t)
		var a1: float = lerp(PI * 0.95, PI * 1.95, t + 0.8 / segs)
		var col := Color(0.2, 1.0, 0.3) if t < 0.6 else (Color(1.0, 0.9, 0.2) if t < 0.85 else Color(1.0, 0.2, 0.2))
		if t > frac:
			col = Color(0.15, 0.15, 0.2, 0.7)
		draw_arc(center, radius, a0, a1, 3, col, 9.0)
	# The air meter: the tow from the car ahead (cyan), the push from the car
	# behind (gold), and the side-draft holding you back (red, from the right).
	var am := air(p, race)
	_draw_draft_meter(p, am)
	# Time of day, track temperature and the weather.
	if race.weather and control:
		var wr := _banner_rect()
		draw_string(Game.arcade_font, Vector2(wr.position.x, 44 + top), race.weather.summary(), HORIZONTAL_ALIGNMENT_CENTER, wr.size.x, 10, Color(0.85, 0.9, 1.0))
	if l_crew.visible:
		var r := Rect2(l_crew.position - Vector2(8, 3), l_crew.size + Vector2(16, 6))
		r.size.y = max(r.size.y, l_crew.get_minimum_size().y + 6.0)
		draw_rect(r, Color(0.05, 0.05, 0.1, 0.72))
		draw_rect(Rect2(r.position, Vector2(3, r.size.y)), l_crew.label_settings.font_color)
	# Car condition: damage by corner, tyres and fuel.
	# Car condition, top right under your position (where the map used to be).
	var cc := status_rect().position + Vector2(4, 4)
	var dmg: Dictionary = p.damage
	var dc := func(x: float) -> Color:
		return Color(0.3, 1.0, 0.4).lerp(Color(1.0, 0.85, 0.2), clamp(x * 2.0, 0.0, 1.0)).lerp(Color(1.0, 0.2, 0.15), clamp(x * 2.0 - 1.0, 0.0, 1.0))
	draw_rect(Rect2(cc + Vector2(-4, -4), Vector2(78, 102)), Color(0, 0, 0, 0.35))
	draw_rect(Rect2(cc + Vector2(8, 0), Vector2(14, 6)), dc.call(dmg.front))
	draw_rect(Rect2(cc + Vector2(8, 56), Vector2(14, 6)), dc.call(dmg.rear))
	draw_rect(Rect2(cc + Vector2(0, 8), Vector2(6, 46)), dc.call(dmg.left))
	draw_rect(Rect2(cc + Vector2(24, 8), Vector2(6, 46)), dc.call(dmg.right))
	# Tyre temperatures at the four corners: blue cold, green in the window, red hot.
	var tt: PackedFloat32Array = p.tyre_temp
	var corners := [Vector2(0, 0), Vector2(24, 0), Vector2(0, 56), Vector2(24, 56)]
	for i in 4:
		var t: float = tt[i]
		var tc := Color(0.3, 0.55, 1.0).lerp(Color(0.3, 1.0, 0.4), clamp((t - 55.0) / 35.0, 0.0, 1.0))
		tc = tc.lerp(Color(1.0, 0.25, 0.15), clamp((t - 115.0) / 30.0, 0.0, 1.0))
		if p.tyre_air[i] < 0.9 and int(blink * 6.0) % 2 == 0:
			tc = Color(1, 1, 1) # tyre going down: flashing
		# Each tyre's health as a traffic light round it: green fine, amber hot
		# or worn, red about to fail (flashing).
		var hl: float = CrewWatch.tyre_health(p, i)
		var hc := Color(0.25, 0.9, 0.35) if hl < 0.34 else (Color(1.0, 0.75, 0.15) if hl < 0.7 else Color(1.0, 0.2, 0.15))
		if hl >= 0.7 and int(blink * 5.0) % 2 == 0:
			hc = Color(1, 1, 1)
		draw_rect(Rect2(cc + corners[i] - Vector2(2, 2), Vector2(10, 10)), hc)
		draw_rect(Rect2(cc + corners[i], Vector2(6, 6)), tc)
	var f := Game.arcade_font
	draw_string(f, cc + Vector2(36, 14), "TIRE", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.8, 0.9, 1.0))
	draw_string(f, cc + Vector2(36, 28), "%d%%" % int(p.tyre_grip() * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, dc.call(p.tyre_wear * 0.7))
	draw_string(f, cc + Vector2(36, 44), "FUEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.8, 0.9, 1.0))
	if p.saving:
		# SAVE mode on: a green tag by the fuel.
		draw_rect(Rect2(cc + Vector2(60, 35), Vector2(18, 11)), Color(0.15, 0.6, 0.25, 0.9))
		draw_string(f, cc + Vector2(60, 44), "SV", HORIZONTAL_ALIGNMENT_CENTER, 18, 9, Color.WHITE)
	draw_string(f, cc + Vector2(36, 58), "%.1f" % (p.fuel / 3.785), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, dc.call(1.0 - p.fuel / 75.0))
	# Water temperature (F, like the real dash), and the DVP clock when it's running.
	var wt: float = p.engine_temp
	var wcol: Color = dc.call(clamp((wt - 105.0) / 40.0, 0.0, 1.0))
	if wt > 125.0 and int(blink * 4.0) % 2 == 0:
		wcol = Color(1, 1, 1)
	draw_string(f, cc + Vector2(-2, 82), "H2O %d" % int(wt * 1.8 + 32.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, wcol)
	if p.dvp_clock >= 0.0:
		draw_string(f, cc + Vector2(-2, 94), "DVP %d:%02d" % [int(p.dvp_clock) / 60, int(p.dvp_clock) % 60], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 0.6, 0.2))
	_draw_alongside(p)
	_draw_map(p)


## The course map, top left beside the lap, lap time and best lap: every car on
## it, you flashing on top, with the leader and the cars either side of you
## numbered.
const LAP_BLOCK_W := 150.0


func map_rect() -> Rect2:
	var mm: float = clamp(H * 0.24, 64.0, 116.0)
	return Rect2(LAP_BLOCK_W, 8.0 + top, mm, mm)


## The draft meter: a column under the pause button, above the speedometer.
func draft_meter_rect() -> Rect2:
	var st := status_rect()
	var top_y: float = st.position.y + 36.0 # under the II pause button
	var bottom_y: float = H - 140.0 # over the DRAFT label and the speedometer
	return Rect2(st.position.x - 12.0 - 48.0, top_y, 48.0, max(bottom_y - top_y, 0.0))


var _cut_shown := 0.0 # the meter's needle, eased


## What the draft is doing to car p, from the numbers the physics uses: `cut` is
## how much less drag it has than in clean air (the tow and a push from behind;
## negative when a side-draft or the turbulent edge of a line adds drag), `max`
## the most this track's air can cut it, `frac` the cut as a share of that (the
## meter's height), and `hp` what it's worth: the drag force it saves (the same
## force the physics applies, q * CdA * the cut) times the speed, in horsepower.
func draft_reading(p: Node3D) -> Dictionary:
	var dm: float = p.drag_mult
	var cut: float = 1.0 - dm
	var mx: float = race.draft_max() if race and race.has_method("draft_max") else 0.5
	var frac: float = clamp(cut / max(mx, 0.005), -0.35, 1.0)
	var v: float = p.speed()
	var dmg_aero: float = float(p.damage.front) + float(p.damage.rear)
	var force: float = 0.5 * p.RHO * v * v * float(p.cda) * cut * (1.0 + 0.25 * dmg_aero)
	return {"cut": cut, "max": mx, "frac": frac, "hp": force * v / 745.7}


func _draw_draft_meter(p: Node3D, am: Dictionary) -> void:
	var r := draft_meter_rect()
	if r.size.y < 60.0:
		return # no room on this screen (the DRAFT label still says it)
	var f: Font = Game.arcade_font
	var rd := draft_reading(p)
	_cut_shown = lerp(_cut_shown, float(rd.frac), 0.25)
	var cx: float = r.get_center().x
	draw_string(f, Vector2(r.position.x - 10, r.position.y + 9), "DRAFT", HORIZONTAL_ALIGNMENT_CENTER, r.size.x + 20, 10, Color(0.3, 1.0, 1.0))
	# The bar: zero a fifth of the way up, the track's strongest draft at the top,
	# extra drag (side-draft, the air wall) in red below zero.
	var bar := Rect2(cx - 8.0, r.position.y + 14.0, 16.0, r.size.y - 44.0)
	var zero_y: float = bar.end.y - bar.size.y * 0.2
	var up: float = zero_y - bar.position.y
	var down: float = bar.end.y - zero_y
	draw_rect(bar.grow(2.0), Color(0, 0, 0, 0.55))
	draw_rect(bar, Color(0.12, 0.14, 0.2, 0.75))
	var v: float = _cut_shown
	if v > 0.0:
		var h: float = up * v
		# Cyan in a light tow, green in a good one, white-hot at the most there is.
		var col := Color(0.3, 0.9, 1.0).lerp(Color(0.35, 1.0, 0.4), clamp(v * 1.6, 0.0, 1.0)).lerp(Color(1, 1, 0.85), clamp((v - 0.8) * 5.0, 0.0, 1.0))
		draw_rect(Rect2(bar.position.x, zero_y - h, bar.size.x, h), col)
	elif v < 0.0:
		draw_rect(Rect2(bar.position.x, zero_y, bar.size.x, down * min(-v / 0.35, 1.0)), Color(1.0, 0.3, 0.25))
	# Ticks every quarter, and the zero line.
	for k in [0.25, 0.5, 0.75]:
		var ty: float = zero_y - up * k
		draw_line(Vector2(bar.position.x - 3, ty), Vector2(bar.position.x, ty), Color(1, 1, 1, 0.55), 1.0)
	draw_line(Vector2(bar.position.x - 4, zero_y), Vector2(bar.end.x + 4, zero_y), Color(1, 1, 1, 0.85), 1.5)
	# The numbers: the drag cut now, and what it's worth.
	var pct: float = float(rd.cut) * 100.0
	var pct_txt := ("%+.0f%%" % -pct) if abs(pct) >= 10.0 else ("%+.1f%%" % -pct)
	if abs(pct) < 0.05:
		pct_txt = "0%"
	draw_string(f, Vector2(r.position.x - 12, bar.end.y + 13), pct_txt + " DRAG", HORIZONTAL_ALIGNMENT_CENTER, r.size.x + 24, 10, Color(0.85, 0.95, 1.0) if pct >= 0.0 else Color(1.0, 0.5, 0.45))
	var hp: float = rd.hp
	if abs(hp) >= 1.0:
		draw_string(f, Vector2(r.position.x - 12, bar.end.y + 25), "%+d HP" % roundi(hp), HORIZONTAL_ALIGNMENT_CENTER, r.size.x + 24, 10, Color(0.35, 1.0, 0.4) if hp > 0.0 else Color(1.0, 0.5, 0.45))
	# PULL OUT: an arrow beside the meter toward the side with room.
	if am.cue:
		var side_dir: float = -1.0 if am.out_side < 0 else 1.0
		var ay: float = zero_y - up * 0.5
		var ax: float = bar.position.x - 12.0
		draw_colored_polygon(PackedVector2Array([Vector2(ax + 6 * side_dir, ay), Vector2(ax - 4 * side_dir, ay - 6), Vector2(ax - 4 * side_dir, ay + 6)]), Color(0.4, 1.0, 0.4))


## The speedometer and tachometer, bottom right (the phone's brake sits to its left).
func speedo_rect() -> Rect2:
	return Rect2(W - 130.0, H - 118.0, 130.0, 118.0)


## The car's state (damage, tyres, fuel, water temperature), top right under
## your position.
func status_rect() -> Rect2:
	return Rect2(W - 14.0 - 82.0, 96.0 + top, 82.0, 106.0)


## The free stretch across the top between the map and your position: the flag
## banner, the weather line and the crew chief's calls are centred in it.
func top_band() -> Vector2:
	return Vector2(map_rect().end.x + 10.0, W - 140.0)


func _banner_rect() -> Rect2:
	var b := top_band()
	var bw: float = min(240.0, b.y - b.x)
	return Rect2((b.x + b.y) * 0.5 - bw * 0.5, 4.0 + top + mirror_room, bw, 24.0)


var high_contrast: bool:
	get:
		return int(Game.settings.get("map_contrast", 0)) == 1


func _draw_map(p: Node3D) -> void:
	var r := map_rect()
	var mm_size := r.size.x
	var mm_pos := r.position
	var pts: PackedVector2Array = track.minimap
	var poly := PackedVector2Array()
	for q in pts:
		poly.append(mm_pos + q * mm_size)
	poly.append(poly[0])
	draw_polyline(poly, Color(0, 0, 0, 0.8), 5.0)
	draw_polyline(poly, Color(0.85, 0.85, 0.9), 2.5)
	var sf: Vector2 = mm_pos + track.to_minimap(track.pos[0]) * mm_size
	draw_rect(Rect2(sf - Vector2(1.5, 4.0), Vector2(3.0, 8.0)), Color.WHITE) # start/finish
	var f := Game.arcade_font
	var ppos: int = race.position_of(p) - 1
	for i in race.order.size():
		var c: Node3D = race.order[i]
		if c == p or (c.out and control):
			continue
		var cp: Vector2 = mm_pos + track.to_minimap(c.global_position) * mm_size
		if high_contrast:
			# Colour-blind safe: everyone white on black, the leader ringed in yellow.
			draw_circle(cp, 4.2, Color.BLACK)
			draw_circle(cp, 3.0, Color(0.92, 0.92, 0.92))
			if i == 0:
				draw_arc(cp, 5.2, 0.0, TAU, 16, Color(1, 0.85, 0.0), 1.6)
		else:
			draw_circle(cp, 3.4, Color(0, 0, 0, 0.8))
			draw_circle(cp, 2.6, c.team.c1)
		if i == 0 or abs(i - ppos) == 1:
			var tag := str(i + 1)
			draw_string_outline(f, cp + Vector2(4, -3), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 3, Color.BLACK)
			draw_string(f, cp + Vector2(4, -3), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 0.9, 0.3) if i == 0 else Color.WHITE)
	var pp: Vector2 = mm_pos + track.to_minimap(p.global_position) * mm_size
	if high_contrast:
		# You: a big square that blinks black / white, told apart by shape, not colour.
		var on := int(blink * 5.0) % 2 == 0
		draw_rect(Rect2(pp - Vector2(6, 6), Vector2(12, 12)), Color.WHITE if on else Color.BLACK)
		draw_rect(Rect2(pp - Vector2(6, 6), Vector2(12, 12)), Color.BLACK if on else Color.WHITE, false, 2.0)
	else:
		draw_circle(pp, 5.0, Color(0, 0, 0))
		draw_circle(pp, 4.0, Color(1, 0.9, 0.1) if int(blink * 5.0) % 2 == 0 else Color(1, 0.3, 0.1))
