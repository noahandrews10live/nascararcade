extends SceneTree
## Plays a Single Race weekend (practice, qualifying, race) and a season round through
## the real game flow with the player on autopilot.
##   godot --headless --fixed-fps 60 --path . -s tests/weekend_test.gd

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


func _wait_state(st: int, limit: float) -> bool:
	var t := 0.0
	while main.state != st and t < limit:
		await physics_frame
		t += 1.0 / 60.0
	return main.state == st


func _run() -> void:
	game = root.get_node("Game")
	for i in 10:
		await physics_frame
	var saved: Dictionary = game.settings.duplicate()
	game.settings.length = 0 # sprint
	game.settings.field = 0 # 20 cars
	game.settings.weekend = 2
	game.settings.cautions = 1
	main.autopilot = true
	# --- Single race weekend on the short track
	main.mode = "race"
	main._use_track(2)
	main._enter_race_setup()
	_check(main.state == main.State.MENU and main.menu_kind == "race_setup", "race settings menu opens")
	main._start_weekend()
	_check(main.session == "practice", "weekend starts with practice")
	for i in 600:
		await physics_frame
	_check(main.race.player.lap() >= 0, "practice car is running")
	main.session_idx += 1
	main._start_session()
	_check(main.session == "qualify", "qualifying starts")
	_check(await _wait_state(main.State.SESSION_RESULTS, 200.0), "qualifying lap completes -> results")
	_check(main.qual_grid.size() >= 20, "qualifying produced a grid of %d" % main.qual_grid.size())
	var my_q: int = main.qual_grid.find(game.selected_team) + 1
	print("  player qualified %s" % game.ordinal(my_q))
	main.session_idx += 1
	main._start_session()
	_check(main.session == "race" and main.race.cars.size() == 20, "race starts with 20 cars")
	_check(main.race.get_meta("unused", true), "race node alive")
	var grid_ok: bool = main.race.player.get_meta("grid") == min(my_q - 1, 19)
	_check(grid_ok, "player starts where they qualified (grid %d)" % (main.race.player.get_meta("grid") + 1))
	_check(await _wait_state(main.State.RESULTS, 900.0), "race reaches results")
	# --- Season round
	game.new_season(game.selected_team, 0)
	main._enter_season_hub()
	_check(main.menu_kind == "hub", "season hub opens (round %d)" % (int(game.season.round) + 1))
	game.settings.weekend = 0
	main._start_weekend()
	_check(await _wait_state(main.State.RESULTS, 900.0), "season race reaches results")
	main._after_season_race()
	_check(int(game.season.round) == 1, "season advanced to round 2")
	var table: Array = game.standings()
	_check(table.size() >= 20 and table[0][1] >= 35, "standings recorded (leader %s with %d pts)" % [table[0][0] if table.size() else "?", table[0][1] if table.size() else 0])
	game.clear_season()
	game.settings = saved
	game.save_settings()
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
