extends SceneTree
## In-race goals (goals.gd):
##   - every race sets them: a stage gain, lead a lap, beat a rival who starts
##     just ahead of you;
##   - the stage goal is judged at the stage's end (the real one, run here), and
##     the next stage's goal is set from where you finished it;
##   - leading a lap pays the moment it happens, in gold on the ticker;
##   - a car that wrecks you becomes the rival;
##   - beating the rival is judged at the flag, and the goals' XP goes into the
##     race's award.
##   godot --headless --fixed-fps 60 -s tests/goals_test.gd

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


func _run() -> void:
	game = root.get_node("Game")
	for i in 20:
		await physics_frame
	main.clear_checkpoint()
	game.settings.length = 1
	game.settings.field = 1
	game.settings.weather = 0
	game.settings.weekend = 0
	game.settings.cautions = 0
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
	var p: Node3D = race.player
	var gl: Node = main.goals
	_check(gl != null, "the race has goals")
	if gl == null:
		quit(1)
		return
	var ids: Array = gl.goals.map(func(g): return g.id)
	print("   goals: %s" % str(gl.goals.map(func(g): return g.text)))
	_check(ids.has("stage1") and ids.has("lead") and ids.has("rival"), "a stage gain, lead a lap and beat a rival")
	_check(gl.rival != null and int(gl.rival.get_meta("grid")) < int(p.get_meta("grid")), "the rival starts ahead of you")
	var s1: Dictionary = gl._goal("stage1")
	print("   stage 1 from P%d: target P%d" % [gl._pos(p), int(s1.target)])
	_check(int(s1.target) == max(1, gl._pos(p) - 3), "three spots to gain in the stage")

	# The stage, run for real (a short one).
	while not race.running:
		await physics_frame
	ctl.stage_ends.assign([race.order[0].lap() + 2, 100000])
	var n := 0
	while ctl.stage == 1 and n < 60 * 240:
		await physics_frame
		n += 1
	_check(ctl.stage == 2, "stage 1 ends")
	var s2: Dictionary = gl._goal("stage2")
	print("   stage 1: %s (P%d at the end), stage 2 goal: %s" % [{1: "DONE", -1: "MISSED", 0: "OPEN"}[int(s1.state)], race.order.find(p) + 1, s2.get("text", "-")])
	_check(int(s1.state) != 0, "judged at the stage's end")
	_check(not s2.is_empty() and int(s2.state) == 0, "and the next stage's goal is set")

	# Leading a lap.
	var e0: int = gl.earned
	p.laps_led += 1
	await _frames(2)
	var lead: Dictionary = gl._goal("lead")
	_check(int(lead.state) == 1 and gl.earned == e0 + gl.XP_LEAD, "leading a lap pays %d XP at once" % gl.XP_LEAD)
	var tk: Dictionary = gl.ticker()
	_check(tk.gold and String(tk.text).contains("LEAD A LAP"), "in gold on the ticker")
	main.hud.crew_time = 0.0
	await process_frame
	await process_frame
	_check(main.hud.l_goal.visible and String(main.hud.l_goal.text).contains("LEAD A LAP"), "the HUD shows it")
	gl.flash_t = 0.0
	tk = gl.ticker()
	print("   ticker: %s" % tk.text)
	_check(not tk.gold and String(tk.text).begins_with("GOAL:"), "then the open goals, in turn")

	# A car that wrecks you is the rival.
	var o: Node3D = null
	for c in race.cars:
		if c != p and c != gl.rival and not c.out:
			o = c
			break
	p.rivals[o] = 0.8
	await _frames(2)
	_check(gl.rival == o and String(gl.flash).contains("NEW RIVAL"), "a car that wrecks you is the rival now")

	# The flag: beat the rival, the rest missed, the XP in the award.
	gl._on_finished(p, 3)
	_check(int(gl._goal("rival").state) == 1, "ahead of the rival at the flag: done")
	_check(gl.goals.all(func(g): return int(g.state) != 0), "everything else judged")
	var e: int = gl.earned
	var a: Dictionary = game.award_race(5, 20, 10, false, e)
	print("   goals earned %d XP; award %d" % [e, int(a.xp)])
	_check(int(a.xp) == 60 + 15 * 8 + 10 * 6 + e and int(a.goals) == e, "the goals' XP goes into the race's award")
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
