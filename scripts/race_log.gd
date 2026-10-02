extends Node
## The race recorder: follows your car through a race and keeps what the
## debrief needs to explain it afterwards.
##   - every lap: position, lap time, gap to the leader, tyre grip and
##     temperatures, fuel, the flag;
##   - every half second: your position, so each place gained or lost is put down
##     to a cause: the START, ON TRACK (green-flag passing), PIT STOPS, CAUTIONS
##     (the field reshuffled by everyone's pit calls) or INCIDENTS (spins, hitting
##     the wall, contact, a tyre going down);
##   - the key moments, each with the lap and where on the track it happened;
##   - how the car handled: front against rear grip use in the corners (tight or
##     loose), lock-ups, wall hits, and the hottest each tyre got.
## Kept as plain data (`summary()`), so it's easy to show, save or send.

const SAMPLE := 0.5

var race: Node3D
var me: Node3D
var started := false
var t := 0.0
var start_pos := 0
var finish_pos := 0
var laps: Array = [] # [{lap, pos, time, gap, grip, fuel, flag, temps}]
var events: Array = [] # [{t, lap, kind, text, where, pos}]
var gained := {"START": 0, "ON TRACK": 0, "PIT STOPS": 0, "CAUTIONS": 0, "INCIDENTS": 0}
var passes_made := 0
var passes_lost := 0
var wall_hits := 0
var spins := 0
var lockups := 0
var contacts := {} # car number -> times touched
var peak_temp := [0.0, 0.0, 0.0, 0.0]
var peak_carcass := [0.0, 0.0, 0.0, 0.0]
var balance_sum := 0.0 # front minus rear grip use, in the corners
var balance_n := 0
var pit_stops: Array = [] # [{lap, before, after}]
var cautions := 0
var led_laps := 0

var _sample_t := 0.0
var _pos := 0
var _last_pit_t := -100.0
var _pit_before := 0
var _last_incident_t := -100.0
var _last_caution_t := -100.0
var _green_t := 0.0
var _was_pitting := false
var _was_spinning := false
var _was_locked := false
var _wall_cool := 0.0
var _last_contact := {} # car -> time


func begin(r: Node3D) -> void:
	race = r
	me = r.player
	if me == null:
		return
	race.incident.connect(_on_incident)
	race.contact.connect(_on_contact)
	race.lap_completed.connect(_on_lap)
	me.tyre_failed.connect(_on_tyre_failed)
	if race.control:
		race.control.message.connect(_on_message)


## Called every physics step while the race runs (and on the cool-down lap).
func tick(delta: float) -> void:
	if race == null or me == null or not is_instance_valid(me):
		return
	if not race.running:
		return
	if not started:
		started = true
		start_pos = race.position_of(me)
		_pos = start_pos
		_green_t = 0.0
		_event("start", "Started %s" % Game.ordinal(start_pos))
	t += delta
	_green_t += delta
	# Handling, every step: grip use front and rear when cornering at speed.
	var k: float = abs(race.track.curvature_at(me.s()))
	if k > 1.0 / 800.0 and me.speed() > 18.0 and not me.spinning and me.pit_state == 0:
		var f := 0.0
		var rr := 0.0
		for i in 2:
			f += abs(me._fy_prev[i]) / max(me._cap[i], 1.0)
			rr += abs(me._fy_prev[i + 2]) / max(me._cap[i + 2], 1.0)
		balance_sum += (f - rr) * 0.5
		balance_n += 1
	for i in 4:
		peak_temp[i] = max(peak_temp[i], me.tyre_temp[i])
		peak_carcass[i] = max(peak_carcass[i], me.carcass_temp[i])
	var locked: bool = me.locked_wheels != 0 and me.speed() > 15.0
	if locked and not _was_locked:
		lockups += 1
	_was_locked = locked
	# Hitting the wall (once per hit).
	_wall_cool = max(_wall_cool - delta, 0.0)
	if me.wall_hit > 6.0 and _wall_cool <= 0.0:
		wall_hits += 1
		_wall_cool = 1.5
		_last_incident_t = t
		_event("wall", "Hit the wall in %s" % _where(), {"speed": me.wall_hit})
	# A spin.
	if me.spinning and not _was_spinning:
		spins += 1
		_last_incident_t = t
		_event("spin", "Spun in %s" % _where())
	_was_spinning = me.spinning
	# Pit stops.
	var pitting: bool = me.pit_state != 0
	if pitting and not _was_pitting:
		_pit_before = _pos
	if _was_pitting and not pitting:
		_last_pit_t = t
		var after: int = race.position_of(me)
		pit_stops.append({"lap": _lap(), "before": _pit_before, "after": after})
		_event("pit", "Pit stop: %s to %s" % [Game.ordinal(_pit_before), Game.ordinal(after)])
	_was_pitting = pitting
	# Positions, every half second: who gained what, and why.
	_sample_t += delta
	if _sample_t >= SAMPLE:
		_sample_t = 0.0
		var p: int = race.position_of(me)
		if p != _pos:
			var d := _pos - p # + = gained
			gained[_cause()] += d
			if _cause() == "ON TRACK":
				if d > 0:
					passes_made += d
				else:
					passes_lost += -d
			_pos = p


