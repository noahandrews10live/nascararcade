extends Node3D
## Runs a race: spawns the field, drives the AI, works out the aero between cars
## (drafting, side-drafting, dirty air), resolves car-to-car contact as rigid-body
## impulses, and keeps lap timing and the running order.

signal lap_completed(car: Node3D, laps_done: int, lap_time: float)
signal car_finished(car: Node3D, place: int)
signal incident(car: Node3D, kind: String)

const Car := preload("res://scripts/car.gd")
const SkidMarks := preload("res://scripts/skid_marks.gd")

var track: Node3D
var cars: Array[Node3D] = []
var order: Array[Node3D] = [] # current running order
var player: Node3D = null
var player2: Node3D = null # split-screen second player
var laps := 3
var time := 0.0
var running := false
var finish_count := 0
var rng := RandomNumberGenerator.new()
var lanes: Array[float] = []
var arcade := false # rubber-banding for the arcade mode only
var field_size := 40
var arcade_setup := false # set before setup() for arcade races (ignores sim settings)
var career := false # apply the career car's R&D level to the player
var debug_no_lane_changes := false
var control: Node = null # race_control.gd when the full rules are on
var _tick_count := 0

# Replay recording: per frame, for every car (and the pace car): dist, d, yaw, v, visible.
const REC_HZ := 10.0
const REC_MAX := 6000 # frames kept (10 minutes)
const REC_STRIDE := 9 # dist, d, yaw, v, visible, roll, pitch, heave, flags
## Moments worth a highlight: {t (recording clock), car (index), kind}.
var highlights: Array = []
var _leader_rec: Node3D
var rec_times := PackedFloat32Array()
var rec_data := PackedFloat32Array()
var rec_clock := 0.0
var _rec_next := 0.0
var rec_cars: Array[Node3D] = []
var wear_scale := 1.0 # fuel burn / tyre wear multiplier so short races still need pit strategy


## `grid` (optional) is the starting order as team indices, e.g. from qualifying.
var skids: MultiMeshInstance3D
var weather: Node = null # weather.gd, when the race has time and weather running
## Debris on the track from wrecks: [{s, d, age}]. Running over it can cut a tyre
## or block the grille; a lot of it brings out the caution.
var debris: Array = []
var _debris_mm: MultiMeshInstance3D
const MAX_DEBRIS := 48

func setup(trk: Node3D, player_team: int, lap_count: int, size := 40, grid: Array = [], player2_team := -1) -> void:
	track = trk
	track.rubber_laps = 0.0
	skids = SkidMarks.new()
	add_child(skids)
	_build_debris_mesh()
	laps = lap_count
	field_size = size
	if Game.debug_seed != 0:
		rng.seed = Game.debug_seed
		seed(Game.debug_seed)
	else:
		rng.randomize()
	var hw: float = track.width * 0.5
	var lane_w: float = min(4.0, (track.width - 3.0) / 3.0)
	lanes = [-hw + 2.2, -hw + 2.2 + lane_w, -hw + 2.2 + lane_w * 2.0]
	if Game.teams.size() < field_size:
		Game._fill_teams()
	var team_ids: Array[int] = []
	for i in Game.teams.size():
		if i != player_team and i != player2_team:
			team_ids.append(i)
	team_ids.shuffle()
	var grid_player: int = min(int(track.cfg.grid_player), field_size - 1)
	var roster: Array[int] = []
	if grid.size() >= field_size:
		for p in field_size:
			roster.append(int(grid[p]))
		grid_player = roster.find(player_team)
	else:
		for p in field_size:
			if player_team >= 0 and p == grid_player:
				roster.append(player_team)
			else:
				roster.append(team_ids.pop_back())
	var grid_p2 := -1
	if player2_team >= 0:
		grid_p2 = grid_player + 1 if grid_player + 1 < field_size else grid_player - 1
		roster[grid_p2] = player2_team
	for p in roster.size():
		var c: Node3D = Car.new()
		c.name = "Car%s" % Game.teams[roster[p]].num
		add_child(c)
		c.setup(Game.teams[roster[p]], track)
		c.is_player = (player_team >= 0 and p == grid_player) or p == grid_p2
		c.ai = not c.is_player
		c.assisted = true
		c.manual = Game.manual_shift
		c.ai_skill = float(Game.teams[roster[p]].get("skill", rng.randf_range(0.955, 0.99))) * (Game.ai_skill_scale() / 0.985 if not arcade_setup else 1.0)
		c.damage_mult = 1.0 if (Game.settings.damage == 1 or arcade_setup) else 0.0
		# Each driver has a character: the better ones are steadier and smarter.
		var talent: float = clamp((c.ai_skill - 0.95) / 0.04, 0.0, 1.0)
		c.ai_patience = rng.randf_range(0.2, 0.9)
		c.ai_consistency = clamp(rng.randf_range(0.65, 0.9) + talent * 0.1, 0.6, 0.99)
		c.ai_racecraft = clamp(rng.randf_range(0.3, 0.8) + talent * 0.2, 0.2, 1.0)
		if arcade_setup:
			c.ai_consistency = 0.97 # the arcade game is against the clock: no pile-ups ahead
		c.ai_aggression = rng.randf_range(0.2, 0.9)
		c.set_meta("grid", p)
		c.set_meta("idx", cars.size())
		c.tyre_failed.connect(_on_tyre_failed)
		cars.append(c)
		if p == grid_p2:
			player2 = c
			c.assisted = Game.assists
			c.assist_level = Game.assist_level
			Game.apply_setup(c)
		elif c.is_player:
			player = c
			c.assisted = Game.assists or arcade_setup
			c.assist_level = 1.0 if arcade_setup else Game.assist_level
			if not arcade_setup:
				Game.apply_setup(c)
			if career:
				Game.apply_career(c)
	order = cars.duplicate()


