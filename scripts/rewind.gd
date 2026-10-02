extends Node
## REWIND: made a mistake? Go back five seconds and try again. The last ten
## seconds of the race are kept (every car: where it was, how fast, its tyres,
## fuel and damage, and the flag); rewinding puts everyone back, cancels a
## caution your crash brought out, and counts you back in 3-2-1.
##   - offered for a few seconds after you spin, crash or hit the wall (a button
##     on a phone, BACKSPACE on a keyboard), and on the pause screen;
##   - a few per race (Options -> REWIND), never online or in the daily
##     challenge, and a lap you rewound in doesn't count as a record.

signal rewound

const EVERY := 0.5
const KEEP := 20.0
const BACK := 5.0
const OFFER := 7.0

var main: Node
var race: Node3D
var left := 3 # rewinds left this race
var used := 0
var offer_t := 0.0 # seconds the REWIND prompt stays up
var _snaps: Array = [] # [{t, flag, cautions, cars: [...]}]
var _t := 0.0
var _mark := -1.0 # when the mistake happened (the race clock): rewind to before it


func begin(r: Node3D, uses: int) -> void:
	race = r
	left = uses
	used = 0
	offer_t = 0.0
	_snaps.clear()
	_t = 0.0
	_mark = -1.0


func available() -> bool:
	return race != null and is_instance_valid(race) and left > 0 and _target() != null


## Called every physics step while racing.
## (The pit call and replays can come several seconds after the mistake, so a
## good stretch is kept.)
func tick(delta: float) -> void:
	if race == null or not is_instance_valid(race) or not race.running:
		return
	offer_t = max(offer_t - delta, 0.0)
	_t += delta
	if _t < EVERY:
		return
	_t = 0.0
	_snaps.append(_snapshot())
	while _snaps.size() > int(KEEP / EVERY) + 1:
		_snaps.pop_front()


## Put the REWIND prompt up (after a spin, a wall hit, a wreck).
func offer() -> void:
	if left > 0:
		if offer_t <= 0.0:
			_mark = race.time if race else -1.0
		offer_t = OFFER


func _snapshot() -> Dictionary:
	var cars: Array = []
	for c in race.cars:
		cars.append({
			"dist": c.dist, "d": c.d, "v": c.v, "fuel": c.fuel, "wear": c.tyre_wear,
			"wear4": c.tyre_wear4.duplicate(), "temp": c.tyre_temp.duplicate(), "carcass": c.carcass_temp.duplicate(),
			"air": c.tyre_air.duplicate(), "leak": c.tyre_leak.duplicate(), "damage": c.damage.duplicate(),
			"out": c.out, "why": c.out_reason, "best": c.best_lap, "last": c.last_lap, "lap_start": c.lap_start_time,
			"led": c.laps_led, "pts": c.stage_points, "water": c.engine_temp, "pit": c.pit_state, "want_pit": c.want_pit,
			"towed": c.towed, "finished": c.finished,
		})
	var ctl: Node = race.control
	return {"t": race.time, "flag": ctl.flag if ctl else 0, "cautions": ctl.caution_count if ctl else 0,
		"stage": ctl.stage if ctl else 1, "nres": ctl.stage_results.size() if ctl else 0, "cars": cars}


## The snapshot to go back to: about BACK seconds ago, under green, with your car
## on the track (not in the pits, not finished).
func _target() -> Variant:
	# Five seconds before the mistake (if there's just been one), else before now.
	var now: float = race.time
	if _mark >= 0.0 and now - _mark < KEEP - BACK:
		now = _mark
	var green: int = race.control.Flag.GREEN if race.control else 0
	for i in range(_snaps.size() - 1, -1, -1):
		var s: Dictionary = _snaps[i]
		if now - float(s.t) < BACK - 0.01:
			continue
		var me: int = race.cars.find(race.player)
		if me < 0:
			return null
		var mine: Dictionary = s.cars[me]
		if int(s.flag) != green or int(mine.pit) != 0 or bool(mine.out) or bool(mine.finished):
			continue
		return s
	return null


func rewind() -> bool:
	if not available():
		return false
	var s: Dictionary = _target()
	var ctl: Node = race.control
	if ctl and ctl.flag != ctl.Flag.GREEN:
		ctl.cancel_caution(int(s.cautions))
	if ctl:
		# A stage that ended after the snapshot ends again when the leader gets there.
		ctl.stage = int(s.stage)
		ctl.stage_results = ctl.stage_results.slice(0, int(s.nres))
	race.time = float(s.t)
	for i in min(race.cars.size(), s.cars.size()):
		var c: Node3D = race.cars[i]
		var d: Dictionary = s.cars[i]
		if bool(d.towed) and not c.towed:
			continue
		c.towed = bool(d.towed)
		c.visible = not c.towed
		c.pace_mode = false
		c.dist = float(d.dist)
		c.d = float(d.d)
		c.ai_lane = c.d
		c.kin_d = c.d
		c.v = float(d.v)
		c.kin_v = c.v
		c.vy = 0.0
		c.r = 0.0
		c.yaw = 0.0
		c.spinning = false
		c.tumbling = false
		c.fuel = float(d.fuel)
		c.tyre_wear = float(d.wear)
		c.tyre_wear4 = d.wear4.duplicate()
		c.tyre_temp = d.temp.duplicate()
		c.carcass_temp = d.carcass.duplicate()
		c.tyre_air = d.air.duplicate()
		c.tyre_leak = d.leak.duplicate()
		for k in d.damage:
			c.damage[k] = float(d.damage[k])
		c._update_damage_visual()
		c.out = bool(d.out)
		c.out_reason = String(d.why)
		c.best_lap = float(d.best)
		c.last_lap = float(d.last)
		c.lap_start_time = float(d.lap_start)
		c.laps_led = int(d.led)
		c.stage_points = int(d.pts)
		c.engine_temp = float(d.water)
		c.pit_state = int(d.pit)
		c.want_pit = bool(d.want_pit)
		c.wall_hit = 0.0
		c.lap_idx = c.lap()
		c.reset_chassis()
		c.sync_visual()
	# The lap you rewound in doesn't count as a record.
	race.player.set_meta("lap_void", true)
	race.clear_debris()
	race._update_order()
	# Snapshots after this point never happened.
	while not _snaps.is_empty() and float(_snaps[-1].t) > float(s.t):
		_snaps.pop_back()
	left -= 1
	used += 1
	offer_t = 0.0
	_mark = -1.0
	rewound.emit()
	return true
