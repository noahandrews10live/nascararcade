extends SceneTree
## Superspeedway pack tools (pack.gd), at Thunder Beach:
##   - a drafting partner of your make is named before the green, and trusts you;
##   - the push call: a car that trusts you goes with you, onto your bumper, and
##     you feel the push in the air; one that doesn't hangs you out (out of line);
##   - nobody's your friend on the last lap (your partner least selfish);
##   - pushing a car builds its trust (and the spotter says so);
##   - your partner, just ahead in your line, asks you for a push.
##   godot --headless --fixed-fps 60 -s tests/pack_test.gd

var main: Node
var game: Node
var failures := 0
var said: Array = []


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


func _heard(part: String) -> bool:
	for t in said:
		if String(t).contains(part):
			return true
	return false


## Wait for a car in line right behind you (the pack shuffles).
func _pusher(pk: Node, p: Node3D) -> Node3D:
	var n := 0
	while n < 60 * 60:
		var c: Node3D = pk.pusher_for(p)
		if c and pk.cool <= 0.0:
			return c
		await physics_frame
		n += 1
	return null


func _run() -> void:
	game = root.get_node("Game")
	for i in 20:
		await physics_frame
	main.clear_checkpoint()
	game.settings.length = 1
	game.settings.field = 0
	game.settings.weather = 0
	game.settings.weekend = 0
	game.settings.cautions = 0
	game.tracks[0].full_laps = 600
	main.mode = "race"
	main.session = "race"
	main._use_track(0)
	main._enter_track_select()
	main._enter_car_select()
	main._enter_countdown()
	main.autopilot = true
	var race = main.race
	var pk: Node = race.pack
	var p: Node3D = race.player
	race.control.message.connect(func(t, _k): said.append(t))

	# 1. The partner.
	_check(pk.active, "the pack tools are on at a superspeedway")
	var pt: Node3D = pk.partner
	_check(pt != null and pt.partner and pt.trust >= 0.7, "a drafting partner, who trusts you")
	if pt:
		var mk: int = int(p.team.get("make", -1))
		var any_same := false
		for c in race.cars:
			if c != p and int(c.team.get("make", -2)) == mk:
				any_same = true
		print("   partner: #%s (%s), you: %s" % [pt.team.num, pt.team.get("make", ""), mk])
		_check(not any_same or int(pt.team.get("make", -2)) == mk, "of your make")
	while not race.running:
		await physics_frame
	await _frames(10)
	_check(_heard("DRAFTING PARTNER"), "named on the radio at the green")
	# (Two by two from the start, lines held: a car right behind you in your line.)
	race.debug_no_lane_changes = true # (the field holds its lines from here)
	await _frames(60 * 15) # (up to speed)

	# 2. A car that trusts you goes with you.
	var c: Node3D = await _pusher(pk, p)
	_check(c != null, "a car in line behind you")
	if c:
		c.trust = 1.0
		var r: String = pk.call_push(p)
		_check(r == "help" and _heard("GOING WITH YOU"), "it goes with you (%s)" % r)
		var g0: float = race._gap(c, p)
		var min_gap := 1e9
		var max_push := 0.0
		for i in 60 * 8:
			await physics_frame
			min_gap = min(min_gap, race._gap(c, p))
			if OS.get_environment("DEBUG_PK") != "" and i % 30 == 0:
				print("   [t %.1f gap %.1f, v %.2f vs you %.2f, thr %.2f, drag %.3f vs %.3f, push_t %.1f, d %.1f/%.1f]" % [i / 60.0, race._gap(c, p), c.v, p.v, c.throttle, c.drag_mult, p.drag_mult, c.push_t, c.d, p.d])
			var air = p.get_meta("air", Vector4.ZERO)
			max_push = max(max_push, air.y)
		print("   push: from %.1f m to %.1f m (centres), your push air %.2f" % [g0, min_gap, max_push])
		_check(min_gap < 6.0, "onto your bumper")
		_check(max_push > 0.3, "and you feel the push")

	# 3. One that doesn't trust you hangs you out.
	await _frames(60 * 3)
	c = await _pusher(pk, p)
	if c:
		c.trust = 0.0
		var r: String = pk.call_push(p)
		_check(r == "hang" and _heard("HUNG YOU OUT"), "a car that doesn't trust you hangs you out (%s)" % r)
		var out := 0.0
		var g0: float = race._gap(c, p)
		var back := 0.0
		for i in 60 * 4:
			await physics_frame
			out = max(out, abs(c.d - p.d))
			back = max(back, race._gap(c, p) - g0)
			if OS.get_environment("DEBUG_PK") != "" and i % 30 == 0:
				print("   [hang t %.1f gap %.1f, v %.2f vs you %.2f, thr %.2f brk %.2f, hang_t %.1f back %s, lane %.1f d %.1f/%.1f]" % [i / 60.0, race._gap(c, p), c.v, p.v, c.throttle, c.brake, c.hang_t, c.get_meta("hang_back", false), c.ai_lane, c.d, p.d])
		print("   hung out: %.1f m out of line, %.1f m further back" % [out, back])
		_check(out > 2.0 or back > 4.0, "and pulls out of line (or, boxed in, backs out of your draft)")
	else:
		_check(false, "a second car in line behind you")

	# 4. The last lap.
	var other: Node3D = null
	for o in race.cars:
		if o != p and o != pt:
			other = o
			break
	other.trust = 0.55
	var mid_o: float = pk.willing(other, p)
	var mid_p: float = pk.willing(pt, p)
	var laps0: int = race.laps
	race.laps = p.lap() + 1
	var last_o: float = pk.willing(other, p)
	var last_p: float = pk.willing(pt, p)
	race.laps = laps0
	print("   willing mid-race %.2f / partner %.2f; last lap %.2f / partner %.2f" % [mid_o, mid_p, last_o, last_p])
	_check(mid_o >= pk.HELP_AT and last_o < pk.HELP_AT, "a car that would help mid-race won't on the last lap")
	_check(last_p > last_o and last_p - mid_p > last_o - mid_o, "your partner is the least selfish")

	# 5. Pushing builds trust.
	other.trust = 0.5
	said.clear()
	pk.on_push(p, other)
	_check(other.trust > 0.5 and _heard("RETURN THE FAVOUR"), "your push builds its trust (%.2f)" % other.trust)
	var t1: float = other.trust
	pk.on_push(p, other)
	_check(other.trust == t1, "(one push counts once)")

	# 6. The partner asks.
	said.clear()
	pt.dist = p.dist + 15.0
	pt.d = p.d
	pt.ai_lane = p.d
	pk._ask_t = 0.0
	await _frames(2)
	_check(_heard("WANTS A PUSH"), "your partner, ahead in your line, asks for a push")

	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