## Turns on cautions, pit stops, stages and points.
func enable_rules() -> void:
	control = load("res://scripts/race_control.gd").new()
	control.name = "RaceControl"
	add_child(control)
	control.setup(self)
	# Short races get proportionally thirstier cars and faster tyre wear so pit
	# strategy still matters (a tank should last ~40% of the race).
	var race_km: float = laps * track.length / 1000.0
	wear_scale = clamp(150.0 / max(race_km * 0.4, 1.0), 1.0, 8.0)
	if Game.settings.wear == 0:
		wear_scale = 0.0
	for c in cars:
		c.burn_scale = wear_scale
	control.cautions_enabled = Game.settings.cautions == 1


func give_lap(c: Node3D) -> void:
	c.dist += track.length
	c.lap_idx += 1


func tow(c: Node3D) -> void:
	c.towed = true
	c.visible = false


## Final-lap caution: the running order stands as the finish.
func freeze_finish() -> void:
	for c in order:
		if not c.finished:
			finish_count += 1
			c.finished = true
			c.finish_time = time
			c.finish_order = finish_count
			if c.is_player:
				c.ai = true
			car_finished.emit(c, finish_count)


## Places the field in a two-wide rolling start with the leader at `leader_dist`.
func grid_up(leader_dist: float, pace_speed: float) -> void:
	for c in cars:
		var p: int = c.get_meta("grid")
		var row := p / 2
		c.dist = leader_dist - row * 9.0 - (p % 2) * 1.0
		c.pace_lane = lanes[0] if p % 2 == 0 else lanes[1]
		c.d = c.pace_lane
		c.ai_lane = c.pace_lane
		c.v = pace_speed
		c.pace_speed = pace_speed
		c.pace_mode = true
		c.yaw = 0.0
		c.lap_idx = c.lap()
		c.sync_visual()
	_update_order()


func go_green() -> void:
	running = true
	for c in cars:
		c.pace_mode = false


func tick(delta: float) -> void:
	time += delta if running else 0.0
	_record(delta)
	_build_neighbors()
	_update_detail()
	if weather and running:
		weather.tick(delta)
	if control:
		control.tick(delta)
	_aero(delta)
	_tick_count += 1
	var ai_turn := _tick_count % 2
	for ci in cars.size():
		var c: Node3D = cars[ci]
		if c.towed:
			continue
		# The AI thinks at 30 Hz (half the field each tick); cars in the pit box
		# every tick so the stop timer runs at full speed.
		if c.ai and running and (ci % 2 == ai_turn or c.pit_state == 3 or c.is_player):
			_drive_ai(c, delta if (c.pit_state == 3 or c.is_player) else delta * 2.0)
		if arcade and player and c != player and running and not player.finished:
			var gap: float = c.dist - player.dist
			var target := 1.0
			if gap > 60.0:
				target = lerp(1.0, 0.93, clamp((gap - 60.0) / 250.0, 0.0, 1.0))
			elif gap < -80.0:
				target = lerp(1.0, 1.05, clamp((-gap - 80.0) / 250.0, 0.0, 1.0))
			c.rubber = move_toward(c.rubber, target, delta * 0.02)
			c.drag_mult *= 1.0 / pow(c.rubber, 3.0)
		if c.remote:
			c.step_remote(delta)
			continue
		var was_out: bool = c.out
		var was_spin: bool = c.spinning
		c.step(delta)
		skids.track_car(c)
		if c.wall_hit > 9.0 or (c.tumbling and randf() < delta * 3.0):
			spawn_debris(c.s(), c.d, 1 + int(c.wall_hit > 15.0))
		if c.has_flat() and c.ai and not c.is_player and c.pit_state == 0 and control and control.enabled and not c.out:
			c.want_pit = true
			c.pit_plan = "4"
		elif c.ai and not c.is_player and c.pit_state == 0 and control and control.enabled and not c.out and maxf(maxf(c.tyre_wear4[0], c.tyre_wear4[1]), maxf(c.tyre_wear4[2], c.tyre_wear4[3])) > 0.85 and laps - control.leader().lap() > 2:
			c.want_pit = true # green-flag stop before the tyres go to the cords
			c.pit_plan = "4"
		elif c.grille_block > 0.2 and c.engine_temp > 132.0 and c.ai and not c.is_player and c.pit_state == 0 and control and control.enabled and not c.out:
			c.want_pit = true # get the debris pulled off the grille
			c.pit_plan = "F"
		elif weather and c.ai and not c.is_player and c.pit_state == 0 and control and control.enabled and track.cfg.get("road", false):
			var w: float = weather.average_wet()
			if c.tyre_compound == "slick" and w > 0.35:
				c.want_pit = true
				c.pit_plan = "W"
			elif c.tyre_compound == "wet" and w < 0.12:
				c.want_pit = true
				c.pit_plan = "4"
		if c.pit_state == 3: # in the pit box
			c.v = 0.0
			c.vy = 0.0
			c.r = 0.0
		if c.out and not was_out:
			incident.emit(c, "out")
			highlights.append({"t": rec_clock, "car": ci, "kind": "OUT: %s" % c.out_reason})
		elif c.spinning and not was_spin:
			incident.emit(c, "spin")
			highlights.append({"t": rec_clock, "car": ci, "kind": "FLIP" if c.tumbling else "SPIN"})
	_collide()
	if not debris.is_empty():
		_debris_tick(delta)
	# Laps / finish
	for c in cars:
		var li: int = c.lap()
		if li > c.lap_idx:
			c.lap_idx = li
			track.rubber_laps = max(track.rubber_laps, float(li))
			if li == 0:
				c.lap_start_time = time
			elif li >= 1 and not c.finished:
				if c == order[0]:
					c.laps_led += 1
					if control:
						control.on_leader_lap(li)
				var lt: float = time - c.lap_start_time
				c.lap_start_time = time
				c.last_lap = lt
				if c.best_lap <= 0.0 or lt < c.best_lap:
					c.best_lap = lt
				if c.is_player:
					c.end_lap_trace(lt)
				lap_completed.emit(c, li, lt)
				if li >= laps:
					if finish_count == 0 and control:
						control.checkered()
					finish_count += 1
					c.finished = true
					c.finish_time = time
					c.finish_order = finish_count
					if c.is_player:
						c.ai = true # autopilot for the cool-down lap
					car_finished.emit(c, finish_count)
	_update_order()


