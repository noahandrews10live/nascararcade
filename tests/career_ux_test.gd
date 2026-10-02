extends SceneTree
## Career extras: the owner's season goal (on the hub, with progress), the
## weekend preview before each race, milestones (celebrated once, with prize
## money), the season-end goal bonus, and the offer of an easier or tougher
## field after a run of races that says so.
##   ST_NO_INTRO=1 godot --headless --fixed-fps 60 -s tests/career_ux_test.gd

var main: Node
var game: Node
var failures := 0
var _saved := {}
const FILES := ["user://career.cfg", "user://career_season.cfg", "user://settings.cfg"]


func _initialize() -> void:
	for f in FILES:
		_saved[f] = FileAccess.get_file_as_bytes(f) if FileAccess.file_exists(f) else null
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _restore() -> void:
	for f in FILES:
		if _saved[f] == null:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		else:
			var fa := FileAccess.open(f, FileAccess.WRITE)
			fa.store_buffer(_saved[f])


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _rows() -> Array:
	return main.menu.rows


func _row(id: String) -> Dictionary:
	for r in main.menu.rows:
		if String(r.get("id", "")) == id:
			return r
	return {}


func _run() -> void:
	game = root.get_node("Game")
	await _frames(20)
	main.clear_checkpoint()
	game.settings.field = 3 # 24 cars? whatever FIELDS[3] is
	game.settings.difficulty = 1
	game.recent = []
	game.track_setups = {}
	game.new_career(2)
	main.mode = "career"
	main._enter_career_hub()
	await _frames(3)
	var goal: int = game.season_goal()
	var field: int = max(game.standings().size(), game.field_size())
	_check(goal == int(round(field * 0.6)), "a rookie's first goal: about the top 60%% of the field (top %d of %d)" % [goal, field])
	var gr := _row("goal")
	_check(String(gr.get("label", "")).contains("TOP %d" % goal) and String(gr.get("hint", "")).begins_with("FINISH TOP %d" % goal), "the hub shows it (%s / %s)" % [gr.get("label", ""), gr.get("hint", "")])
	_check(game.season_goal_text(goal + 2).ends_with("2 PLACES TO GO") and game.season_goal_text(goal).ends_with("ON TARGET"), "with progress: 'n places to go' / 'on target'")
	# The weekend preview.
	main._on_menu_activated("weekend")
	await _frames(3)
	_check(main.menu_kind == "preview" and String(_rows()[0].label) == "GO RACING", "RACE n/m opens the weekend preview, GO RACING first")
	var labels: String = " | ".join(_rows().map(func(r): return String(r.label)))
	print("   ", labels)
	_check(labels.contains("-MILE ") and labels.contains("LAPS"), "the track: length, kind and laps")
	_check(_rows().any(func(r): return String(r.label).begins_with("WEATHER")), "the weather")
	_check(labels.contains("YOUR FORM: NO RACES YET"), "your form (none yet)")
	_check(not _row("rnd").is_empty() and String(_row("rnd").label).begins_with("UPGRADE TIP: "), "the upgrade worth most here, linked to the shop")
	_check(String(_row("garage").label).begins_with("SETUP: STANDARD"), "and the setup")
	for i in 3:
		game.add_recent(game.selected_track, 6 + i * 2, 24)
	main._enter_preview()
	await _frames(2)
	labels = " | ".join(_rows().map(func(r): return String(r.label)))
	_check(labels.contains("YOUR FORM: EXPECT ") and labels.contains("BEST FINISH 6TH"), "after a few races: a finish range, and your best here")
	main._on_menu_activated("pv_back")
	await _frames(2)
	_check(main.menu_kind == "hub", "BACK goes to the hub")
	# Milestones.
	var money0: int = int(game.career.money)
	game.career_race(3, 24, 2, false)
	var got: Array = game.check_milestones(3, false, 2)
	var ids: Array = got.map(func(m): return m.id)
	_check(ids.has("first_start") and ids.has("top10") and ids.has("top5") and ids.has("podium") and ids.has("led") and not ids.has("win"), "a 3rd place leading laps: first start, top 10, top 5, podium, led a lap (%s)" % str(ids))
	var cash := 0
	for m in got:
		cash += int(m.cash)
	_check(int(game.career.money) - money0 > cash and cash > 0, "and the owner pays out for them (+$%d)" % cash)
	_check(game.check_milestones(3, false, 2).is_empty(), "each only once")
	main._enter_milestones(got, "hub")
	await _frames(2)
	_check(main.menu_kind == "milestone" and main.screen.get_children().any(func(c): return c.get_script() and String(c.get_script().resource_path).ends_with("confetti.gd")), "a celebration screen, with confetti")
	_check(_rows().any(func(r): return String(r.label).begins_with("NEXT: ")), "and what to chase next")
	main._on_menu_activated("ms_go")
	await _frames(2)
	_check(main.menu_kind == "hub", "CONTINUE goes on to the hub")
	# Season end: goal met.
	var m1: int = int(game.career.money)
	game.career_season_end(goal, 500, 0)
	var se: Dictionary = game.career.season_end
	_check(se.met and int(se.bonus) >= 250000 and int(game.career.money) - m1 == int(se.bonus), "goal met at season's end: a bonus ($%d)" % int(se.bonus))
	_check(se.milestones.has("goal"), "and the SEASON GOAL milestone")
	_check(game.season_goal() == max(goal - 4, 1), "next year's goal is four places better (top %d)" % game.season_goal())
	main._enter_standings(true)
	await _frames(40)
	var ev := InputEventAction.new()
	ev.action = "start"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(3)
	_check(main.menu_kind == "milestone", "after the final standings: the season's milestones")
	# A run of races that says the field is wrong.
	var D: GDScript = load("res://scripts/debrief.gd")
	game.recent = []
	for i in 3:
		game.add_recent(0, 22, 24)
	_check(game.recent_streak() == "struggling", "three finishes in the back quarter: struggling")
	var base := {"gained": {}, "events": [], "finish": 22, "peak_carcass": [90, 90, 90, 90], "pit_stops": [], "balance": 0.0}
	var tips: Array = D.coach(base, {"field": 24, "difficulty": 1, "streak": game.recent_streak(), "my_best": 15.0, "winner_best": 15.0})
	_check(tips[0].get("action", {}).get("kind", "") == "difficulty" and int(tips[0].action.delta) == -1, "the debrief offers an easier field first")
	_check(tips.filter(func(t): return t.get("action", {}).get("kind", "") == "difficulty").size() == 1, "just once")
	game.recent = []
	for i in 3:
		game.add_recent(0, 1, 24)
	tips = D.coach(base.merged({"finish": 1}, true), {"field": 24, "difficulty": 1, "streak": game.recent_streak(), "career": true})
	_check(tips[0].get("action", {}).get("delta", 0) == 1, "three wins in a row: a tougher field (even in a career)")
	game.settings.difficulty = 0
	_check(game.recent_streak() == "", "a new difficulty starts a new run")
	_restore()
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
