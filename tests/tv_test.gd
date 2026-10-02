extends SceneTree
## The TV broadcast package: the ticker across the top carries the flag, the lap
## and every car in running order; when cars change places their cells slide and
## get green / red arrows; the HUD makes room for it (and gives back the room
## when TV GRAPHICS is SIMPLE); a stage end puts up the stage results board.
##   ST_NO_INTRO=1 godot --headless --fixed-fps 60 -s tests/tv_test.gd

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
	await _frames(20)
	main.clear_checkpoint()
	game.settings.weather = 0
	game.settings.field = 0
	game.settings.weekend = 0
	game.settings.cautions = 1
	game.settings.tv_graphics = 1
	main.mode = "race"
	main.session = "race"
	main._use_track(0)
	main._enter_countdown()
	main.autopilot = true
	while main.state != main.State.RACE:
		await physics_frame
	await _frames(10)
	var tk: Control = main.tv_ticker
	_check(tk.visible and main.hud.top > 20.0 and main.hud.ticker_on, "the ticker is up and the HUD has moved down for it (top %.0f)" % main.hud.top)
	_check(not main.hud.l_board.visible and not main.hud.l_flag.visible, "the old top-5 board and flag banner step aside")
	_check(not main.showtime._ticker.visible, "and the old bottom ticker too")
	_check(tk._slot.size() == main.race.cars.size(), "every car has a cell (%d)" % tk._slot.size())
	# Watch for position changes over a while of pack racing.
	var changes := 0
	var slid := false
	for i in 60 * 40:
		await physics_frame
		changes = max(changes, tk._change.size())
		for c in tk._slot:
			var target: int = main.race.order.find(c)
			if abs(float(tk._slot[c]) - float(target)) > 0.1:
				slid = true
	_check(changes > 0, "places change and the cells get arrows (up to %d at once)" % changes)
	_check(slid, "cells slide to their new places rather than jump")
	_check(tk._gap_text.get(main.race.order[0], "") == "LEADER" and String(tk._gap_text.get(main.race.order[1], "")).begins_with("+"), "the leader says LEADER, the rest the gap (%s)" % tk._gap_text.get(main.race.order[1], ""))
	# The stage board.
	main.race.control._end_stage()
	await _frames(3)
	_check(tk._stage_t > 0.0 and tk._stage_board.size() == 2 and tk._stage_board[1].size() == 10, "a stage end puts up the top 10")
	# SIMPLE: the old HUD back.
	game.settings.tv_graphics = 0
	await _frames(3)
	_check(not tk.visible and main.hud.top == 0.0 and main.hud.l_flag.visible, "TV GRAPHICS: SIMPLE gives the old HUD back")
	game.settings.tv_graphics = 1
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