func _record(delta: float) -> void:
	rec_clock += delta
	if rec_clock < _rec_next:
		return
	_rec_next = rec_clock + 1.0 / REC_HZ
	if rec_cars.is_empty():
		rec_cars = cars.duplicate()
		if control:
			rec_cars.append(control.pace_car)
	rec_times.append(rec_clock)
	for c in rec_cars:
		rec_data.append(c.dist)
		rec_data.append(c.d)
		rec_data.append(c.yaw)
		rec_data.append(c.v)
		rec_data.append(1.0 if c.visible else 0.0)
		var roll: float = c.chassis_roll
		var pitch: float = c.chassis_pitch
		var z: float = c.chassis_z
		if c.tumbling:
			# Flips replay as big roll / pitch / height on the normal pose.
			var tr: Transform3D = track.car_transform(c.s(), c.d, c.yaw)
			var e: Vector3 = (tr.basis.inverse() * c.t_basis).get_euler()
			pitch = e.x
			roll = e.z
			var su: Array = c._surface_under(c.t_pos, c.s())
			z = (c.t_pos - (su[2] as Vector3)).dot(su[3]) - Car.CG_H
		rec_data.append(roll)
		rec_data.append(pitch)
		rec_data.append(z)
		rec_data.append(float(int(c.spinning) | (int(c.total_damage() > 0.3 or c.out) << 1) | (int(c.scraping) << 2)))
	# Lead changes are highlights too.
	if not order.is_empty() and order[0] != _leader_rec:
		if _leader_rec != null and running:
			highlights.append({"t": rec_clock, "car": cars.find(order[0]), "kind": "LEAD CHANGE"})
		_leader_rec = order[0]
	if rec_times.size() > REC_MAX + 600:
		var drop := 600
		rec_times = rec_times.slice(drop)
		rec_data = rec_data.slice(drop * rec_cars.size() * REC_STRIDE)


## Puts every car where it was at recording time t (interpolated).
## Blend every car between its last two physics positions (see Car.interpolate).
func interpolate(f: float) -> void:
	for c in cars:
		c.interpolate(f)
	if control and control.pace_car.visible:
		control.pace_car.interpolate(f)


func replay_apply(t: float) -> void:
	var n := rec_times.size()
	if n < 2:
		return
	var lo := 0
	var hi := n - 1
	t = clamp(t, rec_times[0], rec_times[n - 1])
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if rec_times[mid] <= t:
			lo = mid
		else:
			hi = mid
	var f: float = (t - rec_times[lo]) / max(rec_times[hi] - rec_times[lo], 0.0001)
	var stride := rec_cars.size() * REC_STRIDE
	for k in rec_cars.size():
		var c: Node3D = rec_cars[k]
		var a := lo * stride + k * REC_STRIDE
		var b := hi * stride + k * REC_STRIDE
		c.tumbling = false
		c.dist = lerp(rec_data[a], rec_data[b], f)
		c.d = lerp(rec_data[a + 1], rec_data[b + 1], f)
		c.yaw = lerp_angle(rec_data[a + 2], rec_data[b + 2], f)
		c.v = lerp(rec_data[a + 3], rec_data[b + 3], f)
		c.visible = rec_data[a + 4] > 0.5
		c.chassis_roll = lerp_angle(rec_data[a + 5], rec_data[b + 5], f)
		c.chassis_pitch = lerp_angle(rec_data[a + 6], rec_data[b + 6], f)
		c.chassis_z = lerp(rec_data[a + 7], rec_data[b + 7], f)
		var flags := int(rec_data[a + 8])
		c.spinning = flags & 1
		c.r = 0.0
		c.slide = 1.0 if flags & 1 else 0.0
		c.scrub = 0.0
		c.scraping = (flags & 4) != 0
		c.sync_visual(false)


## Neighbour index, rebuilt once per tick: every car gets a flat list
## [other, gap, other, gap, ...] of the cars within 170 m ahead / 60 m behind (gap > 0 =
## ahead). Everything that looks at nearby cars uses it instead of scanning the field.
const NB_AHEAD := 170.0
const NB_BEHIND := 60.0
## At most this many cars ahead / behind go in a car's list, so a bunched-up
## field (cautions, restarts) doesn't make every per-car loop long.
const NB_MAX_AHEAD := 12
const NB_MAX_BEHIND := 8

var _nb_cars: Array = []
var _nb_s := PackedFloat32Array()


## Cars well away from a player run their physics at a lower rate.
func _update_detail() -> void:
	var L: float = track.length
	for c in cars:
		var far := true
		for p in [player, player2]:
			if p != null and abs(fposmod(c.dist - p.dist + L * 0.5, L) - L * 0.5) < 150.0:
				far = false
		c.far_away = far and not c.is_player


func _build_neighbors() -> void:
	## Cars sorted by track position; the order barely changes between ticks, so
	## an insertion sort over the previous order is close to linear.
	var L: float = track.length
	if _nb_cars.size() != cars.size():
		_nb_cars = cars.duplicate()
	var m := _nb_cars.size()
	_nb_s.resize(m)
	for i in m:
		_nb_s[i] = _nb_cars[i].s()
	for i in range(1, m):
		var sv: float = _nb_s[i]
		var cv = _nb_cars[i]
		var j := i - 1
		while j >= 0 and _nb_s[j] > sv:
			_nb_s[j + 1] = _nb_s[j]
			_nb_cars[j + 1] = _nb_cars[j]
			j -= 1
		_nb_s[j + 1] = sv
		_nb_cars[j + 1] = cv
	var idx: Array[int] = []
	for i in m:
		if not _nb_cars[i].towed:
			idx.append(i)
		else:
			_nb_cars[i].nb = []
	var n := idx.size()
	for k in n:
		var i: int = idx[k]
		var s0: float = _nb_s[i]
		var lst: Array = []
		var used := 0
		for step in range(1, mini(n, NB_MAX_AHEAD + 1)):
			var e: int = idx[(k + step) % n]
			var g: float = _nb_s[e] - s0
			if g < 0.0:
				g += L
			if g > NB_AHEAD:
				break
			lst.append(_nb_cars[e])
			lst.append(g)
			used = step
		for step in range(1, mini(n - used, NB_MAX_BEHIND + 1)):
			var e: int = idx[(k - step + n) % n]
			var g: float = _nb_s[e] - s0
			if g > 0.0:
				g -= L
			if g < -NB_BEHIND:
				break
			lst.append(_nb_cars[e])
			lst.append(g)
		_nb_cars[i].nb = lst


