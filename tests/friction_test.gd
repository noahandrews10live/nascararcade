extends SceneTree
## Less friction, and REPORT A PROBLEM:
##   - the home screen leads with the next race (career, season, or the last
##     race again), one tap from the weekend;
##   - the pit call has a one-tap "take the crew chief's call";
##   - the pause screen says where you are and how the car is;
##   - OPTIONS previews tilt steering live while it's picked;
##   - REPORT A PROBLEM (pause, F8, options): a screenshot, the race so far and
##     the settings go to the server; offline it waits on the device and goes
##     the next time.
##   python3 tests/tools/fake_cloud.py 24795 &
##   ST_CLOUD=http://127.0.0.1:24795 ST_NO_INTRO=1 godot --headless --fixed-fps 60 -s tests/friction_test.gd

var main: Node
var game: Node
var failures := 0
var base := OS.get_environment("ST_CLOUD")


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


func _until(cond: Callable, limit := 600) -> bool:
	var n := 0
	while not cond.call() and n < limit:
		await process_frame
		n += 1
	return cond.call()


func _http_state() -> Variant:
	var req := HTTPRequest.new()
	root.add_child(req)
	req.request(base + "/debug/state")
	var res: Array = await req.request_completed
	req.queue_free()
	return JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())


func _ids() -> Array:
	return main._modes().map(func(m): return m[2])


