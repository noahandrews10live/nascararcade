extends Node3D
## Runs a race: spawns the field, drives the AI, resolves contact, drafting,
## lap timing and running order.

signal lap_completed(car: Node3D, laps_done: int, lap_time: float)
signal car_finished(car: Node3D, place: int)

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


func setup(trk: Node3D, player_team: int, lap_count: int) -> void:
	track = trk
	laps = lap_count
	rng.randomize()
	var hw: float = track.width * 0.5
	lanes = [-hw + 2.3, -hw + 2.3 + 4.3, -hw + 2.3 + 8.6]
	var team_ids: Array[int] = []
	for i in Game.teams.size():
		if i != player_team:
			team_ids.append(i)
	team_ids.shuffle()
	var grid_player: int = track.cfg.grid_player
	var roster: Array[int] = []
	for p in Game.FIELD_SIZE:
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
		c.ai_skill = rng.randf_range(0.965, 1.0)
		if not c.is_player:
			# The AI field is a touch slower than the player's pick at base.
			c.top_speed *= rng.randf_range(0.965, 0.995)
		c.set_meta("grid", p)
		cars.append(c)
		if c.is_player:
			player = c
	order = cars.duplicate()


## Places the field in a two-wide rolling start formation with the leader at `leader_dist`.
func grid_up(leader_dist: float, pace_speed: float) -> void:
	for c in cars:
		var p: int = c.get_meta("grid")
		var row := p / 2
		c.dist = leader_dist - row * 13.0 - (p % 2) * 1.5
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
	var L: float = track.length
	# Draft detection
	for c in cars:
		var best := 0.0
		for o in cars:
			if o == c:
				continue
			var gap := _gap(c, o)
			if gap > 4.5 and gap < 32.0 and abs(o.d - c.d) < 2.2:
				best = max(best, clamp(1.0 - (gap - 6.0) / 26.0, 0.0, 1.0))
		c.draft = move_toward(c.draft, best, delta * 1.5)
	for c in cars:
		if c.ai and running:
			_drive_ai(c, delta)
		if player and c != player and running and not player.finished:
			var gap: float = c.dist - player.dist
			var target := 1.0
			if gap > 60.0:
				target = lerp(1.0, 0.93, clamp((gap - 60.0) / 250.0, 0.0, 1.0))
			elif gap < -80.0:
				target = lerp(1.0, 1.05, clamp((-gap - 80.0) / 250.0, 0.0, 1.0))
			c.rubber = move_toward(c.rubber, target, delta * 0.02)
		c.step(delta)
	_collide()
	# Laps / finish
	for c in cars:
		var li: int = c.lap()
		if li > c.lap_idx:
			c.lap_idx = li
			if li == 0:
				c.lap_start_time = time
			elif li >= 1 and not c.finished:
				var lt: float = time - c.lap_start_time
				c.lap_start_time = time
				c.last_lap = lt
				if c.best_lap <= 0.0 or lt < c.best_lap:
					c.best_lap = lt
				lap_completed.emit(c, li, lt)
				if li >= laps:
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
		return a.dist > b.dist)
	for i in order.size():
		order[i].set_meta("pos", i + 1)


func position_of(c: Node3D) -> int:
	return c.get_meta("pos", 1)


func _lane_clear(c: Node3D, lane: float) -> bool:
	for o in cars:
		if o == c:
			continue
		var gap := _gap(c, o)
		if gap > -9.0 and gap < 16.0 and abs(o.d - lane) < 2.4:
			return false
	return true


func _drive_ai(c: Node3D, delta: float) -> void:
	var ss: float = c.s()
	var k: float = track.curvature_at(ss)
	var target: float = track.profile_at(ss + max(c.v, 0.0) * 0.6) * sqrt(c.mu) * c.ai_skill
	# Traffic
	c.ai_lane_timer -= delta
	var ahead: Node3D = null
	var ahead_gap := 1e9
	for o in cars:
		if o == c:
			continue
		var gap := _gap(c, o)
		if gap > 0.0 and gap < 40.0 and abs(o.d - c.d) < 2.3 and gap < ahead_gap:
			ahead = o
			ahead_gap = gap
	if c.ai_lane_timer <= 0.0:
		c.ai_lane_timer = rng.randf_range(0.3, 0.8)
		if ahead and ahead_gap < 22.0 and (ahead.v < c.v + 1.5 or ahead_gap < 10.0):
			var choices: Array[float] = []
			for ln in lanes:
				if abs(ln - c.ai_lane) > 1.0 and abs(ln - c.ai_lane) < 5.0 and _lane_clear(c, ln):
					choices.append(ln)
			if choices.size() > 0:
				c.ai_lane = choices[rng.randi() % choices.size()]
		elif rng.randf() < 0.25 and c.ai_lane != lanes[0] and _lane_clear(c, lanes[0]):
			c.ai_lane = lanes[0] if c.ai_lane == lanes[1] else lanes[1]
	if ahead and ahead_gap < 12.0 and abs(c.ai_lane - ahead.d) < 2.3:
		target = min(target, ahead.v - (12.0 - ahead_gap) * 0.4)
	# Pedals
	if c.v < target - 0.5:
		c.throttle = 1.0
		c.brake = 0.0
	elif c.v > target + 3.0:
		c.throttle = 0.0
		c.brake = clamp((c.v - target) / 10.0, 0.2, 1.0)
	else:
		c.throttle = 0.3
		c.brake = 0.0
	# Steering: aim yaw toward the chosen lane, feeding forward the track curvature.
	var a_des: float = clamp((c.ai_lane - c.d) * 0.05, -0.1, 0.1)
	var ds: float = c.v * cos(c.yaw) / (1.0 + k * c.d)
	var want_rate: float = (a_des - c.yaw) * 4.0 - k * ds
	var mr: float = c.max_steer_rate()
	var st: float = clamp(want_rate / mr, -1.0, 1.0) if mr > 0.001 else 0.0
	c.steer_in = st
	c.steer = st


func _collide() -> void:
	var n := cars.size()
	for i in n:
		var a: Node3D = cars[i]
		for j in range(i + 1, n):
			var b: Node3D = cars[j]
			var gap := _gap(a, b) # b ahead of a when > 0
			var dd: float = b.d - a.d
			var px: float = Car.LENGTH - abs(gap)
			var py: float = Car.WIDTH - abs(dd)
			if px <= 0.0 or py <= 0.0:
				continue
			if px / Car.LENGTH < py / Car.WIDTH:
				var front: Node3D = b if gap > 0.0 else a
				var rear: Node3D = a if gap > 0.0 else b
				front.dist += px * 0.5
				rear.dist -= px * 0.5
				var dv: float = rear.v - front.v
				if dv > 0.0:
					rear.v -= dv * 0.6
					front.v += dv * 0.4
					rear.bump = max(rear.bump, dv)
					front.bump = max(front.bump, dv)
					front.yaw += rng.randf_range(-0.03, 0.03) * clamp(dv / 5.0, 0.0, 1.0)
			else:
				var sgn := 1.0 if dd >= 0.0 else -1.0
				a.d -= sgn * py * 0.5
				b.d += sgn * py * 0.5
				a.yaw -= sgn * 0.035
				b.yaw += sgn * 0.035
				a.v *= 0.997
				b.v *= 0.997
				var hit: float = abs(a.v * sin(a.yaw) - b.v * sin(b.yaw)) + 1.0
				a.bump = max(a.bump, hit)
				b.bump = max(b.bump, hit)