func _gap(from: Node3D, to: Node3D) -> float:
	## Distance along track from `from` forward to `to` (-L/2 .. L/2).
	var L: float = track.length
	return fposmod(to.dist - from.dist + L * 0.5, L) - L * 0.5


func _update_order() -> void:
	order = cars.duplicate()
	order.sort_custom(func(a, b):
		if a.finished != b.finished:
			return a.finished
		if a.finished:
			return a.finish_order < b.finish_order
		if a.towed != b.towed:
			return b.towed
		if a.out != b.out:
			return b.out
		return a.dist > b.dist)
	for i in order.size():
		order[i].set_meta("pos", i + 1)


func position_of(c: Node3D) -> int:
	return c.get_meta("pos", 1)


# --- aero ------------------------------------------------------------------------

## Next Gen aero, 2026 style. Superspeedways: big draft that stacks through a pack,
## push from the car behind, side-drafting. Intermediates and short tracks: a small
## draft on the straights but dirty air that takes front downforce off a trailing car,
## so it pushes (gets tight) in the corners.
func _aero(delta: float) -> void:
	## Every car leaves a wake: a velocity deficit strongest right behind it, widening
	## and fading with distance, and stronger when that car is itself in a draft (so
	## a line of cars stacks up). Each car samples the air around it:
	##   nose     - the tow (less drag) and dirty air on the splitter (less front grip);
	##   spoiler  - the pressure bubble ahead of a car right behind (a push: less drag;
	##              offset to one side it takes air off the spoiler: the rear goes loose);
	##   sides    - side-draft from a car at your rear quarter, and the "air wall" of
	##              turbulent air at the edge of a line when you pull out.
	var strength: float = float(track.cfg.draft)
	var n := cars.size()
	var drag := PackedFloat32Array()
	drag.resize(n)
	var front := PackedFloat32Array()
	front.resize(n)
	var draft_amt := PackedFloat32Array()
	draft_amt.resize(n)
	# Front of the pack back, so the tow can stack.
	var idx := range(n)
	idx.sort_custom(func(a, b): return cars[a].dist > cars[b].dist)
	for ii in n:
		var i: int = idx[ii]
		var c: Node3D = cars[i]
		drag[i] = 1.0
		front[i] = 1.0
		if c.towed:
			continue
		var tow := 0.0
		var dirty := 0.0
		var push := 0.0
		var loosen := 0.0
		var side := 0.0
		var wall := 0.0
		var nbl: Array = c.nb
		for q in range(0, nbl.size(), 2):
			var o: Node3D = nbl[q]
			var gap: float = nbl[q + 1] # CG to CG, + = o ahead
			var y: float = abs(o.d - c.d)
			if gap > 0.0:
				var x: float = max(gap - Car.LENGTH, 0.0) # our nose to their tail
				var sigma: float = 1.5 + 0.03 * x
				var j: int = o.get_meta("idx", 0)
				var core: float = exp(-x / 25.0) * exp(-(y * y) / (sigma * sigma))
				tow = max(tow, core * (1.0 + 0.6 * draft_amt[j]))
				dirty = max(dirty, exp(-x / 12.0) * exp(-(y * y) / 1.44))
				# The wake's turbulent edge: pulling out of line hits a wall of air.
				wall = max(wall, exp(-x / 8.0) * exp(-pow((y - 2.4) / 0.5, 2.0)))
			else:
				var xb: float = max(-gap - Car.LENGTH, 0.0) # their nose to our bumper
				push = max(push, exp(-xb / 3.0) * exp(-(y * y)))
				# A car beside us with its nose at our rear quarter side-drafts us: the
				# low pressure between the cars holds us back.
				side = max(side, exp(-pow((-gap - 2.5) / 2.0, 2.0)) * exp(-pow((y - 2.6) / 0.6, 2.0)))
				loosen = max(loosen, exp(-xb / 4.0) * clamp((y - 0.4) / 0.6, 0.0, 1.0) * clamp((2.6 - y) / 0.6, 0.0, 1.0))
		tow = min(tow, 1.3)
		draft_amt[i] = tow
		var reduction: float = tow * 0.13 * strength + push * 0.05 * strength
		drag[i] = (1.0 - reduction) * (1.0 + side * 0.07 * strength) * (1.0 + wall * 0.04 * strength)
		# Dirty air matters most where the draft doesn't dominate.
		front[i] = 1.0 - dirty * 0.38 * (1.2 - strength)
		c.set_meta("loosen", loosen)
		c.set_meta("air", Vector4(tow, push, side, wall))
	for i in n:
		var c: Node3D = cars[i]
		c.drag_mult = drag[i]
		c.df_front_mult = move_toward(c.df_front_mult, front[i], delta * 3.0)
		c.df_rear_mult = move_toward(c.df_rear_mult, 1.0 - 0.28 * float(c.get_meta("loosen", 0.0)), delta * 3.0)
		c.draft = move_toward(c.draft, clamp(draft_amt[i], 0.0, 1.0), delta * 2.0)


# --- AI --------------------------------------------------------------------------

