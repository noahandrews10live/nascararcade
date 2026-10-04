extends SceneTree
## CAUTION DRIVING: YOU DRIVE. Under yellow the car is yours:
##   - it isn't driven for you (the HUD says hold your spot, and the limit);
##   - flat out, the limiter holds you to the field's pace and keeps your gap:
##     you can't run into the car in front;
##   - pass a car under yellow and the spotter says give it back: do, and that's
##     that; don't, and it's a pass-through;
##   - at the green you're already driving (nothing to wait for);
##   - AUTO: the car follows the pace car itself, as before.
##   godot --headless --fixed-fps 60 -s tests/caution_drive_test.gd

var main: Node
var game: Node
var failures := 0
var said: Array = []


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1


func _heard(part: String) -> bool:
	return said.any(func(t): return String(t).contains(part))


## A driver: flat out (the limiter does the rest), steering to hold the lane.
func _drive(p: Node3D, lane: float) -> void:
	Input.action_press("accelerate")
	var steer: float = clamp((lane - p.d) * 0.12 - p.yaw * 1.5, -1.0, 1.0)
	if steer > 0.02:
		Input.action_press("steer_right", steer)
		Input.action_release("steer_left")
	elif steer < -0.02:
		Input.action_press("steer_left", -steer)
		Input.action_release("steer_right")
	else:
		Input.action_release("steer_left")
		Input.action_release("steer_right")


func _hands_off() -> void:
	for a in ["accelerate", "brake", "steer_left", "steer_right"]:
		Input.action_release(a)


## Through the pit call (staying out) to the lined-up field.
func _past_pit_call(ctl: Node, p: Node3D) -> void:
	var n := 0
	while (ctl.quick_phase == "slow" or ctl.quick_phase == "decide") and n < 60 * 60:
		if main.pit_menu and is_instance_valid(main.pit_menu):
			main.pit_menu.set_value("plan", main._pit_info.options.find(""))
			main._close_pit_menu()
		if main.pit_show and main.pit_show.showing:
			main.pit_show._end_show()
		_drive(p, p.d)
		await physics_frame
		n += 1


func _run() -> void:
	game = root.get_node("Game")
	for i in 20:
		await physics_frame
	main.clear_checkpoint()
	game.settings.length = 1
	game.settings.field = 0
	game.settings.weather = 0
	game.settings.weekend = 0
	game.settings.cautions = 1
	game.settings.pit_view = 0
	game.settings.auto_gas = 0
	game.settings.caution_drive = 1
	game.tracks[1].full_laps = 600
	main.mode = "race"
	main.session = "race"
	main._use_track(1)
	main._enter_track_select()
	main._enter_car_select()
	main._enter_countdown()
	main.autopilot = true
	var race = main.race
	var ctl = race.control
	ctl.debris_rate = 0.0
	ctl.stage_ends.assign([])
	ctl.message.connect(func(t, _k): said.append(t))
	for i in 60 * 25:
		await physics_frame
	var p: Node3D = race.player

	# 1. Under yellow, the car is yours.
	ctl.throw_caution("test", null)
	main.autopilot = false
	p.autopilot_forced = false
	for i in 30:
		_drive(p, p.d)
		await physics_frame
	_check(not p.ai, "under yellow the car isn't driven for you")
	print("   HUD: '%s'" % main.hud.auto_reason)
	_check(String(main.hud.auto_reason).contains("HOLD YOUR SPOT"), "the HUD says hold your spot, with the limit")
	await _past_pit_call(ctl, p)
	# 2. Flat out behind the line: held to the pace, the gap kept.
	var over := 0.0
	var min_gap := 1e9
	var n := 0
	var lane: float = p.d
	while ctl.flag == ctl.Flag.YELLOW and ctl.caution_elapsed < 28.0 and n < 60 * 40:
		_drive(p, lane)
		await physics_frame
		n += 1
		over = max(over, p.v - ctl.caution_cap(p))
		for c in race.cars:
			if c != p and abs(c.d - p.d) < 2.0 and not c.out:
				var g: float = race._gap(p, c)
				if g > 0.0:
					min_gap = min(min_gap, g)
	print("   flat out under yellow: at most %.1f m/s over the limit, closest %.1f m (centres) to the car ahead" % [over, min_gap])
	_check(over < 3.0, "the limiter holds you to the field's pace")
	_check(min_gap > 5.5, "and keeps your gap (no running into the car in front)")

	# 3. Passing under yellow.
	if ctl.flag == ctl.Flag.YELLOW:
		var victim: Node3D = null
		for c in race.order:
			if c != p and c.dist > p.dist and c.pit_state == 0 and not c.out:
				if victim == null or c.dist < victim.dist:
					victim = c
		if victim:
			var back_to: float = p.dist
			said.clear()
			p.dist = victim.dist + 8.0 # (alongside, then by)
			p.d = victim.d + 3.6
			for i in 20:
				_drive(p, p.d)
				await physics_frame
			_check(_heard("GIVE IT BACK"), "pass a car under yellow: the spotter says give it back")
			p.dist = victim.dist - 12.0
			p.d = victim.d
			for i in 20:
				_drive(p, p.d)
				await physics_frame
			_check(_heard("BACK WHERE YOU BELONG") and p.penalty == "", "give it back: no penalty")
			# Again, and keep it this time.
			said.clear()
			p.dist = victim.dist + 8.0
			p.d = victim.d + 3.6
			n = 0
			while p.penalty == "" and ctl.flag == ctl.Flag.YELLOW and n < 60 * 12:
				_drive(p, p.d)
				await physics_frame
				n += 1
			print("   kept it: penalty '%s' after %.1f s" % [p.penalty, n / 60.0])
			_check(p.penalty == "PT" and _heard("PASSING UNDER CAUTION"), "keep it: a pass-through")
			p.penalty = ""
			p.want_pit = false
			if p.pit_state == 1:
				p.pit_state = 0
	# 4. The green: already yours.
	n = 0
	while ctl.flag == ctl.Flag.YELLOW and n < 60 * 60:
		_drive(p, p.d)
		await physics_frame
		n += 1
	await physics_frame
	print("   at the green: ai %s, launch hold %.1f" % [p.ai, p.launch_hold])
	_check(ctl.flag != ctl.Flag.YELLOW and not p.ai and p.launch_hold == 0.0, "at the green you're already driving")
	_hands_off()

	# 5. AUTO: the car follows the pace car.
	main.autopilot = true
	for i in 60 * 10:
		await physics_frame
	game.settings.caution_drive = 0
	ctl.throw_caution("test", null)
	main.autopilot = false
	p.autopilot_forced = false
	for i in 30:
		await physics_frame
	_check(p.ai and String(main.hud.auto_reason).begins_with("CAUTION: THE CAR FOLLOWS"), "AUTO: the car follows the pace car itself")
	main.autopilot = true
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
