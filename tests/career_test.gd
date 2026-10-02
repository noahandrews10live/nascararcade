extends SceneTree
## Career: start, buy R&D, race (earnings/stats), finish a season, roll into year 2.
var main: Node
var game: Node
var failures := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _check(cond: bool, msg: String) -> void:
	print("  ok   " if cond else "  FAIL ", msg)
	if not cond:
		failures += 1


func _race_to_results() -> bool:
	main._start_weekend()
	var t := 0.0
	while main.state != main.State.RESULTS and t < 2400.0:
		await physics_frame
		t += 1.0 / 60.0
	print("    race took %.0fs sim, laps %d, cautions %d, state %d" % [t, main.race.laps, main.race.control.caution_count if main.race.control else -1, main.state])
	return main.state == main.State.RESULTS


func _run() -> void:
	game = root.get_node("Game")
	for i in 10:
		await physics_frame
	var saved: Dictionary = game.settings.duplicate()
	game.settings.length = 0
	game.settings.field = 0
	game.settings.weekend = 0
	main.autopilot = true
	main.mode = "career"
	game.new_career(0)
	main._enter_career_hub()
	_check(main.menu_kind == "hub" and game.career.year == 1, "career hub opens, year 1, bank $%s" % game.money_text(game.career.money))
	_check(game.buy_upgrade("engine") and game.career.upgrades.engine == 1, "bought an engine upgrade")
	_check(not game.buy_upgrade("engine") or game.career.money >= 0, "can't overspend")
	var money0: int = game.career.money
	_check(await _race_to_results(), "career race reaches results")
	var p: Node3D = main.race.player
	# A new career car matches the field; the engine level bought above adds to it.
	var base_power: float = float(game.tracks[game.selected_track].get("hp", 670)) * 745.7 * float(game.teams[0].get("speed", 1.0))
	_check(p.power > base_power * 1.005 and p.power <= base_power * game.upgrade_mult("engine", 1) + 1.0, "the engine upgrade adds its horsepower (%.0f vs %.0f hp stock)" % [p.power / 745.7, base_power / 745.7])
	main._after_season_race()
	_check(game.career.money > money0 and game.career.stats.starts == 1, "earned money and logged a start (%s)" % game.career.last)
	# Jump to the last race of the season.
	game.season.round = game.season.schedule.size() - 1
	main._return_hub()
	_check(await _race_to_results(), "season finale reaches results")
	main._after_season_race()
	if main.state == main.State.MENU and main.menu_kind == "milestone":
		print("   milestones: ", main.menu.rows.map(func(r): return r.label))
		main._on_menu_activated("ms_go") # a milestone first (e.g. a first podium)
	_check(main.state == main.State.STANDINGS, "final standings shown")
	_check(game.career.year == 2 and game.season.round == 0 and game.career.history.size() == 1, "rolled into year 2 (last season: %s)" % game.ordinal(game.career.history[0].pos))
	main._enter_career_stats()
	_check(main.state == main.State.STANDINGS, "career record screen opens")
	game.clear_career()
	game.clear_season()
	game.settings = saved
	game.save_settings()
	print("FAILURES: ", failures)
	quit(1 if failures else 0)