## Is `lane` safe to move into? Looks for cars in (or heading into) that lane
## alongside, closing from behind, or too slow just ahead.
func _lane_clear(c: Node3D, lane: float) -> bool:
	var nbl: Array = c.nb
	for q in range(0, nbl.size(), 2):
		var o: Node3D = nbl[q]
		var g: float = nbl[q + 1]
		var in_lane: bool = abs(o.d - lane) < 2.6 or abs(o.ai_lane - lane) < 1.0
		if not in_lane:
			continue
		if g > -13.0 and g < 16.0:
			return false
		var closing_from_behind: float = o.v - c.v
		if g <= -13.0 and g > -45.0 and closing_from_behind > 0.1 and -g / closing_from_behind < 2.5:
			return false
		var closing_ahead: float = c.v - o.v
		if g >= 16.0 and g < 45.0 and closing_ahead > 0.1 and g / closing_ahead < 2.0:
			return false
	return true


func _drive_ai(c: Node3D, delta: float) -> void:
	if c.out:
		c.ai_r_des = 0.0
		return
	# Facing the wrong way after a spin: turn it around (a driver's three-point turn).
	if abs(c.yaw) > 1.4 and c.speed() < 7.0 and c.pit_state != 3:
		c.ai_reverse = 0.0
		c.throttle = 0.25
		c.brake = 0.0
		c.ai_r_des = 0.0
		c.steer_in = -sign(c.yaw)
		c.yaw = move_toward(c.yaw, 0.0, delta * 0.9)
		c.r = 0.0
		return
	# Stuck nose-first against a wall or another car: back up and straighten out.
	if c.speed() < 2.0 and not c.pace_mode and c.pit_state == 0 and c.ai_reverse <= 0.0:
		c.ai_stuck += delta
	else:
		c.ai_stuck = max(c.ai_stuck - delta, 0.0)
	if c.ai_stuck > 1.2:
		c.ai_reverse = 1.2
		c.ai_stuck = 0.0
	if c.ai_reverse > 0.0:
		c.ai_reverse -= delta
		c.throttle = 0.0
		c.brake = 1.0
		c.ai_r_des = 0.0
		c.steer_in = clamp(c.yaw * 2.0, -1.0, 1.0)
		return
	# Under caution or on pit road, race control says where to be.
	var controlled := false
	var ctl_target := 0.0
	if control and control.enabled and (control.flag == control.Flag.YELLOW or c.pit_state != 0 or c.want_pit):
		var tl: Array = control.caution_drive(c) if control.flag == control.Flag.YELLOW else control.green_pit(c)
		controlled = true
		ctl_target = tl[0]
		c.ai_lane = tl[1]
		c.kin_v = tl[0]
		c.kin_d = tl[1]
		if c.pit_state >= 2:
			return # pit road is driven automatically
	var ss: float = c.s()
	var k: float = track.curvature_at(ss)
	var look: float = max(c.v, 0.0) * 0.7
	var grip_scale: float = sqrt(c.mu * c.tyre_grip() * c._track_grip) * lerp(0.92, 1.0, c.df_front_mult)
	var target: float = track.profile_at(ss + look) * grip_scale * c.ai_skill * 0.95
	# In the wet drivers leave a margin: less feel, spray, and puddles off line.
	target *= 1.0 - 0.05 * c._wet
	if c.flat_time > 1.2:
		target *= 0.55 # limp it back to pit road (after the moment it takes to react)
	if controlled:
		target = min(target, ctl_target)
	# Traffic
	c.ai_lane_timer -= delta
	var ahead: Node3D = null
	var ahead_gap := 1e9
	var search: float = 160.0 if controlled else 70.0
	var nbl: Array = c.nb
	for q in range(0, nbl.size(), 2):
		var o: Node3D = nbl[q]
		var gap: float = nbl[q + 1]
		var same_lane: bool = abs(o.d - c.d) < 2.2 or (controlled and abs(o.ai_lane - c.ai_lane) < 1.0 and abs(o.d - c.d) < 4.5)
		if gap > 0.0 and gap < search and same_lane and gap < ahead_gap:
			if c.pit_state >= 2 and o.pit_state < 2:
				continue # on pit road, ignore the track
			ahead = o
			ahead_gap = gap
	# Under caution the leader follows the pace car.
	if controlled and control.flag == control.Flag.YELLOW and c.pit_state <= 1 and control.pace_car.visible:
		var pg: float = _gap(c, control.pace_car)
		if pg > 0.0 and pg < ahead_gap:
			ahead = control.pace_car
			ahead_gap = pg - 36.0
	var drafting_track: bool = float(track.cfg.draft) > 0.8
	# Stuck behind someone: patient drivers ride, impatient ones force it sooner.
	if ahead and ahead_gap < 20.0 and not controlled:
		c._stuck_behind += delta
	else:
		c._stuck_behind = 0.0
	var laps_left: int = laps - c.lap()
	if c.ai_lane_timer <= 0.0 and not debug_no_lane_changes and not controlled:
		c.ai_lane_timer = rng.randf_range(0.4, 1.0)
		var blocked: bool = ahead != null and ahead_gap < 20.0 and (ahead.v < c.v + 0.8 or ahead_gap < 9.0)
		if blocked and not drafting_track and c._stuck_behind > c.ai_patience * 4.0:
			_try_pass(c)
		elif drafting_track and _try_block(c, laps_left):
			pass
		elif ahead and drafting_track and ahead_gap < 12.0 and rng.randf() < c.ai_aggression * 0.35:
			# Pack racing: pull out, and the smart ones pick the lane that's moving.
			if rng.randf() < c.ai_racecraft:
				_pick_draft_lane(c)
			else:
				_try_pass(c)
		else:
			# Settle into the nearest proper lane, then drift down toward the
			# preferred (shortest) one when there's room.
			var idx := _nearest_lane(c.ai_lane)
			if abs(lanes[idx] - c.ai_lane) > 0.3 and _lane_clear(c, lanes[idx]):
				c.ai_lane = lanes[idx]
			elif idx > 0 and rng.randf() < 0.2 and _lane_clear(c, lanes[idx - 1]):
				c.ai_lane = lanes[idx - 1]
	# Side awareness: never steer into a car that is alongside, and give it racing
	# room through the corners (a touch less speed so we don't slide into it).
	for q in range(0, nbl.size(), 2):
		var o: Node3D = nbl[q]
		if c.pit_state != 0:
			break
		var g: float = nbl[q + 1]
		var side: float = o.d - c.d
		if abs(g) < 6.0 and not controlled and abs(side) < 3.6 and abs(k) > 0.001:
			target = min(target, c.v - 0.3) if (side * sign(k) > 0.0) else target * 0.985
		if abs(g) < 7.5 and abs(side) < 3.4 and abs(side) > 0.3:
			if sign(c.ai_lane - c.d) == sign(side) and abs(c.ai_lane - c.d) > 0.3:
				c.ai_lane = clamp(c.d, lanes[0], lanes[2]) # hold our line
	# Following distance: time based, tighter where the draft rewards it.
	var want_gap: float = max(7.0, c.v * (0.14 if drafting_track else 0.32))
	if controlled:
		want_gap = 9.0
	if ahead and (abs(c.ai_lane - ahead.d) < 2.2 or controlled) and ahead_gap < max(want_gap * 2.0, search):
		var bump_ok: bool = drafting_track and abs(k) < 0.001 and abs(ahead.yaw) < 0.08 and c.ai_aggression > 0.6 and not controlled
		# Short-track bump-and-run late in the race, or a car with a score to settle.
		var grudge: float = float(c.rivals.get(ahead, 0.0))
		var short_track: bool = float(track.cfg.get("radius", 250.0)) < 120.0
		if not controlled and ((short_track and laps_left <= 3 and c.ai_aggression > 0.7) or grudge > 0.6) and abs(ahead.yaw) < 0.1:
			bump_ok = true
			want_gap = min(want_gap, 5.5)
		var err: float = ahead_gap - want_gap
		# Never close faster than we could stop behind it.
		var av: float = max(ahead.v, 0.0)
		var match_v: float = sqrt(av * av + 2.0 * 4.5 * err) if err >= 0.0 else av + err * 0.6
		if bump_ok and ahead_gap < 8.0:
			match_v = ahead.v + (1.6 if c.rivals.get(ahead, 0.0) > 0.6 else 1.0)
		target = min(target, match_v)
	# Avoid spinning cars ahead.
	for q in range(0, nbl.size(), 2):
		var o: Node3D = nbl[q]
		if o.spinning or o.out:
			var g: float = nbl[q + 1]
			if g > 0.0 and g < 90.0:
				if abs(o.d - c.ai_lane) < 3.5:
					var alt := lanes[2] if o.d < 0.0 else lanes[0]
					c.ai_lane = alt
				target = min(target, max(o.speed() + 8.0, target * 0.8))
	# Running out of grip (drifting up the track): lift until the car turns again.
	var lifting: bool = abs(k) > 0.001 and (c.d - c.ai_lane) * sign(k) > 1.2
	# Can the car actually turn as tight as the track does here? (The corner
	# ahead is covered by the speed profile.)
	var r_need: float = abs(k) * cos(track.bank_at(ss)) * c.v
	if r_need > 0.9 * c.r_max_now:
		target = min(target, c.v * 0.9 * c.r_max_now / max(r_need, 0.001))
	# Mistakes: an inconsistent driver under pressure (a car on the bumper late in
	# the race) sometimes overdrives a corner.
	if not controlled and c.pit_state == 0:
		if c._mistake > 0.0:
			c._mistake -= delta
			target *= 1.05
		else:
			var pressure := 1.0
			for q in range(0, nbl.size(), 2):
				var gq: float = nbl[q + 1]
				if gq < 0.0 and gq > -10.0:
					pressure = 2.5
					break
			if laps_left <= 5:
				pressure *= 1.5
			if abs(k) > 0.002 and rng.randf() < (1.0 - c.ai_consistency) * 0.01 * pressure * delta * 60.0:
				c._mistake = rng.randf_range(0.6, 1.4)
	# Pedals, eased in and out like a driver's feet.
	var want_thr := 0.0
	var want_brk := 0.0
	if c.v > target + 2.0:
		# Brake gently mid-corner (and under caution), harder on the straights.
		var brk_cap: float = 0.35 if abs(k) > 0.001 else 0.8
		if controlled and c.pit_state == 0:
			brk_cap = min(brk_cap, 0.3)
		want_brk = clamp((c.v - target) / 14.0, 0.05, brk_cap)
	elif lifting:
		want_thr = 0.2
	elif c.v < target - 0.5:
		want_thr = 1.0
	else:
		want_thr = clamp(0.5 + (target - c.v) * 0.2, 0.0, 1.0)
	if c.slide > 0.2:
		want_thr = 0.0 # catch it
		want_brk = 0.0
	c.throttle = move_toward(c.throttle, want_thr, delta * (6.0 if want_thr < c.throttle else 2.5))
	c.brake = move_toward(c.brake, want_brk, delta * 4.0)
	# Steering: ask the assist for the yaw rate that follows the lane, with the
	# track curvature fed forward.
	var r_track: float = -k * cos(track.bank_at(ss)) * c.v / (1.0 + k * c.d)
	# Ease across lanes: about 2.5 m/s of sideways speed at racing speed.
	var max_psi: float = clamp((4.0 if controlled else 2.5) / max(c.v, 10.0), 0.03, 0.14)
	var psi_des: float = clamp((c.ai_lane - c.d) * 0.015 * (80.0 / max(c.v, 30.0)), -max_psi, max_psi)
	# Steer by the direction of travel (heading plus slip), not just the heading.
	var course: float = c.yaw + atan2(c.vy, max(c.v, 5.0))
	c.ai_r_des = r_track + (psi_des - course) * 2.5
	c.steer_in = clamp(c.ai_r_des, -1.0, 1.0)


