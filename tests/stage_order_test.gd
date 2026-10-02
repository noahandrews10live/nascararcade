extends SceneTree
## Stage breaks: the field restarts in the order it finished the stage, whether
## a car pits or not (quick cautions and full ones), so a stop is free and the
## crew chiefs all take one; other cautions still put pitters behind the cars
## that stay out.
##   ST_NO_INTRO=1 godot --headless --fixed-fps 60 -s tests/stage_order_test.gd

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


func _nums(a: Array) -> Array:
	return a.map(func(c): return c.team.num)


func _start(quick: bool) -> void:
	main.clear_checkpoint()
	game.settings.weather = 0
	game.settings.field = 0
	game.settings.weekend = 0
	game.settings.cautions = 1 if quick else 2
	game.settings.length = 2
	main.mode = "race"
	main.session = "race"
	main._use_track(1)
	main._enter_countdown()
	main.autopilot = true
	while main.state != main.State.RACE:
		await physics_frame
	await _frames(60 * 50)


## You drive again (the autopilot's car is an AI, which makes its own pit calls).
func _hand_back() -> void:
	main.autopilot = false
	main.race.player.autopilot_forced = false
	main.race.player.ai = false


## The lead-lap cars in running order.
func _lead_lap(ctl: Node) -> Array:
	var lead: Node3D = main.race.order[0]
	return main.race.order.filter(func(c): return not c.out and not c.towed and ctl._laps_down(c, lead) == 0)


func _run() -> void:
	game = root.get_node("Game")
	await _frames(20)
	# --- quick caution at a stage break
	await _start(true)
	var ctl: Node = main.race.control
	_hand_back()
	ctl._end_stage() # the leader takes the stage: stage-end caution
	var frozen: Array = _nums(ctl._freeze)
	_check(ctl.stage_break and ctl.flag == ctl.Flag.YELLOW, "a stage end throws a stage-break caution")
	var n := 0
	while not (main.pit_menu and is_instance_valid(main.pit_menu)) and n < 60 * 30:
		await physics_frame
		n += 1
	_check(main.pit_menu != null, "the pit call comes")
	var info: Dictionary = main._pit_info
	_check(info.stage_break and info.estimate.values().all(func(v): return int(v) == int(info.position)), "the pit call: every choice restarts where you finished the stage (%s, you %s)" % [str(info.estimate), info.position])
	_check(str(main.pit_menu.get_children().filter(func(c): return c is Label).map(func(l): return l.text)).contains("STAGE BREAK"), "and it says the stop is free")
	main.pit_menu.set_value("plan", info.options.find("4"))
	main._close_pit_menu()
	await _frames(3)
	var pitted: int = ctl._calls.values().filter(func(v): return v != "").size()
	var order: Array = _nums(_lead_lap(ctl))
	var want: Array = frozen.filter(func(x): return order.has(x))
	print("   stage order %s\n   restart     %s\n   %d of %d pitted" % [str(want.slice(0, 10)), str(order.slice(0, 10)), pitted, ctl._calls.size()])
	_check(order.size() > 5 and order == want, "the restart order is the stage's finishing order")
	_check(pitted >= ctl._calls.size() * 0.7, "and most crews take the free stop (%d of %d)" % [pitted, ctl._calls.size()])
	# --- an ordinary caution still costs pitters their spots
	await _frames(60 * 20)
	var w := 0
	while ctl.flag != ctl.Flag.GREEN and w < 60 * 120:
		await physics_frame
		w += 1
		if w % 300 == 0:
			print("   waiting for green: flag %d phase '%s' armed %s one_to_go %s laps %d/%d" % [ctl.flag, ctl.quick_phase, ctl.restart_armed, ctl.one_to_go, ctl.caution_laps, ctl.caution_needed_laps])
	_check(ctl.flag == ctl.Flag.GREEN, "the stage break ends: green again")
	await _frames(60 * 10)
	_hand_back()
	ctl.throw_caution("DEBRIS", null)
	_check(not ctl.stage_break, "a debris caution is not a stage break")
	n = 0
	while not (main.pit_menu and is_instance_valid(main.pit_menu)) and n < 60 * 30:
		await physics_frame
		n += 1
	info = main._pit_info
	_check(int(info.estimate["4"]) > int(info.estimate[""]) or int(info.position) >= int(info.field) - 1, "there, pitting puts you behind the cars that stay out (%s)" % str(info.estimate))
	main._close_pit_menu()
	await _frames(3)
	# --- full cautions at a stage break
	main._enter_title()
	await _frames(5)
	await _start(false)
	ctl = main.race.control
	ctl.quick = false
	while ctl.flag != ctl.Flag.GREEN:
		await physics_frame # (a caution of its own first)
	ctl._end_stage()
	frozen = _nums(ctl._freeze)
	_check(ctl.stage_break and frozen.size() > 10, "full caution: a stage break, the order frozen (%d cars)" % frozen.size())
	n = 0
	while not ctl.one_to_go and n < 60 * 360: # (the whole field stops: a lap and a half)
		await physics_frame
		n += 1
	await _frames(2)
	_check(ctl.one_to_go, "full caution: ONE TO GO (%.0f s)" % (n / 60.0))
	print("   at one to go: order %d, lead lap %d, pit states %s, leader #%s" % [main.race.order.size(), _lead_lap(ctl).size(), str(main.race.order.map(func(c): return c.pit_state)), main.race.order[0].team.num])
	order = _nums(_lead_lap(ctl).filter(func(c): return c.pit_state == 0))
	want = frozen.filter(func(x): return order.has(x))
	print("   stage order %s\n   lined up    %s" % [str(want.slice(0, 10)), str(order.slice(0, 10))])
	_check(order.size() > 5 and order == want, "full caution: lined up in the stage's finishing order")
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
