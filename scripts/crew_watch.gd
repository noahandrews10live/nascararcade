extends Node
## The crew chief keeps an eye on your car and tells you before things go
## wrong, not after: a tyre getting hot enough to blow, tyres worn out, not
## enough fuel to finish, the water temperature climbing. Each call is made
## once and made again only if it gets worse (or after it's been fixed and
## comes back).

signal warn(text: String, urgent: bool)

const CHECK := 0.5
const HOT := 155.0 # carcass C: blowouts start at 175
const VERY_HOT := 167.0
const WORN := 0.8
const VERY_WORN := 0.95
const NAMES := ["LEFT FRONT", "RIGHT FRONT", "LEFT REAR", "RIGHT REAR"]

var race: Node3D
var me: Node3D
var _t := 0.0
var _level := {} # what -> the level already called (0 none, 1 warned, 2 urgent)
var _said_t := {} # what -> when it was last called
const REPEAT_GAP := 90.0 # s before a warning that cleared is made again
var log: Array = [] # [{t, text, urgent}] (for tests and problem reports)
var _time := 0.0


func begin(r: Node3D) -> void:
	race = r
	me = r.player


## Fuel per lap as your car actually burns it, measured lap by lap (green laps
## with no pit stop), separately for normal laps and SAVE laps. Until a SAVE lap
## has been run, saving is reckoned at SAVE_CUT less (tests/save_test.gd).
const SAVE_CUT := 0.13
var _fpl := {false: 0.0, true: 0.0}
var _lap_seen := -1
var _lap_fuel0 := 0.0
var _lap_clean := true
var _lap_saving := true
var _lap_normal := true
signal offer_save(on: bool) # the crew chief says saving makes it (the HUD offers a button)


func fuel_per_lap(c: Node3D, saving: bool) -> float:
	var m: float = _fpl[saving]
	if m > 0.0:
		return m
	var normal: float = _fpl[false] if _fpl[false] > 0.0 else race.fuel_per_lap(c)
	if saving:
		return _fpl[true] if _fpl[true] > 0.0 else normal * (1.0 - SAVE_CUT)
	return normal


func _measure() -> void:
	var lap: int = me.lap()
	var ctl: Node = race.control
	if me.pit_state != 0 or (ctl and ctl.flag == ctl.Flag.YELLOW):
		_lap_clean = false
	if me.saving:
		_lap_normal = false
	else:
		_lap_saving = false
	if lap != _lap_seen:
		if _lap_seen >= 1 and lap == _lap_seen + 1 and _lap_clean and (_lap_saving or _lap_normal):
			var used: float = _lap_fuel0 - me.fuel
			if used > 0.05:
				var k: bool = _lap_saving
				_fpl[k] = used if _fpl[k] <= 0.0 else lerp(_fpl[k], used, 0.5)
		_lap_seen = lap
		_lap_fuel0 = me.fuel
		_lap_clean = true
		_lap_saving = me.saving
		_lap_normal = not me.saving


