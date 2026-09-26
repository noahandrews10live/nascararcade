extends Node
## Race control: flags, cautions and the pace car, pit road, the free pass and
## wave-arounds, double-file restarts with the choose rule, stages, overtime and
## points. Owned by race.gd; it steers the AI (and the player's car on autopilot)
## whenever the field isn't racing under green.

signal flag_changed(flag: String)
signal message(text: String, kind: String) # kind: flag, spotter, pit, stage, info

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
var debris_rate := 0.012 # chance per green lap of a debris caution

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
var final_lap_caution := false

# pit road
var pit_speed := 20.0
var box_spacing := 10.0

# spotter
var _spot_state := ""
var _spot_timer := 0.0
var _dt := 1.0 / 60.0


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
	_update_pace_car(delta)
	match flag:
		Flag.GREEN, Flag.WHITE:
			_green_tick(delta)
		Flag.YELLOW:
			caution_elapsed += delta
			_caution_tick(delta)
	if flag != Flag.CHECKERED:
		_spotter(delta)


func checkered() -> void:
	flag = Flag.CHECKERED
	flag_changed.emit("CHECKERED")


func _green_tick(delta: float) -> void:
	_green_since += delta
	if not cautions_enabled:
		return
	for c in race.cars:
		if c.towed or c.finished or c.pit_state != Pit.NONE:
			continue
		var bad: bool = c.spinning or c.out or (c.v < 6.0 and _green_since > 6.0 and not c.pace_mode)
		if bad:
			_incident_timers[c] = _incident_timers.get(c, 0.0) + delta
			if _incident_timers[c] > (0.6 if c.spinning or c.out else 2.5):
				if OS.is_debug_build() and OS.get_environment("RC_DEBUG") != "":
					print("caution car #%s spin=%s out=%s v=%.1f pit=%d d=%.1f s=%.0f" % [c.team.num, c.spinning, c.out, c.v, c.pit_state, c.d, c.s()])
				throw_caution("ACCIDENT" if c.total_damage() > 0.1 or c.out else "SPIN", c)
				return
		else:
			_incident_timers.erase(c)


## Called by race.gd when the leader completes a lap under green.
func on_leader_lap(lap_done: int) -> void:
	if not enabled:
		return
	if flag == Flag.YELLOW:
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


func _end_stage() -> void:
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
	throw_caution("STAGE %d END" % (stage - 1), null)


func throw_caution(reason: String, who: Node3D) -> void:
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
	var pl: int = pace_car.lap()
	if pl > _pace_last_lap and not restart_armed:
		_pace_last_lap = pl
		caution_laps += 1
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
			c.pit_plan = "4" if c.tyre_wear > 0.2 or laps_left > 25 or randf() < 0.6 else "2"
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
		for o in race.cars:
			if o == c or o.towed or o.pit_state != Pit.NONE or o.out:
				continue
			if race.position_of(o) < my_rank:
				var g: float = race._gap(c, o)
				if g < -2.0 and g > -L * 0.45:
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
	var tyre_t := 0.0
	match c.pit_plan:
		"4":
			tyre_t = 10.0 + randf() * 1.6
			c.tyre_wear = 0.0
		"2":
			tyre_t = 5.8 + randf() * 1.0
			c.tyre_wear *= 0.5
	var fuel_add: float = Car.FUEL_CAPACITY - c.fuel
	var fuel_t: float = fuel_add / 7.5
	c.fuel = Car.FUEL_CAPACITY
	var repair := 0.0
	if c.total_damage() > 0.05:
		repair = 6.0 + c.total_damage() * 40.0
		for k in c.damage:
			c.damage[k] *= 0.4
		c._update_damage_visual()
	c.pit_timer = max(tyre_t, fuel_t) + repair
	message_for(c, "PIT STOP  %s  %.1fs" % [{"4": "4 TIRES + FUEL", "2": "2 TIRES + FUEL", "F": "FUEL ONLY"}.get(c.pit_plan, "FUEL"), c.pit_timer], "pit")


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
	for o in race.cars:
		if o == p or o.towed or o.pit_state != Pit.NONE:
			continue
		var g: float = race._gap(p, o)
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
