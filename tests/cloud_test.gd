extends SceneTree
## The online career against a stand-in server (tests/tools/fake_cloud.py):
##   - the game registers you on first run (id, secret, friend code, saved);
##   - a new best lap goes to the leaderboard with its ghost; a slower one doesn't;
##   - an impossible lap time is refused;
##   - adding a friend by code, then chasing their ghost in practice;
##   - the daily challenge result and the weekly time trial boards;
##   - XP and levels after a race, and schemes locked until their level;
##   - the frame-rate stats after a race;
##   - the LEADERBOARDS screen shows the times.
##   python3 tests/tools/fake_cloud.py 24790 &
##   ST_CLOUD=http://127.0.0.1:24790 godot --headless --fixed-fps 60 -s tests/cloud_test.gd

var main: Node
var failures := 0
var base := OS.get_environment("ST_CLOUD")


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


## Waits for a callback-style call: `start` gets a Callable to call with the result.
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


func _http(method: HTTPClient.Method, path: String, body = null) -> Variant:
	var req := HTTPRequest.new()
	root.add_child(req)
	req.request(base + path, PackedStringArray(["Content-Type: application/json"]), method, JSON.stringify(body) if body != null else "")
	var res: Array = await req.request_completed
	req.queue_free()
	return JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())


func _run() -> void:
	var game: Node = root.get_node("Game")
	var cloud: Node = main.cloud
	_check(cloud.enabled and base != "", "the cloud talks to the stand-in server (ST_CLOUD)")
	# Registration happens at start-up.
	var n := 0
	while not cloud.registered() and n < 600:
		await process_frame
		n += 1
	_check(cloud.registered() and cloud.friend_code.length() == 6, "registered on first run with a friend code (%s)" % cloud.friend_code)
	var cf := ConfigFile.new()
	_check(cf.load("user://cloud.cfg") == OK and cf.get_value("me", "id", "") == cloud.id, "the identity is saved on the device")
	# Laps.
	var ghost_samples := PackedFloat32Array()
	for i in 200:
		ghost_samples.append_array(PackedFloat32Array([i * 0.1, i * 5.0, 0.0, 0.0]))
	var r1: Array = await _await_cb(func(cb): cloud.submit_lap(1, 30.5, 2, ghost_samples, cb))
	_check(r1[0] == true and r1[1].improved, "a best lap goes to the leaderboard")
	var r2: Array = await _await_cb(func(cb): cloud.submit_lap(1, 31.0, 2, ghost_samples, cb))
	_check(r2[0] == true and not r2[1].improved, "a slower lap doesn't replace it")
	var r3: Array = await _await_cb(func(cb): cloud.submit_lap(1, 5.0, 2, ghost_samples, cb))
	_check(r3[0] == false, "an impossible lap time is refused")
	var top: Array = (await _await_cb(func(cb): cloud.top_laps(1, cb)))[0]
	_check(top.size() >= 1 and top[0].player_id == cloud.id and int(top[0].lap_ms) == 30500 and top[0].name != "?", "the track board lists it with the driver's name")
	# A friend with a faster lap and a ghost.
	var fg := PackedFloat32Array()
	for i in 300:
		fg.append_array(PackedFloat32Array([i * 0.1, i * 8.0, 1.0, 0.0]))
	var ghost_b64 := Marshalls.raw_to_base64(var_to_bytes(fg).compress(FileAccess.COMPRESSION_DEFLATE))
	await _http(HTTPClient.METHOD_POST, "/debug/seed", {"name": "RIVAL RACER", "num": "44", "code": "RIVAL1", "track": 1, "lap_ms": 29900, "ghost": ghost_b64})
	var fr: Array = await _await_cb(func(cb): cloud.add_friend("rival1", cb))
	_check(fr[0] == true, "adding a friend by code (%s)" % String(fr[1]))
	n = 0
	while cloud.friends.is_empty() and n < 300:
		await process_frame
		n += 1
	_check(cloud.friends.size() == 1 and cloud.friends[0].name == "RIVAL RACER", "the friend list loads")
	var rv: Dictionary = (await _await_cb(func(cb): cloud.rival_ghost(1, cb)))[0]
	_check(rv.has("samples") and (rv.samples as PackedFloat32Array).size() == fg.size(), "their ghost comes back decoded")
	# Practice at that track: the rival ghost is there to chase.
	main.mode = "race"
	main.session = "practice"
	main._use_track(1)
	main._enter_countdown()
	main.autopilot = true
	n = 0
	while not main.rival.active and n < 600:
		await process_frame
		n += 1
	_check(main.rival.active, "practice brings your friend's ghost to chase")
	main._enter_title()
	await _frames(5)
	_check(not main.rival.active, "the ghost leaves with the session")
	# Events.
	cloud.submit_daily(3, 125.4)
	await _frames(60)
	var db: Array = (await _await_cb(func(cb): cloud.event_board(game.daily_event_key(), cb)))[0]
	_check(db.size() == 1 and int(db[0].score) == 3012540, "the daily board has today's result (place, then time)")
	var wk: Dictionary = game.weekly_event()
	_check(String(wk.key).begins_with("weekly-") and int(wk.track) >= 0 and int(wk.track) < 11, "this week's time trial: %s (%s)" % [wk.name, wk.key])
	# XP and levels.
	var lv0: int = game.level()
	var aw: Dictionary = game.award_race(1, 20, 30, true)
	print("   a clean win in a 20-car, 30-lap race: +%d XP (level %d)" % [aw.xp, aw.level])
	_check(int(aw.xp) >= 400 and game.level() >= lv0, "a win earns XP")
	_check(game.level_for(0) == 1 and game.level_for(500) == 2 and game.level_for(499) == 1, "levels: 500 XP to level 2")
	game.progress.xp = 0
	_check(game.scheme_unlocked(0) and not game.scheme_unlocked(4), "FLAMES is locked at level 1")
	game.progress.xp = 3000
	_check(game.scheme_unlocked(4), "and unlocks at level %d" % game.SCHEME_LEVEL[4])
	# Stats.
	cloud.submit_session({"device": "test", "touch": true, "fps_avg": 60.0, "fps_p5": 50.0, "cars": 20, "quality": 2, "secs": 90, "mode": "race"})
	await _frames(60)
	var st = await _http(HTTPClient.METHOD_GET, "/debug/state")
	_check(st is Dictionary and int(st.sessions) >= 1, "the frame-rate stats arrive")
	# The leaderboards screen.
	main._board = 0
	main._board_track = 1
	main._enter_boards()
	n = 0
	while main._board_state == "loading" and n < 600:
		await process_frame
		n += 1
	await _frames(3)
	var labels := []
	for r in main.menu.rows:
		labels.append(String(r.label))
	print("   board rows: ", labels.slice(0, 6))
	_check(labels.any(func(l): return l.contains("RIVAL RACER")) and labels.any(func(l): return l.contains("(YOU)")), "the LEADERBOARDS screen lists the times")
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