func _nearest_lane(x: float) -> int:
	var best := 0
	for i in lanes.size():
		if abs(lanes[i] - x) < abs(lanes[best] - x):
			best = i
	return best


## Superspeedway line choice: go to the lane whose line is moving (more cars
## drafting in it just ahead, and faster).
func _pick_draft_lane(c: Node3D) -> void:
	var best_lane: float = c.ai_lane
	var best_score := -INF
	for ln in lanes:
		if abs(ln - c.ai_lane) > 5.0 or (abs(ln - c.ai_lane) > 1.0 and not _lane_clear(c, ln)):
			continue
		var cnt := 0
		var vsum := 0.0
		var nbl: Array = c.nb
		for q in range(0, nbl.size(), 2):
			var o: Node3D = nbl[q]
			var g: float = nbl[q + 1]
			if g > 0.0 and g < 80.0 and abs(o.d - ln) < 1.8:
				cnt += 1
				vsum += o.v
		var score: float = cnt * 2.0 + (vsum / cnt - c.v if cnt > 0 else -3.0)
		if score > best_score:
			best_score = score
			best_lane = ln
	c.ai_lane = best_lane


## Blocking: a run is coming in the other lane, so move over to take it away. Smart
## drivers do it late in the race; it can go wrong (hooked in the right rear).
func _try_block(c: Node3D, laps_left: int) -> bool:
	if c.ai_racecraft < 0.4 or rng.randf() > c.ai_racecraft * (0.6 if laps_left <= 5 else 0.2):
		return false
	var nbl: Array = c.nb
	for q in range(0, nbl.size(), 2):
		var o: Node3D = nbl[q]
		var g: float = nbl[q + 1]
		if g < -6.0 and g > -30.0 and o.v > c.v + 0.8 and abs(o.d - c.d) > 2.4:
			var ln: float = lanes[_nearest_lane(o.d)]
			# Only if nobody is alongside us in the way.
			var clear := true
			for q2 in range(0, nbl.size(), 2):
				var o2: Node3D = nbl[q2]
				if abs(float(nbl[q2 + 1])) < 7.0 and abs(o2.d - ln) < 2.2:
					clear = false
					break
			if clear:
				c.ai_lane = ln
				return true
	return false