func _run() -> void:
	game = root.get_node("Game")
	await _frames(20)
	main.clear_checkpoint()
	game.settings.weather = 0
	game.settings.field = 0
	game.settings.weekend = 0
	# --- the home screen's next race
	game.clear_career()
	game.use_season(false)
	game.clear_season()
	game.recent = []
	_check(not _ids().has("again") and not String(_ids()[0]).ends_with("_next"), "nothing raced yet: no NEXT tile")
	game.add_recent(4, 7, 20)
	_check(_ids()[0] == "again" and String(main._modes()[0][0]).begins_with("RACE AGAIN"), "after a race: RACE AGAIN leads (%s)" % main._modes()[0][0])
	game.new_season(1, 1)
	game.use_season(false)
	game.save_season()
	_check(_ids()[0] == "season_next", "a season going: NEXT: SEASON RACE leads")
	game.new_career(2)
	_check(_ids()[0] == "career_next" and String(main._modes()[0][1]).contains("YEAR 1"), "a career going: NEXT: CAREER RACE leads")
	main._start_mode("career_next")
	await _frames(3)
	_check(main.menu_kind == "preview" and main.mode == "career", "one tap: the career's next weekend")
	main._start_mode("season_next")
	await _frames(3)
	_check(main.mode == "season" and main.state == main.State.COUNTDOWN, "one tap: the season's next race")
	game.clear_career()
	game.use_season(false)
	game.clear_season()
	main._enter_title()
	await _frames(3)
	main._start_mode("again")
	await _frames(3)
	_check(main.state == main.State.COUNTDOWN and game.selected_track == 4, "one tap: the last race again")
	# --- the pause screen
	while main.state != main.State.RACE:
		await physics_frame
	await _frames(120)
	var ev := InputEventAction.new()
	ev.action = "pause"
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	var up := InputEventAction.new()
	up.action = "pause"
	Input.parse_input_event(up)
	await _frames(3)
	_check(main.paused and main.pause_layer.visible, "paused")
	_check(main.pause_status.text.begins_with("LAP ") and main.pause_status.text.contains("TIRES ") and main.pause_status.text.contains("FUEL "), "the pause screen: lap, place, tires, fuel (%s)" % main.pause_status.text)
	# --- REPORT A PROBLEM, online
	_check(main.cloud.enabled and base != "", "the cloud talks to the stand-in server")
	main.cloud.id = "" # a fresh stand-in server: register again
	main.cloud.secret = ""
	for f in main.cloud.pending_reports():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	main.open_report()
	await _until(func(): return main.report != null and is_instance_valid(main.report))
	var rp: Control = main.report
	_check(rp != null and rp.visible, "F8 / REPORT A PROBLEM opens the report over the paused race")
	rp._toggle("HANDLING")
	rp.note.text = "the car spun on its own"
	var pl: Dictionary = rp.payload()
	_check(pl.tags == ["HANDLING"] and pl.note == "the car spun on its own" and pl.version == game.VERSION, "a tag, a note and the version")
	_check(pl.state.has("race") and pl.state.race.has("log") and pl.state.race.has("where") and pl.state.settings.has("difficulty"), "the race so far (the recorder's log, where you are) and the settings")
	_check(JSON.stringify(pl).length() < 400000, "small enough to send (%d bytes)" % JSON.stringify(pl).length())
	var keys_before: bool = main.paused
	rp._do_send()
	var sent: bool = await _until(func(): return not is_instance_valid(rp), 400)
	var st = await _http_state()
	_check(st is Dictionary and int(st.reports) == 1 and st.last_report.note == "the car spun on its own", "it reaches the server")
	_check(sent and main.report == null and keys_before and main.paused, "then closes, back on the pause screen")
	_check(main.cloud.pending_reports().is_empty(), "nothing left waiting on the device")
	# --- offline: kept, and sent later
	var real: String = main.cloud._base
	main.cloud._base = "http://127.0.0.1:9" # nothing listens there
	main.open_report()
	await _until(func(): return main.report != null and is_instance_valid(main.report))
	rp = main.report
	rp.note.text = "offline one"
	rp._do_send()
	await _until(func(): return String(rp._status.text).begins_with("NO CONNECTION"), 900)
	_check(String(rp._status.text).begins_with("NO CONNECTION"), "offline: saved on the phone, and it says so")
	_check(main.cloud.pending_reports().size() == 1, "one report waiting")
	await _until(func(): return not is_instance_valid(rp), 400)
	main.cloud._base = real
	main.cloud.send_pending()
	await _until(func(): return main.cloud.pending_reports().is_empty(), 600)
	st = await _http_state()
	_check(int(st.reports) == 2 and st.last_report.note == "offline one" and main.cloud.pending_reports().is_empty(), "back online: it goes up")
	# Typing in the note doesn't drive the game.
	main.open_report()
	await _until(func(): return main.report != null and is_instance_valid(main.report))
	var q := InputEventAction.new()
	q.action = "quit_race"
	q.pressed = true
	Input.parse_input_event(q)
	await _frames(3)
	_check(main.state == main.State.RACE, "keys go to the report, not the race (Q doesn't quit)")
	main.report.close()
	await _frames(2)
	# --- the pit call: one tap for the crew chief's call
	var info := {"options": ["", "2", "4"], "names": ["STAY OUT", "2 TIRES + FUEL", "4 TIRES + FUEL"], "advice": "4", "reason": "TEST",
		"position": 5, "field": 20, "laps_left": 30, "wear": 0.3, "grip": 0.95, "fuel_laps": 20, "damage": 0.0, "estimate": {"": 3, "2": 6, "4": 9}}
	var called := []
	main.race.control.set_meta("test", true)
	main._on_pit_call(info)
	await _frames(2)
	_check(String(main.pit_menu.rows[0].label).begins_with("TAKE THE CREW CHIEF'S CALL: 4 TIRES") and main.pit_menu.cursor == 1, "the pit call: a one-tap crew chief's call on top (the cursor stays on PIT CALL)")
	main.pit_menu.set_value("plan", 0)
	main.pit_menu.activated.emit("advice")
	await _frames(2)
	_check(main.pit_menu == null and not main.paused, "one tap sends it")
	# --- OPTIONS: tilt preview
	main._enter_options()
	await _frames(2)
	var sp: Control = null
	for c in main.screen.get_children():
		if c.get_script() and String(c.get_script().resource_path).ends_with("steer_preview.gd"):
			sp = c
	_check(sp != null and not sp.visible, "OPTIONS: the tilt preview waits")
	for i in main.menu.rows.size():
		if String(main.menu.rows[i].get("id", "")) == "tilt_sens":
			main.menu.cursor = i
	await _frames(2)
	_check(sp.visible, "and shows while TILT STEERING is picked")
	game.settings.tilt_sens = 3
	var quick: float = sp.TouchControls.tilt_steer(5.0)
	game.settings.tilt_sens = 0
	var gentle: float = sp.TouchControls.tilt_steer(5.0)
	_check(quick > gentle, "VERY QUICK steers more for the same tilt (%.2f vs %.2f)" % [quick, gentle])
	game.settings.tilt_sens = 1
	_check(main.menu.rows.any(func(r): return r.get("id", "") == "report"), "OPTIONS has REPORT A PROBLEM")
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
