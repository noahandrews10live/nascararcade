extends SceneTree
## Leagues and paint, against the stand-in server (tests/tools/fake_cloud.py):
##   - paint: your own sponsor name goes on the car; a paint code carries the
##     whole scheme to another car (and a scheme you haven't unlocked comes over
##     as the basic one); junk isn't a paint code;
##   - a league: create it (a code to share), a friend joins with the code, both
##     race round 1; the finish goes up as the round's result, a worse try
##     doesn't replace a better one, and the points table adds it up;
##   - a weekly league only opens round 1 to begin with;
##   - the LEAGUES screen lists it, and its hub shows the rounds and the table.
##   python3 tests/tools/fake_cloud.py 24790 &
##   ST_CLOUD=http://127.0.0.1:24790 godot --headless --fixed-fps 60 -s tests/league_test.gd

var main: Node
var game: Node
var failures := 0
var base := OS.get_environment("ST_CLOUD")


func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://cloud.cfg"))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1


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


func _http(path: String, body = null) -> Variant:
	var req := HTTPRequest.new()
	root.add_child(req)
	req.request(base + path, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, JSON.stringify(body) if body != null else "")
	var res: Array = await req.request_completed
	req.queue_free()
	return JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())


func _run() -> void:
	game = root.get_node("Game")
	for i in 20:
		await process_frame
	main.clear_checkpoint()

	# --- paint ---
	game.custom.sponsor_text = "joe's garage!!"
	var t: Dictionary = game.custom_team()
	print("   sponsor on the car: '%s'" % t.sponsor)
	_check(t.sponsor == "JOE'S GARAGE!", "your own sponsor name goes on the car (capitals, cleaned)")
	game.custom.sponsor_text = ""
	_check(game.custom_team().sponsor == game.SPONSORS[game.custom.sponsor], "empty: the sponsor from the list")
	game.custom.num = 42
	game.custom.c1 = 3
	game.custom.c2 = 9
	game.custom.sponsor_text = "THUNDER LEAGUE"
	var code: String = game.paint_code()
	game.custom.num = 7
	game.custom.c1 = 0
	game.custom.sponsor_text = ""
	_check(game.paint_from_code(code) and int(game.custom.num) == 42 and int(game.custom.c1) == 3 and int(game.custom.c2) == 9 and game.custom.sponsor_text == "THUNDER LEAGUE", "a paint code carries the whole scheme")
	_check(not game.paint_from_code("not a code") and int(game.custom.num) == 42, "junk isn't a paint code")
	var d: Dictionary = game.custom.duplicate()
	d.scheme = 99
	_check(game.paint_from_code("PT1:" + Marshalls.utf8_to_base64(JSON.stringify(d))) and (int(game.custom.scheme) == 0 or game.scheme_unlocked(int(game.custom.scheme))), "a scheme you haven't unlocked comes over as one you have")
	game.custom.sponsor_text = ""

	# --- a league ---
	var cloud: Node = main.cloud
	var n0 := 0
	while not cloud.registered() and n0 < 600:
		await process_frame
		n0 += 1
	_check(cloud.registered(), "registered with the server")
	var r: Array
	r = await _await_cb(func(cb): cloud.league_create("SATURDAY NIGHT", [2, 1, 0], 0, false, cb))
	_check(r[0] == true and String(r[1].league.code).length() == 6, "a league is made, with a 6-character code")
	var lg: Dictionary = r[1].league
	print("   league %s, code %s, rounds %s, round %d open" % [lg.name, lg.code, str(lg.rounds), int(lg.current) + 1])
	# A friend joins with the code, and posts a result.
	var friend: Dictionary = await _http("/functions/v1/st", {"action": "register", "name": "BUDDY", "num": "8"})
	var fj: Dictionary = await _http("/functions/v1/st", {"action": "league_join", "id": friend.id, "secret": friend.secret, "code": lg.code})
	_check(fj.get("ok", false), "a friend joins with the code")
	await _http("/functions/v1/st", {"action": "league_result", "id": friend.id, "secret": friend.secret, "league_id": lg.id, "round": 0, "place": 3, "field": 20})
	# Our round 1: a real race.
	game.settings.field = 0
	game.settings.cautions = 0
	game.settings.weather = 0
	game.settings.weekend = 0
	main._race_league_round(lg, 0)
	main.autopilot = true
	_check(main.race.laps == game.race_laps(2) and main.race.track == main.track, "round 1: the round's track at the league's length (%d laps)" % main.race.laps)
	var n := 0
	while main.state != main.State.RESULTS and n < 60 * 600:
		await physics_frame
		n += 1
	var place: int = main.race.order.find(main.race.player) + 1
	for i in 120:
		await process_frame
	r = await _await_cb(func(cb): cloud.league_table(lg.id, cb))
	var table: Array = r[1].table if r[0] else []
	print("   finished %s; table %s" % [game.ordinal(place), str(table.map(func(x): return "%s %d" % [x.name, x.points]))])
	var me_row: Array = table.filter(func(x): return String(x.id) == cloud.id)
	_check(me_row.size() == 1 and int(me_row[0].points) > 0 and me_row[0].rounds.has("0"), "the finish went up as round 1's result")
	_check(table.size() == 2 and int(table[0].points) >= int(table[1].points), "the points table adds it up (2 drivers)")
	_check(main.league_round.is_empty() and game.league_length == -1, "and the race leaves league mode")
	# A worse try doesn't replace a better one.
	var before: int = int(me_row[0].points) if me_row.size() > 0 else 0
	r = await _await_cb(func(cb): cloud.league_result(lg.id, 0, 20, 20, 100.0, 20.0, cb))
	r = await _await_cb(func(cb): cloud.league_table(lg.id, cb))
	me_row = r[1].table.filter(func(x): return String(x.id) == cloud.id)
	_check(int(me_row[0].points) == before, "a worse try doesn't replace a better one")

	# A weekly league: round 2 isn't open yet.
	r = await _await_cb(func(cb): cloud.league_create("WEEKLY", [0, 1], 1, true, cb))
	var wk: Dictionary = r[1].league
	r = await _await_cb(func(cb): cloud.league_result(wk.id, 1, 1, 20, 100.0, 20.0, cb))
	_check(r[0] == false and String(r[1]).contains("ISN'T OPEN"), "a weekly league opens a round a week")

	# The screens.
	main._enter_mode_select()
	main._enter_online()
	main._on_league_menu("lg_list")
	n = 0
	while main._leagues.size() < 2 and n < 300:
		await process_frame
		n += 1
	var labels: Array = main.menu.rows.map(func(x): return String(x.get("label", "")))
	_check(labels.has("SATURDAY NIGHT") and labels.has("WEEKLY"), "LEAGUES lists your leagues")
	main._on_league_menu("lg_open:%d" % main._leagues.find(main._leagues.filter(func(x): return x.name == "SATURDAY NIGHT")[0]))
	n = 0
	while not main._league.has("table") and n < 300:
		await process_frame
		n += 1
	labels = main.menu.rows.map(func(x): return String(x.get("label", "")))
	print("   hub: %s" % str(labels))
	_check(labels.any(func(l): return l.begins_with("R1 ")) and labels.has("STANDINGS") and labels.any(func(l): return l.contains("PTS")), "the hub: the rounds and the standings")
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
