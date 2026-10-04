extends SceneTree
## Restarts are a skill:
##   - the AI leader goes somewhere inside the restart zone, and the field reacts
##     to the green in its own time (the leader first, the others a beat later);
##   - your car rolls on at pace after the green until you hit the gas, and the
##     time it took is called ("RESTART: 0.20 s");
##   - hitting the gas in the restart window before the green is jumping it: the
##     black flag, and a pass-through down pit road (no stop) that you then serve;
##   - leading, you choose: the gas before the zone is a jump, in the zone it
##     throws the green there and then.
##   godot --headless --fixed-fps 60 -s tests/restart_test.gd

var main: Node
var game: Node
var failures := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


## A caution, the pit call taken as it stands (or STAY OUT), and on to the
## restart window.
func _to_window(ctl: Node, stay_out := false) -> bool:
	ctl.throw_caution("test", null)
	var n := 0
	while not (ctl.restart_armed and ctl.restart_window) and n < 60 * 120:
		if main.pit_menu and is_instance_valid(main.pit_menu):
			if stay_out:
				var opts: Array = main._pit_info.options
				main.pit_menu.set_value("plan", opts.find(""))
			main._close_pit_menu()
		if main.pit_show and main.pit_show.showing:
			main.pit_show._end_show()
		await physics_frame
		n += 1
	return ctl.restart_window


func _human(p: Node3D) -> void:
	main.autopilot = false
	p.autopilot_forced = false


## Put your car at the front of the field (same lap), so you lead the restart.
func _to_front(p: Node3D) -> void:
	main.race._update_order()
	var lead: Node3D = main.race.order[0]
	if lead != p:
		p.dist = lead.dist + 30.0
		p.d = lead.d
		p.v = lead.v
		p.sync_visual()
	main.race._update_order()


