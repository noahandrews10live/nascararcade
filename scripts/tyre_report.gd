extends Control
## The tire report: what the crew reads with the pyrometer when you come in.
## Each tyre's tread across inside / middle / outside (F), and what it says about
## the car, in plain words:
##   - inside hot: too much camber; outside hot: not enough;
##   - middle hot: too much air in that side; edges hot: too little;
##   - fronts hotter than rears: the car's tight; rears hotter: loose.
## Read at the end of each lap (main keeps the last); shown every few laps in
## practice, at your pit stops, and on demand (Y, or TIRE REPORT when paused).

const NAMES := ["LF", "RF", "LR", "RR"]
const IO_HOT := 7.0 # C across the tread: a camber call
const CROWN_HOT := 5.0 # C middle against edges: a pressure call
const BALANCE_HOT := 12.0 # C fronts against rears: a balance call

var report: Dictionary = {}
var show_t := 0.0
var W := 640.0
var H := 480.0


func _ready() -> void:
	Game.center_frame(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The reading off `car` now: {cells: 4 x [inside, middle, outside] in F,
## advice: [lines], lap}.
static func read(car: Node3D) -> Dictionary:
	var cells: Array = []
	var io := []
	var crown := []
	var avg := []
	for i in 4:
		var t: Array = car.tread_temps(i)
		cells.append(t.map(func(c): return int(round(c * 1.8 + 32.0))))
		io.append(float(t[0]) - float(t[2]))
		crown.append(float(t[1]) - (float(t[0]) + float(t[2])) * 0.5)
		avg.append((float(t[0]) + float(t[1]) + float(t[2])) / 3.0)
	var advice: Array = []
	# Balance first: it's the big one.
	var fr: float = (avg[0] + avg[1]) * 0.5 - (avg[2] + avg[3]) * 0.5
	if fr > BALANCE_HOT:
		advice.append("FRONTS RUNNING HOTTER THAN THE REARS: IT'S TIGHT - TAKE WEDGE OUT OR RAISE THE TRACK BAR")
	elif fr < -BALANCE_HOT:
		advice.append("REARS RUNNING HOTTER THAN THE FRONTS: IT'S LOOSE - ADD WEDGE OR LOWER THE TRACK BAR")
	# Camber: the worst tyre.
	var worst := 0
	for i in 4:
		if abs(io[i]) > abs(io[worst]):
			worst = i
	if io[worst] > IO_HOT:
		advice.append("%s INSIDE HOT (%d F ACROSS): TOO MUCH CAMBER - TAKE SOME OUT" % [NAMES[worst], int(io[worst] * 1.8)])
	elif io[worst] < -IO_HOT:
		advice.append("%s OUTSIDE HOT (%d F ACROSS): NOT ENOUGH CAMBER - ADD SOME" % [NAMES[worst], int(-io[worst] * 1.8)])
	# Pressures, by side.
	for side in [0, 1]:
		var c: float = (crown[side] + crown[side + 2]) * 0.5
		var which: String = "LEFT" if side == 0 else "RIGHT"
		if c > CROWN_HOT:
			advice.append("%s SIDES HOT IN THE MIDDLE: TOO MUCH AIR - LOWER THE %s PRESSURES" % [which, which])
		elif c < -CROWN_HOT:
			advice.append("%s SIDES HOT ON THE EDGES: TOO LITTLE AIR - RAISE THE %s PRESSURES" % [which, which])
	if advice.is_empty():
		advice.append("TEMPS LOOK EVEN ACROSS ALL FOUR - THE CAR'S CLOSE")
	return {"cells": cells, "advice": advice, "lap": car.lap(), "io": io, "crown": crown, "balance": fr}


func show_report(r: Dictionary, seconds: float) -> void:
	report = r
	show_t = seconds
	visible = true


func _process(delta: float) -> void:
	if show_t > 0.0:
		show_t -= delta
		if show_t <= 0.0:
			visible = false
		queue_redraw()


func _tcol(f_deg: float) -> Color:
	var t: float = (f_deg - 32.0) / 1.8
	var c := Color(0.3, 0.55, 1.0).lerp(Color(0.3, 1.0, 0.4), clamp((t - 55.0) / 35.0, 0.0, 1.0))
	return c.lerp(Color(1.0, 0.25, 0.15), clamp((t - 115.0) / 30.0, 0.0, 1.0))


func _draw() -> void:
	if report.is_empty():
		return
	var f := Game.arcade_font
	var pw: float = min(W - 40.0, 520.0)
	var x0: float = (W - pw) * 0.5
	var y0 := 96.0
	var lines: Array = report.advice
	var ph: float = 168.0 + 30.0 * lines.size()
	draw_rect(Rect2(x0, y0, pw, ph), Color(0, 0, 0, 0.78))
	draw_string(f, Vector2(x0 + 10, y0 + 18), "TIRE REPORT  -  AFTER LAP %d   (INSIDE / MIDDLE / OUTSIDE, F)" % int(report.lap), HORIZONTAL_ALIGNMENT_LEFT, pw - 20, 11, Color(1, 0.85, 0.2))
	for i in 4:
		var cx: float = x0 + pw * 0.5 - 170.0 + (i % 2) * 180.0
		var cy: float = y0 + 32.0 + (i / 2) * 62.0
		draw_string(f, Vector2(cx, cy + 12), NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
		var c: Array = report.cells[i]
		# On the page the left tyres read outside..inside, the rights inside..outside,
		# the way they sit on the car.
		var order: Array = [2, 1, 0] if i % 2 == 0 else [0, 1, 2]
		for k in 3:
			var v: float = float(c[order[k]])
			var r := Rect2(cx + 26.0 + k * 40.0, cy, 38, 20)
			draw_rect(r, _tcol(v))
			draw_string(f, r.position + Vector2(5, 15), "%d" % int(v), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0, 0, 0))
		draw_string(f, Vector2(cx + 26.0, cy + 34), ("OUT  MID  IN" if i % 2 == 0 else "IN   MID  OUT"), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.7, 0.75, 0.8))
	var ly: float = y0 + 162.0
	for l in lines:
		draw_multiline_string(f, Vector2(x0 + 10, ly), String(l), HORIZONTAL_ALIGNMENT_LEFT, pw - 20, 10, 2, Color(0.85, 0.95, 1.0))
		ly += 30.0
