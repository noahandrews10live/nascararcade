extends SceneTree
## Your car's drivetrain and tyres: wheelspin with the assists off, traction
## control and ABS holding the slip near the grip peak, a wheel locking under hard
## braking, engine braking (stronger in a low gear), the drive cut during an
## upshift, and the tyres building side force over a short rolling distance.
##   godot --headless --fixed-fps 60 -s tests/drivetrain_test.gd

var Track: GDScript
var Race: GDScript
const DT := 1.0 / 60.0
var failures := 0
var t: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1


## One car alone at the start line, driven by the test (not the AI).
func _car(speed: float) -> Array:
	var race: Node3D = Race.new()
	root.add_child(race)
	race.setup(t, -1, 3, 1)
	race.grid_up(0.0, 30.0)
	race.go_green()
	var c: Node3D = race.cars[0]
	c.is_player = true
	c.ai = false
	c.dist = 20.0
	c.d = race.lanes[0]
	c.yaw = 0.0
	c.vy = 0.0
	c.r = 0.0
	c.v = speed
	c.steer_in = 0.0
	c.steer = 0.0
	c.throttle = 0.0
	c.brake = 0.0
	c.reset_chassis()
	return [race, c]


func _run() -> void:
	Track = load("res://scripts/track.gd")
	Race = load("res://scripts/race.gd")
	var game := root.get_node("Game")
	t = Track.new()
	root.add_child(t)
	t.setup(game.tracks[1])

	# 1. Assists off, flat out from a roll in first: the rears spin up.
	var rc: Array = _car(8.0)
	var c: Node3D = rc[1]
	c.assisted = false
	c.gear = 1
	var k_max := 0.0
	var spun := false
	for i in 90:
		c.throttle = 1.0
		rc[0].tick(DT)
		k_max = max(k_max, c.kappa_r)
		spun = spun or c.kappa_r > 0.25
	print("   assists off: peak rear slip %.2f" % k_max)
	_check(spun, "wheelspin on a full throttle with the assists off")
	rc[0].free()

	# 2. Traction control (FULL): the same launch holds the slip at the peak.
	rc = _car(8.0)
	c = rc[1]
	c.assisted = true
	c.assist_level = 1.0
	c.gear = 1
	k_max = 0.0
	var v0: float = c.v
	for i in 90:
		c.throttle = 1.0
		rc[0].tick(DT)
		k_max = max(k_max, c.kappa_r)
	print("   traction control: peak rear slip %.3f, %.1f -> %.1f m/s" % [k_max, v0, c.v])
	_check(k_max <= 0.1201, "traction control keeps the rear slip at or under 12%")
	_check(c.v > v0 + 6.0, "and the car still pulls away hard")
	rc[0].free()

	# 3. A stamp on the brakes at 60 m/s with no ABS: a wheel locks.
	rc = _car(60.0)
	c = rc[1]
	c.assisted = false
	c.gear = 4
	var locked := false
	var k_min := 0.0
	for i in 60:
		c.brake = 1.0
		rc[0].tick(DT)
		k_min = min(k_min, min(c.kappa_f, c.kappa_r))
		locked = locked or c.locked_wheels != 0
	print("   hard braking, no ABS: lowest slip %.2f, %.1f m/s left" % [k_min, c.v])
	_check(locked, "a wheel locks under full braking without ABS")
	rc[0].free()

	# ABS holds the slip near the peak instead.
	rc = _car(60.0)
	c = rc[1]
	c.assisted = true
	c.assist_level = 1.0
	c.gear = 4
	k_min = 0.0
	for i in 60:
		c.brake = 1.0
		rc[0].tick(DT)
		k_min = min(k_min, min(c.kappa_f, c.kappa_r))
	print("   hard braking, ABS: lowest slip %.3f" % k_min)
	_check(k_min >= -0.1201, "ABS keeps the wheels from locking")
	rc[0].free()

	# 4. Engine braking: coasting at 35 m/s slows the car faster in 2nd than 4th.
	var decel := []
	for g in [2, 4]:
		rc = _car(35.0)
		c = rc[1]
		c.manual = true
		c.gear = g
		var va: float = c.v
		for i in 60:
			c.throttle = 0.0
			rc[0].tick(DT)
		decel.append(va - c.v)
		rc[0].free()
	print("   coasting 1 s from 35 m/s: 2nd loses %.2f m/s, 4th %.2f" % [decel[0], decel[1]])
	_check(decel[0] > decel[1] + 0.2, "engine braking is stronger in a lower gear")

	# 5. The drive cuts for a moment on an upshift.
	rc = _car(20.0)
	c = rc[1]
	c.assisted = true
	c.gear = 1
	var cut_seen := false
	var acc_before := 0.0
	var acc_during := 99.0
	var last_v: float = c.v
	var last_gear: int = c.gear
	for i in 600:
		c.throttle = 1.0
		rc[0].tick(DT)
		var acc: float = (c.v - last_v) / DT
		if c.gear != last_gear:
			cut_seen = cut_seen or c._shift_t > 0.0 or acc < acc_before * 0.8
			acc_during = min(acc_during, acc)
		elif c._shift_t <= 0.0:
			acc_before = acc
		last_v = c.v
		last_gear = c.gear
		if c.gear >= 3:
			break
	print("   upshift: accel before %.1f m/s², through the shift %.1f" % [acc_before, acc_during])
	_check(c.gear >= 2, "the gearbox upshifts under power")
	_check(cut_seen and acc_during < acc_before, "the drive cuts during the shift")
	rc[0].free()

	# 6. Tyre relaxation: side force builds over a short rolling distance, so a
	# sudden full lock gets most of its grip within a frame at speed but only a
	# fraction of it at walking pace.
	var frac := []
	for sp in [5.0, 40.0]:
		rc = _car(sp)
		c = rc[1]
		c.assisted = false
		c.manual = true
		c.gear = 2 if sp < 10.0 else 4
		c.steer = 1.0
		c.steer_in = 1.0
		rc[0].tick(DT)
		frac.append(abs(c._fy_state[0]) / max(c._nw[0], 1.0))
		rc[0].free()
	print("   front side force after one frame of full lock (per unit load): %.2f at 5 m/s, %.2f at 40 m/s" % [frac[0], frac[1]])
	_check(frac[0] < 0.6 * frac[1], "side force takes longer to build at low speed (tyre relaxation)")
	_check(frac[1] > 0.5, "and is nearly all there within a frame at speed")

	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
