extends SceneTree
## The saved game online, and moving to a new phone (against tests/tools/fake_cloud.py):
##   - progress and the garage go up by themselves a few seconds after they change;
##   - the old phone makes a code; the new phone (nothing saved yet) enters it and
##     gets the account, its friend code and the whole saved game;
##   - the old phone is signed out;
##   - daily streaks: +XP a day, broken by a missed day, CHECKERED at 7 days.
##   python3 tests/tools/fake_cloud.py 24791 &
##   ST_CLOUD=http://127.0.0.1:24791 ST_NO_INTRO=1 godot --headless --fixed-fps 60 -s tests/cloud_save_test.gd

var main: Node
var failures := 0


func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://cloud.cfg"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://progress.cfg"))
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


func _await_cb(start: Callable, limit := 600) -> Array:
	var box := {"done": false, "args": []}
	start.call(func(a = null, b = null):
		box.done = true
		box.args = [a, b])
	var n := 0
	while not box.done and n < limit:
		await process_frame
		n += 1
	return box.args


func _run() -> void:
	var game: Node = root.get_node("Game")
	var cloud: Node = main.cloud
	var n := 0
	while not cloud.registered() and n < 600:
		await process_frame
		n += 1
	_check(cloud.registered(), "registered")
	# The old phone plays: XP and a custom driver.
	game.progress.xp = 4321
	game.save_progress()
	game.custom.driver = "PHONE ONE"
	game.save_custom()
	n = 0
	while cloud.last_sync == "" and n < 900:
		await process_frame
		n += 1
	_check(cloud.last_sync != "", "the saved game went up by itself (%.1f s after the change)" % (n / 60.0))
	var old_id: String = cloud.id
	var old_secret: String = cloud.secret
	var old_code: String = cloud.friend_code
	var r: Array = await _await_cb(func(cb): cloud.transfer_code(cb))
	_check(r[0] == true and String(r[1]).length() == 8, "MOVE TO A NEW PHONE gives a code: %s" % String(r[1]))
	var code := String(r[1])
	# A new phone: nothing on it.
	for f in cloud.SYNC_FILES + ["cloud.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + f))
	cloud.id = ""
	cloud.secret = ""
	cloud.friend_code = ""
	cloud.last_sync = ""
	game.progress.xp = 0
	game.custom.driver = "NEW PHONE"
	var c: Array = await _await_cb(func(cb): cloud.claim(code.to_lower(), cb))
	_check(c[0] == true, "the new phone enters it: %s" % String(c[1]))
	_check(cloud.id == old_id and cloud.friend_code == old_code, "same account, same friend code")
	_check(int(game.progress.xp) == 4321 and String(game.custom.driver) == "PHONE ONE", "and the whole saved game (%d XP, %s)" % [int(game.progress.xp), game.custom.driver])
	var cf := ConfigFile.new()
	_check(cf.load("user://progress.cfg") == OK and int(cf.get_value("progress", "xp", 0)) == 4321, "written to this phone")
	var again: Array = await _await_cb(func(cb): cloud.claim(code, cb))
	_check(again[0] == false, "a code works once")
	# The old phone's secret no longer works.
	var keep_secret: String = cloud.secret
	cloud.secret = old_secret
	var old: Array = await _await_cb(func(cb): cloud.push_save(cb))
	_check(old[0] == false, "the old phone is signed out")
	cloud.secret = keep_secret
	# The account screen.
	main._enter_account()
	await _frames(3)
	var labels: Array = main.menu.rows.map(func(r): return String(r.label))
	_check(labels.any(func(l): return l.contains(old_code)) and labels.has("MOVE TO A NEW PHONE"), "ACCOUNT shows the friend code and MOVE TO A NEW PHONE")
	# Streaks.
	game.progress.streak = 6
	game.progress.best_streak = 6
	game.progress.streak_day = game._day_key(-1)
	var xp0 := int(game.progress.xp)
	var st: Dictionary = game.add_streak_day()
	_check(int(st.streak) == 7 and int(game.progress.xp) == xp0 + 700, "day 7 in a row: +700 XP")
	_check(st.unlocked_scheme and game.scheme_unlocked(7), "and the CHECKERED scheme")
	_check(int(game.add_streak_day().xp) == 0, "only once a day")
	game.progress.streak_day = game._day_key(-3)
	_check(game.streak_now() == 0 and int(game.add_streak_day().streak) == 1, "a missed day starts it again")
	_check(game.scheme_unlocked(7), "the scheme stays unlocked")
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
