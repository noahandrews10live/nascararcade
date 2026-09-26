extends Control
## In-race HUD: time, lap, position, speedo/tach, draft meter, minimap and big messages.

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
	add_child(l_sub)


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
	l_spot.position = Vector2(0, H - 88)
	l_flag.position = Vector2(W * 0.5 - 120, 4)
	l_sub.size = Vector2(W, 30)
	l_sub.position = Vector2(0, H * 0.46)


func _place(l: Label, p: Vector2, corner: int) -> void:
	match corner:
		0:
			l.position = p
		1:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.size = Vector2(W, 0)
			l.position = Vector2(0, p.y)
		2:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			l.size = Vector2(200, 0)
			l.position = Vector2(W - 200 + p.x, p.y)
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


func clear_messages() -> void:
	msg_time = 0.0
	sub_time = 0.0
	l_msg.text = ""
	l_sub.text = ""


func _process(delta: float) -> void:
	if auto_size and l_msg:
		var sz: Vector2 = get_viewport().get_visible_rect().size
		if not sz.is_equal_approx(Vector2(W, H)):
			W = sz.x
			H = sz.y
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
	if spot_time > 0.0:
		spot_time -= delta
		l_spot.visible = true
	else:
		l_spot.visible = false
	if race == null or race.player == null:
		return
	var p: Node3D = race.player if player_idx == 1 or race.player2 == null else race.player2
	l_board.visible = H > 440.0
	# Flag / race-control strip (Single Race mode)
	l_flag.visible = control != null
	if control:
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
			txt += "   PIT: " + {"4": "4T", "2": "2T", "F": "FUEL"}[p.pit_plan]
		l_flag.text = txt
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
	l_draft.visible = p.draft > 0.35 and int(blink * 6.0) % 2 == 0
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


func _draw() -> void:
	if race == null or race.player == null or track == null:
		return
	var p: Node3D = race.player if player_idx == 1 or race.player2 == null else race.player2
	if control:
		var fc: Color = [Color(0.1, 0.8, 0.2), Color(1.0, 0.85, 0.05), Color(0.95, 0.95, 0.95), Color(0.9, 0.9, 0.9)][control.flag]
		draw_rect(Rect2(W * 0.5 - 120, 4, 240, 24), fc)
		if control.flag == control.Flag.CHECKERED:
			for i in 24:
				for j in 2:
					if (i + j) % 2 == 0:
						draw_rect(Rect2(W * 0.5 - 120 + i * 10, 4 + j * 12, 10, 12), Color(0.05, 0.05, 0.05))
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
	# Draft meter
	var dm := Rect2(Vector2(W - 162, H - 12), Vector2(150, 6))
	draw_rect(dm, Color(0, 0, 0, 0.6))
	draw_rect(Rect2(dm.position, Vector2(dm.size.x * p.draft, dm.size.y)), Color(0.3, 1.0, 1.0))
	# Time of day, track temperature and the weather.
	if race.weather and control:
		draw_string(Game.arcade_font, Vector2(W * 0.5 - 120, 44), race.weather.summary(), HORIZONTAL_ALIGNMENT_CENTER, 240, 10, Color(0.85, 0.9, 1.0))
	# Car condition: damage by corner, tyres and fuel.
	var cc := Vector2(160, H - 104)
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
		draw_rect(Rect2(cc + corners[i], Vector2(6, 6)), tc)
	var f := Game.arcade_font
	draw_string(f, cc + Vector2(36, 14), "TIRE", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.8, 0.9, 1.0))
	draw_string(f, cc + Vector2(36, 28), "%d%%" % int(p.tyre_grip() * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, dc.call(p.tyre_wear * 0.7))
	draw_string(f, cc + Vector2(36, 44), "FUEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.8, 0.9, 1.0))
	draw_string(f, cc + Vector2(36, 58), "%.1f" % (p.fuel / 3.785), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, dc.call(1.0 - p.fuel / 75.0))
	# Water temperature (F, like the real dash), and the DVP clock when it's running.
	var wt: float = p.engine_temp
	var wcol: Color = dc.call(clamp((wt - 105.0) / 40.0, 0.0, 1.0))
	if wt > 125.0 and int(blink * 4.0) % 2 == 0:
		wcol = Color(1, 1, 1)
	draw_string(f, cc + Vector2(-2, 82), "H2O %d" % int(wt * 1.8 + 32.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, wcol)
	if p.dvp_clock >= 0.0:
		draw_string(f, cc + Vector2(-2, 94), "DVP %d:%02d" % [int(p.dvp_clock) / 60, int(p.dvp_clock) % 60], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 0.6, 0.2))
	# Minimap
	var mm_size: float = min(110.0, H * 0.3)
	var mm_pos := Vector2(12, H - mm_size - 10)
	draw_rect(Rect2(mm_pos - Vector2(4, 4), Vector2(mm_size + 8, mm_size + 8)), Color(0, 0, 0, 0.35))
	var pts: PackedVector2Array = track.minimap
	var poly := PackedVector2Array()
	for q in pts:
		poly.append(mm_pos + q * mm_size)
	poly.append(poly[0])
	draw_polyline(poly, Color(0, 0, 0, 0.8), 5.0)
	draw_polyline(poly, Color(0.85, 0.85, 0.9), 2.5)
	var sf: Vector2 = mm_pos + track.to_minimap(track.pos[0]) * mm_size
	draw_circle(sf, 3.0, Color.WHITE)
	for c in race.cars:
		if c == p:
			continue
		draw_circle(mm_pos + track.to_minimap(c.global_position) * mm_size, 3.0, c.team.c1)
	var pp: Vector2 = mm_pos + track.to_minimap(p.global_position) * mm_size
	draw_circle(pp, 5.0, Color(0, 0, 0))
	draw_circle(pp, 4.0, Color(1, 0.9, 0.1) if int(blink * 5.0) % 2 == 0 else Color(1, 0.3, 0.1))
