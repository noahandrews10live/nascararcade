extends Node
## Race control: flags, cautions and the pace car, pit road, the free pass and
## wave-arounds, double-file restarts with the choose rule, stages, overtime and
## points. Owned by race.gd; it steers the AI (and the player's car on autopilot)
## whenever the field isn't racing under green.

signal flag_changed(flag: String)
signal message(text: String, kind: String) # kind: flag, spotter, pit, stage, info
## Quick cautions: the player's pit call is needed (main pauses and asks).
signal pit_call(info: Dictionary)
## Quick cautions: the stops are done and the field is lined up (for the board).
signal pit_report(lines: Array)
## Online: the host asks another player's screen for their pit call; a
## player's screen sends its answer back; the host lines everyone up.
signal remote_pit_call(car: Node3D, info: Dictionary)
signal remote_answer(call: String, wedge_change: float)
signal lined_up(rows: Array)

enum Flag { GREEN, YELLOW, WHITE, CHECKERED }
enum Pit { NONE, APPROACH, LANE, SERVICE, EXIT }

const Car := preload("res://scripts/car.gd")
const CAUTION_LAPS := 3
const POINTS := [40, 35, 34, 33, 32, 31, 30, 29, 28, 27, 26, 25, 24, 23, 22, 21, 20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1]

var race: Node3D
var track: Node3D
var flag := Flag.GREEN
var enabled := true
var pits_enabled := true
var cautions_enabled := true
var debris_rate := 0.003 # chance per green lap of a "phantom" debris caution
var weather_hold := false # ovals: keep the field under caution while it's wet

# caution state
var caution_count := 0
var caution_elapsed := 0.0
var caution_laps := 0 # completed by the pace car
var caution_needed_laps := CAUTION_LAPS
var pit_open := false
var one_to_go := false
var restart_armed := false
var pace_car: Node3D
var _pace_last_lap := 0
var _incident_timers := {}
var _green_since := 0.0
var _last_caution_reason := ""
var lane_choice := {} # car -> 0 inside / 1 outside
var player_lane_choice := 0
var choosing := false

# stages
var stage_ends: Array[int] = []
var stage := 1
var stage_results: Array = [] # per stage: array of car nums top 10

# overtime
var overtime := false

# Quick cautions (the default): about 15 seconds from the yellow to the green.
# The field slows for a moment, every team makes its pit call (the player on a
# pause screen), the stops are worked out, and the field is lined up double file
# in the right order just before the restart zone. FULL cautions run the real
# laps behind the pace car instead.
const QUICK_SLOW_TIME := 3.5 # seconds of yellow before the pit calls
const QUICK_RESTART_BEFORE := 520.0 # leader's distance before the line when lined up (about 15 s in all)
const PIT_ROAD_LOSS := 4.0 # extra seconds pit road costs over staying on track
var quick := true
var quick_phase := "" # "", "slow", "decide", "roll"
var _quick_t := 0.0
var _freeze: Array = [] # running order when the caution came out (scoring freeze)
var _calls := {} # car -> "4", "2", "F", "W", "S" (slicks) or "" (stay out)
var _adjust := {} # car -> wedge change asked for
var _cause: Node3D = null
var player_pending := false
var final_lap_caution := false

# pit road
var pit_speed := 20.0
var box_spacing := 10.0

# spotter
var _spot_state := ""
var _spot_timer := 0.0
var _dt := 1.0 / 60.0
## Online. The host runs race control for everyone. The other players' race
## control follows it (`follower`): flags, the pace car and the restart line-up
## come from the host, and only their own car's pit call is theirs.
var follower := false
var remote_humans := {} # host: cars driven by the other players
var _waiting := {} # host: players whose pit call hasn't come in yet
var _decide_t := 0.0


func setup(r: Node3D) -> void:
	race = r
	track = r.track
	pit_speed = float(track.cfg.get("pit_mph", 45)) / 2.23694
	var laps: int = race.laps
	if laps >= 12:
		stage_ends = [int(round(laps * 0.25)), int(round(laps * 0.5))]
	var zone: float = track.pit_half() * 2.0 - 50.0
	box_spacing = clamp(zone / max(race.cars.size(), 1), 3.0, 12.0)
	var i := 0
	for c in race.cars:
		c.set_meta("box", i)
		i += 1
	_build_pace_car()


func _build_pace_car() -> void:
	pace_car = Car.new()
	pace_car.name = "PaceCar"
	race.add_child(pace_car)
	pace_car.setup({"num": "", "driver": "PACE CAR", "sponsor": "OFFICIAL PACE CAR", "c1": Color(0.95, 0.95, 0.97), "c2": Color(0.1, 0.2, 0.7), "cn": Color(0.1, 0.1, 0.1), "speed": 1.0, "handling": 1.0}, track)
	var bar := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.2, 0.12, 0.3)
	bar.mesh = bm
	bar.material_override = Game.make_mat("light", Color(1.0, 0.6, 0.05))
	bar.position = Vector3(0, 1.58, 0.45)
	pace_car.model.add_child(bar)
	pace_car.set_meta("lightbar", bar)
	pace_car.visible = false
	pace_car.process_mode = Node.PROCESS_MODE_DISABLED


func box_s(c: Node3D) -> float:
	return fposmod(track.pit_in_s() + 30.0 + float(c.get_meta("box", 0)) * box_spacing, track.length)


func leader() -> Node3D:
	for c in race.order:
		if not c.towed:
			return c
	return race.order[0]


# --- main tick ---------------------------------------------------------------------

func tick(delta: float) -> void:
	_dt = delta
	if not enabled or not race.running:
		return
	if follower:
		# The host decides; this screen just tows its own wreck and spots.
		if flag == Flag.YELLOW:
			for c in race.cars:
				if c.out and not c.towed and not c.remote:
					c.set_meta("out_time", c.get_meta("out_time", race.time))
					if race.time - float(c.get_meta("out_time")) > 6.0:
						race.tow(c)
		if flag != Flag.CHECKERED:
			_spotter(delta)
		return
	_update_pace_car(delta)
	match flag:
		Flag.GREEN, Flag.WHITE:
			_green_tick(delta)
		Flag.YELLOW:
			caution_elapsed += delta
			if caution_elapsed > 20.0 and not race.debris.is_empty():
				race.clear_debris() # the safety crews sweep it up
			_caution_tick(delta)
	if flag != Flag.CHECKERED:
		_spotter(delta)