func _cause() -> String:
	var ctl = race.control
	if _green_t < 25.0 and cautions == 0 and t < 30.0:
		return "START"
	if me.pit_state != 0 or t - _last_pit_t < 20.0:
		return "PIT STOPS"
	if t - _last_incident_t < 10.0:
		return "INCIDENTS"
	if ctl and (ctl.flag == ctl.Flag.YELLOW or t - _last_caution_t < 3.0):
		return "CAUTIONS"
	return "ON TRACK"


func _lap() -> int:
	return max(me.lap() + 1, 1)


func _where() -> String:
	return race.track.place_name(me.s()) if race.track.has_method("place_name") else ""


func _event(kind: String, text: String, extra := {}) -> void:
	var e := {"t": t, "lap": _lap(), "kind": kind, "text": text, "where": _where(), "pos": race.position_of(me)}
	e.merge(extra)
	events.append(e)


func _on_lap(car: Node3D, laps_done: int, lap_time: float) -> void:
	if car != me:
		return
	var lead: Node3D = race.order[0]
	var ctl = race.control
	var temps: Array = []
	for i in 4:
		temps.append(int(me.tyre_temp[i]))
	var flag := "G"
	if ctl and ctl.flag == ctl.Flag.YELLOW:
		flag = "Y"
	var p: int = race.position_of(me)
	if p == 1:
		led_laps += 1
	laps.append({"lap": laps_done, "pos": p, "time": lap_time, "gap": (lead.dist - me.dist) / max(me.v, 20.0) if lead != me else 0.0,
		"grip": me.tyre_grip(), "wear": me.tyre_wear, "fuel": me.fuel, "flag": flag, "temps": temps, "pit": me.pitted_this_caution})


func _on_incident(car: Node3D, kind: String) -> void:
	if car != me:
		return
	_last_incident_t = t
	if kind == "out":
		_event("out", "Out of the race in %s" % _where())


func _on_contact(who_hit: Node3D, hit: Node3D, vn: float) -> void:
	if who_hit != me and hit != me:
		return
	var other: Node3D = hit if who_hit == me else who_hit
	if t - float(_last_contact.get(other, -100.0)) < 3.0:
		return
	_last_contact[other] = t
	var num: String = other.team.num
	contacts[num] = int(contacts.get(num, 0)) + 1
	if vn > 3.5:
		_last_incident_t = t
		if who_hit == me:
			_event("contact", "Ran into #%s in %s" % [num, _where()], {"speed": vn})
		else:
			_event("contact", "#%s ran into you in %s" % [num, _where()], {"speed": vn})


func _on_tyre_failed(car: Node3D, wheel: int, kind: String) -> void:
	var names := ["LEFT FRONT", "RIGHT FRONT", "LEFT REAR", "RIGHT REAR"]
	_last_incident_t = t
	var why := ""
	match kind:
		"blowout":
			why = "it overheated (%d C)" % int(me.carcass_temp[wheel]) if me.carcass_temp[wheel] > 170.0 else "it was worn out (%d%%)" % int(me.tyre_wear4[wheel] * 100.0)
		"cut":
			why = "cut by debris or bent bodywork"
		_:
			why = kind
	_event("tyre", "%s tyre went down: %s" % [names[wheel], why], {"wheel": wheel})


func _on_message(text: String, kind: String) -> void:
	if kind == "flag" and text.begins_with("CAUTION"):
		cautions += 1
		_last_caution_t = t
		_event("caution", text.capitalize().replace("Caution  -  ", "Caution: "))
	elif kind == "flag" and text.begins_with("GREEN"):
		_last_caution_t = t
	elif kind == "stage" and text.begins_with("STAGE"):
		_event("stage", text.capitalize())


func finish(place: int) -> void:
	finish_pos = place
	if me and is_instance_valid(me):
		_event("finish", "Finished %s" % Game.ordinal(place))


## Everything as plain data: for the debrief screen, saving and problem reports.
func summary() -> Dictionary:
	var green: Array = []
	for l in laps:
		if l.flag == "G" and float(l.time) > 0.0 and not l.pit:
			green.append(float(l.time))
	return {
		"start": start_pos, "finish": finish_pos if finish_pos > 0 else (race.position_of(me) if me else 0),
		"laps": laps, "events": events, "gained": gained, "passes_made": passes_made, "passes_lost": passes_lost,
		"wall_hits": wall_hits, "spins": spins, "lockups": lockups, "contacts": contacts,
		"peak_temp": peak_temp, "peak_carcass": peak_carcass,
		"balance": balance_sum / max(balance_n, 1), "pit_stops": pit_stops, "cautions": cautions, "led": led_laps,
		"green_laps": green,
	}