func tick(delta: float) -> void:
	if race == null or me == null or not is_instance_valid(me) or not race.running:
		return
	_measure()
	_time += delta
	_t += delta
	if _t < CHECK:
		return
	_t = 0.0
	if me.pit_state != 0 or me.out:
		return
	# Tyres: the hottest one, and how worn they are.
	var hot_i := 0
	for i in 4:
		if me.carcass_temp[i] > me.carcass_temp[hot_i]:
			hot_i = i
	var ct: float = me.carcass_temp[hot_i]
	_call("hot", 2 if ct > VERY_HOT else (1 if ct > HOT else 0), 0 if ct < HOT - 12.0 else -1,
		"%s IS GETTING HOT (%d C) - EASE UP IN THE CORNERS" % [NAMES[hot_i], int(ct)],
		"%s IS ABOUT TO LET GO (%d C) - BACK OFF OR PIT NOW" % [NAMES[hot_i], int(ct)])
	var worn_i := 0
	for i in 4:
		if me.tyre_wear4[i] > me.tyre_wear4[worn_i]:
			worn_i = i
	var w: float = me.tyre_wear4[worn_i]
	_call("worn", 2 if w > VERY_WORN else (1 if w > WORN else 0), 0 if w < 0.3 else -1,
		"TIRES ARE ABOUT DONE (%s %d%%) - SAVE THEM OR PIT WHEN YOU CAN" % [NAMES[worn_i], int(w * 100.0)],
		"TIRES ARE GONE - THEY COULD BLOW, PIT NOW")
	# Fuel: enough to get to the end? If saving would make it, say so (and by how
	# much); if not, when to pit.
	var normal_laps: float = me.fuel / max(fuel_per_lap(me, false), 0.001)
	var save_laps: float = me.fuel / max(fuel_per_lap(me, true), 0.001)
	var to_go: float = float(race.laps - me.lap()) - fposmod(me.dist, race.track.length) / race.track.length
	var fuel_laps: int = int(normal_laps)
	var fl := 0
	if normal_laps < to_go:
		fl = 2 if normal_laps <= 1.5 else (1 if normal_laps <= 4.5 else 0)
	var can_save: bool = normal_laps < to_go and save_laps >= to_go + 0.3 and to_go <= 45.0
	if can_save:
		if not me.saving:
			_call("save", 1, -1,
				"FUEL FOR %d LAPS, %d TO GO - SAVE AND WE MAKE IT (%.1f LAPS SPARE)" % [fuel_laps, ceili(to_go), save_laps - to_go], "")
			offer_save.emit(true)
		else:
			_call("save", 2, -1, "", "KEEP SAVING - WE MAKE IT BY %.1f LAPS" % (save_laps - to_go))
	elif me.saving and normal_laps >= to_go + 0.5:
		_call("saved", 1, -1, "FUEL'S GOOD NOW - YOU CAN RACE IT", "")
	else:
		_call("fuel", fl, 0 if normal_laps > 6.5 else -1,
			"FUEL FOR %d LAPS, %d TO GO - PIT IN THE NEXT %d" % [fuel_laps, ceili(to_go), max(fuel_laps - 1, 1)],
			"YOU'RE ABOUT TO RUN DRY - PIT THIS LAP")
	# Water temperature (a grille full of grass or rubber, or too long in the draft).
	var wt: float = me.engine_temp
	_call("water", 2 if wt > 130.0 else (1 if wt > 118.0 else 0), 0 if wt < 108.0 else -1,
		"WATER TEMP IS CLIMBING (%d F) - GET SOME CLEAN AIR" % int(wt * 1.8 + 32.0),
		"ENGINE'S COOKING (%d F) - PULL OUT OF THE DRAFT NOW" % int(wt * 1.8 + 32.0))


## Makes the call for `level` if it's worse than what's already been said;
## `reset` 0 means the problem has gone away (so it can be called again).
func _call(what: String, level: int, reset: int, text1: String, text2: String) -> void:
	var said: int = int(_level.get(what, 0))
	if reset == 0 and level == 0:
		_level[what] = 0
		return
	if level > said:
		# The same warning again soon after it went away (a temperature hovering
		# round the line) isn't news: give it a while. Urgent calls always go.
		if said == 0 and level == 1 and _time - float(_said_t.get(what, -1e9)) < REPEAT_GAP:
			return
		_said_t[what] = _time
		_level[what] = level
		var text := text2 if level == 2 else text1
		log.append({"t": _time, "text": text, "urgent": level == 2})
		warn.emit(text, level == 2)


## The worst state of each tyre, 0 good .. 1 about to fail (the HUD's lights).
static func tyre_health(car: Node3D, i: int) -> float:
	if car.tyre_air[i] < 0.9:
		return 1.0
	var heat: float = clamp((car.carcass_temp[i] - 140.0) / 35.0, 0.0, 1.0)
	var wear: float = clamp((car.tyre_wear4[i] - 0.55) / 0.45, 0.0, 1.0)
	return max(heat, wear)