func checkered() -> void:
	flag = Flag.CHECKERED
	flag_changed.emit("CHECKERED")


## Watches for incidents under green, the way race control does on an oval:
##   - a wreck: a car out, a heavily damaged car, three or more cars spinning;
##   - a car that gets turned around (past about 80 degrees), even if it drives
##     off again;
##   - a hard hit on the wall (it leaves debris and a wounded car);
##   - a car stopped anywhere off pit road (the racing surface, the apron, the
##     grass), or crawling round well off the pace after an incident;
##   - a pile of debris on the racing surface (race.gd).
## A slide that's caught doesn't. Road courses only go yellow for a car that's out,
## stopped on the track or stuck off it.
const TURNED_AROUND := 1.4 # rad
const HARD_WALL_HIT := 11.0 # m/s into the wall
func _green_tick(delta: float) -> void:
	_green_since += delta
	if not cautions_enabled:
		return
	var road: bool = track.cfg.get("road", false)
	var spinning_now := 0
	for c in race.cars:
		if c.spinning and not c.towed and c.pit_state == Pit.NONE:
			spinning_now += 1
	var lead := leader()
	var pack_speed: float = max(abs(lead.v), 20.0)
	for c in race.cars:
		if c.towed or c.finished or c.pit_state != Pit.NONE:
			continue
		# On the racing surface (not down on the apron, the grass or in the infield).
		var on_surface: bool = c.d > track.inner_edge() - 0.5 and not c.on_grass
		var near_pits: bool = track.in_pit_roadway(c.s()) and c.d < track.inner_edge()
		var st: Dictionary = _incident_timers.get(c, {})
		var reason := ""
		if c.out:
			st.t = st.get("t", 0.0) + delta
			if st.t > 1.0:
				reason = "ACCIDENT"
		elif not road and c.wall_hit > HARD_WALL_HIT and _green_since > 3.0:
			reason = "CAR IN THE WALL"
		elif c.spinning or st.has("spun"):
			st.spun = true
			st.t = st.get("t", 0.0) + delta
			st.yaw = max(float(st.get("yaw", 0.0)), abs(c.yaw))
			if c.speed() < 10.0 and (on_surface or not road) and not near_pits:
				st.stop = st.get("stop", 0.0) + delta
			if c.speed() < pack_speed * 0.55:
				st.slow = st.get("slow", 0.0) + delta
			if not road and st.t > 0.8 and (c.total_damage() > 0.3 or spinning_now >= 3):
				reason = "ACCIDENT"
			elif not road and st.yaw > TURNED_AROUND and st.t > 1.0:
				reason = "SPIN"
			elif st.get("stop", 0.0) > (4.0 if road else 1.5):
				reason = "SPIN"
			elif not road and st.get("slow", 0.0) > 6.0:
				reason = "SLOW CAR"
			elif not c.spinning and c.speed() > max(15.0, pack_speed * (0.0 if road else 0.55)) and st.t > 1.0:
				_incident_timers.erase(c) # gathered it up and kept going
				if c.is_player or randf() < 0.3:
					message.emit("#%s SPUN AND KEPT IT GOING" % c.team.num, "spotter")
				continue
			elif st.t > (10.0 if road else 12.0):
				_incident_timers.erase(c)
				continue
		elif c.v < 6.0 and _green_since > 6.0 and not c.pace_mode and not near_pits and (on_surface or not road or c.on_grass):
			# Stopped: on the track, or (ovals) anywhere off pit road; stuck in the
			# grass on a road course.
			st.stop = st.get("stop", 0.0) + delta
			if st.stop > (6.0 if road and on_surface else (12.0 if road else 3.0)):
				reason = "STALLED CAR" if on_surface else "CAR STOPPED"
		else:
			_incident_timers.erase(c)
			continue
		_incident_timers[c] = st
		if reason != "":
			if OS.is_debug_build() and OS.get_environment("RC_DEBUG") != "":
				print("caution %s car #%s spin=%s out=%s v=%.1f dmg=%.2f d=%.1f s=%.0f yaw=%.2f" % [reason, c.team.num, c.spinning, c.out, c.v, c.total_damage(), c.d, c.s(), c.yaw])
			throw_caution(reason, c)
			return


## Called by race.gd when the leader completes a lap under green.
func on_leader_lap(lap_done: int) -> void:
	if not enabled or follower:
		return
	if flag == Flag.YELLOW:
		# A stage that ends under caution still ends (points, no extra yellow).
		if stage <= stage_ends.size() and lap_done >= stage_ends[stage - 1]:
			_end_stage(false)
		return
	# Stage end
	if stage <= stage_ends.size() and lap_done >= stage_ends[stage - 1]:
		_end_stage()
		return
	if lap_done == race.laps - 1 and flag == Flag.GREEN:
		flag = Flag.WHITE
		flag_changed.emit("WHITE")
		message.emit("WHITE FLAG", "flag")
	elif cautions_enabled and randf() < debris_rate and lap_done < race.laps - 3 and _green_since > 60.0:
		throw_caution("DEBRIS", null)


func _end_stage(caution := true) -> void:
	var top: Array = []
	var i := 0
	for c in race.order:
		if c.towed:
			continue
		if i < 10:
			c.stage_points += 10 - i
			top.append(c)
		i += 1
	stage_results.append(top.map(func(c): return c.team.num))
	message.emit("STAGE %d WINNER  #%s %s" % [stage, top[0].team.num, top[0].team.driver], "stage")
	stage += 1
	if caution:
		throw_caution("STAGE %d END" % (stage - 1), null)


## What brought the caution out, in words: who, what and where
## ("#24 GORDON SPUN IN TURN 2", "YOU HIT THE WALL IN TURN 4").
var caution_detail := ""


