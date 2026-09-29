extends SceneTree
## Restarting and retiring a career from the career hub:
##   - the hub offers RESTART CAREER and RETIRE, each behind a confirm screen
##     whose first (default) choice keeps the career;
##   - starting over in the same car wipes the year, bank, upgrades and record
##     back to a fresh $1,000,000 career in that car;
##   - starting over in a new car goes to car select with no career left;
##   - a race checkpoint from the old career is thrown away.
##   ST_NO_INTRO=1 godot --headless --fixed-fps 60 -s tests/career_restart_test.gd

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
		await process_frame


func _ids() -> Array:
	return main.menu.rows.map(func(r): return r.id)


## A career a few seasons in: money spent, upgrades bought, races won.
func _played_career(team: int) -> void:
	game.new_career(team)
	game.career.money = 42000
	game.career.year = 3
	game.career.upgrades.engine = 3
	game.career.stats.wins = 7
	game.season.round = 4
	game.save_career()
	game.save_season()


## A checkpoint as if the app had closed mid-race in this career.
func _fake_checkpoint() -> void:
	var cf := ConfigFile.new()
	cf.set_value("race", "data", {"mode": "career", "track": 0, "team": 0, "laps": 10, "lap": 3, "cars": [{}], "place": 1})
	cf.save(main.RESUME_PATH)


func _run() -> void:
	game = root.get_node("Game")
	await _frames(20)
	var team := 3
	_played_career(team)
	main.mode = "career"
	main._enter_career_hub()
	await _frames(2)
	var ids := _ids()
	_check(ids.has("restart") and ids.has("retire"), "the career hub offers RESTART CAREER and RETIRE")

	# Restart asks first, and backing out changes nothing.
	main._on_menu_activated("restart")
	await _frames(2)
	_check(main.menu_kind == "career_confirm", "RESTART CAREER asks to confirm")
	_check(_ids()[0] == "cr_cancel" and main.menu.cursor == 0, "the default choice keeps the career")
	main._on_menu_cancelled()
	await _frames(2)
	_check(main.menu_kind == "hub" and int(game.career.year) == 3 and int(game.career.money) == 42000, "backing out keeps the career as it was")

	# Start over in the same car.
	_fake_checkpoint()
	_check(not main.resume_info().is_empty(), "(a checkpoint from this career is waiting)")
	main._on_menu_activated("restart")
	await _frames(2)
	main._on_menu_activated("cr_same")
	await _frames(2)
	var cr: Dictionary = game.career
	_check(int(cr.team) == team, "start over keeps the same car")
	_check(int(cr.year) == 1 and int(cr.money) == game.CAREER_START_MONEY, "year 1 with $%s in the bank" % game.money_text(game.CAREER_START_MONEY))
	_check(int(cr.upgrades.engine) == 0 and int(cr.stats.wins) == 0, "upgrades and record are wiped")
	_check(int(game.season.round) == 0 and game.season.get("career", false), "a fresh season, from race 1")
	_check(main.resume_info().is_empty(), "the old career's race checkpoint is thrown away")
	_check(main.menu_kind == "hub", "and it lands back in the career hub")
	var cf := ConfigFile.new()
	_check(cf.load(game.CAREER_PATH) == OK and int(cf.get_value("career", "data", {}).get("money", 0)) == game.CAREER_START_MONEY, "the fresh career is saved")

	# Start over in a new car: pick a car, and career mode starts afresh with it.
	_played_career(team)
	main._enter_career_hub()
	main._on_menu_activated("restart")
	await _frames(2)
	main._on_menu_activated("cr_new")
	await _frames(2)
	_check(main.state == main.State.CAR_SELECT and main.mode == "career", "start over in a new car goes to car select")
	_check(game.career.is_empty() and not FileAccess.file_exists(game.CAREER_PATH), "with the old career deleted")

	# Retire asks first, then deletes.
	_played_career(team)
	main._enter_career_hub()
	main._on_menu_activated("retire")
	await _frames(2)
	_check(main.menu_kind == "career_confirm" and _ids()[0] == "cr_cancel", "RETIRE asks to confirm, defaulting to keep racing")
	main._on_menu_activated("cr_retire")
	await _frames(2)
	_check(game.career.is_empty() and game.season.is_empty(), "retiring deletes the career and its season")

	main.clear_checkpoint()
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