func _try_pass(c: Node3D) -> void:
	var choices: Array[float] = []
	for ln in lanes:
		if abs(ln - c.ai_lane) > 1.0 and abs(ln - c.ai_lane) < 5.0 and _lane_clear(c, ln):
			choices.append(ln)
	if choices.size() > 0:
		c.ai_lane = choices[rng.randi() % choices.size()]


# --- contact ---------------------------------------------------------------------

func _axes(c: Node3D) -> Array[Vector2]:
	return [Vector2(cos(c.yaw), sin(c.yaw)), Vector2(-sin(c.yaw), cos(c.yaw))]


func _collide() -> void:
	for a in cars:
		if a.towed or a.pit_state >= 2:
			continue
		var nbl: Array = a.nb
		for q in range(0, nbl.size(), 2):
			var gap: float = nbl[q + 1]
			if gap < 0.0 or gap > 7.0:
				continue
			var b: Node3D = nbl[q]
			if b.pit_state >= 2 or abs(b.d - a.d) > 6.0:
				continue
			_contact(a, b, Vector2(gap, b.d - a.d))


## Oriented-box contact in the local track plane (x along, y right). `rel` is b's
## CG relative to a's. Resolves with an impulse at the contact point, so a tap in
## the right rear really does turn a car around.
func _contact(a: Node3D, b: Node3D, rel: Vector2) -> void:
	var ax := _axes(a)
	var bx := _axes(b)
	var ext := Vector2(Car.HALF_L, Car.HALF_W)
	var best_ov := INF
	var best_n := Vector2.ZERO
	for axis in [ax[0], ax[1], bx[0], bx[1]]:
		var ra: float = ext.x * abs(ax[0].dot(axis)) + ext.y * abs(ax[1].dot(axis))
		var rb: float = ext.x * abs(bx[0].dot(axis)) + ext.y * abs(bx[1].dot(axis))
		var dist: float = rel.dot(axis)
		var ov: float = ra + rb - abs(dist)
		if ov <= 0.0:
			return
		if ov < best_ov:
			best_ov = ov
			best_n = axis * (1.0 if dist >= 0.0 else -1.0)
	var n: Vector2 = best_n # from a towards b
	# Contact point: on a's face along n, centred on the overlap of the two faces.
	var t_ax := Vector2(-n.y, n.x)
	var ra_n: float = ext.x * abs(ax[0].dot(n)) + ext.y * abs(ax[1].dot(n))
	var rta: float = ext.x * abs(ax[0].dot(t_ax)) + ext.y * abs(ax[1].dot(t_ax))
	var rtb: float = ext.x * abs(bx[0].dot(t_ax)) + ext.y * abs(bx[1].dot(t_ax))
	var bt: float = rel.dot(t_ax)
	var lo: float = max(-rta, bt - rtb)
	var hi: float = min(rta, bt + rtb)
	var cp: Vector2 = n * (ra_n - best_ov * 0.5) + t_ax * ((lo + hi) * 0.5)
	var ra_p: Vector2 = cp
	var rb_p: Vector2 = cp - rel
	var vrel: Vector2 = a.point_velocity(ra_p) - b.point_velocity(rb_p)
	var vn: float = vrel.dot(n)
	# Separate the boxes. (Online, each player only moves and pushes the car they
	# own; the other side of the contact is handled on its owner's machine.)
	var ka: float = 0.0 if a.remote else (0.5 if not b.remote else 1.0)
	var kb: float = 0.0 if b.remote else (0.5 if not a.remote else 1.0)
	a.dist -= n.x * best_ov * ka
	a.d -= n.y * best_ov * ka
	b.dist += n.x * best_ov * kb
	b.d += n.y * best_ov * kb
	if vn <= 0.0:
		return
	# Gentle rubs mostly slide the cars along each other (sheet metal flexes, the
	# drivers hold on); hard hits transfer their full impulse.
	var e := 0.1
	var soft: float = clamp(vn / 3.0, 0.35, 1.0)
	var j: float = (1.0 + e) * vn * soft / (a.inv_mass_along(n, ra_p) + b.inv_mass_along(n, rb_p))
	var t: Vector2 = Vector2(-n.y, n.x)
	var vt: float = vrel.dot(t)
	var jt: float = clamp(vt / (a.inv_mass_along(t, ra_p) + b.inv_mass_along(t, rb_p)), -0.15 * j, 0.15 * j)
	var imp: Vector2 = n * j + t * jt
	if not a.remote:
		a.apply_impulse(-imp, ra_p)
		a.add_damage(j, ra_p)
	if not b.remote:
		b.apply_impulse(imp, rb_p)
		b.add_damage(j, rb_p)
	# Grudges: the car that got hit (in the rear or turned) remembers who did it.
	if vn > 3.0 and not arcade:
		var victim: Node3D = b if n.x > 0.3 else a # b is ahead along n: a hit b from behind
		var culprit: Node3D = a if victim == b else b
		victim.rivals[culprit] = min(float(victim.rivals.get(culprit, 0.0)) + clamp(vn / 10.0, 0.1, 0.6), 1.0)
		if culprit.is_player and victim.rivals[culprit] > 0.5 and control:
			control.message_for(culprit, "SPOTTER: THE %s IS HOT AT YOU" % victim.team.num, "spotter")
	var hit: float = vn
	a.bump = max(a.bump, hit)
	b.bump = max(b.bump, hit)
	if vn > 7.0:
		spawn_debris(a.s() + cp.x, a.d + cp.y, 1 + int(vn > 14.0))
		if highlights.is_empty() or rec_clock - float(highlights[-1].t) > 3.0:
			highlights.append({"t": rec_clock, "car": cars.find(b), "kind": "CONTACT"})
	# Big hits can climb one car over another: the struck car gets lifted and
	# rolled (how cars get airborne in real wrecks).
	if vn > 11.0:
		var lift: float = j * 0.09 * clamp((vn - 11.0) / 15.0, 0.0, 1.0)
		for pair in [[a, -1.0], [b, 1.0]]:
			var x: Node3D = pair[0]
			var side: float = x.track_to_body(n * pair[1]).y
			x.kick(lift * abs(side), side * lift * 0.9, 0.0)