func caution_why(reason: String, who: Node3D, where := "") -> String:
	if who == null:
		match reason:
			"DEBRIS":
				return "DEBRIS ON TRACK" + (" IN " + where if where != "" else "")
			_:
				return ""
	if where == "":
		where = track.place_name(who.s())
	var name: String = "YOU" if who.is_player else "#%s %s" % [who.team.num, who.team.driver.get_slice(" ", who.team.driver.get_slice_count(" ") - 1)]
	var what := ""
	match reason:
		"ACCIDENT":
			what = "WRECKED"
		"CAR IN THE WALL":
			what = "HIT THE WALL"
		"SPIN":
			what = "SPUN"
		"SLOW CAR":
			what = ("ARE" if who.is_player else "IS") + " CRAWLING AFTER A SPIN"
		"STALLED CAR", "CAR STOPPED":
			what = "STOPPED"
		_:
			what = reason
	var text := "%s %s IN %s" % [name, what, where]
	for i in 4:
		if who.tyre_air[i] < 0.9:
			text += " - TIRE DOWN"
			break
	return text


func throw_caution(reason: String, who: Node3D, where := "") -> void:
	if flag == Flag.YELLOW:
		return
	var lead := leader()
	# A caution after the white flag ends the race under yellow.
	if flag == Flag.WHITE and lead.lap() >= race.laps - 1:
		final_lap_caution = true
		flag = Flag.YELLOW
		flag_changed.emit("YELLOW")
		message.emit("CAUTION ON THE FINAL LAP", "flag")
		race.freeze_finish()
		return
	flag = Flag.YELLOW
	caution_elapsed = 0.0
	caution_count += 1
	caution_laps = 0
	caution_needed_laps = CAUTION_LAPS + (1 if who and who.out else 0)
	pit_open = false
	one_to_go = false
	restart_armed = false
	choosing = false
	lane_choice.clear()
	_last_caution_reason = reason
	_incident_timers.clear()
	for c in race.cars:
		c.pitted_this_caution = false
	flag_changed.emit("YELLOW")
	message.emit("CAUTION  -  %s" % reason, "flag")
	caution_detail = caution_why(reason, who, where)
	if caution_detail != "":
		message.emit(caution_detail, "why")
	# Pace car picks up the leader.
	pace_car.visible = true
	pace_car.process_mode = Node.PROCESS_MODE_INHERIT
	# The pace car pulls out well ahead so the field can slow down gradually.
	pace_car.dist = lead.dist + min(420.0, track.length * 0.3)
	pace_car.d = race.lanes[0]
	pace_car.pace_lane = race.lanes[0]
	pace_car.v = pace_speed()
	pace_car.pace_speed = pace_speed()
	pace_car.pace_mode = true
	_pace_last_lap = pace_car.lap()
	# Overtime: a late caution guarantees a green-white-checkered finish.
	if lead.lap() >= race.laps - 2:
		overtime = true
	if quick:
		quick_phase = "slow"
		_quick_t = 0.0
		_cause = who
		_calls.clear()
		_adjust.clear()
		player_pending = false
		_freeze = race.order.filter(func(c): return not c.towed and not c.finished)


func pace_speed() -> float:
	return pit_speed * 1.6


func _update_pace_car(delta: float) -> void:
	if flag != Flag.YELLOW or final_lap_caution:
		return
	pace_car.step(delta)
	var bar: MeshInstance3D = pace_car.get_meta("lightbar")
	bar.visible = int(Time.get_ticks_msec() / 250) % 2 == 0
	if restart_armed:
		# Pull off onto pit road and out of sight.
		pace_car.pace_lane = track.pit_lane_d()
		if track.in_pit_zone(pace_car.s()) and fposmod(pace_car.s() - track.pit_in_s(), track.length) < track.pit_half():
			pace_car.visible = false


func _caution_tick(delta: float) -> void:
	if final_lap_caution:
		return
	# Count laps by the pace car crossing the line.
	# Wrecked cars get towed off.
	for c in race.cars:
		if c.out and not c.towed:
			c.set_meta("out_time", c.get_meta("out_time", race.time))
			if race.time - float(c.get_meta("out_time")) > 6.0:
				race.tow(c)
	if quick_phase != "":
		_quick_tick(delta)
		if quick_phase != "roll":
			return
	var pl: int = pace_car.lap()
	if pl > _pace_last_lap and not restart_armed and quick_phase == "":
		_pace_last_lap = pl
		caution_laps += 1
		if weather_hold:
			# Rain: circle behind the pace car until the track is dry.
			caution_needed_laps = max(caution_needed_laps, caution_laps + 2)
			one_to_go = false
			if caution_laps > 1:
				message.emit("HOLDING FOR RAIN - JET DRYERS ON TRACK", "flag")
		if caution_laps == 1:
			# Tow the wrecks, open pit road, award the free pass.
			for c in race.cars:
				if c.out and not c.towed:
					race.tow(c)
			if pits_enabled:
				pit_open = true
				message.emit("PIT ROAD IS OPEN", "pit")
				_ai_pit_decisions()
			_free_pass()
		if caution_laps == caution_needed_laps - 1:
			one_to_go = true
			message.emit("ONE TO GO", "flag")
			_wave_around()
			choosing = true
		if caution_laps >= caution_needed_laps:
			restart_armed = true
			choosing = false
			if overtime:
				var lead := leader()
				race.laps = max(race.laps, lead.lap() + 2)
				message.emit("OVERTIME  -  GREEN-WHITE-CHECKERED", "flag")
	if one_to_go and choosing:
		_assign_lanes()
	# Restart: the leader goes when the field reaches the restart zone.
	if restart_armed:
		var lead := leader()
		var to_line: float = fposmod(-lead.s(), track.length)
		if to_line < 80.0 and to_line > 5.0:
			_go_green()


func _go_green() -> void:
	flag = Flag.GREEN
	quick_phase = ""
	one_to_go = false
	restart_armed = false
	pit_open = false
	_green_since = 0.0
	pace_car.visible = false
	pace_car.process_mode = Node.PROCESS_MODE_DISABLED
	flag_changed.emit("GREEN")
	message.emit("GREEN FLAG!", "flag")
	var lead := leader()
	if lead.lap() == race.laps - 1:
		flag = Flag.WHITE
		flag_changed.emit("WHITE")


