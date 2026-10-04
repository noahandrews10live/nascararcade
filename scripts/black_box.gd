extends Control
## The black box (B, or TIMING when paused): the timing screen a crew chief
## watches, over the race.
##   - your last and best laps, and the leader's last;
##   - three sectors: this lap's (or the last lap's) times against your best in
##     each, green faster, red slower;
##   - the gap to the car ahead, the car behind and the leader, in seconds;
##   - fuel (laps of it and litres), tyres, laps led, position.
## The sectors are timed here (a third of the lap each), so it works in every
## session.

var main: Node
var W := 640.0
var H := 480.0
var car: Node3D = null
var sec_now := [0.0, 0.0, 0.0] # this lap's sector times so far
var sec_last := [0.0, 0.0, 0.0] # the last full lap's
var sec_best := [0.0, 0.0, 0.0] # your best in each sector
var _sec := -1
var _sec_t0 := 0.0
var _lap_seen := -1
var _from_start := false # the sector being timed began at its start line
var _redraw := 0.0


func _ready() -> void:
	Game.center_frame(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func begin(c: Node3D) -> void:
	car = c
	sec_now = [0.0, 0.0, 0.0]
	sec_last = [0.0, 0.0, 0.0]
	sec_best = [0.0, 0.0, 0.0]
	_sec = -1
	_lap_seen = -1


## Each physics tick (main): time the sectors.
func tick(race_time: float) -> void:
	if car == null or not is_instance_valid(car) or car.track == null:
		return
	var L: float = car.track.length
	var sec: int = clampi(int(fposmod(car.dist, L) / L * 3.0), 0, 2)
	var lap: int = car.lap()
	if _sec < 0:
		_sec = sec
		_lap_seen = lap
		_sec_t0 = race_time
		_from_start = false
		return
	if sec != _sec or lap != _lap_seen:
		var t: float = race_time - _sec_t0
		# (Only a sector run from its start to its end counts.)
		var clean: bool = _from_start and (sec == (_sec + 1) % 3) and car.pit_state == 0
		if clean and t > 0.5:
			sec_now[_sec] = t
			if sec_best[_sec] <= 0.0 or t < sec_best[_sec]:
				sec_best[_sec] = t
		if _sec == 2 and sec == 0:
			sec_last = sec_now.duplicate()
			sec_now = [0.0, 0.0, 0.0]
		_from_start = sec == (_sec + 1) % 3
		_sec = sec
		_lap_seen = lap
		_sec_t0 = race_time


func toggle() -> void:
	visible = not visible


func _process(delta: float) -> void:
	if visible:
		_redraw -= delta
		if _redraw <= 0.0:
			_redraw = 0.2
			queue_redraw()


## The numbers on the screen (also what the test reads).
func reading() -> Dictionary:
	var race: Node3D = main.race if main else null
	if race == null or car == null or not is_instance_valid(car):
		return {}
	var order: Array = race.order
	var i: int = order.find(car)
	var gap := func(a: Node3D, b: Node3D) -> float:
		return (a.dist - b.dist) / max(abs(b.v), 20.0)
	var ahead: Node3D = order[i - 1] if i > 0 else null
	var behind: Node3D = order[i + 1] if i >= 0 and i + 1 < order.size() else null
	var lead: Node3D = order[0] if order.size() > 0 else null
	var per: float = race.fuel_per_lap(car)
	return {
		"pos": i + 1, "of": order.size(), "lap": car.lap() + 1, "laps": race.laps,
		"last": car.last_lap, "best": car.best_lap, "leader_last": lead.last_lap if lead else 0.0,
		"ahead": ahead, "gap_ahead": gap.call(ahead, car) if ahead else 0.0,
		"behind": behind, "gap_behind": gap.call(car, behind) if behind else 0.0,
		"gap_leader": gap.call(lead, car) if lead and lead != car else 0.0,
		"fuel": car.fuel, "fuel_laps": car.fuel / max(per, 0.001), "tyres": car.tyre_grip(), "led": car.laps_led,
		"sec_now": sec_now, "sec_last": sec_last, "sec_best": sec_best,
	}


func _t(x: float) -> String:
	return Game.format_time(x) if x > 0.0 else "--"


func _draw() -> void:
	var r: Dictionary = reading()
	if r.is_empty():
		return
	var f := Game.arcade_font
	var pw: float = min(W - 40.0, 470.0)
	var x0: float = (W - pw) * 0.5
	var y0 := 100.0
	draw_rect(Rect2(x0, y0, pw, 172), Color(0, 0, 0, 0.8))
	var gold := Color(1, 0.85, 0.2)
	var dim := Color(0.65, 0.7, 0.78)
	var wht := Color(0.92, 0.95, 1.0)
	draw_string(f, Vector2(x0 + 10, y0 + 18), "BLACK BOX", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, gold)
	draw_string(f, Vector2(x0 + 10, y0 + 18), "LAP %d/%d   P%d OF %d" % [r.lap, r.laps, r.pos, r.of], HORIZONTAL_ALIGNMENT_RIGHT, pw - 20, 12, wht)
	draw_string(f, Vector2(x0 + 10, y0 + 40), "LAST %s    BEST %s    LEADER'S LAST %s" % [_t(r.last), _t(r.best), _t(r.leader_last)], HORIZONTAL_ALIGNMENT_LEFT, pw - 20, 11, wht)
	# Sectors: this lap's so far, else the last lap's, against your best.
	draw_string(f, Vector2(x0 + 10, y0 + 64), "SECTORS", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, dim)
	for k in 3:
		var t: float = r.sec_now[k] if r.sec_now[k] > 0.0 else r.sec_last[k]
		var b: float = r.sec_best[k]
		var col := wht
		var d := ""
		if t > 0.0 and b > 0.0:
			d = " (%+.2f)" % (t - b)
			col = Color(0.35, 1.0, 0.45) if t - b <= 0.005 else (Color(1.0, 0.45, 0.35) if t - b > 0.1 else Color(1.0, 0.85, 0.3))
		draw_string(f, Vector2(x0 + 70 + k * 130, y0 + 64), "S%d %s%s" % [k + 1, ("%.2f" % t) if t > 0.0 else "--", d], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
	var ahead_s: String = ("#%s  -%.2f S" % [r.ahead.team.num, r.gap_ahead]) if r.ahead else "--"
	var behind_s: String = ("#%s  +%.2f S" % [r.behind.team.num, r.gap_behind]) if r.behind else "--"
	draw_string(f, Vector2(x0 + 10, y0 + 90), "AHEAD %s     BEHIND %s     LEADER %s" % [ahead_s, behind_s, ("-%.1f S" % r.gap_leader) if r.gap_leader > 0.0 else "YOU"], HORIZONTAL_ALIGNMENT_LEFT, pw - 20, 11, wht)
	draw_string(f, Vector2(x0 + 10, y0 + 116), "FUEL %.1f LAPS (%.1f L)     TIRES %d%%     LED %d" % [r.fuel_laps, r.fuel, int(r.tyres * 100.0), r.led], HORIZONTAL_ALIGNMENT_LEFT, pw - 20, 11, wht)
	draw_string(f, Vector2(x0 + 10, y0 + 156), "B TO CLOSE" if not Game.touch_active else "PAUSE -> TIMING TO CLOSE", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, dim)