# --- debris ----------------------------------------------------------------------

func _build_debris_mesh() -> void:
	var bm := BoxMesh.new()
	bm.size = Vector3(0.45, 0.06, 0.3)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = bm
	mm.instance_count = MAX_DEBRIS
	mm.visible_instance_count = 0
	_debris_mm = MultiMeshInstance3D.new()
	_debris_mm.name = "Debris"
	_debris_mm.multimesh = mm
	_debris_mm.material_override = Game.make_mat("carbon", Color(0.12, 0.12, 0.13))
	add_child(_debris_mm)


func spawn_debris(s_at: float, d_at: float, count: int) -> void:
	for k in count:
		if debris.size() >= MAX_DEBRIS:
			debris.pop_front()
		debris.append({"s": fposmod(s_at + rng.randf_range(-6.0, 10.0), track.length), "d": clamp(d_at + rng.randf_range(-3.0, 3.0), track.inner_edge(), track.outer_edge() - 0.5), "age": 0.0, "hit": {}})
	_debris_visual()


func clear_debris() -> void:
	debris.clear()
	_debris_visual()


func _debris_visual() -> void:
	var mm: MultiMesh = _debris_mm.multimesh
	mm.visible_instance_count = debris.size()
	for k in debris.size():
		var dd: Dictionary = debris[k]
		var tr: Transform3D = track.car_transform(dd.s, dd.d, float(k) * 1.7)
		tr.origin += tr.basis.y * 0.04
		mm.set_instance_transform(k, tr)


## Cars running over debris: a chance of cutting the tyre that hits it, or of the
## piece ending up on the grille. Pieces get knocked around or away.
func _debris_tick(delta: float) -> void:
	var L: float = track.length
	var moved := false
	for k in range(debris.size() - 1, -1, -1):
		var dd: Dictionary = debris[k]
		dd.age += delta
		for c in cars:
			if c.towed or c.tumbling or c.pit_state >= 2:
				continue
			var ds: float = fposmod(dd.s - c.s() + L * 0.5, L) - L * 0.5
			if abs(ds) > 2.6 or abs(dd.d - c.d) > 1.3:
				continue
			if dd.hit.has(c):
				continue
			dd.hit[c] = true
			var roll := rng.randf()
			if roll < 0.07:
				var wheel: int = (0 if ds > 0.0 else 2) + (1 if dd.d > c.d else 0)
				c.fail_tyre(wheel, "cut")
			elif roll < 0.3 and ds > 0.5:
				c.grille_block = min(c.grille_block + rng.randf_range(0.25, 0.5), 0.8)
				if control:
					control.message_for(c, "DEBRIS ON THE GRILLE - WATCH THE WATER TEMP", "pit")
			# Knocked aside, or away for good.
			if rng.randf() < 0.5:
				debris.remove_at(k)
				moved = true
				break
			dd.d = clamp(dd.d + rng.randf_range(-2.0, 2.0), track.inner_edge(), track.outer_edge() - 0.5)
			moved = true
	if moved:
		_debris_visual()
	# A pile of it on the racing surface brings out the caution.
	if control and control.enabled and control.cautions_enabled and control.flag == control.Flag.GREEN:
		var on_track := 0
		for dd in debris:
			if dd.age > 12.0:
				on_track += 1
		if on_track >= 3:
			control.throw_caution("DEBRIS", null)


func _on_tyre_failed(c: Node3D, wheel: int, kind: String) -> void:
	var names := ["LEFT FRONT", "RIGHT FRONT", "LEFT REAR", "RIGHT REAR"]
	if control:
		if kind == "blowout":
			control.message_for(c, "TIRE DOWN!  %s BLEW" % names[wheel], "pit")
		else:
			control.message_for(c, "%s IS GOING DOWN - PIT THIS LAP" % names[wheel], "pit")
	if kind == "blowout":
		incident.emit(c, "tyre")