func _free_pass() -> void:
	var lead := leader()
	for c in race.order:
		if c.towed or c.out:
			continue
		if c.lap() < lead.lap() and (lead.dist - c.dist) > track.length * 0.5:
			race.give_lap(c)
			message.emit("FREE PASS: #%s %s" % [c.team.num, c.team.driver], "info")
			return


func _wave_around() -> void:
	var lead := leader()
	for c in race.order:
		if c.towed or c.out or c.pitted_this_caution or c.pit_state != Pit.NONE:
			continue
		if lead.dist - c.dist > track.length * 0.6:
			race.give_lap(c)


func _ai_pit_decisions() -> void:
	var laps_left: int = race.laps - leader().lap()
	for c in race.cars:
		if c.towed or c.out:
			continue
		if not c.ai and c.is_player:
			continue # the player chooses
		var fuel_need: float = laps_left * track.length / 1000.0 * 0.5 * c.burn_scale
		var wants: bool = c.tyre_wear > 0.12 or c.fuel < fuel_need + 5.0 or c.total_damage() > 0.12
		if laps_left < 6 and c.fuel > fuel_need:
			wants = false
		if wants or randf() < 0.15:
			# Strategy: leaders late in the race play track position (two tyres, or
			# fuel only if it'll make it); cars further back take four and charge.
			var pos: int = race.position_of(c)
			if laps_left < 10 and c.tyre_wear < 0.25 and pos <= 8 and c.has_flat() == false:
				c.pit_plan = "F" if laps_left < 6 else "2"
			elif laps_left < 30 and pos <= 5 and c.tyre_wear < 0.3:
				c.pit_plan = "2"
			else:
				c.pit_plan = "4"
			if c.has_flat():
				c.pit_plan = "4"
			c.want_pit = true


func _assign_lanes() -> void:
	# Choose rule: each car picks a lane at the cone; order within a lane follows
	# the running order.
	for c in race.order:
		if c.towed or lane_choice.has(c):
			continue
		if c.is_player and not c.ai_driving_caution_choice:
			lane_choice[c] = player_lane_choice
		else:
			lane_choice[c] = 0 if randf() < 0.62 else 1


# --- driving under caution --------------------------------------------------------

## Target (speed, lane) for a car under caution. Returns [target_speed, lane].
## Single file behind the pace car (each car simply follows the one ahead, see
## race.gd); cars that are ahead of the pace car go round to the tail. From "one to
## go" the line splits into two lanes by the choose rule.
func caution_drive(c: Node3D) -> Array:
	if c.pit_state != Pit.NONE:
		return pit_drive(c)
	if c.want_pit and pit_open:
		c.pit_state = Pit.APPROACH
		return pit_drive(c)
	var L: float = track.length
	var pv: float = pace_car.v
	var lane: float = race.lanes[lane_choice.get(c, 0)] if one_to_go else race.lanes[0]
	if not one_to_go:
		# Hold the current lane while the field slows; merge to single file only
		# where there's room.
		var here: float = race.lanes[race._nearest_lane(c.d)]
		if caution_elapsed < 14.0 or (here != race.lanes[0] and not race._lane_clear(c, race.lanes[0])):
			lane = here
	# Scoring is frozen at the caution: a car that is physically ahead of cars
	# scored ahead of it (typically lapped cars in front of the leader) moves to the
	# outside and lets the line go by, so it ends up where it's scored.
	var ahead_of_pace: float = fposmod(c.s() - pace_car.s() + L * 0.5, L) - L * 0.5
	var yielding: bool = ahead_of_pace > -8.0 and ahead_of_pace < L * 0.45
	if caution_elapsed < 14.0:
		yielding = false
	elif not yielding:
		var my_rank: int = race.position_of(c)
		var nbl: Array = c.nb
		for q in range(0, nbl.size(), 2):
			var o: Node3D = nbl[q]
			if o.pit_state != Pit.NONE or o.out:
				continue
			if nbl[q + 1] < -2.0 and race.position_of(o) < my_rank:
				yielding = true
				break
	# Everyone lifts and coasts down together rather than jumping on the brakes.
	var coast: float = max(pv * 1.7, 95.0 - 2.5 * caution_elapsed)
	if yielding:
		var out_lane: float = race.lanes[2]
		if abs(c.d - out_lane) > 1.5 and not race._lane_clear(c, out_lane):
			out_lane = race.lanes[race._nearest_lane(c.d)]
		return [min(pv * 0.55, coast), out_lane]
	# Close up to the car ahead (race.gd's follower logic does the spacing).
	return [min(pv * 1.7, coast), lane]


func pit_drive(c: Node3D) -> Array:
	var res := _pit_drive(c)
	if c.pit_state >= Pit.LANE and c.pit_state != Pit.SERVICE:
		# Queue behind the car ahead on pit road.
		var nbl: Array = c.nb
		for q in range(0, nbl.size(), 2):
			var o: Node3D = nbl[q]
			if o.pit_state < Pit.LANE or o.pit_state == Pit.SERVICE:
				continue
			var g: float = nbl[q + 1]
			if g > 0.0 and g < 14.0 and abs(o.kin_d - res[1]) < 1.2:
				res[0] = min(res[0], max(o.v - (14.0 - g) * 0.8, 0.0))
	return res


