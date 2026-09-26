extends Node3D
## Runs a race: spawns the field, drives the AI, works out the aero between cars
## (drafting, side-drafting, dirty air), resolves car-to-car contact as rigid-body
## impulses, and keeps lap timing and the running order.

signal lap_completed(car: Node3D, laps_done: int, lap_time: float)
signal car_finished(car: Node3D, place: int)
signal incident(car: Node3D, kind: String)

const Car := preload("res://scripts/car.gd")

var track: Node3D
var cars: Array[Node3D] = []
var order: Array[Node3D] = [] # current running order
var player: Node3D = null
var laps := 3
var time := 0.0
var running := false
var finish_count := 0
var rng := RandomNumberGenerator.new()
var lanes: Array[float] = []
var arcade := false # rubber-banding for the arcade mode only
var field_size := 40
var debug_no_lane_changes := false
var control: Node = null # race_control.gd when the full rules are on
var wear_scale := 1.0 # fuel burn / tyre wear multiplier so short races still need pit strategy


func setup(trk: Node3D, player_team: int, lap_count: int, size := 40) -> void:
	track = trk
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
		if i != player_team:
			team_ids.append(i)
	team_ids.shuffle()
	var grid_player: int = min(int(track.cfg.grid_player), field_size - 1)
	var roster: Array[int] = []
	for p in field_size:
		if player_team >= 0 and p == grid_player:
			roster.append(player_team)
		else:
			roster.append(team_ids.pop_back())
	for p in roster.size():
		var c: Node3D = Car.new()
		c.name = "Car%s" % Game.teams[roster[p]].num
		add_child(c)
		c.setup(Game.teams[roster[p]], track)
		c.is_player = player_team >= 0 and p == grid_player
		c.ai = not c.is_player
		c.assisted = true
		c.manual = Game.manual_shift
		c.ai_skill = float(Game.teams[roster[p]].get("skill", rng.randf_range(0.955, 0.99)))
		c.ai_aggression = rng.randf_range(0.2, 0.9)
		c.set_meta("grid", p)
		cars.append(c)
		if c.is_player:
			player = c
			c.assisted = Game.assists
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
	for c in cars:
		c.burn_scale = wear_scale


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
	if control:
		control.tick(delta)
	_aero(delta)
	for c in cars:
		if c.towed:
			continue
		if c.ai and running:
			_drive_ai(c, delta)
		if arcade and player and c != player and running and not player.finished:
			var gap: float = c.dist - player.dist
			var target := 1.0
			if gap > 60.0:
				target = lerp(1.0, 0.93, clamp((gap - 60.0) / 250.0, 0.0, 1.0))
			elif gap < -80.0:
				target = lerp(1.0, 1.05, clamp((-gap - 80.0) / 250.0, 0.0, 1.0))
			c.rubber = move_toward(c.rubber, target, delta * 0.02)
			c.drag_mult *= 1.0 / pow(c.rubber, 3.0)
		var was_out: bool = c.out
		var was_spin: bool = c.spinning
		c.step(delta)
		if c.pit_state == 3: # in the pit box
			c.v = 0.0
			c.vy = 0.0
			c.r = 0.0
		if c.out and not was_out:
			incident.emit(c, "out")
		elif c.spinning and not was_spin:
			incident.emit(c, "spin")
	_collide()
	# Laps / finish
	for c in cars:
		var li: int = c.lap()
		if li > c.lap_idx:
			c.lap_idx = li
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
	var strength: float = float(track.cfg.draft)
	var n := cars.size()
	var drag := PackedFloat32Array()
	drag.resize(n)
	var front := PackedFloat32Array()
	front.resize(n)
	var draft_amt := PackedFloat32Array()
	draft_amt.resize(n)
	# Process from the front of the pack back so the tow can stack.
	var idx := range(n)
	idx.sort_custom(func(a, b): return cars[a].dist > cars[b].dist)
	var rank := {}
	for i in n:
		rank[cars[idx[i]]] = i
		drag[i] = 1.0
		front[i] = 1.0
	for ii in n:
		var i: int = idx[ii]
		var c: Node3D = cars[i]
		if c.towed:
			continue
		var best := 0.0
		var dirty := 0.0
		var pushed := 0.0
		var side_pen := 0.0
		for j in n:
			if j == i:
				continue
			var o: Node3D = cars[j]
			if o.towed:
				continue
			var gap: float = _gap(c, o) # o ahead when > 0
			var lat: float = abs(o.d - c.d)
			if gap > 3.0 and gap < 45.0 and lat < 2.2:
				# Tow from the car ahead, stronger when it is itself in a draft.
				var t: float = clamp(1.0 - (gap - 5.0) / 40.0, 0.0, 1.0) * (1.0 - lat / 2.2 * 0.5)
				t *= 1.0 + 0.6 * draft_amt[j]
				best = max(best, t)
				if gap < 25.0:
					dirty = max(dirty, clamp(1.0 - (gap - 5.0) / 20.0, 0.0, 1.0) * (1.0 - lat / 2.2))
			elif gap < -3.0 and gap > -9.0 and lat < 1.8:
				# A car right on the bumper pushes air under this one.
				pushed = max(pushed, 1.0)
			if abs(gap) < 5.0 and lat > 1.9 and lat < 3.6 and gap > 0.0 and gap < 4.0:
				# Side draft: a car alongside our rear quarter slows us down.
				side_pen = max(side_pen, 1.0 - abs(gap - 2.0) / 3.0)
		best = min(best, 1.3)
		draft_amt[i] = best
		var reduction: float = best * 0.13 * strength + pushed * 0.05 * strength
		drag[i] = (1.0 - reduction) * (1.0 + side_pen * 0.07 * strength)
		# Dirty air matters most where the draft doesn't dominate.
		front[i] = 1.0 - dirty * 0.38 * (1.2 - strength)
	for i in n:
		var c: Node3D = cars[i]
		c.drag_mult = drag[i]
		c.df_front_mult = move_toward(c.df_front_mult, front[i], delta * 3.0)
		c.draft = move_toward(c.draft, clamp(draft_amt[i], 0.0, 1.0), delta * 2.0)


