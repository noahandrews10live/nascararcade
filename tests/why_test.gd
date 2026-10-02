extends SceneTree
## In-the-moment reasons and early warnings:
##   - a caution says who, what and where ("#24 GORDON SPUN IN TURN 2");
##   - your own spins and wall hits say why (contact, the brakes, the throttle,
##     too fast in), and a failed tyre says what killed it;
##   - the crew chief calls a hot tyre, worn tyres, short fuel and the water
##     temperature before they bite: once per level, urgent ones louder;
##   - the HUD shows each tyre's health as a traffic light.
##   ST_NO_INTRO=1 godot --headless --fixed-fps 60 -s tests/why_test.gd

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
	game.settings.length = 1
	main.mode = "race"
	main.session = "race"
	main._use_track(2)
	main._enter_countdown()
	var n := 0
	while main.state != main.State.RACE and n < 60 * 30:
		await physics_frame
		n += 1
	await _frames(60 * 6)
	_check(main.state == main.State.RACE and main.crew_watch != null and main.race_log != null, "a race with the recorder and the crew chief watching")
	var race: Node3D = main.race
	var ctl: Node = race.control
	var me: Node3D = race.player
	var other: Node3D = race.cars[3] if race.cars[3] != me else race.cars[4]
	# Caution reasons.
	var why: String = ctl.caution_why("SPIN", other)
	_check(why.begins_with("#" + other.team.num) and why.contains("SPUN IN ") and (why.contains("TURN") or why.contains("STRETCH")), "a spin: who and where (%s)" % why)
	why = ctl.caution_why("CAR IN THE WALL", me)
	_check(why.begins_with("YOU HIT THE WALL IN "), "your own: 'YOU HIT THE WALL IN ...' (%s)" % why)
	_check(ctl.caution_why("DEBRIS", null, "TURN 3") == "DEBRIS ON TRACK IN TURN 3", "debris: where it is")
	_check(ctl.caution_why("RAIN", null) == "", "rain needs no more words")
	var got: Array = []
	ctl.message.connect(func(t, k): got.append([t, k]))
	print("   flag before: ", ctl.flag, " cautions ", ctl.caution_count, " reason ", ctl._last_caution_reason)
	ctl.throw_caution("SPIN", other)
	_check(got.any(func(x): return x[1] == "why" and String(x[0]).contains("#" + other.team.num)), "the caution comes with its reason on screen")
	_check(main.race_log.events.any(func(e): return e.kind == "caution" and String(e.text).contains("#" + other.team.num)), "and the debrief's key moments get it too")
	# Why you spun.
	var lg: Node = main.race_log
	lg._hist = [{"t": lg.t - 0.5, "thr": 1.0, "brk": 0.0, "front": 0.7, "rear": 1.0, "locked": false, "v": 50.0}]
	lg._last_contact_by = {}
	_check(lg._why_spin().begins_with("LOOSE ON THE THROTTLE"), "full throttle, rear at the limit: loose on the throttle")
	lg._hist = [{"t": lg.t - 0.5, "thr": 0.0, "brk": 0.9, "front": 0.8, "rear": 0.9, "locked": true, "v": 50.0}]
	_check(lg._why_spin().begins_with("LOCKED THE REARS"), "hard on the brakes: locked them")
	lg._hist = [{"t": lg.t - 0.5, "thr": 0.3, "brk": 0.0, "front": 0.95, "rear": 0.8, "locked": false, "v": 50.0}]
	_check(lg._why_spin().begins_with("TOO FAST"), "neither: too fast into the corner")
	lg._last_contact_by = {"who": "24", "t": lg.t - 0.5}
	_check(lg._why_spin() == "CONTACT WITH #24", "just after contact: the contact")
	_check(lg._why_wall() == "PUSHED THERE BY #24", "a wall hit after contact: pushed there")
	lg._last_contact_by = {}
	var shown: Array = []
	lg.moment.connect(func(e): shown.append(e))
	lg._event("spin", "Spun in TURN 1", {"why": "TEST REASON"})
	await _frames(2)
	_check(shown.size() == 1 and String(main.hud.l_sub.text).contains("TEST REASON"), "a spin's reason goes up on screen (%s)" % main.hud.l_sub.text)
	# Tyre failures say why.
	me.carcass_temp[1] = 181.0
	_check(me.failure_cause(1, "blowout").begins_with("IT OVERHEATED"), "a blowout from heat: 'it overheated'")
	me.carcass_temp[1] = 90.0
	me.tyre_wear4[1] = 0.97
	_check(me.failure_cause(1, "blowout").begins_with("IT WAS WORN OUT"), "from wear: 'worn out'")
	_check(me.failure_cause(1, "cut").contains("DEBRIS"), "a cut: debris or bodywork")
	me.tyre_wear4[1] = 0.0
	# The crew chief's early warnings.
	ctl.flag = ctl.Flag.GREEN
	var cw: Node = main.crew_watch
	var calls: Array = []
	cw.warn.connect(func(t, u): calls.append([t, u]))
	main.state = main.State.RACE
	me.pit_state = 0
	me.carcass_temp[1] = 158.0
	await _frames(40)
	me.carcass_temp[1] = 158.0
	await _frames(40)
	_check(calls.size() == 1 and String(calls[0][0]).begins_with("RIGHT FRONT IS GETTING HOT") and not calls[0][1], "a hot tyre: one call, not repeated (%s)" % str(calls))
	_check(String(main.hud.l_crew.text).contains("RIGHT FRONT"), "and it's on the HUD")
	me.carcass_temp[1] = 170.0
	await _frames(40)
	_check(calls.size() == 2 and calls[1][1] and String(calls[1][0]).contains("ABOUT TO LET GO"), "hotter still: an urgent call")
	_check(cw.tyre_health(me, 1) > 0.7 and cw.tyre_health(me, 0) < 0.34, "the HUD light: red for that tyre, green for a cool one")
	me.carcass_temp[1] = 90.0
	await _frames(40)
	calls.clear()
	var per_lap: float = race.track.length / 1000.0 * 0.62 * me.burn_scale
	me.fuel = per_lap * 3.5
	await _frames(40)
	_check(calls.any(func(c): return String(c[0]).begins_with("FUEL FOR 3 LAPS")), "short on fuel: how many laps are left in it (%s)" % str(calls))
	me.fuel = 70.0
	me.engine_temp = 125.0
	await _frames(40)
	_check(calls.any(func(c): return String(c[0]).begins_with("WATER TEMP")), "the water temperature climbing")
	me.engine_temp = 95.0
	me.tyre_wear4[2] = 0.85
	await _frames(40)
	_check(calls.any(func(c): return String(c[0]).begins_with("TIRES ARE ABOUT DONE")), "worn tyres")
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