func _pit_drive(c: Node3D) -> Array:
	var L: float = track.length
	var ss: float = c.s()
	var pin: float = track.pit_in_s()
	var lane_d: float = track.pit_lane_d()
	match c.pit_state:
		Pit.APPROACH:
			var to_entry: float = fposmod(pin - ss, L)
			if (to_entry > L * 0.5 or to_entry < track.PIT_LANE_EXT - 10.0) and c.d < track.inner_edge():
				# Onto the pit entry lane: pit road driving is automatic from here.
				c.pit_state = Pit.LANE
				message_for(c, "ON PIT ROAD", "pit")
			# Slow early, drop to the apron, then onto the pit entry lane.
			var target: float = max(pit_speed, sqrt(pit_speed * pit_speed + 2.0 * 6.0 * max(to_entry - 60.0, 0.0)))
			var lane: float = race.lanes[0]
			if flag == Flag.YELLOW:
				# Stay at caution pace in the line until peeling off.
				target = min(target, pace_car.v * 1.15)
				var here: float = race.lanes[race._nearest_lane(c.d)]
				lane = race.lanes[0] if (caution_elapsed >= 14.0 and race._lane_clear(c, race.lanes[0])) else here
			if to_entry < 420.0 and (abs(c.d - race.lanes[0]) < 1.5 or c.d < race.lanes[0]):
				lane = track.apron_edge() + 1.5
			if to_entry < 160.0:
				lane = lane_d + 1.6
			return [target, lane]
		Pit.LANE:
			var to_box: float = fposmod(box_s(c) - ss, L)
			if to_box > L * 0.5:
				to_box = 0.0
			var to_line: float = fposmod(pin - ss, L)
			if to_line < L * 0.5 and to_line > 0.0:
				# Still on the entry lane: slow to pit road speed by the line.
				return [max(pit_speed, sqrt(pit_speed * pit_speed + 2.0 * 6.0 * to_line) * 0.9), lane_d + 1.6]
			if to_box < 1.5 and c.v < 3.0:
				_start_service(c)
				return [0.0, lane_d - 1.6]
			var t2: float = min(pit_speed, sqrt(max(2.0 * 5.0 * (to_box - 1.0), 0.0)) + 0.5)
			if OS.get_environment("PITDBG") != "" and c.v < 1.0:
				print("pitdbg #%s to_box=%.1f box=%.0f s=%.0f v=%.2f t2=%.2f" % [c.team.num, to_box, box_s(c), ss, c.v, t2])
			return [t2, lane_d - 1.6 if to_box < 30.0 else lane_d + 1.6]
		Pit.SERVICE:
			c.pit_timer -= _dt
			if c.pit_timer <= 0.0:
				c.pit_state = Pit.EXIT
				message_for(c, "GO GO GO!", "pit")
			return [0.0, lane_d - 1.6]
		Pit.EXIT:
			var past_exit: float = fposmod(ss - track.pit_out_s(), L)
			if past_exit < L * 0.5 and past_exit > 0.0:
				# Accelerate up the exit lane and blend back onto the track.
				if past_exit > track.PIT_LANE_EXT and race._lane_clear(c, race.lanes[0]):
					c.pit_state = Pit.NONE
					c.want_pit = false
					if c.is_player and not c.autopilot_forced:
						c.ai = false
					return [pit_speed * 3.0, race.lanes[0]]
				if past_exit > track.PIT_LANE_EXT - 40.0 and not race._lane_clear(c, race.lanes[0]):
					return [pit_speed * 1.5, track.apron_edge() + 1.5] # wait for a gap
				return [pit_speed * 2.0, track.apron_edge() + 1.5 if past_exit > 60.0 else lane_d + 1.6]
			return [pit_speed, lane_d + 1.6]
	return [pit_speed, lane_d]


func _start_service(c: Node3D) -> void:
	c.pit_state = Pit.SERVICE
	c.v = 0.0
	c.vy = 0.0
	c.r = 0.0
	c.pitted_this_caution = true
	c.pit_timer = _service(c)
	message_for(c, "PIT STOP  %s  %.1fs" % [{"4": "4 TIRES + FUEL", "2": "2 TIRES + FUEL", "F": "FUEL ONLY"}.get(c.pit_plan, "FUEL"), c.pit_timer], "pit")


## Does the work of a stop on c (tyres, fuel, repairs, the damaged vehicle
## policy) and returns how long it took.
func _service(c: Node3D) -> float:
	var tyre_t := 0.0
	var corners: Array = []
	var compound := ""
	if c.pit_plan == "W" or (c.tyre_compound == "wet" and c.pit_plan in ["4", "2"]):
		# Switching compound means all four.
		compound = "wet" if c.pit_plan == "W" else "slick"
		c.pit_plan = "4"
	match c.pit_plan:
		"4":
			tyre_t = 10.0 + randf() * 1.6
			corners = [0, 1, 2, 3]
		"2":
			tyre_t = 5.8 + randf() * 1.0
			corners = [1, 3] # right sides
	# Any tyre that's down gets changed whatever the plan.
	for i in 4:
		if c.tyre_air[i] < 0.95 and not corners.has(i):
			corners.append(i)
			tyre_t = max(tyre_t, 5.8 if corners.size() <= 2 else 10.0)
	c.change_tyres(corners, compound)
	c.grille_block = 0.0 # the crew pulls the debris off
	var fuel_add: float = Car.FUEL_CAPACITY - c.fuel
	var fuel_t: float = fuel_add / 7.5
	c.fuel = Car.FUEL_CAPACITY
	var repair := 0.0
	if c.total_damage() > 0.05:
		repair = 6.0 + c.total_damage() * 40.0
		# Damaged vehicle policy: repairs come off a six-minute clock, and a car that
		# can't be fixed well enough to make minimum speed is out.
		if c.total_damage() > 0.12:
			if c.dvp_clock < 0.0:
				c.dvp_clock = 360.0
			c.dvp_clock -= repair
		for k in c.damage:
			c.damage[k] *= 0.4
		c._update_damage_visual()
		if c.dvp_clock >= 0.0:
			if c.dvp_clock <= 0.0:
				c.out = true
				c.out_reason = "DVP"
				message_for(c, "DAMAGED VEHICLE POLICY: OUT OF TIME - YOUR RACE IS OVER", "pit")
			elif c.total_damage() > 0.3:
				c.out = true
				c.out_reason = "DVP"
				message_for(c, "TOO MUCH DAMAGE TO MAKE MINIMUM SPEED - PARKED", "pit")
			else:
				message_for(c, "DAMAGED VEHICLE POLICY: %d:%02d OF REPAIRS LEFT" % [int(c.dvp_clock) / 60, int(c.dvp_clock) % 60], "pit")
	return max(tyre_t, fuel_t) * c.pit_crew_mult + repair


# --- quick cautions ------------------------------------------------------------------