func _robot() -> void:
	main.autopilot = true


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
	game.settings.caution_drive = 0 # (AUTO: the car follows the pace car; caution_drive_test covers YOU DRIVE)
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
	ctl.stage_ends.assign([]) # (no stage breaks: they set their own restart order)
	await _frames(60 * 25)
	var p: Node3D = race.player

	# 1. A normal restart: wait for the green, then the gas.
	_check(await _to_window(ctl), "a caution comes round to the restart window")
	_human(p)
	await _frames(2)
	print("   under caution the HUD says: '%s'" % main.hud.auto_reason)
	_check(String(main.hud.auto_reason).begins_with("CAUTION") and main.hud.l_auto.visible, "the HUD says the car is following the pace car until the green")
	var go_at: float = ctl.restart_go_at
	var n := 0
	while ctl.flag == ctl.Flag.YELLOW and n < 60 * 30:
		await physics_frame
		n += 1
	var lead: Node3D = race.order[0]
	var lead_to_line: float = fposmod(-lead.s(), race.track.length)
	print("   leader went %.0f m before the line (planned %.0f, zone %.0f)" % [lead_to_line, go_at, ctl.RESTART_ZONE])
	_check(ctl.flag != ctl.Flag.YELLOW and lead_to_line < ctl.RESTART_ZONE + 3.0, "the leader goes inside the restart zone")
	var holds := []
	for c in race.cars:
		if c != lead and c != p and not c.out:
			holds.append(c.launch_hold)
	holds.sort()
	print("   AI reactions %.2f .. %.2f s, the leader %.2f" % [holds[0], holds[-1], lead.launch_hold])
	_check(lead.launch_hold == 0.0 and holds[0] > 0.05 and holds[-1] > holds[0] + 0.1, "the field reacts in its own time, the leader first")
	_check(p.launch_hold > 1.0, "your car waits for your gas")
	await _frames(12)
	_check(p.ai and p.launch_hold > 0.0, "and rolls on at pace until then")
	_check(String(main.hud.auto_reason).contains("HIT THE GAS"), "with the HUD saying so")
	Input.action_press("accelerate")
	await _frames(3)
	var react: float = float(p.get_meta("restart_reaction", -1.0))
	print("   your reaction %.2f s; crew call '%s'" % [react, main.hud.l_crew.text])
	_check(p.launch_hold == 0.0 and react > 0.15 and react < 0.35, "the gas launches you, and the reaction is timed")
	_check(String(main.hud.l_crew.text).contains("RESTART"), "and called")
	Input.action_release("accelerate")
	_check(p.penalty == "", "no penalty for a clean restart")
	_robot()
	await _frames(60 * 20)

	# 2. Jumping it: the gas in the window before the green.
	_check(await _to_window(ctl), "the next restart")
	_human(p)
	await _frames(2)
	Input.action_press("accelerate")
	await _frames(3)
	Input.action_release("accelerate")
	_check(p.penalty == "PT" and p.want_pit, "the gas before the green is a jump: a pass-through penalty")
	_robot()
	var states := {}
	n = 0
	while (p.penalty != "" or p.pit_state != 0 or not states.has(ctl.Pit.EXIT)) and n < 60 * 200:
		await physics_frame
		states[p.pit_state] = true
		n += 1
	print("   pit states on the penalty %s" % str(states.keys()))
	_check(states.has(ctl.Pit.LANE) and states.has(ctl.Pit.EXIT) and not states.has(ctl.Pit.SERVICE) and p.pit_state == 0 and p.penalty == "", "served as a pass-through: down pit road, no stop")
	await _frames(60 * 10)

	# 2b. On a phone (the gas is half the screen), a touch before the green is
	# never a jump: it's ignored, and the car is yours a moment after the green.
	_check(await _to_window(ctl), "a restart on a phone")
	main.touch.active = true
	_human(p)
	await _frames(2)
	Input.action_press("accelerate")
	await _frames(3)
	Input.action_release("accelerate")
	_check(p.penalty == "" and not p.want_pit, "a touch on the gas before the green isn't a jump")
	n = 0
	while ctl.flag == ctl.Flag.YELLOW and n < 60 * 30:
		await physics_frame
		n += 1
	await _frames(int(60 * 1.2))
	_check(p.launch_hold == 0.0 and not p.ai, "and the car is yours within a second of the green, gas or not")
	main.touch.active = false
	_robot()
	await _frames(60 * 10)

	# 3. Leading the restart: the gas before the zone is a jump, even for the
	# leader (served like any other)...
	_to_front(p)
	_check(await _to_window(ctl, true), "a restart with you in the lead")
	_check(race.order[0] == p, "you lead it")
	_human(p)
	await _frames(2)
	if ctl.restart_to_zone > 5.0:
		Input.action_press("accelerate")
		await _frames(2)
		Input.action_release("accelerate")
		_check(p.penalty == "PT", "leading, the gas before the zone is a jump")
	_robot()
	n = 0
	while (p.penalty != "" or p.pit_state != 0) and n < 60 * 200:
		await physics_frame
		n += 1
	await _frames(60 * 10)

	# ... and in the zone, your gas throws the green.
	_to_front(p)
	_check(await _to_window(ctl, true), "another restart with you in the lead")
	_human(p)
	n = 0
	while ctl.restart_to_zone > -10.0 and ctl.flag == ctl.Flag.YELLOW and n < 60 * 30:
		await physics_frame
		n += 1
	_check(ctl.flag == ctl.Flag.YELLOW, "the green waits for you in the zone")
	print("   in the zone: %.0f m in, leading %s, pit state %d, penalty '%s'" % [-ctl.restart_to_zone, race.order[0] == p, p.pit_state, p.penalty])
	Input.action_press("accelerate")
	await _frames(3)
	Input.action_release("accelerate")
	print("   after the gas: flag %d, launch hold %.2f, penalty '%s'" % [ctl.flag, p.launch_hold, p.penalty])
	_check(ctl.flag != ctl.Flag.YELLOW and p.launch_hold == 0.0, "in the zone, your gas throws the green")
	_robot()
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