# --- AI --------------------------------------------------------------------------

## Is `lane` safe to move into? Looks for cars in (or heading into) that lane
## alongside, closing from behind, or too slow just ahead.
func _lane_clear(c: Node3D, lane: float) -> bool:
	for o in cars:
		if o == c:
			continue
		var g := _gap(c, o)
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
	var grip_scale: float = sqrt(c.mu * c.tyre_grip()) * lerp(0.92, 1.0, c.df_front_mult)
	var target: float = track.profile_at(ss + look) * grip_scale * c.ai_skill * 0.95
	if controlled:
		target = min(target, ctl_target)
	# Traffic
	c.ai_lane_timer -= delta
	var ahead: Node3D = null
	var ahead_gap := 1e9
	var search: float = 160.0 if controlled else 70.0
	for o in cars:
		if o == c or o.towed:
			continue
		var gap: float = _gap(c, o)
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
	if c.ai_lane_timer <= 0.0 and not debug_no_lane_changes and not controlled:
		c.ai_lane_timer = rng.randf_range(0.4, 1.0)
		if ahead and ahead_gap < 20.0 and (ahead.v < c.v + 0.8 or ahead_gap < 9.0) and not drafting_track:
			_try_pass(c)
		elif ahead and drafting_track and ahead_gap < 12.0 and rng.randf() < c.ai_aggression * 0.35:
			# Pack racing: pull out and look for a run.
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
	for o in cars:
		if o == c or o.towed or c.pit_state != 0:
			continue
		var g := _gap(c, o)
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
		var err: float = ahead_gap - want_gap
		# Never close faster than we could stop behind it.
		var av: float = max(ahead.v, 0.0)
		var match_v: float = sqrt(av * av + 2.0 * 4.5 * err) if err >= 0.0 else av + err * 0.6
		if bump_ok and ahead_gap < 8.0:
			match_v = ahead.v + 1.0
		target = min(target, match_v)
	# Avoid spinning cars ahead.
	for o in cars:
		if o != c and (o.spinning or o.out) and not o.towed:
			var g := _gap(c, o)
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
	var n := cars.size()
	for i in n:
		var a: Node3D = cars[i]
		if a.towed:
			continue
		for j in range(i + 1, n):
			var b: Node3D = cars[j]
			if b.towed or ((a.pit_state >= 2) != (b.pit_state >= 2)):
				continue
			var gap: float = _gap(a, b)
			if abs(gap) > 7.0 or abs(b.d - a.d) > 6.0:
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
	# Separate the boxes.
	a.dist -= n.x * best_ov * 0.5
	a.d -= n.y * best_ov * 0.5
	b.dist += n.x * best_ov * 0.5
	b.d += n.y * best_ov * 0.5
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
	a.apply_impulse(-imp, ra_p)
	b.apply_impulse(imp, rb_p)
	a.add_damage(j, ra_p)
	b.add_damage(j, rb_p)
	var hit: float = vn
	a.bump = max(a.bump, hit)
	b.bump = max(b.bump, hit)