const PLAN_NAMES := {"4": "4 TIRES + FUEL", "2": "2 TIRES + FUEL", "F": "FUEL ONLY", "W": "WET TIRES + FUEL", "": "STAY OUT"}


func _quick_tick(delta: float) -> void:
	if quick_phase == "slow":
		_quick_t += delta
		if _quick_t >= QUICK_SLOW_TIME:
			_quick_decide()
	elif quick_phase == "decide" and not _waiting.is_empty():
		# Online: a player who doesn't answer gets their crew chief's call.
		_decide_t += delta
		if _decide_t > 20.0:
			for c in _waiting:
				_calls[c] = ai_pit_call(c)
			_waiting.clear()
			if not player_pending:
				_quick_apply()
	# "decide": waiting for the player's call (the game is paused meanwhile).
	# "roll": lined up; the normal restart logic takes it from here.


func _is_human(c: Node3D) -> bool:
	return c != null and c == race.player and not c.autopilot_forced


## Every team makes its call; the player is asked (main pauses the game).
func _quick_decide() -> void:
	for c in race.cars:
		if c.out and not c.towed:
			race.tow(c)
	_freeze = _freeze.filter(func(c): return is_instance_valid(c) and not c.towed and not c.out)
	if _freeze.is_empty():
		quick_phase = ""
		return
	_waiting.clear()
	_decide_t = 0.0
	for c in _freeze:
		c.set_meta("crew_var", randf_range(-0.6, 0.6)) # this stop's crew speed, good or bad
		if not pits_enabled:
			_calls[c] = ""
		elif remote_humans.has(c):
			_waiting[c] = true # online: that player makes the call on their screen
		elif not _is_human(c):
			_calls[c] = ai_pit_call(c)
	for c in _waiting:
		remote_pit_call.emit(c, player_info(c))
	var p: Node3D = race.player
	if pits_enabled and _is_human(p) and _freeze.has(p):
		quick_phase = "decide"
		player_pending = true
		pit_call.emit(player_info())
	elif not _waiting.is_empty():
		quick_phase = "decide"
	else:
		_quick_apply()


## What the player's pit call screen shows: the choices, the crew chief's advice,
## the car's state and where each choice would put them for the restart.
func player_info(who: Node3D = null) -> Dictionary:
	var p: Node3D = who if who else race.player
	var lead: Node3D = _freeze[0]
	var laps_left: int = max(race.laps - lead.lap(), 0)
	var options: Array = ["4", "2", "F", ""]
	if track.cfg.get("road", false) and race.weather and race.weather.mode > 0:
		options.insert(2, "W")
	var est := {}
	for o in options:
		_calls[p] = o
		est[o] = _compute_order().find(p) + 1
	_calls.erase(p)
	var per_lap: float = track.length / 1000.0 * 0.5 * max(p.burn_scale, 0.01)
	return {
		"options": options,
		"names": options.map(func(o): return PLAN_NAMES[o]),
		"advice": ai_pit_call(p, true),
		"estimate": est,
		"position": _freeze.find(p) + 1,
		"field": _freeze.size(),
		"laps_left": laps_left,
		"wear": clamp(p.tyre_wear, 0.0, 1.5),
		"grip": p.tyre_grip(),
		"fuel_laps": p.fuel / max(per_lap, 0.001),
		"damage": p.total_damage(),
		"reason": _last_caution_reason,
	}


## The player's answer: the stop to make ("" stays out) and a wedge change.
func resolve_player(call: String, wedge_change: float) -> void:
	if follower:
		player_pending = false
		remote_answer.emit(call, wedge_change) # to the host
		return
	if quick_phase != "decide":
		return
	_calls[race.player] = call
	if wedge_change != 0.0:
		_adjust[race.player] = wedge_change
	player_pending = false
	if _waiting.is_empty():
		_quick_apply()


## Online (host): another player's pit call has come in.
func resolve_remote(c: Node3D, call: String, wedge_change: float) -> void:
	if quick_phase != "decide" or not _waiting.has(c):
		return
	_calls[c] = call
	if wedge_change != 0.0:
		_adjust[c] = wedge_change
	_waiting.erase(c)
	if not player_pending and _waiting.is_empty():
		_quick_apply()


## A team's pit call from the car's state, the race situation and the driver's
## character. Tyres are worth positions over the run that's left; a stop costs the
## places of the cars behind that stay out. Crew chiefs of smart drivers weigh it
## well; aggressive ones value track position; inconsistent ones guess.
func ai_pit_call(c: Node3D, advice := false) -> String:
	var lead: Node3D = _freeze[0] if not _freeze.is_empty() else leader()
	var laps_left: int = max(race.laps - lead.lap(), 0)
	var pos: int = max(_freeze.find(c) + 1, 1)
	var field: int = max(_freeze.size(), 1)
	var per_lap: float = track.length / 1000.0 * 0.5 * max(c.burn_scale, 0.01)
	var fuel_laps: float = c.fuel / max(per_lap, 0.001)
	# Running dry within a few laps makes a stop compulsory. Otherwise topping up is
	# worth what it saves later: nothing if it'll make the finish, and in proportion
	# to how much of the tank has gone if it won't.
	var need_fuel: bool = fuel_laps < min(float(laps_left), 6.0) + 1.0
	var used: float = 1.0 - c.fuel / c.FUEL_CAPACITY
	var fuel_gain: float = used * 9.0 if fuel_laps < laps_left + 1.0 else 0.0
	# Stops that aren't a choice.
	if c.has_flat() or c.total_damage() > 0.08:
		return "4"
	if track.cfg.get("road", false) and race.weather:
		var wet: float = race.weather.average_wet()
		if c.tyre_compound == "slick" and wet > 0.35:
			return "W"
		if c.tyre_compound == "wet" and wet < 0.12:
			return "4"
	if laps_left <= 2:
		return "F" if need_fuel else ""
	# Positions fresh tyres are worth over the run (worn tyres lose grip, and the
	# run to the flag or the next stop is what they're good for).
	var horizon: float = min(float(laps_left), 35.0)
	var right_wear: float = (c.tyre_wear4[1] + c.tyre_wear4[3]) * 0.5
	var gain4: float = c.tyre_wear * horizon * 0.9
	var gain2: float = right_wear * horizon * 0.62
	# Positions a stop costs: the share of the cars behind that will stay out,
	# more of them late in a race; the lead is worth extra.
	var stay_share: float = 0.3 if laps_left > 40 else (0.45 if laps_left > 15 else 0.6)
	var cost: float = float(field - pos) * stay_share + (2.5 if pos <= 3 else 0.0)
	cost = min(cost, 12.0)
	gain4 *= lerp(0.85, 1.15, c.ai_racecraft) * lerp(0.9, 1.1, c.ai_patience)
	gain2 *= lerp(0.85, 1.15, c.ai_racecraft)
	cost *= lerp(0.8, 1.3, c.ai_aggression)
	if not advice:
		var guess: float = (1.0 - c.ai_consistency) * 0.8
		gain4 *= 1.0 + randf_range(-guess, guess)
		gain2 *= 1.0 + randf_range(-guess, guess)
		cost *= 1.0 + randf_range(-guess, guess)
	var scores := {"4": gain4 + fuel_gain - cost, "2": gain2 + fuel_gain - cost * 0.8, "F": fuel_gain - cost * 0.65}
	if not need_fuel:
		scores[""] = 0.0
	var best := ""
	var best_score := -1e9
	for k in scores:
		if scores[k] > best_score:
			best_score = scores[k]
			best = k
	return best


