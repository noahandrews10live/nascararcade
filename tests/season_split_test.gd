extends SceneTree
## Season mode and the career keep separate seasons: a career in one car and a
## Season in another don't take over each other (the car, the standings and the
## points stay with their own mode, across restarts too). An old save with the
## career's season in season.cfg is moved to its own file.
##   ST_NO_INTRO=1 godot --headless --fixed-fps 60 -s tests/season_split_test.gd

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


func _run() -> void:
	game = root.get_node("Game")
	await _frames(20)
	main.clear_checkpoint()
	var career_car := 2 # e.g. your car
	var season_car := 5 # #31
	# A career in one car, a couple of races in.
	game.use_season(true)
	game.new_career(career_car)
	game.season.round = 2
	game.season.points[game.teams[career_car].num] = 77
	game.save_season()
	# Then a Season in another car.
	game.use_season(false)
	game.new_season(season_car, 0)
	game.season.points[game.teams[season_car].num] = 12
	game.save_season()
	# Back to the career.
	main.mode = "career"
	main._enter_career_hub()
	await _frames(2)
	_check(game.selected_team == career_car, "the career hub drives the career's car (#%s)" % game.teams[career_car].num)
	_check(int(game.season.team) == career_car and int(game.season.round) == 2, "and its own season: same car, round 3 still next")
	_check(int(game.season.points.get(game.teams[career_car].num, 0)) == 77, "with its own points")
	# And Season mode still has its own.
	main._enter_season_hub()
	await _frames(2)
	_check(game.selected_team == season_car and int(game.season.team) == season_car, "Season mode still drives its car (#%s)" % game.teams[season_car].num)
	_check(int(game.season.points.get(game.teams[season_car].num, 0)) == 12 and not game.season.get("career", false), "with its own points")
	# Both survive a restart of the game (loading from disk).
	game._season_career = false
	game.load_season()
	game.load_career()
	game.use_season(true)
	_check(int(game.season.team) == career_car and int(game.season.round) == 2, "after a restart the career's season is still the career's")
	game.use_season(false)
	_check(int(game.season.team) == season_car, "and Season mode's is still Season mode's")

	# An old save: the career's season in season.cfg (as before the split).
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.CAREER_SEASON_PATH))
	var cf := ConfigFile.new()
	cf.set_value("season", "data", {"team": career_car, "round": 4, "career": true, "schedule": [0, 1, 2, 3, 4, 5], "points": {}, "wins": {}, "top5": {}, "history": []})
	cf.save(game.SEASON_PATH)
	game._split_seasons()
	game._season_career = false
	game.load_season()
	_check(game.season.is_empty(), "an old career season moves out of Season mode's file")
	game.use_season(true)
	_check(int(game.season.get("round", -1)) == 4, "into the career's own")

	# Clean up.
	game.clear_season()
	game.use_season(false)
	game.clear_season()
	game.clear_career()
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