func _laps_down(c: Node3D, lead: Node3D) -> int:
	return max(0, int(floor((lead.dist - c.dist) / track.length + 0.0001)))


## Seconds a stop takes (the same figure predicts and decides the pit road order).
func _stop_time(c: Node3D, call: String) -> float:
	var t := 0.0
	match call:
		"4", "W":
			t = 10.8
		"2":
			t = 6.4
		"F":
			t = (c.FUEL_CAPACITY - c.fuel) / 7.5
	t = max(t, (c.FUEL_CAPACITY - c.fuel) / 7.5)
	if c.total_damage() > 0.05:
		t += 6.0 + c.total_damage() * 40.0
	return t * c.pit_crew_mult + float(c.get_meta("crew_var", 0.0))


## The restart order. Scoring freezes when the caution comes out; cars that stay
## out keep their places, cars that pit come off pit road in the order they get
## out (where they went in plus how long the stop took) behind them. Then the free
## pass car, the other lapped cars, and the wave-arounds at the back.
func _compute_order() -> Array:
	var lead: Node3D = _freeze[0]
	var stay: Array = []
	var pitters: Array = []
	var lapped: Array = []
	var waved: Array = []
	var lucky: Node3D = null
	var entry := 0
	for c in _freeze:
		var call: String = _calls.get(c, "")
		var down: int = _laps_down(c, lead)
		if down == 0:
			if call == "":
				stay.append(c)
			else:
				pitters.append([c, entry * 0.45 + PIT_ROAD_LOSS + _stop_time(c, call)])
				entry += 1
		elif lucky == null and down == 1 and c != _cause:
			lucky = c
		elif call == "":
			waved.append(c)
		else:
			lapped.append(c)
	pitters.sort_custom(func(a, b): return a[1] < b[1])
	var out: Array = stay.duplicate()
	for pp in pitters:
		out.append(pp[0])
	if lucky:
		out.append(lucky)
	out.append_array(lapped)
	out.append_array(waved)
	return out


## Makes the stops and lines the field up for the restart.
func _quick_apply() -> void:
	var L: float = track.length
	var lead: Node3D = _freeze[0]
	var order := _compute_order()
	# Laps down, worked out before anyone moves; the free pass and wave-arounds get one back.
	var down := {}
	var gifted := {}
	for c in order:
		down[c] = _laps_down(c, lead)
	var pitted := 0
	var lines: Array = []
	var lucky: Node3D = _lucky(down)
	for c in order:
		var call: String = _calls.get(c, "")
		if down[c] > 0 and (call == "" or c == lucky):
			down[c] -= 1
			gifted[c] = true
		c.want_pit = false
		c.pit_state = Pit.NONE
		c.pitted_this_caution = call != ""
		if call != "":
			c.pit_plan = call
			_service(c)
			pitted += 1
		if _adjust.has(c):
			c.wedge = clamp(c.wedge + float(_adjust[c]), -900.0, 900.0)
	# Line up double file, the leader QUICK_RESTART_BEFORE short of the line.
	var base: float = ceil((lead.dist + 250.0 + QUICK_RESTART_BEFORE) / L) * L - QUICK_RESTART_BEFORE
	if overtime:
		race.laps = max(race.laps, int(floor(base / L)) + 2)
	lane_choice.clear()
	for k in order.size():
		var c: Node3D = order[k]
		var row: int = k / 2
		var lane: int = k % 2
		c.dist = base - row * 9.0 - lane * 1.0 - down[c] * L
		c.lap_idx = c.lap()
		c.set_meta("lap_void", true) # the lap the field was lined up in isn't a real lap time
		c.tumbling = false
		c.v = pace_speed()
		c.vy = 0.0
		c.r = 0.0
		c.yaw = 0.0
		c.d = race.lanes[lane]
		c.ai_lane = c.d
		c.pace_lane = c.d
		c.kin_d = c.d
		c.kin_v = c.v
		c.ai_reverse = 0.0
		c.reset_chassis()
		c.sync_visual()
		lane_choice[c] = lane
	race._update_order()
	# Stages the leader passed while the field was lined up still count.
	var lead_now: Node3D = order[0]
	while stage <= stage_ends.size() and lead_now.lap() >= stage_ends[stage - 1]:
		_end_stage(false)
	# The pace car leads them to the restart zone, then peels off.
	pace_car.dist = base + 45.0
	pace_car.d = race.lanes[0]
	pace_car.pace_lane = race.lanes[0]
	pace_car.v = pace_speed()
	pace_car.visible = true
	pace_car.sync_visual()
	race.clear_debris()
	one_to_go = true
	choosing = false
	pit_open = false
	quick_phase = "roll"
	if weather_hold:
		# Wet oval: circle behind the pace car until it's dry (the full caution logic).
		restart_armed = false
		one_to_go = false
		quick_phase = ""
		caution_laps = 1
		_pace_last_lap = pace_car.lap()
	else:
		restart_armed = true
	# The board: who pitted, who stayed out, and how it came out for the player.
	var p: Node3D = race.player
	var stay_out := 0
	for c in order:
		if _calls.get(c, "") == "" and down[c] == 0 and not gifted.has(c):
			stay_out += 1
	lines.append("PIT STOPS: %d PITTED, %d STAYED OUT" % [pitted, stay_out])
	if lead_now:
		lines.append("LEADER: #%s %s (%s)" % [lead_now.team.num, lead_now.team.driver, PLAN_NAMES[_calls.get(lead_now, "")]])
	if p and order.has(p):
		var before: int = _freeze.find(p) + 1
		var after: int = order.find(p) + 1
		var delta: int = before - after
		var call: String = _calls.get(p, "")
		lines.append("YOU: %s - RESTART %s %s" % [PLAN_NAMES[call], _ordinal(after), ("(+%d)" % delta) if delta > 0 else (("(%d)" % delta) if delta < 0 else "")])
		if gifted.has(p):
			lines.append("YOU GET YOUR LAP BACK")
	pit_report.emit(lines)
	var rows: Array = []
	for c in order:
		rows.append([race.cars.find(c), c.dist, c.d, c.lap_idx, _calls.get(c, ""), float(_adjust.get(c, 0.0))])
	lined_up.emit(rows)
	message.emit("RESTART COMING UP - DOUBLE FILE", "pit")


## Online: the flag state as the host has it, for the other players' screens.
func remote_state() -> Dictionary:
	return {"flag": int(flag), "qp": quick_phase, "otg": one_to_go, "ra": restart_armed, "po": pit_open,
		"stage": stage, "laps": race.laps, "cc": caution_count, "ch": choosing, "ot": overtime,
		"flc": final_lap_caution, "pace": pace_car.visible}


const FLAG_NAMES := ["GREEN", "YELLOW", "WHITE", "CHECKERED"]


## Online (a player's screen): take on the host's flag state.
func apply_remote_state(st: Dictionary) -> void:
	var was: int = flag
	flag = int(st.flag) as Flag
	quick_phase = String(st.qp)
	one_to_go = bool(st.otg)
	restart_armed = bool(st.ra)
	pit_open = bool(st.po)
	stage = int(st.stage)
	race.laps = int(st.laps)
	caution_count = int(st.cc)
	choosing = bool(st.ch)
	overtime = bool(st.ot)
	if bool(st.flc) and not final_lap_caution:
		final_lap_caution = true
		race.freeze_finish()
	pace_car.visible = bool(st.pace)
	pace_car.process_mode = Node.PROCESS_MODE_INHERIT if pace_car.visible else Node.PROCESS_MODE_DISABLED
	if flag == Flag.YELLOW and was != Flag.YELLOW:
		caution_elapsed = 0.0
		for c in race.cars:
			c.pitted_this_caution = false
	if flag != was:
		flag_changed.emit(FLAG_NAMES[flag])


## Online (a player's screen): the host lined the field up for the restart.
## `mine` is this player's car: it makes the stop it called.
func apply_lineup(rows: Array, mine: Node3D) -> void:
	for r in rows:
		var idx: int = int(r[0])
		if idx < 0 or idx >= race.cars.size():
			continue
		var c: Node3D = race.cars[idx]
		c.dist = float(r[1])
		c.d = float(r[2])
		c.lap_idx = int(r[3])
		c.set_meta("lap_void", true)
		c.v = pace_speed()
		c.vy = 0.0
		c.r = 0.0
		c.yaw = 0.0
		c.ai_lane = c.d
		c.pace_lane = c.d
		c.kin_d = c.d
		c.kin_v = c.v
		c.want_pit = false
		c.pit_state = Pit.NONE
		var call: String = String(r[4])
		c.pitted_this_caution = call != ""
		if c == mine:
			if call != "":
				c.pit_plan = call
				_service(c)
			if float(r[5]) != 0.0:
				c.wedge = clamp(c.wedge + float(r[5]), -900.0, 900.0)
		if not c.remote:
			c.reset_chassis()
		c.sync_visual()
	race._update_order()


func _lucky(down: Dictionary) -> Node3D:
	for c in _freeze:
		if down.get(c, 0) == 1 and c != _cause:
			return c
	return null


func _ordinal(n: int) -> String:
	if n % 100 >= 11 and n % 100 <= 13:
		return "%dTH" % n
	match n % 10:
		1: return "%dST" % n
		2: return "%dND" % n
		3: return "%dRD" % n
	return "%dTH" % n


func message_for(c: Node3D, text: String, kind: String) -> void:
	if c.is_player:
		message.emit(text, kind)


## Green-flag pit stop handling (the car drives itself down pit road).
func green_pit(c: Node3D) -> Array:
	if c.pit_state == Pit.NONE:
		c.pit_state = Pit.APPROACH
	return pit_drive(c)


# --- spotter ----------------------------------------------------------------------

func _spotter(delta: float) -> void:
	var p: Node3D = race.player
	if p == null or p.towed or p.finished:
		return
	_spot_timer -= delta
	var low := false
	var high := false
	var nbl: Array = p.nb
	for q in range(0, nbl.size(), 2):
		var o: Node3D = nbl[q]
		if o.pit_state != Pit.NONE:
			continue
		var g: float = nbl[q + 1]
		var side: float = o.d - p.d
		if abs(g) < 5.5 and abs(side) < 4.2 and abs(side) > 1.0:
			if side < 0.0:
				low = true
			else:
				high = true
	var state := "3 WIDE" if (low and high) else ("CAR LOW" if low else ("CAR HIGH" if high else "CLEAR"))
	if state != _spot_state:
		if state == "CLEAR" and _spot_state != "":
			message.emit("CLEAR", "spotter")
		elif state != "CLEAR":
			message.emit(state, "spotter")
		_spot_state = state


# --- points -----------------------------------------------------------------------

func finishing_points(place: int, c: Node3D) -> int:
	var base: int = POINTS[min(place - 1, POINTS.size() - 1)]
	return base + c.stage_points
